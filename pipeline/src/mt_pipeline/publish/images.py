"""Commons image metadata filtering and image sidecar artifact emission."""

from __future__ import annotations

import base64
import html
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import threading
import time
from dataclasses import asdict, dataclass
from html.parser import HTMLParser
from typing import Any
from collections.abc import Callable
from urllib.parse import quote, urlencode, unquote, urlparse

from mt_contracts import strip_unsafe_text
from mt_contracts.validation import validate_instance
from mt_pipeline import fetch

from . import partition

COMMONS_API_HOST = "commons.wikimedia.org"
UPLOAD_HOST = "upload.wikimedia.org"
USER_AGENT = "MakingTracksPipeline/0.1 (https://making-tracks.app; rob@making-tracks.app)"
ACCEPTED_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}
PUBLIC_DOMAIN_LICENSE_URL = "https://creativecommons.org/publicdomain/mark/1.0/"
CC0_LICENSE_URL = "https://creativecommons.org/publicdomain/zero/1.0/"
CC_LICENSE_RE = re.compile(
    r"^cc-by(?P<nc>-nc)?(?P<sa>-sa)?-"
    r"(?P<version>1\.0|2\.0|2\.1|2\.5|3\.0|4\.0)"
    r"(?P<port>-[a-z]{2}(?:_[a-z]+)?|-igo)?$"
)
MAX_ORIGINAL_IMAGE_BYTES = 32 * 1024 * 1024
COMMONS_PRESCALED_WIDTH = 768
MAX_PRESCALED_IMAGE_BYTES = 8 * 1024 * 1024
# Rob-set Wikimedia fetch policy (2026-07-17): compliant UA, <=3 concurrent
# requests, and a hard ceiling of 200 requests/minute with 429 Retry-After backoff.
WIKIMEDIA_MAX_CONCURRENT_REQUESTS = 3
WIKIMEDIA_MAX_REQUESTS_PER_MINUTE = 200
WIKIMEDIA_MIN_429_BACKOFF_SECONDS = 5.0
WIKIMEDIA_MAX_RETRY_AFTER_SECONDS = 300.0
COMMONS_METADATA_BATCH_SIZE = 50
WIKIMEDIA_RETRY_ATTEMPTS = 4
IMAGE_WORKER_TIMEOUT_SECONDS = 30
TRANSIENT_REJECT_REASONS = frozenset({"metadata_fetch_failed", "download_failed"})
MAX_AUDITED_IMAGE_ROWS = 1_000_000
MAX_AUDITED_IMAGE_JSONL_BYTES = 512 * 1024 * 1024
MAX_AUDITED_THUMB_BYTES = 1_048_576
_HEX_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_CC_BY_LICENSE_CODE_RE = re.compile(
    r"^CC-BY(-SA)?-(1\.0|2\.0|2\.1|2\.5|3\.0|4\.0)(-[A-Z]{2}(_[A-Z]+)?|-IGO)?$"
)
_COMMONS_FILE_PATH_RE = re.compile(r"^/wiki/File:(?!.*(?:\.\.|/))[^?#\s]+$")


@dataclass(frozen=True)
class ImageCandidate:
    place_id: str
    lat: float
    lon: float
    image_url: str


@dataclass(frozen=True)
class ImageAttribution:
    creator: str | None
    license_code: str
    license_name: str
    license_url: str
    source_url: str
    modified: bool


@dataclass(frozen=True)
class CommonsImageMetadata:
    image_url: str
    source_url: str
    attribution: ImageAttribution


@dataclass(frozen=True)
class MetadataDecision:
    accepted: bool
    metadata: CommonsImageMetadata | None = None
    reason: str | None = None


@dataclass(frozen=True)
class PlaceImage:
    place_id: str
    lat: float
    lon: float
    thumb_sha256: str
    thumb_bytes: bytes
    width: int
    height: int
    attribution: ImageAttribution


@dataclass(frozen=True)
class ThumbTranscode:
    webp_bytes: bytes
    width: int
    height: int


@dataclass(frozen=True)
class ImageIndexArtifact:
    x: int
    y: int
    json_bytes: bytes
    sha256: str
    byte_len: int


@dataclass(frozen=True)
class ThumbArtifact:
    sha256: str
    webp_bytes: bytes
    byte_len: int


@dataclass(frozen=True)
class PurgeResult:
    files_changed: int
    entries_removed: int


@dataclass(frozen=True)
class GCResult:
    thumbs_removed: int
    bytes_removed: int


class AuditedImageReuseError(ValueError):
    """Raised when an audited image row or referenced thumb is unsafe."""


class _TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_data(self, data: str) -> None:
        self.parts.append(data)

    def handle_entityref(self, name: str) -> None:
        self.parts.append(html.unescape(f"&{name};"))

    def handle_charref(self, name: str) -> None:
        self.parts.append(html.unescape(f"&#{name};"))


