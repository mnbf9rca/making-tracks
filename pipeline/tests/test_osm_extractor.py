import hashlib
import json
import pathlib

import pytest

from mt_pipeline import store
from mt_pipeline.extractors import osm


FIX = pathlib.Path(__file__).parent / "fixtures/osm/sample.osm"
CFG = {
    "historic": True,
    "tourism": ["attraction", "artwork", "viewpoint"],
    "memorial": True,
}


def _db(path):
    conn = store.connect(str(path) + ".db")
    store.init_schema(conn)
    return conn


def test_is_candidate_matches_key_wildcard_and_value_set():
    assert osm.is_candidate({"historic": "castle"}, CFG)
    assert osm.is_candidate({"tourism": "artwork"}, CFG)
    assert not osm.is_candidate({"tourism": "hotel"}, CFG)
    assert not osm.is_candidate({"amenity": "bench"}, CFG)


def test_bootstrap_tag_config_loads_and_is_minimal():
    cfg = osm.load_tag_config(
        pathlib.Path(__file__).parents[1] / "config/osm_candidate_tags.json"
    )
    assert cfg and "historic" in cfg
    assert cfg["tourism"] == ["attraction", "artwork", "viewpoint"]


def test_provenance_verifies_sha256_and_is_loud_on_mismatch(tmp_path):
    pbf = tmp_path / "uk.pbf"
    pbf.write_bytes(b"PBFDATA")
    sha = hashlib.sha256(b"PBFDATA").hexdigest()
    (tmp_path / "uk.pbf.meta.json").write_text(
        json.dumps(
            {
                "source_url": "u",
                "geofabrik_date": "2026-07-14",
                "sha256": sha,
                "size": 7,
            }
        )
    )
    osm.verify_provenance(pbf)

    (tmp_path / "uk.pbf.meta.json").write_text(json.dumps({"sha256": "deadbeef"}))
    with pytest.raises(osm.ProvenanceError):
        osm.verify_provenance(pbf)


def test_provenance_sidecar_must_be_self_describing(tmp_path):
    pbf = tmp_path / "uk.pbf"
    pbf.write_bytes(b"PBFDATA")
    sha = hashlib.sha256(b"PBFDATA").hexdigest()
    (tmp_path / "uk.pbf.meta.json").write_text(json.dumps({"sha256": sha}))

    with pytest.raises(osm.ProvenanceError):
        osm.verify_provenance(pbf)


def test_extractor_path_verifies_provenance_before_parsing(tmp_path):
    path = tmp_path / "sample.osm"
    path.write_text(FIX.read_text())
    (tmp_path / "sample.osm.meta.json").write_text(
        json.dumps(
            {
                "source_url": "https://download.geofabrik.de/test.osm.pbf",
                "geofabrik_date": "2026-07-14",
                "sha256": "deadbeef",
                "size": path.stat().st_size,
            }
        )
    )
    conn = _db(tmp_path / "w")

    with pytest.raises(osm.ProvenanceError):
        osm.OsmExtractor(CFG).extract("united-kingdom", path, conn, run_id="r1")
    assert conn.execute("SELECT COUNT(*) FROM source_records").fetchone()[0] == 0


def test_extracts_nodes_and_way_centroids_skips_noncandidate_and_relations(tmp_path):
    conn = _db(tmp_path / "w")

    count = osm.OsmExtractor(CFG).extract("united-kingdom", FIX, conn, run_id="r1")
    rows = conn.execute(
        "SELECT source_ref, name, lat, lon FROM source_records ORDER BY source_ref"
    ).fetchall()

    assert count == 2
    assert rows[0][0] == "osm:node/10"
    assert rows[1][0] == "osm:way/100"
    assert abs(rows[1][2] - 1.5) < 1e-9
    assert abs(rows[1][3] - 1.0) < 1e-9


def test_wikidata_tag_rides_in_props_as_the_a2_join_key(tmp_path):
    conn = _db(tmp_path / "w")

    osm.OsmExtractor(CFG).extract("united-kingdom", FIX, conn, run_id="r1")
    props = json.loads(
        conn.execute(
            "SELECT props_json FROM source_records WHERE source_ref='osm:node/10'"
        ).fetchone()[0]
    )

    assert props["wikidata"] == "Q42"
    assert props["historic"] == "memorial"


