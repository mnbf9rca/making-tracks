"""Historic England NHLE extractor over GeoJSON snapshots."""

from __future__ import annotations

import json
import logging
import math
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
    if "27700" in crs:
        # Verified 2026-07-15: Historic England's Hub export endpoint can
        # return EPSG:27700 even when requested with outSR=4326.
        return "bng"
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


def _bng_to_wgs84(easting: float, northing: float) -> tuple[float, float]:
    airy_a = 6377563.396
    airy_b = 6356256.909
    f0 = 0.9996012717
    lat0 = math.radians(49)
    lon0 = math.radians(-2)
    n0 = -100000.0
    e0 = 400000.0
    e2 = 1 - (airy_b * airy_b) / (airy_a * airy_a)
    n = (airy_a - airy_b) / (airy_a + airy_b)

    lat = lat0
    meridional = 0.0
    while northing - n0 - meridional >= 0.00001:
        lat += (northing - n0 - meridional) / (airy_a * f0)
        ma = (1 + n + (5 / 4) * n**2 + (5 / 4) * n**3) * (lat - lat0)
        mb = (3 * n + 3 * n**2 + (21 / 8) * n**3) * math.sin(lat - lat0) * math.cos(lat + lat0)
        mc = ((15 / 8) * n**2 + (15 / 8) * n**3) * math.sin(2 * (lat - lat0)) * math.cos(2 * (lat + lat0))
        md = (35 / 24) * n**3 * math.sin(3 * (lat - lat0)) * math.cos(3 * (lat + lat0))
        meridional = airy_b * f0 * (ma - mb + mc - md)

    sin_lat = math.sin(lat)
    cos_lat = math.cos(lat)
    tan_lat = math.tan(lat)
    nu = airy_a * f0 / math.sqrt(1 - e2 * sin_lat * sin_lat)
    rho = airy_a * f0 * (1 - e2) / (1 - e2 * sin_lat * sin_lat) ** 1.5
    eta2 = nu / rho - 1
    de = easting - e0
    sec_lat = 1 / cos_lat

    vii = tan_lat / (2 * rho * nu)
    viii = tan_lat / (24 * rho * nu**3) * (5 + 3 * tan_lat**2 + eta2 - 9 * tan_lat**2 * eta2)
    ix = tan_lat / (720 * rho * nu**5) * (61 + 90 * tan_lat**2 + 45 * tan_lat**4)
    x = sec_lat / nu
    xi = sec_lat / (6 * nu**3) * (nu / rho + 2 * tan_lat**2)
    xii = sec_lat / (120 * nu**5) * (5 + 28 * tan_lat**2 + 24 * tan_lat**4)
    xiia = sec_lat / (5040 * nu**7) * (61 + 662 * tan_lat**2 + 1320 * tan_lat**4 + 720 * tan_lat**6)

    lat_osgb = lat - vii * de**2 + viii * de**4 - ix * de**6
    lon_osgb = lon0 + x * de - xi * de**3 + xii * de**5 - xiia * de**7
    return _osgb36_to_wgs84(lat_osgb, lon_osgb)


def _osgb36_to_wgs84(lat: float, lon: float) -> tuple[float, float]:
    airy_a = 6377563.396
    airy_b = 6356256.909
    wgs_a = 6378137.000
    wgs_b = 6356752.3141
    e2 = 1 - (airy_b * airy_b) / (airy_a * airy_a)
    sin_lat = math.sin(lat)
    cos_lat = math.cos(lat)
    sin_lon = math.sin(lon)
    cos_lon = math.cos(lon)
    nu = airy_a / math.sqrt(1 - e2 * sin_lat * sin_lat)
    x1 = nu * cos_lat * cos_lon
    y1 = nu * cos_lat * sin_lon
    z1 = ((1 - e2) * nu) * sin_lat

    tx, ty, tz = 446.448, -125.157, 542.060
    scale = 1 + 20.4894 * 1e-6
    rx = math.radians(0.1502 / 3600)
    ry = math.radians(0.2470 / 3600)
    rz = math.radians(0.8421 / 3600)
    x2 = tx + x1 * scale - y1 * rz + z1 * ry
    y2 = ty + x1 * rz + y1 * scale - z1 * rx
    z2 = tz - x1 * ry + y1 * rx + z1 * scale

    e2_wgs = 1 - (wgs_b * wgs_b) / (wgs_a * wgs_a)
    p = math.sqrt(x2 * x2 + y2 * y2)
    lat_wgs = math.atan2(z2, p * (1 - e2_wgs))
    prev = 0.0
    while abs(lat_wgs - prev) > 1e-12:
        prev = lat_wgs
        nu = wgs_a / math.sqrt(1 - e2_wgs * math.sin(lat_wgs) ** 2)
        lat_wgs = math.atan2(z2 + e2_wgs * nu * math.sin(lat_wgs), p)
    lon_wgs = math.atan2(y2, x2)
    return math.degrees(lat_wgs), math.degrees(lon_wgs)


def _latlon_from_xy(coord, coord_ref: str):
    x = float(coord[0])
    y = float(coord[1])
    if coord_ref == "bng":
        return _bng_to_wgs84(x, y)
    return y, x


def _point_of(geometry, coord_ref: str):
    gtype = geometry["type"]
    coords = geometry["coordinates"]
    if gtype == "Point":
        return _latlon_from_xy(coords, coord_ref)
    if gtype == "MultiPoint":
        return _latlon_from_xy(_mean_xy(coords), coord_ref)
    if gtype == "Polygon":
        return _latlon_from_xy(_ring_centroid(coords[0]), coord_ref)
    if gtype == "MultiPolygon":
        return _latlon_from_xy(_ring_centroid(coords[0][0]), coord_ref)
    raise ValueError(f"unsupported geometry {gtype}")


class HistoricEnglandExtractor:
    def extract(self, region: str, snapshot_path, conn, *, run_id: str) -> int:
        _snapshot.check_snapshot_size(snapshot_path)
        _snapshot.verify_sha256_sidecar(snapshot_path)
        coord_ref = _geojson_coord_ref(snapshot_path)
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
                        lat, lon = _point_of(feature["geometry"], coord_ref)
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
