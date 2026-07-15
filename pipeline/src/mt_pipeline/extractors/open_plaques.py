"""Open Plaques extractor over local JSON snapshots."""

from __future__ import annotations

import json
import logging
import pathlib
import re

from .. import source_record
from . import _snapshot

MAX_NAME_LEN = 300

_PLAQUE_ID = re.compile(r"[0-9]+")
_COUNTRY_BY_REGION = {
    "uk": "gb",
    "malaysia": "my",
}
_log = logging.getLogger(__name__)


def _country_code(item) -> str | None:
    area = item.get("area")
    if not isinstance(area, dict):
        return None
    country = area.get("country")
    if not isinstance(country, dict):
        return None
    alpha2 = country.get("alpha2")
    if not isinstance(alpha2, str):
        return None
    return alpha2.lower()


class OpenPlaquesExtractor:
    """Config-free extractor; URL and attribution live in a1d_sources.json."""

    def extract(self, region: str, snapshot_path, conn, *, run_id: str) -> int:
        _snapshot.check_snapshot_size(snapshot_path)
        _snapshot.verify_sha256_sidecar(snapshot_path)
        try:
            data = json.loads(pathlib.Path(snapshot_path).read_text())
        except (ValueError, RecursionError) as exc:
            raise _snapshot.SnapshotParseError(
                f"could not parse Open Plaques JSON {snapshot_path}: {exc}"
            ) from exc
        except OSError as exc:
            raise _snapshot.SnapshotParseError(
                f"could not read Open Plaques snapshot {snapshot_path}: {exc}"
            ) from exc
        if not isinstance(data, list):
            raise _snapshot.SnapshotParseError("Open Plaques dump must be a JSON array")

        records: dict[str, source_record.SourceRecord] = {}
        dropped = 0
        parse_dropped = 0
        expected_country = _COUNTRY_BY_REGION.get(region)
        for item in data:
            try:
                if not isinstance(item, dict):
                    dropped += 1
                    continue
                if expected_country and _country_code(item) != expected_country:
                    dropped += 1
                    continue
                raw_id = str(item.get("id", ""))
                if not _PLAQUE_ID.fullmatch(raw_id):
                    dropped += 1
                    continue
                source_ref = f"plaque:openplaques/{raw_id}"
                if source_ref in records:
                    continue
                lat = item.get("latitude")
                lon = item.get("longitude")
                if lat is None or lon is None:
                    dropped += 1
                    continue

                title = item.get("title")
                subject = item.get("lead_subject_name")
                subjects = item.get("subjects")
                if not subject and isinstance(subjects, list) and subjects:
                    first_subject = subjects[0]
                    if isinstance(first_subject, dict):
                        subject = first_subject.get("full_name") or first_subject.get(
                            "title"
                        )
                    elif isinstance(first_subject, str):
                        subject = first_subject
                inscription = item.get("inscription")
                name = next(
                    (
                        str(value)[:MAX_NAME_LEN]
                        for value in (title, subject, inscription)
                        if isinstance(value, str) and value.strip()
                    ),
                    "",
                )

                props = {}
                if isinstance(inscription, str):
                    props["inscription"] = inscription
                if isinstance(subject, str):
                    props["lead_subject"] = subject
                try:
                    record = source_record.parse(
                        region=region,
                        source="plaque",
                        source_ref=source_ref,
                        name=name,
                        lat=lat,
                        lon=lon,
                        props=props,
                    )
                except source_record.SourceRecordError:
                    parse_dropped += 1
                    continue
                records[source_ref] = record
            except Exception as exc:
                dropped += 1
                _log.debug("skipped plaque: %s: %s", type(exc).__name__, exc)

        if dropped or parse_dropped:
            _log.warning(
                "Open Plaques extract %s: skipped %d record(s)", snapshot_path, dropped
            )
            if parse_dropped:
                _log.warning(
                    "Open Plaques extract %s: dropped %d record(s) at source-record validation",
                    snapshot_path,
                    parse_dropped,
                )

        count = 0
        for source_ref in sorted(records):
            source_record.persist(conn, records[source_ref], run_id=run_id)
            count += 1
        return count
