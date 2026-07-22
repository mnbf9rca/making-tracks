"""Bounded conditional-fetch probes for upstream source classes."""

from __future__ import annotations

import dataclasses
import hashlib
import json
import time
import urllib.error
import urllib.request
from collections.abc import Iterable

from . import acquire, fetch

DEFAULT_TIMEOUT_SECONDS = 20
DEFAULT_DEADLINE_SECONDS = 60
DEFAULT_MAX_BYTES = 64 * 1024
CONDITIONAL_METHOD = "GET"


@dataclasses.dataclass(frozen=True)
class ProbeTarget:
    upstream_class: str
    label: str
    url: str
    expected_hosts: tuple[str, ...]
    accept: str = "*/*"
    range_header: str | None = None
    max_bytes: int = DEFAULT_MAX_BYTES


@dataclasses.dataclass(frozen=True)
class FetchObservation:
    status: int | None
    etag: str | None = None
    last_modified: str | None = None
    sha256: str | None = None
    bytes_read: int = 0
    error: str | None = None


@dataclasses.dataclass(frozen=True)
class ProbeSummary:
    outcome: str
    hash_verdict: str


@dataclasses.dataclass(frozen=True)
class ProbeResult:
    target: ProbeTarget
    initial: FetchObservation
    followup: FetchObservation | None
    summary: ProbeSummary

    def as_dict(self) -> dict:
        return {
            "upstream_class": self.target.upstream_class,
            "label": self.target.label,
            "url": self.target.url,
            "range": self.target.range_header,
            "initial": dataclasses.asdict(self.initial),
            "followup": dataclasses.asdict(self.followup) if self.followup else None,
            "summary": dataclasses.asdict(self.summary),
            "etag_strength": etag_strength(self.initial.etag),
            "has_last_modified": bool(self.initial.last_modified),
            "method": CONDITIONAL_METHOD,
        }


def etag_strength(value: str | None) -> str:
    if not value:
        return "missing"
    stripped = value.strip()
    if stripped.startswith("W/"):
        tag = stripped[2:]
        return "weak" if _is_quoted_etag(tag) else "malformed"
    return "strong" if _is_quoted_etag(stripped) else "malformed"


def _is_quoted_etag(value: str) -> bool:
    return len(value) >= 2 and value.startswith('"') and value.endswith('"')


def conditional_headers(observation: FetchObservation) -> dict[str, str]:
    headers: dict[str, str] = {}
    if observation.etag:
        headers["If-None-Match"] = observation.etag
    if observation.last_modified:
        headers["If-Modified-Since"] = observation.last_modified
    return headers


def request_headers(
    target: ProbeTarget,
    *,
    conditional: dict[str, str] | None = None,
) -> dict[str, str]:
    headers = {
        "User-Agent": acquire.USER_AGENT,
        "Accept": target.accept,
        "Accept-Encoding": "identity",
    }
    if target.range_header:
        headers["Range"] = target.range_header
    if conditional:
        headers.update(conditional)
    return headers


def summarize_pair(
    initial: FetchObservation,
    followup: FetchObservation | None,
) -> ProbeSummary:
    if initial.error:
        return ProbeSummary(outcome="initial_error", hash_verdict="not_checked")
    if initial.status is not None and not 200 <= initial.status < 300:
        return ProbeSummary(
            outcome=f"unprobed_initial_status_{initial.status}",
            hash_verdict="not_checked",
        )
    if not conditional_headers(initial):
        return ProbeSummary(outcome="no_validators", hash_verdict="not_checked")
    if followup is None:
        return ProbeSummary(outcome="not_probed", hash_verdict="not_checked")
    if followup.error:
        return ProbeSummary(outcome="followup_error", hash_verdict="not_checked")
    if followup.status == 304:
        return ProbeSummary(outcome="not_modified", hash_verdict="not_rechecked_304")
    if followup.status == 200 or followup.status == 206:
        if initial.sha256 is None or followup.sha256 is None:
            return ProbeSummary(outcome="ok", hash_verdict="not_checked")
        verdict = "unchanged" if initial.sha256 == followup.sha256 else "changed"
        return ProbeSummary(outcome="ok", hash_verdict=verdict)
    return ProbeSummary(
        outcome=f"unexpected_status_{followup.status}",
        hash_verdict="not_checked",
    )


def fetch_observation(
    target: ProbeTarget,
    *,
    conditional: dict[str, str] | None = None,
    timeout: int = DEFAULT_TIMEOUT_SECONDS,
    deadline: int = DEFAULT_DEADLINE_SECONDS,
    opener=None,
) -> FetchObservation:
    expected_hosts = set(target.expected_hosts)
    if not fetch._validate_target(target.url, expected_hosts):
        return FetchObservation(
            status=None,
            error=f"invalid target: {target.url!r}",
        )
    opener = opener or fetch._opener(expected_hosts)
    request = urllib.request.Request(
        target.url,
        headers=request_headers(target, conditional=conditional),
    )
    try:
        with opener.open(request, timeout=timeout) as response:
            return _observation_from_response(response, target.max_bytes, deadline)
    except urllib.error.HTTPError as exc:
        return _observation_from_response(exc, target.max_bytes, deadline)
    except Exception as exc:
        return FetchObservation(status=None, error=str(exc))