class WikimediaRateLimiter:
    def __init__(self, *, requests_per_minute: int) -> None:
        self._min_interval = 60.0 / requests_per_minute
        self._next_allowed = 0.0
        self._lock = threading.Lock()

    def wait(self) -> None:
        with self._lock:
            now = time.monotonic()
            if now < self._next_allowed:
                time.sleep(self._next_allowed - now)
                now = time.monotonic()
            self._next_allowed = max(now, self._next_allowed) + self._min_interval


WIKIMEDIA_RATE_LIMITER = WikimediaRateLimiter(
    requests_per_minute=WIKIMEDIA_MAX_REQUESTS_PER_MINUTE
)
WIKIMEDIA_REQUEST_SEMAPHORE = threading.BoundedSemaphore(
    WIKIMEDIA_MAX_CONCURRENT_REQUESTS
)


def commons_filename_from_upload_url(url: str) -> str | None:
    parsed = urlparse(url)
    if parsed.scheme != "https":
        return None
    if parsed.hostname == UPLOAD_HOST and parsed.path:
        filename = unquote(parsed.path.rsplit("/", 1)[-1]).strip()
        return filename or None
    if parsed.hostname == COMMONS_API_HOST and parsed.path.startswith("/wiki/Special:FilePath/"):
        filename = unquote(parsed.path.rsplit("/", 1)[-1]).strip()
        return filename or None
    return None


def commons_source_url_from_image_url(url: str) -> str | None:
    filename = commons_filename_from_upload_url(url)
    if filename is None:
        return None
    return "https://commons.wikimedia.org/wiki/File:" + quote(
        filename.replace(" ", "_"), safe=":"
    )


def commons_prescaled_url(filename: str) -> str:
    return (
        "https://commons.wikimedia.org/wiki/Special:FilePath/"
        + quote(filename, safe="")
        + f"?width={COMMONS_PRESCALED_WIDTH}"
    )


def fetch_commons_imageinfo(filename: str) -> dict[str, Any]:
    batch = fetch_commons_imageinfo_batch([filename])
    return batch.get(filename, {"query": {"pages": {}}})


def fetch_commons_imageinfo_batch(filenames: list[str]) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    unique_filenames = sorted(dict.fromkeys(filenames))
    for start in range(0, len(unique_filenames), COMMONS_METADATA_BATCH_SIZE):
        chunk = unique_filenames[start : start + COMMONS_METADATA_BATCH_SIZE]
        titles = [f"File:{filename}" for filename in chunk]
        query = (
            "https://commons.wikimedia.org/w/api.php?"
            + urlencode(
                {
                    "action": "query",
                    "format": "json",
                    "prop": "imageinfo",
                    "iiprop": "url|mime|extmetadata",
                    "titles": "|".join(titles),
                }
            )
        )
        payload = _wikimedia_request(
            lambda query=query: fetch.get_json(
                query,
                expected_hosts={COMMONS_API_HOST},
                headers={"User-Agent": USER_AGENT},
            )
        )
        pages = payload.get("query", {}).get("pages", {})
        if not isinstance(pages, dict):
            continue
        for page_id, page in pages.items():
            if not isinstance(page, dict):
                continue
            title = page.get("title")
            if not isinstance(title, str) or not title.startswith("File:"):
                continue
            filename = title.removeprefix("File:")
            out[filename] = {"query": {"pages": {str(page_id): page}}}
    return out


def _wikimedia_request(operation: Callable[[], Any]) -> Any:
    last_retryable: fetch.FetchError | None = None
    for attempt in range(WIKIMEDIA_RETRY_ATTEMPTS):
        WIKIMEDIA_RATE_LIMITER.wait()
        with WIKIMEDIA_REQUEST_SEMAPHORE:
            try:
                return operation()
            except fetch.FetchError as exc:
                if exc.status not in {429, 503}:
                    raise
                delay = exc.retry_after
                if delay is None:
                    delay = WIKIMEDIA_MIN_429_BACKOFF_SECONDS * (2**attempt)
                delay = max(WIKIMEDIA_MIN_429_BACKOFF_SECONDS, float(delay))
                if delay > WIKIMEDIA_MAX_RETRY_AFTER_SECONDS:
                    raise
                last_retryable = exc
        if attempt < WIKIMEDIA_RETRY_ATTEMPTS - 1:
            time.sleep(delay)
    assert last_retryable is not None
    raise last_retryable


