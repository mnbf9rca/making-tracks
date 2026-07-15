"""Historic England NHLE extractor over GeoJSON snapshots."""

from __future__ import annotations

import json
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


def _coord_ref(crs_name):
    if crs_name is None:
        return "wgs84"
    crs = str(crs_name).lower()
    if "4326" in crs or "crs84" in crs:
        return "wgs84"
    raise _snapshot.SnapshotParseError(
        f"unsupported NHLE coordinate reference: {crs_name}"
    )


def _geojson_coord_ref(snapshot_path) -> str:
    top_type = None
    features_seen = False
    exceeded_transfer_limit = False
    crs_name = None
    with open(snapshot_path, "rb") as stream:
        for prefix, event, value in ijson.parse(stream):
            if prefix == "type" and event == "string":
                top_type = value
            elif prefix == "properties.exceededTransferLimit" and event == "boolean":
                # Defense in depth for accidental ArcGIS query snapshots. Normal
                # acquisition uses the full Hub export, requested as WGS84 GeoJSON.
                exceeded_transfer_limit = exceeded_transfer_limit or bool(value)
            elif prefix == "crs.properties.name" and event == "string":
                crs_name = value
            elif prefix == "features":
                if event != "start_array":
                    raise _snapshot.SnapshotParseError(
                        f"{snapshot_path} has non-array GeoJSON features"
                    )
                features_seen = True
                break

    if top_type != "FeatureCollection":
        raise _snapshot.SnapshotParseError(
            f"{snapshot_path} is not a GeoJSON FeatureCollection"
        )
    if exceeded_transfer_limit:
        raise _snapshot.SnapshotParseError(
            f"{snapshot_path} is an incomplete ArcGIS response: exceededTransferLimit"
        )
    if not features_seen:
        raise _snapshot.SnapshotParseError(f"{snapshot_path} lacks GeoJSON features")
    return _coord_ref(crs_name)


def _mean_xy(points):
    if not points:
        raise ValueError("empty coordinate sequence")
    return (
        sum(point[0] for point in points) / len(points),
        sum(point[1] for point in points) / len(points),
    )


def _ring_centroid(ring):
    if len(ring) > MAX_RING_POINTS:
        raise ValueError(f"ring too large: {len(ring)} > {MAX_RING_POINTS}")
    points = ring[:-1] if len(ring) >= 2 and ring[0] == ring[-1] else ring
    return _mean_xy(points)


def _latlon_from_xy(coord):
    x = float(coord[0])
    y = float(coord[1])
    return y, x


def _point_of(geometry):
    gtype = geometry["type"]
    coords = geometry["coordinates"]
    if gtype == "Point":
        return _latlon_from_xy(coords)
    if gtype == "MultiPoint":
        return _latlon_from_xy(_mean_xy(coords))
    if gtype == "Polygon":
        return _latlon_from_xy(_ring_centroid(coords[0]))
    if gtype == "MultiPolygon":
        return _latlon_from_xy(_ring_centroid(coords[0][0]))
    raise ValueError(f"unsupported geometry {gtype}")


class HistoricEnglandExtractor:
    def extract(self, region: str, snapshot_path, conn, *, run_id: str) -> int:
        _snapshot.check_snapshot_size(snapshot_path)
        _snapshot.verify_sha256_sidecar(snapshot_path)
        _geojson_coord_ref(snapshot_path)
        dropped = 0
        parse_dropped = 0
        conn.execute("DROP TABLE IF EXISTS _mt_he_records")
        conn.execute(
            """
            CREATE TEMP TABLE _mt_he_records (
                source_ref TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                lat REAL NOT NULL,
                lon REAL NOT NULL,
                props_json TEXT NOT NULL
            )
            """
        )
        try:
            with open(snapshot_path, "rb") as stream:
                for feature in ijson.items(stream, "features.item"):
                    try:
                        props = feature.get("properties") or {}
                        raw_id = str(props.get(HE_ID_KEY, ""))
                        if not _LIST_ENTRY.fullmatch(raw_id):
                            dropped += 1
                            continue
                        source_ref = f"hehle:{raw_id}"
                        lat, lon = _point_of(feature["geometry"])
                        name = str(props.get(HE_NAME_KEY) or "")[:MAX_NAME_LEN]
                        out = {}
                        grade = props.get(HE_GRADE_KEY)
                        if isinstance(grade, str):
                            out["grade"] = grade
                        try:
                            record = source_record.parse(
                                region=region,
                                source="hehle",
                                source_ref=source_ref,
                                name=name,
                                lat=lat,
                                lon=lon,
                                props=out,
                            )
                        except source_record.SourceRecordError:
                            parse_dropped += 1
                            continue
                        conn.execute(
                            """
                            INSERT OR IGNORE INTO _mt_he_records
                                (source_ref, name, lat, lon, props_json)
                            VALUES (?, ?, ?, ?, ?)
                            """,
                            (
                                record.source_ref,
                                record.name,
                                record.lat,
                                record.lon,
                                json.dumps(
                                    record.props,
                                    sort_keys=True,
                                    ensure_ascii=False,
                                    allow_nan=False,
                                ),
                            ),
                        )
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

        if dropped or parse_dropped:
            _log.warning(
                "HE extract %s: skipped %d malformed feature(s)",
                snapshot_path,
                dropped,
            )
            if parse_dropped:
                _log.warning(
                    "HE extract %s: dropped %d feature(s) at source-record validation",
                    snapshot_path,
                    parse_dropped,
                )

        count = 0
        for source_ref, name, lat, lon, props_json in conn.execute(
            """
            SELECT source_ref, name, lat, lon, props_json
            FROM _mt_he_records
            ORDER BY source_ref
            """
        ):
            record = source_record.SourceRecord(
                region=region,
                source="hehle",
                source_ref=source_ref,
                name=name,
                lat=lat,
                lon=lon,
                props=json.loads(props_json),
            )
            source_record.persist(conn, record, run_id=run_id)
            count += 1
        conn.execute("DROP TABLE IF EXISTS _mt_he_records")
        return count