def test_osm_name_translation_tags_ride_in_bounded_props_for_search_index(tmp_path):
    path = tmp_path / "names.osm"
    path.write_text(
        _osm(
            '<node id="1" lat="1" lon="1" version="1">'
            '<tag k="historic" v="castle"/><tag k="name" v="Fort"/>'
            '<tag k="name:ms" v="Kota Lama"/>'
            '<tag k="name:zh" v="古堡"/>'
            '<tag k="alt_name" v="Benteng Lama; Old Fort"/>'
            '<tag k="int_name" v="International Fort"/></node>'
        )
    )
    conn = _db(tmp_path / "names")

    assert osm.OsmExtractor(CFG).extract("united-kingdom", path, conn, run_id="r1") == 1
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])

    assert props["name:ms"] == "Kota Lama"
    assert props["name:zh"] == "古堡"
    assert props["alt_name"] == "Benteng Lama; Old Fort"
    assert props["int_name"] == "International Fort"


def test_binary_pbf_parity_with_xml(tmp_path):
    import osmium

    pbf = tmp_path / "sample.pbf"
    writer = osmium.SimpleWriter(str(pbf))
    for node_id, lat, lon, tags in [
        (1, 0.0, 0.0, {}),
        (2, 0.0, 2.0, {}),
        (3, 2.0, 2.0, {}),
        (4, 4.0, 0.0, {}),
        (10, 51.5, -0.12, {"historic": "memorial", "name": "A Memorial", "wikidata": "Q42"}),
        (11, 51.4, -0.10, {"amenity": "bench"}),
    ]:
        writer.add_node(
            osmium.osm.mutable.Node(id=node_id, location=(lon, lat), tags=tags)
        )
    writer.add_way(
        osmium.osm.mutable.Way(
            id=100,
            nodes=[1, 2, 3, 4, 1],
            tags={"historic": "castle", "name": "A Castle"},
        )
    )
    writer.close()
    xml_conn = _db(tmp_path / "x")
    pbf_conn = _db(tmp_path / "y")

    osm.OsmExtractor(CFG).extract("united-kingdom", FIX, xml_conn, run_id="r1")
    osm.OsmExtractor(CFG).extract("united-kingdom", pbf, pbf_conn, run_id="r1")
    xml_rows = xml_conn.execute(
        "SELECT source_ref, name, lat, lon FROM source_records ORDER BY source_ref"
    ).fetchall()
    pbf_rows = pbf_conn.execute(
        "SELECT source_ref, name, lat, lon FROM source_records ORDER BY source_ref"
    ).fetchall()

    assert xml_rows == pbf_rows


def test_index_type_is_threaded_to_pyosmium(tmp_path):
    with pytest.raises(osm.OsmParseError):
        osm.OsmExtractor(CFG).extract(
            "united-kingdom",
            FIX,
            _db(tmp_path / "idx"),
            run_id="r1",
            index_type="not_a_real_osmium_index",
        )


def _osm(nodes_xml):
    return '<?xml version="1.0"?><osm version="0.6">' + nodes_xml + "</osm>"


def test_corrupt_file_is_a_loud_typed_osm_parse_error(tmp_path):
    over = tmp_path / "over.osm"
    over.write_text(
        _osm(
            '<node id="1" lat="1" lon="1" version="1">'
            f'<tag k="d" v="{"z" * 5000}"/></node>'
        )
    )
    with pytest.raises(osm.OsmParseError):
        osm.OsmExtractor(CFG).extract("united-kingdom", over, _db(tmp_path / "o"), run_id="r1")

    garbage = tmp_path / "g.pbf"
    garbage.write_bytes(b"not a real pbf")
    with pytest.raises(osm.OsmParseError):
        osm.OsmExtractor(CFG).extract("united-kingdom", garbage, _db(tmp_path / "g"), run_id="r1")


def test_too_many_candidates_is_a_loud_bounded_abort(tmp_path, monkeypatch):
    monkeypatch.setattr(osm, "MAX_CANDIDATE_RECORDS", 3)
    nodes = "".join(
        f'<node id="{index}" lat="1" lon="1" version="1">'
        '<tag k="historic" v="x"/><tag k="name" v="Many"/></node>'
        for index in range(10)
    )
    path = tmp_path / "many.osm"
    path.write_text(_osm(nodes))

    with pytest.raises(osm.TooManyCandidatesError):
        osm.OsmExtractor(CFG).extract("united-kingdom", path, _db(tmp_path / "m"), run_id="r1")