def _download_wikimedia_file(url: str, dest: pathlib.Path, *, expected_hosts: set[str] | None = None, max_bytes: int = MAX_ORIGINAL_IMAGE_BYTES) -> int:
    return _wikimedia_request(
        lambda: fetch.get_to_file(
            url,
            dest,
            expected_hosts=expected_hosts or {UPLOAD_HOST},
            max_bytes=max_bytes,
            headers={"User-Agent": USER_AGENT},
        )
    )


def candidates_from_source_records(
    conn,
    region: str,
    places: list[dict[str, Any]],
) -> list[ImageCandidate]:
    source_refs = sorted(
        {
            ref
            for place in places
            for ref in place.get("source_refs", [])
            if isinstance(ref, str)
        }
    )
    if not source_refs:
        return []
    rows = conn.execute(
        """
        SELECT source_ref, props_json
        FROM source_records
        WHERE region = ?
        """,
        (region,),
    )
    images_by_ref: dict[str, str] = {}
    wanted = set(source_refs)
    for source_ref, props_json in rows:
        if source_ref not in wanted:
            continue
        try:
            props = json.loads(props_json)
        except (ValueError, RecursionError):
            continue
        image_url = props.get("image") if isinstance(props, dict) else None
        if isinstance(image_url, str) and commons_filename_from_upload_url(image_url):
            images_by_ref[str(source_ref)] = image_url

    candidates: list[ImageCandidate] = []
    for place in sorted(places, key=lambda item: str(item["place_id"])):
        for source_ref in sorted(place.get("source_refs", [])):
            image_url = images_by_ref.get(source_ref)
            if image_url is None:
                continue
            candidates.append(
                ImageCandidate(
                    place_id=str(place["place_id"]),
                    lat=float(place["lat"]),
                    lon=float(place["lon"]),
                    image_url=image_url,
                )
            )
            break
    return candidates


def build_place_images(
    candidates: list[ImageCandidate],
    *,
    cache_dir,
) -> list[PlaceImage]:
    cache_root = pathlib.Path(cache_dir)
    if not candidates:
        return []
    raw_dir = cache_root / "raw"
    thumb_dir = cache_root / "thumbs"
    reject_dir = cache_root / "rejects"
    accepted_dir = cache_root / "accepted"
    raw_dir.mkdir(parents=True, exist_ok=True)
    thumb_dir.mkdir(parents=True, exist_ok=True)
    reject_dir.mkdir(parents=True, exist_ok=True)
    accepted_dir.mkdir(parents=True, exist_ok=True)

    out: list[PlaceImage] = []
    candidate_files: list[tuple[ImageCandidate, str]] = []
    for candidate in sorted(candidates, key=lambda item: item.place_id):
        reject_path = reject_dir / f"{candidate.place_id}.json"
        if _cached_reject_matches(reject_path, candidate):
            continue
        cached = _read_cached_place_image(
            accepted_dir / f"{candidate.place_id}.json",
            thumb_dir=thumb_dir,
            candidate=candidate,
        )
        if cached is not None:
            out.append(cached)
            continue
        filename = commons_filename_from_upload_url(candidate.image_url)
        if filename is None:
            _write_reject(reject_path, candidate, "image_url_invalid")
            continue
        candidate_files.append((candidate, filename))

    if not candidate_files:
        return out

    imageinfo_by_filename = fetch_commons_imageinfo_batch(
        [filename for _candidate, filename in candidate_files]
    )

    for candidate, filename in candidate_files:
        reject_path = reject_dir / f"{candidate.place_id}.json"
        payload = imageinfo_by_filename.get(filename)
        if payload is None:
            _write_reject(reject_path, candidate, "metadata_missing")
            continue
        try:
            decision = metadata_from_commons_imageinfo(payload)
        except Exception:
            _write_reject(reject_path, candidate, "metadata_invalid")
            continue
        if not decision.accepted or decision.metadata is None:
            _write_reject(reject_path, candidate, decision.reason or "metadata_rejected")
            continue
        raw_path = raw_dir / f"{candidate.place_id}.source"
        try:
            _download_wikimedia_file(
                commons_prescaled_url(filename),
                raw_path,
                expected_hosts={COMMONS_API_HOST, UPLOAD_HOST},
                max_bytes=MAX_PRESCALED_IMAGE_BYTES,
            )
        except Exception:
            try:
                _download_wikimedia_file(decision.metadata.image_url, raw_path)
            except Exception:
                _write_reject(reject_path, candidate, "download_failed")
                continue
        try:
            thumb = transcode_to_webp_thumb(raw_path)
        except Exception:
            _write_reject(reject_path, candidate, "decode_failed")
            continue
        thumb_sha = hashlib.sha256(thumb.webp_bytes).hexdigest()
        thumb_path = thumb_dir / thumb_sha[:2] / f"{thumb_sha}.webp"
        thumb_path.parent.mkdir(parents=True, exist_ok=True)
        thumb_path.write_bytes(thumb.webp_bytes)
        place_image = PlaceImage(
            place_id=candidate.place_id,
            lat=candidate.lat,
            lon=candidate.lon,
            thumb_sha256=thumb_sha,
            thumb_bytes=thumb.webp_bytes,
            width=thumb.width,
            height=thumb.height,
            attribution=decision.metadata.attribution,
        )
        _write_accepted(accepted_dir / f"{candidate.place_id}.json", candidate, place_image)
        out.append(place_image)
    return out


