"""Historic England NHLE extractor over GeoJSON snapshots."""

from __future__ import annotations

import logging
import re

import ijson

from .. import source_record
from . import _snapshot

MAX_NAME_LEN = 300
MAX_RING_POINTS = 100_000

# Confirmed 2026-07-15 against Historic England's ArcGIS item
# 767f279327a24845bf47dfe5eae9862b. Listed building point layer 0 and polygon
# layer 3 expose popup field names ListEntry, Name, and Grade.
HE_ID_KEY = "ListEntry"
HE_NAME_KEY = "Name"
HE_GRADE_KEY = "Grade"

_LIST_ENTRY = re.compile(r"[0-9]+")
_log = logging.getLogger(__name__)


def _ring_centroid(ring):
    if len(ring) > MAX_RING_POINTS:
        raise ValueError(f"ring too large: {len(ring)} > {MAX_RING_POINTS}")
    points = ring[:-1] if len(ring) >= 2 and ring[0] == ring[-1] else ring
    if not points:
        raise ValueError("empty ring")
    return (
        sum(point[1] for point in points) / len(points),
        sum(point[0] for point in points) / len(points),
    )


def _point_of(geometry):
    gtype = geometry["type"]
    coords = geometry["coordinates"]
    if gtype == "Point":
        return coords[1], coords[0]
    if gtype == "Polygon":
        return _ring_centroid(coords[0])
    if gtype == "MultiPolygon":
        return _ring_centroid(coords[0][0])
    raise ValueError(f"unsupported geometry {gtype}")


class HistoricEnglandExtractor:
    def extract(self, region: str, snapshot_path, conn, *, run_id: str) -> int:
        _snapshot.check_snapshot_size(snapshot_path)
        _snapshot.verify_sha256_sidecar(snapshot_path)
        records: dict[str, dict] = {}
        dropped = 0
        try:
            with open(snapshot_path, "rb") as top:
                if next(ijson.items(top, "type"), None) != "FeatureCollection":
                    raise _snapshot.SnapshotParseError(
                        f"{snapshot_path} is not a GeoJSON FeatureCollection"
                    )
            with open(snapshot_path, "rb") as stream:
                for feature in ijson.items(stream, "features.item"):
                    try:
                        props = feature.get("properties") or {}
                        raw_id = str(props.get(HE_ID_KEY, ""))
                        if not _LIST_ENTRY.fullmatch(raw_id):
                            dropped += 1
                            continue
                        source_ref = f"hehle:{raw_id}"
                        if source_ref in records:
                            continue
                        lat, lon = _point_of(feature["geometry"])
                        name = str(props.get(HE_NAME_KEY) or "")[:MAX_NAME_LEN]
                        out = {}
                        grade = props.get(HE_GRADE_KEY)
                        if isinstance(grade, str):
                            out["grade"] = grade
                        records[source_ref] = {
                            "lat": lat,
                            "lon": lon,
                            "name": name,
                            "props": out,
                        }
                    except Exception as exc:
                        dropped += 1
                        _log.debug("skipped HE feature: %s: %s", type(exc).__name__, exc)
        except _snapshot.SnapshotError:
            raise
        except (ijson.JSONError, ValueError) as exc:
            raise _snapshot.SnapshotParseError(
                f"could not parse NHLE GeoJSON {snapshot_path}: {exc}"
            ) from exc
        except OSError as exc:
            raise _snapshot.SnapshotParseError(
                f"could not read NHLE snapshot {snapshot_path}: {exc}"
            ) from exc

        if dropped:
            _log.warning("HE extract %s: skipped %d malformed feature(s)", snapshot_path, dropped)

        count = 0
        for source_ref in sorted(records):
            item = records[source_ref]
            try:
                record = source_record.parse(
                    region=region,
                    source="hehle",
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