def test_too_many_tags_are_bounded(tmp_path):
    tags = (
        '<tag k="historic" v="x"/><tag k="name" v="Many Tags"/>'
        + "".join(
            f'<tag k="k{index}" v="v"/>'
            for index in range(osm.MAX_TAGS_PER_FEATURE + 50)
        )
    )
    path = tmp_path / "m.osm"
    path.write_text(
        _osm(f'<node id="1" lat="1" lon="1" version="1">{tags}</node>')
    )
    conn = _db(tmp_path / "d")

    osm.OsmExtractor(CFG).extract("united-kingdom", path, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])

    assert len(props) <= osm.MAX_TAGS_PER_FEATURE


def test_long_tag_key_is_truncated_at_the_edge(tmp_path):
    longkey = "k" * 150
    path = tmp_path / "lk.osm"
    path.write_text(
        _osm(
            '<node id="1" lat="1" lon="1" version="1">'
            '<tag k="historic" v="castle"/><tag k="name" v="LongKey"/>'
            f'<tag k="{longkey}" v="v"/></node>'
        )
    )
    conn = _db(tmp_path / "lk")

    osm.OsmExtractor(CFG).extract("united-kingdom", path, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])

    assert ("k" * osm.MAX_TAG_KEY_LEN) in props
    assert longkey not in props


def test_garbage_wikidata_tag_is_dropped_record_kept(tmp_path):
    path = tmp_path / "g.osm"
    path.write_text(
        _osm(
            '<node id="1" lat="1" lon="1" version="1">'
            '<tag k="historic" v="castle"/><tag k="name" v="Bad QID"/>'
            '<tag k="wikidata" v="Qwerty; drop"/></node>'
        )
    )
    conn = _db(tmp_path / "d")

    osm.OsmExtractor(CFG).extract("united-kingdom", path, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])

    assert "wikidata" not in props
    assert props["historic"] == "castle"


def test_offglobe_coordinate_is_skipped_in_handler(tmp_path):
    path = tmp_path / "o.osm"
    path.write_text(
        _osm(
            '<node id="1" lat="99" lon="1" version="1">'
            '<tag k="historic" v="x"/><tag k="name" v="Off Globe"/></node>'
        )
    )
    conn = _db(tmp_path / "d")

    assert osm.OsmExtractor(CFG).extract("united-kingdom", path, conn, run_id="r1") == 0


def test_parse_rejected_candidate_is_skipped_and_warned(tmp_path, caplog):
    path = tmp_path / "nameless.osm"
    path.write_text(
        _osm(
            '<node id="1" lat="1" lon="1" version="1">'
            '<tag k="historic" v="castle"/></node>'
        )
    )
    conn = _db(tmp_path / "nameless")

    assert osm.OsmExtractor(CFG).extract("united-kingdom", path, conn, run_id="r1") == 0
    assert any(
        "rejected 1 candidate record" in record.message.lower()
        for record in caplog.records
    )


def test_source_record_rejects_offglobe_coordinate_directly():
    from mt_pipeline import source_record

    with pytest.raises(source_record.SourceRecordError):
        source_record.parse(
            region="united-kingdom",
            source="osm",
            source_ref="osm:node/1",
            name="X",
            lat=99.0,
            lon=1.0,
            props={},
        )


def test_deterministic_same_file_same_records(tmp_path):
    first = _db(tmp_path / "a")
    second = _db(tmp_path / "b")

    osm.OsmExtractor(CFG).extract("united-kingdom", FIX, first, run_id="r1")
    osm.OsmExtractor(CFG).extract("united-kingdom", FIX, second, run_id="r2")
    query = "SELECT source_ref, lat, lon FROM source_records ORDER BY id"

    assert first.execute(query).fetchall() == second.execute(query).fetchall()


def test_provenance_absent_sidecar_proceeds_with_warning(tmp_path, caplog):
    pbf = tmp_path / "dev.pbf"
    pbf.write_bytes(b"x")

    osm.verify_provenance(pbf)

    assert any("provenance" in record.message.lower() for record in caplog.records)


def test_provenance_malformed_sidecar_is_a_typed_error_not_attributeerror(tmp_path):
    pbf = tmp_path / "uk.pbf"
    pbf.write_bytes(b"PBFDATA")
    meta = tmp_path / "uk.pbf.meta.json"

    meta.write_text('["not", "a", "dict"]')
    with pytest.raises(osm.ProvenanceError):
        osm.verify_provenance(pbf)

    meta.write_text(json.dumps({"source_url": "u"}))
    with pytest.raises(osm.ProvenanceError):
        osm.verify_provenance(pbf)

    meta.write_bytes(b"{" + b" " * (osm.MAX_SIDECAR_BYTES + 10))
    with pytest.raises(osm.ProvenanceError):
        osm.verify_provenance(pbf)