def build_place_images_from_audit(
    candidates: list[ImageCandidate],
    *,
    completed_jsonl,
    audited_cache_dir,
) -> list[PlaceImage]:
    audited_rows = _load_audited_image_rows(pathlib.Path(completed_jsonl))
    cache_root = pathlib.Path(audited_cache_dir)
    out: list[PlaceImage] = []
    seen_place_ids: set[str] = set()
    missing = 0
    for candidate in sorted(candidates, key=lambda item: item.place_id):
        if candidate.place_id in seen_place_ids:
            continue
        seen_place_ids.add(candidate.place_id)
        row = audited_rows.get(candidate.place_id)
        if row is None:
            missing += 1
            continue
        out.append(_place_image_from_audited_row(candidate, row, cache_root=cache_root))
    print(
        "AUDITED_IMAGE_REENCODE "
        f"candidates={len(candidates)} selected={len(out)} "
        f"missing_skipped={missing} audited_total={len(audited_rows)}"
    )
    return out


def _load_audited_image_rows(path: pathlib.Path) -> dict[str, dict[str, Any]]:
    try:
        size = path.stat().st_size
    except OSError as exc:
        raise AuditedImageReuseError(f"audited image JSONL is not readable: {path}") from exc
    if size > MAX_AUDITED_IMAGE_JSONL_BYTES:
        raise AuditedImageReuseError(f"audited image JSONL too large: {path}")
    rows: dict[str, dict[str, Any]] = {}
    with path.open(encoding="utf-8") as handle:
        for lineno, line in enumerate(handle, start=1):
            if lineno > MAX_AUDITED_IMAGE_ROWS:
                raise AuditedImageReuseError("audited image JSONL has too many rows")
            if not line.strip():
                continue
            try:
                payload = json.loads(line)
            except json.JSONDecodeError as exc:
                raise AuditedImageReuseError(
                    f"invalid audited image JSONL at line {lineno}: {exc}"
                ) from exc
            if not isinstance(payload, dict):
                raise AuditedImageReuseError(
                    f"audited image row {lineno} must be an object"
                )
            place_id = payload.get("place_id")
            if not isinstance(place_id, str) or not place_id:
                raise AuditedImageReuseError(
                    f"audited image row {lineno} has invalid place_id"
                )
            if place_id in rows:
                raise AuditedImageReuseError(
                    f"audited image JSONL has duplicate place_id at line {lineno}: {place_id}"
                )
            rows[place_id] = payload
    return rows


def _place_image_from_audited_row(
    candidate: ImageCandidate,
    row: dict[str, Any],
    *,
    cache_root: pathlib.Path,
) -> PlaceImage:
    thumb_sha = row.get("thumb_sha256")
    if not isinstance(thumb_sha, str) or _HEX_SHA256_RE.fullmatch(thumb_sha) is None:
        raise AuditedImageReuseError(
            f"audited image row has invalid thumb_sha256 for {candidate.place_id}"
        )
    _verify_retained_audited_thumb(thumb_sha, cache_root=cache_root, place_id=candidate.place_id)
    _positive_int(row.get("width"), label="width", place_id=candidate.place_id)
    _positive_int(row.get("height"), label="height", place_id=candidate.place_id)
    attribution = _audited_attribution(row.get("attribution"), place_id=candidate.place_id)
    image_url = row.get("image_url")
    if image_url is not None:
        if _https_url(image_url) is None:
            raise AuditedImageReuseError(
                f"audited image_url is not safe HTTPS for {candidate.place_id}"
            )
        if image_url != candidate.image_url:
            raise AuditedImageReuseError(
                f"audited image_url drift for {candidate.place_id}: "
                f"{image_url!r} != {candidate.image_url!r}"
            )
    original_path = cache_root / "raw" / f"{candidate.place_id}.source"
    if not original_path.exists():
        raise AuditedImageReuseError(
            f"referenced original missing for {candidate.place_id}: {original_path}"
        )
    if original_path.stat().st_size > MAX_ORIGINAL_IMAGE_BYTES:
        raise AuditedImageReuseError(
            f"audited original exceeds {MAX_ORIGINAL_IMAGE_BYTES} bytes for "
            f"{candidate.place_id}: {original_path}"
        )
    try:
        thumb = transcode_to_webp_thumb(original_path)
    except Exception as exc:
        raise AuditedImageReuseError(
            f"audited original decode failed for {candidate.place_id}: {original_path}"
        ) from exc
    if len(thumb.webp_bytes) > MAX_AUDITED_THUMB_BYTES:
        raise AuditedImageReuseError(
            f"audited reencoded thumb exceeds {MAX_AUDITED_THUMB_BYTES} bytes for "
            f"{candidate.place_id}: {original_path}"
        )
    thumb_sha = hashlib.sha256(thumb.webp_bytes).hexdigest()
    thumb_path = cache_root / "thumbs" / thumb_sha[:2] / f"{thumb_sha}.webp"
    thumb_path.parent.mkdir(parents=True, exist_ok=True)
    thumb_path.write_bytes(thumb.webp_bytes)
    return PlaceImage(
        place_id=candidate.place_id,
        lat=candidate.lat,
        lon=candidate.lon,
        thumb_sha256=thumb_sha,
        thumb_bytes=thumb.webp_bytes,
        width=thumb.width,
        height=thumb.height,
        attribution=attribution,
    )


