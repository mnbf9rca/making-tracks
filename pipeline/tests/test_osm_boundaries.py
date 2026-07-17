import json

import osmium

from mt_pipeline import store
from mt_pipeline.extractors import osm


def _write_boundary_fixture(path):
    writer = osmium.SimpleWriter(str(path))
    try:
        for node_id, lon, lat in [
            (1, 0.0, 0.0),
            (2, 0.1, 0.0),
            (3, 0.1, 0.1),
            (4, 0.0, 0.1),
        ]:
            writer.add_node(
                osmium.osm.mutable.Node(id=node_id, location=(lon, lat))
            )
        writer.add_way(
            osmium.osm.mutable.Way(
                id=10,
                nodes=[1, 2, 3, 4, 1],
            )
        )
        writer.add_relation(
            osmium.osm.mutable.Relation(
                id=100,
                members=[("w", 10, "outer")],
                tags={
                    "type": "boundary",
                    "boundary": "administrative",
                    "admin_level": "6",
                    "name": "Tiny County",
                    "name:ms": "Daerah Tiny",
                    "wikidata": "Q123",
                },
            )
        )
    finally:
        writer.close()


def test_osm_extractor_captures_configured_admin_boundary_areas(tmp_path):
    pbf = tmp_path / "boundary.osm.pbf"
    _write_boundary_fixture(pbf)
    conn = store.connect(tmp_path / "work.db")
    store.init_schema(conn)

    count = osm.OsmExtractor(tag_config={}).extract(
        "uk",
        pbf,
        conn,
        run_id="r1",
        zone_levels={6: "county"},
    )

    assert count == 0
    row = conn.execute(
        """
        SELECT zone_id, osm_relation_id, admin_level, level_name, name,
               name_translations_json, wikidata, bbox_json, geometry_json, run_id
        FROM zone_boundaries
        """
    ).fetchone()
    assert row[:7] == (
        "osm_r100",
        100,
        6,
        "county",
        "Tiny County",
        '{"ms":"Daerah Tiny"}',
        "Q123",
    )
    assert json.loads(row[7]) == [0.0, 0.0, 0.1, 0.1]
    assert json.loads(row[8]) == {
        "type": "MultiPolygon",
        "coordinates": [[[[0.0, 0.0], [0.1, 0.0], [0.1, 0.1], [0.0, 0.1], [0.0, 0.0]]]],
    }
    assert row[9] == "r1"


def test_osm_extractor_ignores_admin_levels_not_declared_for_zones(tmp_path):
    pbf = tmp_path / "boundary.osm.pbf"
    _write_boundary_fixture(pbf)
    conn = store.connect(tmp_path / "work.db")
    store.init_schema(conn)

    osm.OsmExtractor(tag_config={}).extract(
        "uk",
        pbf,
        conn,
        run_id="r1",
        zone_levels={4: "region"},
    )

    assert conn.execute("SELECT COUNT(*) FROM zone_boundaries").fetchone()[0] == 0


def test_osm_boundary_extractor_caps_translations(tmp_path):
    pbf = tmp_path / "boundary.osm.pbf"
    writer = osmium.SimpleWriter(str(pbf))
    try:
        for node_id, lon, lat in [
            (1, 0.0, 0.0),
            (2, 0.1, 0.0),
            (3, 0.1, 0.1),
            (4, 0.0, 0.1),
        ]:
            writer.add_node(osmium.osm.mutable.Node(id=node_id, location=(lon, lat)))
        writer.add_way(osmium.osm.mutable.Way(id=10, nodes=[1, 2, 3, 4, 1]))
        translation_tags = {
            f"name:{chr(97 + (idx // 26))}{chr(97 + (idx % 26))}": f"Name {idx}"
            for idx in range(40)
        }
        writer.add_relation(
            osmium.osm.mutable.Relation(
                id=100,
                members=[("w", 10, "outer")],
                tags={
                    "type": "boundary",
                    "boundary": "administrative",
                    "admin_level": "6",
                    "name": "Tiny County",
                    **translation_tags,
                },
            )
        )
    finally:
        writer.close()
    conn = store.connect(tmp_path / "work.db")
    store.init_schema(conn)

    osm.OsmExtractor(tag_config={}).extract(
        "uk",
        pbf,
        conn,
        run_id="r1",
        zone_levels={6: "county"},
    )

    raw = conn.execute("SELECT name_translations_json FROM zone_boundaries").fetchone()[0]
    assert len(json.loads(raw)) == 32


def test_osm_boundary_extractor_drops_oversized_geometry(tmp_path, monkeypatch):
    pbf = tmp_path / "boundary.osm.pbf"
    _write_boundary_fixture(pbf)
    monkeypatch.setattr(osm, "MAX_BOUNDARY_POINTS", 3)
    conn = store.connect(tmp_path / "work.db")
    store.init_schema(conn)

    osm.OsmExtractor(tag_config={}).extract(
        "uk",
        pbf,
        conn,
        run_id="r1",
        zone_levels={6: "county"},
    )

    assert conn.execute("SELECT COUNT(*) FROM zone_boundaries").fetchone()[0] == 0
