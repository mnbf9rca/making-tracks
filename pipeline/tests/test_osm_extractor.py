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


def test_extracts_nodes_and_way_centroids_skips_noncandidate_and_relations(tmp_path):
    conn = _db(tmp_path / "w")

    count = osm.OsmExtractor(CFG).extract("uk", FIX, conn, run_id="r1")
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

    osm.OsmExtractor(CFG).extract("uk", FIX, conn, run_id="r1")
    props = json.loads(
        conn.execute(
            "SELECT props_json FROM source_records WHERE source_ref='osm:node/10'"
        ).fetchone()[0]
    )

    assert props["wikidata"] == "Q42"
    assert props["historic"] == "memorial"


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

    osm.OsmExtractor(CFG).extract("uk", FIX, xml_conn, run_id="r1")
    osm.OsmExtractor(CFG).extract("uk", pbf, pbf_conn, run_id="r1")
    xml_rows = xml_conn.execute(
        "SELECT source_ref, name, lat, lon FROM source_records ORDER BY source_ref"
    ).fetchall()
    pbf_rows = pbf_conn.execute(
        "SELECT source_ref, name, lat, lon FROM source_records ORDER BY source_ref"
    ).fetchall()

    assert xml_rows == pbf_rows


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