def _verify_retained_audited_thumb(
    thumb_sha: str,
    *,
    cache_root: pathlib.Path,
    place_id: str,
) -> None:
    thumb_path = cache_root / "thumbs" / thumb_sha[:2] / f"{thumb_sha}.webp"
    if not thumb_path.exists():
        raise AuditedImageReuseError(
            f"referenced thumb missing for {place_id}: {thumb_path}"
        )
    if thumb_path.stat().st_size > MAX_AUDITED_THUMB_BYTES:
        raise AuditedImageReuseError(
            f"audited thumb exceeds {MAX_AUDITED_THUMB_BYTES} bytes for "
            f"{place_id}: {thumb_path}"
        )
    thumb_bytes = thumb_path.read_bytes()
    if hashlib.sha256(thumb_bytes).hexdigest() != thumb_sha:
        raise AuditedImageReuseError(
            f"thumb content hash mismatch for {place_id}: {thumb_path}"
        )


def _positive_int(value: object, *, label: str, place_id: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise AuditedImageReuseError(
            f"audited image {label} must be a positive integer for {place_id}"
        )
    return value


def _audited_attribution(value: object, *, place_id: str) -> ImageAttribution:
    if not isinstance(value, dict):
        raise AuditedImageReuseError(f"audited image attribution missing for {place_id}")
    creator = value.get("creator")
    if creator is not None:
        if not isinstance(creator, str) or _unsafe_text(creator, max_length=256):
            raise AuditedImageReuseError(
                f"audited image creator is unsafe for {place_id}"
            )
    license_code = _safe_text_field(value, "license_code", 64, place_id=place_id)
    if _CC_BY_LICENSE_CODE_RE.fullmatch(license_code) is not None and creator is None:
        raise AuditedImageReuseError(
            f"audited image creator is required for {license_code} at {place_id}"
        )
    license_name = _safe_text_field(value, "license_name", 128, place_id=place_id)
    raw_license_url = _safe_text_field(value, "license_url", 512, place_id=place_id)
    license_url, license_url_reason = _license_url(raw_license_url, license_code)
    if license_url is None:
        raise AuditedImageReuseError(
            f"audited image license_url rejected for {place_id}: {license_url_reason}"
        )
    source_url = _safe_commons_file_url(value, "source_url", place_id=place_id)
    modified = value.get("modified")
    if modified is not True:
        raise AuditedImageReuseError(
            f"audited image modified must be true for {place_id}"
        )
    return ImageAttribution(
        creator=creator,
        license_code=license_code,
        license_name=license_name,
        license_url=license_url,
        source_url=source_url,
        modified=modified,
    )


def _safe_text_field(
    value: dict[str, Any], key: str, limit: int, *, place_id: str
) -> str:
    raw = value.get(key)
    if not isinstance(raw, str) or _unsafe_text(raw, max_length=limit):
        raise AuditedImageReuseError(f"audited image {key} is unsafe for {place_id}")
    return raw


def _safe_https_field(value: dict[str, Any], key: str, *, place_id: str) -> str:
    raw = _safe_text_field(value, key, 512, place_id=place_id)
    safe = _https_url(raw)
    if safe is None:
        raise AuditedImageReuseError(
            f"audited image {key} is not safe HTTPS for {place_id}"
        )
    return safe


def _safe_commons_file_url(value: dict[str, Any], key: str, *, place_id: str) -> str:
    raw = _safe_text_field(value, key, 1024, place_id=place_id)
    parsed = urlparse(raw)
    if (
        parsed.scheme != "https"
        or parsed.hostname != "commons.wikimedia.org"
        or parsed.params
        or parsed.query
        or parsed.fragment
        or _COMMONS_FILE_PATH_RE.fullmatch(parsed.path) is None
    ):
        raise AuditedImageReuseError(
            f"audited image {key} is not a safe Commons File URL for {place_id}"
        )
    return raw


def transcode_to_webp_thumb(path) -> ThumbTranscode:
    result = subprocess.run(
        [sys.executable, "-m", "mt_pipeline.publish.image_worker", str(path)],
        check=True,
        capture_output=True,
        timeout=IMAGE_WORKER_TIMEOUT_SECONDS,
    )
    payload = json.loads(result.stdout.decode("utf-8"))

    return ThumbTranscode(
        webp_bytes=base64.b64decode(payload["webp_b64"]),
        width=int(payload["width"]),
        height=int(payload["height"]),
    )


def _write_reject(path: pathlib.Path, candidate: ImageCandidate, reason: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {"image_url": candidate.image_url, "reason": reason},
            sort_keys=True,
            separators=(",", ":"),
        ),
        encoding="utf-8",
    )


