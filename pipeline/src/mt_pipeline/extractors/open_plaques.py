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
_log = logging.getLogger(__name__)


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

        records: dict[str, dict] = {}
        dropped = 0
        for item in data:
            try:
                if not isinstance(item, dict):
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
                records[source_ref] = {
                    "lat": lat,
                    "lon": lon,
                    "name": name,
                    "props": props,
                }
            except Exception as exc:
                dropped += 1
                _log.debug("skipped plaque: %s: %s", type(exc).__name__, exc)

        if dropped:
            _log.warning(
                "Open Plaques extract %s: skipped %d record(s)", snapshot_path, dropped
            )

        count = 0
        for source_ref in sorted(records):
            item = records[source_ref]
            try:
                record = source_record.parse(
                    region=region,
                    source="plaque",
                    source_ref=source_ref,
                    name=item["name"],
                    lat=item["lat"],
                    lon=item["lon"],
                    props=item["props"],
                )
            except source_record.SourceRecordError:
                continue
            source_record.persist(conn, record, run_id=run_id)
            count += 1
        return count
