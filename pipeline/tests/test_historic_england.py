import json
import pathlib

import pytest

from mt_pipeline import store
from mt_pipeline.extractors import historic_england as he


def _db(path):
    conn = store.connect(str(path) + ".db")
    store.init_schema(conn)
    return conn


FIX = pathlib.Path(__file__).parent / "fixtures/registers/he_sample.geojson"


def test_extracts_point_and_polygon_centroid_with_grade(tmp_path):
    conn = _db(tmp_path / "w")

    count = he.HistoricEnglandExtractor().extract("uk", FIX, conn, run_id="r1")
    rows = conn.execute(
        "SELECT source_ref, name, lat, lon FROM source_records ORDER BY source_ref"
    ).fetchall()

    assert count == 2
    assert rows[0][0] == "hehle:1000001"
    assert rows[1][0] == "hehle:1000002"
    assert abs(rows[0][2] - 51.5) < 1e-9
    assert abs(rows[0][3] + 0.12) < 1e-9
    assert abs(rows[1][2] - 1.0) < 1e-9
    assert abs(rows[1][3] - 1.5) < 1e-9


def test_grade_rides_in_props_as_the_heritage_signal(tmp_path):
    conn = _db(tmp_path / "w")

    he.HistoricEnglandExtractor().extract("uk", FIX, conn, run_id="r1")
    props = json.loads(
        conn.execute(
            "SELECT props_json FROM source_records WHERE source_ref='hehle:1000001'"
        ).fetchone()[0]
    )

    assert props["grade"] == "I"


def test_numeric_list_entry_stringifies_to_digits(tmp_path):
    feature = (
        '{"type":"Feature","properties":{"ListEntry":1000005,'
        '"Name":"Numeric Id","Grade":"II"},'
        '"geometry":{"type":"Point","coordinates":[-0.1,51.4]}}'
    )
    path = tmp_path / "num.geojson"
    path.write_text('{"type":"FeatureCollection","features":[' + feature + "]}")
    conn = _db(tmp_path / "num")

    assert he.HistoricEnglandExtractor().extract("uk", path, conn, run_id="r1") == 1
    assert (
        conn.execute("SELECT source_ref FROM source_records").fetchone()[0]
        == "hehle:1000005"
    )


def test_a1d_sources_config_carries_ogl_attribution():
    cfg = json.loads(
        (pathlib.Path(__file__).parents[1] / "config/a1d_sources.json").read_text()
    )

    assert "Open Government Licence" in cfg["historic_england"]["attribution"]
    assert cfg["historic_england"]["license"] == "OGL-3.0"
    assert "outSR=4326" in cfg["historic_england"]["url"]
    assert cfg["historic_england"]["max_bytes"] > 167_768_010
    assert cfg["open_plaques"]["license"] == "PDDL-1.0"


def _geojson(features):
    return '{"type":"FeatureCollection","features":[' + ",".join(features) + "]}"


def test_corrupt_geojson_is_a_loud_typed_error(tmp_path):
    bad = tmp_path / "b.geojson"
    bad.write_text('{"type":"FeatureCollection","features":[ NOT JSON')

    with pytest.raises(he._snapshot.SnapshotParseError):
        he.HistoricEnglandExtractor().extract("uk", bad, _db(tmp_path / "b"), run_id="r1")


def test_wrong_shape_valid_json_is_a_loud_typed_error(tmp_path):
    bad = tmp_path / "w.geojson"
    bad.write_text('{"type":"Topology","objects":{}}')

    with pytest.raises(he._snapshot.SnapshotParseError):
        he.HistoricEnglandExtractor().extract("uk", bad, _db(tmp_path / "w"), run_id="r1")


def test_non_array_features_is_a_loud_typed_error(tmp_path):
    bad = tmp_path / "features.geojson"
    bad.write_text('{"type":"FeatureCollection","features":{}}')

    with pytest.raises(he._snapshot.SnapshotParseError):
        he.HistoricEnglandExtractor().extract("uk", bad, _db(tmp_path / "f"), run_id="r1")


def test_arcgis_exceeded_transfer_limit_is_rejected(tmp_path):
    bad = tmp_path / "partial.geojson"
    bad.write_text(
        '{"type":"FeatureCollection","properties":{"exceededTransferLimit":true},'
        '"features":[]}'
    )

    with pytest.raises(he._snapshot.SnapshotParseError, match="exceededTransferLimit"):
        he.HistoricEnglandExtractor().extract("uk", bad, _db(tmp_path / "p"), run_id="r1")


def test_multipoint_uses_mean_coordinate(tmp_path):
    feature = (
        '{"type":"Feature","properties":{"ListEntry":"1000015","Name":"Multi"},'
        '"geometry":{"type":"MultiPoint","coordinates":[[-2.0,51.0],[-4.0,53.0]]}}'
    )
    path = tmp_path / "mp.geojson"
    path.write_text(_geojson([feature]))
    conn = _db(tmp_path / "mp")

    assert he.HistoricEnglandExtractor().extract("uk", path, conn, run_id="r1") == 1
    lat, lon = conn.execute("SELECT lat, lon FROM source_records").fetchone()
    assert abs(lat - 52.0) < 1e-9
    assert abs(lon + 3.0) < 1e-9