def _cached_reject_matches(path: pathlib.Path, candidate: ImageCandidate) -> bool:
    if not path.exists():
        return False
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return False
    reason = payload.get("reason")
    return (
        payload.get("image_url") == candidate.image_url
        and isinstance(reason, str)
        and reason not in TRANSIENT_REJECT_REASONS
    )


def _write_accepted(path: pathlib.Path, candidate: ImageCandidate, place_image: PlaceImage) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "image_url": candidate.image_url,
                "thumb_sha256": place_image.thumb_sha256,
                "width": place_image.width,
                "height": place_image.height,
                "attribution": asdict(place_image.attribution),
            },
            sort_keys=True,
            separators=(",", ":"),
        ),
        encoding="utf-8",
    )


def _read_cached_place_image(
    path: pathlib.Path,
    *,
    thumb_dir: pathlib.Path,
    candidate: ImageCandidate,
) -> PlaceImage | None:
    if not path.exists():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        if payload.get("image_url") != candidate.image_url:
            return None
        thumb_sha = str(payload["thumb_sha256"])
        thumb_path = thumb_dir / thumb_sha[:2] / f"{thumb_sha}.webp"
        thumb_bytes = thumb_path.read_bytes()
        if hashlib.sha256(thumb_bytes).hexdigest() != thumb_sha:
            return None
        return PlaceImage(
            place_id=candidate.place_id,
            lat=candidate.lat,
            lon=candidate.lon,
            thumb_sha256=thumb_sha,
            thumb_bytes=thumb_bytes,
            width=int(payload["width"]),
            height=int(payload["height"]),
            attribution=ImageAttribution(**payload["attribution"]),
        )
    except Exception:
        return None


def metadata_from_commons_imageinfo(payload: dict[str, Any]) -> MetadataDecision:
    info = _first_imageinfo(payload)
    if info is None:
        return MetadataDecision(False, reason="metadata_missing")
    image_url = _https_url(info.get("url"), host=UPLOAD_HOST)
    if image_url is None:
        return MetadataDecision(False, reason="image_url_invalid")
    if info.get("mime") not in ACCEPTED_MIME_TYPES:
        return MetadataDecision(False, reason="format_unaccepted")
    extmetadata = info.get("extmetadata")
    if not isinstance(extmetadata, dict):
        return MetadataDecision(False, reason="metadata_missing")

    license_raw = _metadata_value(extmetadata, "License")
    license_decision = _normalize_license(license_raw)
    if license_decision[0] is None:
        return MetadataDecision(False, reason=license_decision[1])
    license_code = license_decision[0]
    assert license_code is not None
    license_name = (
        _plain_text(_metadata_value(extmetadata, "LicenseShortName"))
        or _license_display_name(license_code)
    )
    if _unsafe_text(license_name, max_length=128):
        return MetadataDecision(False, reason="license_name_unsafe")
    license_url, license_url_reason = _license_url(
        _metadata_value(extmetadata, "LicenseUrl"), license_code
    )
    if license_url is None:
        return MetadataDecision(False, reason=license_url_reason)

    creator = _plain_text(_metadata_value(extmetadata, "Artist"))
    if license_code not in {"PD", "CC0-1.0"} and creator is None:
        return MetadataDecision(False, reason="creator_missing")
    if creator is not None and _unsafe_text(creator, max_length=256):
        return MetadataDecision(False, reason="creator_unsafe")
    title = _page_title(payload) or f"File:{commons_filename_from_upload_url(image_url)}"
    source_url = _source_url_from_title(title)
    if source_url is None:
        return MetadataDecision(False, reason="source_url_invalid")
    attribution = ImageAttribution(
        creator=creator,
        license_code=license_code,
        license_name=license_name,
        license_url=license_url,
        source_url=source_url,
        modified=True,
    )
    return MetadataDecision(
        True,
        metadata=CommonsImageMetadata(
            image_url=image_url,
            source_url=source_url,
            attribution=attribution,
        ),
    )