def probe_target(target: ProbeTarget) -> ProbeResult:
    initial = fetch_observation(target)
    conditional = conditional_headers(initial)
    followup = (
        fetch_observation(target, conditional=conditional)
        if conditional and initial.status is not None and 200 <= initial.status < 300
        else None
    )
    return ProbeResult(
        target=target,
        initial=initial,
        followup=followup,
        summary=summarize_pair(initial, followup),
    )


def default_probes() -> tuple[ProbeTarget, ...]:
    return (
        ProbeTarget(
            upstream_class="commons_api_metadata",
            label="Commons API imageinfo metadata",
            url=(
                "https://commons.wikimedia.org/w/api.php?"
                "action=query&titles=File%3AExample.jpg&prop=imageinfo&"
                "iiprop=url%7Cmime%7Csize%7Cextmetadata&format=json&maxlag=5"
            ),
            expected_hosts=("commons.wikimedia.org",),
            accept="application/json",
        ),
        ProbeTarget(
            upstream_class="commons_image_file",
            label="Commons small image file",
            url="https://upload.wikimedia.org/wikipedia/commons/a/a9/Example.jpg",
            expected_hosts=("upload.wikimedia.org",),
            accept="image/jpeg",
        ),
        ProbeTarget(
            upstream_class="wikipedia_api",
            label="Wikipedia extracts API",
            url=(
                "https://en.wikipedia.org/w/api.php?"
                "action=query&titles=London&prop=extracts&exintro=1&"
                "explaintext=1&format=json&maxlag=5"
            ),
            expected_hosts=("en.wikipedia.org",),
            accept="application/json",
        ),
        ProbeTarget(
            upstream_class="wikidata_entity_data",
            label="Wikidata wbgetentities sitelink API",
            url=(
                "https://www.wikidata.org/w/api.php?"
                "action=wbgetentities&ids=Q84&props=sitelinks&sitefilter=enwiki&"
                "format=json&maxlag=5"
            ),
            expected_hosts=("www.wikidata.org",),
            accept="application/json",
        ),
        ProbeTarget(
            upstream_class="data_gov_sg_api",
            label="data.gov.sg dataset listing",
            url="https://api-production.data.gov.sg/v2/public/api/datasets?page=1",
            expected_hosts=("api-production.data.gov.sg",),
            accept="application/json",
        ),
        ProbeTarget(
            upstream_class="arcgis_rest",
            label="Historic England NHLE FeatureServer metadata",
            url=(
                "https://services-eu1.arcgis.com/ZOdPfBS3aqqDYPUQ/ArcGIS/rest/services/"
                "National_Heritage_List_for_England_NHLE_v02_VIEW/FeatureServer?f=json"
            ),
            expected_hosts=("services-eu1.arcgis.com",),
            accept="application/json",
        ),
        ProbeTarget(
            upstream_class="protomaps_build",
            label="Configured Protomaps build prefix",
            url="https://build.protomaps.com/20260714.pmtiles",
            expected_hosts=("build.protomaps.com",),
            accept="application/octet-stream",
            range_header="bytes=0-65535",
        ),
        ProbeTarget(
            upstream_class="r2_cdn_catalog",
            label="Published region catalog",
            url="https://tiles.making-tracks.app/regions.json",
            expected_hosts=("tiles.making-tracks.app",),
            accept="application/json",
        ),
    )


def run_default_probes(targets: Iterable[ProbeTarget] | None = None) -> list[ProbeResult]:
    return [probe_target(target) for target in (targets or default_probes())]


def results_json(results: Iterable[ProbeResult]) -> str:
    data = [result.as_dict() for result in results]
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def _observation_from_response(response, max_bytes: int, deadline: int) -> FetchObservation:
    status = getattr(response, "status", None) or getattr(response, "code", None)
    headers = getattr(response, "headers", None)
    etag = headers.get("ETag") if headers is not None else None
    last_modified = headers.get("Last-Modified") if headers is not None else None
    digest = hashlib.sha256()
    total = 0
    start = time.monotonic()
    while True:
        if time.monotonic() - start > deadline:
            return FetchObservation(
                status=status,
                etag=etag,
                last_modified=last_modified,
                bytes_read=total,
                error="exceeded total download deadline",
            )
        chunk = response.read(65536)
        if not chunk:
            break
        total += len(chunk)
        if total > max_bytes:
            return FetchObservation(
                status=status,
                etag=etag,
                last_modified=last_modified,
                bytes_read=total,
                error=f"response exceeded {max_bytes} bytes",
            )
        digest.update(chunk)
    return FetchObservation(
        status=status,
        etag=etag,
        last_modified=last_modified,
        sha256=digest.hexdigest() if total or status not in {304} else None,
        bytes_read=total,
    )