def test_live_he_wgs84_multipoint_shape_is_accepted(tmp_path):
    feature = (
        '{"type":"Feature","properties":{"ListEntry":"1021466",'
        '"Name":"20 and 20A Whitbourne Springs","Grade":"II"},'
        '"geometry":{"type":"MultiPoint",'
        '"coordinates":[[-2.23911708088334,51.19883105846]]}}'
    )
    path = tmp_path / "live.geojson"
    path.write_text(
        '{"type":"FeatureCollection",'
        '"crs":{"type":"name","properties":{"name":"EPSG:4326"}},'
        '"features":[' + feature + "]}"
    )
    conn = _db(tmp_path / "live")

    assert he.HistoricEnglandExtractor().extract("uk", path, conn, run_id="r1") == 1
    lat, lon = conn.execute("SELECT lat, lon FROM source_records").fetchone()
    assert abs(lat - 51.19883105846) < 1e-12
    assert abs(lon + 2.23911708088334) < 1e-12


def test_epsg_27700_snapshot_is_rejected(tmp_path):
    feature = (
        '{"type":"Feature","properties":{"ListEntry":"1000016","Name":"BNG"},'
        '"geometry":{"type":"MultiPoint",'
        '"coordinates":[[383388.770967568,144429.456597934]]}}'
    )
    path = tmp_path / "bng.geojson"
    path.write_text(
        '{"type":"FeatureCollection",'
        '"crs":{"type":"name","properties":{"name":"EPSG:27700"}},'
        '"features":[' + feature + "]}"
    )
    with pytest.raises(he._snapshot.SnapshotParseError, match="EPSG:27700"):
        he.HistoricEnglandExtractor().extract(
            "uk", path, _db(tmp_path / "bng"), run_id="r1"
        )


def test_hostile_huge_grade_does_not_crash_record_kept(tmp_path):
    feature = (
        '{"type":"Feature","properties":{"ListEntry":"1000009","Name":"X","Grade":"'
        + "z" * 5000
        + '"},"geometry":{"type":"Point","coordinates":[-0.1,51.4]}}'
    )
    path = tmp_path / "g.geojson"
    path.write_text(_geojson([feature]))
    conn = _db(tmp_path / "g")

    assert he.HistoricEnglandExtractor().extract("uk", path, conn, run_id="r1") == 1
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert len(props["grade"]) == 300


def test_oversized_ring_feature_is_skipped_not_crashed(tmp_path):
    huge = ",".join("[0.0,0.0]" for _ in range(he.MAX_RING_POINTS + 5))
    bad = (
        '{"type":"Feature","properties":{"ListEntry":"1000013","Name":"Huge"},'
        '"geometry":{"type":"Polygon","coordinates":[[' + huge + "]]}}"
    )
    good = (
        '{"type":"Feature","properties":{"ListEntry":"1000014","Name":"Ok"},'
        '"geometry":{"type":"Point","coordinates":[-0.1,51.4]}}'
    )
    path = tmp_path / "r.geojson"
    path.write_text(_geojson([bad, good]))
    conn = _db(tmp_path / "r")

    assert he.HistoricEnglandExtractor().extract("uk", path, conn, run_id="r1") == 1


def test_malformed_geometry_feature_is_skipped_not_crashed(tmp_path):
    good = (
        '{"type":"Feature","properties":{"ListEntry":"1000010","Name":"Good"},'
        '"geometry":{"type":"Point","coordinates":[-0.1,51.4]}}'
    )
    bad = (
        '{"type":"Feature","properties":{"ListEntry":"1000011","Name":"NoGeom"},'
        '"geometry":null}'
    )
    path = tmp_path / "m.geojson"
    path.write_text(_geojson([bad, good]))
    conn = _db(tmp_path / "m")

    assert he.HistoricEnglandExtractor().extract("uk", path, conn, run_id="r1") == 1


def test_polygon_centroid_is_arithmetic_mean_not_bbox(tmp_path):
    feature = (
        '{"type":"Feature","properties":{"ListEntry":"1000012","Name":"Poly"},'
        '"geometry":{"type":"Polygon","coordinates":[[[0.0,0.0],[0.0,2.0],'
        "[2.0,2.0],[4.0,0.0],[0.0,0.0]]]}}"
    )
    path = tmp_path / "p.geojson"
    path.write_text(_geojson([feature]))
    conn = _db(tmp_path / "p")

    he.HistoricEnglandExtractor().extract("uk", path, conn, run_id="r1")
    lon = conn.execute(
        "SELECT lon FROM source_records WHERE source_ref='hehle:1000012'"
    ).fetchone()[0]
    assert abs(lon - 1.5) < 1e-9


def test_deterministic_same_file_same_records(tmp_path):
    first = _db(tmp_path / "a")
    second = _db(tmp_path / "b")

    he.HistoricEnglandExtractor().extract("uk", FIX, first, run_id="r1")
    he.HistoricEnglandExtractor().extract("uk", FIX, second, run_id="r2")
    query = "SELECT source_ref, lat, lon FROM source_records ORDER BY id"

    assert first.execute(query).fetchall() == second.execute(query).fetchall()