def emit_image_artifacts(
    records: list[PlaceImage],
) -> tuple[list[ImageIndexArtifact], list[ThumbArtifact]]:
    grouped: dict[tuple[int, int], list[PlaceImage]] = {}
    thumbs: dict[str, ThumbArtifact] = {}
    for record in sorted(records, key=lambda item: item.place_id):
        x, y = partition.lonlat_to_z10(record.lat, record.lon)
        grouped.setdefault((x, y), []).append(record)
        thumbs.setdefault(
            record.thumb_sha256,
            ThumbArtifact(
                sha256=record.thumb_sha256,
                webp_bytes=record.thumb_bytes,
                byte_len=len(record.thumb_bytes),
            ),
        )

    index_artifacts: list[ImageIndexArtifact] = []
    for (x, y), tile_records in sorted(grouped.items()):
        payload = {
            "schema_version": 1,
            "min_reader_version": 1,
            "z": 10,
            "x": x,
            "y": y,
            "places": [
                {
                    "place_id": record.place_id,
                    "thumb_sha256": record.thumb_sha256,
                    "bytes": len(record.thumb_bytes),
                    "width": record.width,
                    "height": record.height,
                    "attribution": asdict(record.attribution),
                }
                for record in tile_records
            ],
        }
        validate_instance("image-index", payload)
        data = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
        index_artifacts.append(
            ImageIndexArtifact(
                x=x,
                y=y,
                json_bytes=data,
                sha256=hashlib.sha256(data).hexdigest(),
                byte_len=len(data),
            )
        )
    return index_artifacts, [thumbs[key] for key in sorted(thumbs)]


def select_image_candidates(
    rows: list[tuple[dict[str, Any], ImageCandidate]],
    *,
    limit: int | None,
) -> list[ImageCandidate]:
    ordered = sorted(
        rows,
        key=lambda row: (
            -float(row[0]["score"]),
            int(row[0]["tier"]),
            row[1].place_id,
        ),
    )
    if limit is not None:
        ordered = ordered[:limit]
    return [candidate for _place, candidate in ordered]


def purge_nc_from_staging(root) -> PurgeResult:
    root_path = pathlib.Path(root)
    files_changed = 0
    entries_removed = 0
    for image_path in sorted(root_path.glob("*/[0-9]*T[0-9]*Z/images/10/*/*.json")):
        payload = json.loads(image_path.read_text(encoding="utf-8"))
        places = payload.get("places", [])
        if not isinstance(places, list):
            continue
        kept = [
            place
            for place in places
            if "NC" not in str(place.get("attribution", {}).get("license_code", ""))
        ]
        removed = len(places) - len(kept)
        if not removed:
            continue
        entries_removed += removed
        files_changed += 1
        if kept:
            payload["places"] = kept
            validate_instance("image-index", payload)
            image_path.write_text(
                json.dumps(payload, sort_keys=True, separators=(",", ":")),
                encoding="utf-8",
            )
        else:
            image_path.unlink()
    return PurgeResult(files_changed=files_changed, entries_removed=entries_removed)


def gc_unreferenced_thumbs(root) -> GCResult:
    root_path = pathlib.Path(root)
    referenced: set[str] = set()
    for image_path in sorted(root_path.glob("*/[0-9]*T[0-9]*Z/images/10/*/*.json")):
        payload = json.loads(image_path.read_text(encoding="utf-8"))
        for place in payload.get("places", []):
            if isinstance(place, dict) and isinstance(place.get("thumb_sha256"), str):
                referenced.add(place["thumb_sha256"])

    removed = 0
    bytes_removed = 0
    for thumb_path in sorted((root_path / "thumbs").glob("*/*.webp")):
        sha = thumb_path.stem
        if sha in referenced:
            continue
        size = thumb_path.stat().st_size
        thumb_path.unlink()
        removed += 1
        bytes_removed += size
    return GCResult(thumbs_removed=removed, bytes_removed=bytes_removed)


def _first_imageinfo(payload: dict[str, Any]) -> dict[str, Any] | None:
    query = payload.get("query")
    if not isinstance(query, dict):
        return None
    pages = query.get("pages")
    if not isinstance(pages, dict):
        return None
    for page in pages.values():
        if not isinstance(page, dict):
            continue
        imageinfos = page.get("imageinfo")
        if isinstance(imageinfos, list) and imageinfos and isinstance(imageinfos[0], dict):
            return imageinfos[0]
    return None


def _page_title(payload: dict[str, Any]) -> str | None:
    pages = payload.get("query", {}).get("pages", {})
    if not isinstance(pages, dict):
        return None
    for page in pages.values():
        if isinstance(page, dict) and isinstance(page.get("title"), str):
            title = page["title"].strip()
            if title.startswith("File:"):
                return title
    return None


def _metadata_value(extmetadata: dict[str, Any], key: str) -> str | None:
    item = extmetadata.get(key)
    if not isinstance(item, dict) or not isinstance(item.get("value"), str):
        return None
    return item["value"]


def _plain_text(value: str | None) -> str | None:
    if value is None:
        return None
    parser = _TextExtractor()
    parser.feed(value.replace("<br>", " ").replace("<br/>", " ").replace("<br />", " "))
    text = " ".join("".join(parser.parts).split())
    return text or None


def _unsafe_text(value: str, *, max_length: int) -> bool:
    return len(value) > max_length or strip_unsafe_text(value) != value


def _source_url_from_title(title: str | None) -> str | None:
    if title is None or not title.startswith("File:"):
        return None
    filename = title.removeprefix("File:").replace(" ", "_")
    if not filename or "?" in filename or "#" in filename:
        return None
    if any(part in {"", ".", ".."} for part in filename.split("/")):
        return None
    return "https://commons.wikimedia.org/wiki/File:" + quote(filename, safe="")


def _normalize_license(value: str | None) -> tuple[str | None, str]:
    if value is None or not value.strip():
        return None, "license_missing"
    normalized = _license_token(value)
    if "nd" in re.split(r"[-_]", normalized):
        return None, "license_nd"
    if normalized in {"pd", "public-domain", "publicdomain"}:
        return "PD", ""
    if normalized in {"cc0", "cc-zero", "cc-0", "cc0-1-0"}:
        return "CC0-1.0", ""
    match = CC_LICENSE_RE.fullmatch(normalized)
    if match is None:
        return None, "license_unaccepted"
    if match.group("nc"):
        return None, "license_nc"
    code = "CC-BY"
    if match.group("sa"):
        code += "-SA"
    code += f"-{match.group('version')}"
    if port := match.group("port"):
        code += port.upper()
    return code, ""


def _license_token(value: str) -> str:
    text = _plain_text(value) or value
    text = text.casefold().strip()
    text = re.sub(r"\s+", "-", text)
    text = re.sub(r"-+", "-", text)
    return text.strip("-")


def _license_display_name(code: str) -> str:
    fixed = {
        "PD": "Public domain",
        "CC0-1.0": "Creative Commons Zero 1.0",
    }
    if code in fixed:
        return fixed[code]
    if code.startswith("CC-BY-SA-"):
        return f"Creative Commons Attribution-ShareAlike {code.removeprefix('CC-BY-SA-')}"
    if code.startswith("CC-BY-"):
        return f"Creative Commons Attribution {code.removeprefix('CC-BY-')}"
    raise KeyError(code)


def _license_url(value: str | None, code: str) -> tuple[str | None, str]:
    if code == "PD":
        return PUBLIC_DOMAIN_LICENSE_URL, ""
    if code == "CC0-1.0":
        return CC0_LICENSE_URL, ""
    expected = _cc_license_url_for_code(code)
    if expected is None:
        return None, "license_url_mismatch"
    if value is None or not value.strip():
        return expected, ""
    url = _https_url(value, host=None, allowed_hosts={"creativecommons.org"})
    if url is None:
        return None, "license_url_invalid"
    if url.rstrip("/") != expected.rstrip("/"):
        return None, "license_url_mismatch"
    return expected, ""


def _cc_license_url_for_code(code: str) -> str | None:
    token = code.casefold().removeprefix("cc-")
    match = re.fullmatch(
        r"(?P<kind>by(?:-sa)?)-(?P<version>1\.0|2\.0|2\.1|2\.5|3\.0|4\.0)"
        r"(?P<port>-[a-z]{2}(?:_[a-z]+)?|-igo)?",
        token,
    )
    if match is None:
        return None
    port = match.group("port")
    port_path = f"{port.removeprefix('-')}/" if port else ""
    return (
        f"https://creativecommons.org/licenses/{match.group('kind')}/"
        f"{match.group('version')}/{port_path}"
    )


def _https_url(
    value: object,
    *,
    host: str | None = None,
    allowed_hosts: set[str] | None = None,
) -> str | None:
    if not isinstance(value, str):
        return None
    parsed = urlparse(value)
    if parsed.scheme != "https" or parsed.hostname is None:
        return None
    if host is not None and parsed.hostname != host:
        return None
    if allowed_hosts is not None and parsed.hostname not in allowed_hosts:
        return None
    return value
