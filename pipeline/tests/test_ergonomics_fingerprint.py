import json
from dataclasses import dataclass

from mt_pipeline import source_record, store
from mt_pipeline.ergonomics import fingerprint as F


@dataclass(frozen=True)
class FakeRegionConfig:
    region_id: str
    sources: dict
    languages: list[str]


def _conn(tmp_path):
    tmp_path.mkdir(parents=True, exist_ok=True)
    conn = store.connect(tmp_path / "w.db")
    store.init_schema(conn)
    return conn


def _inputs(tmp_path, region_config=None, *, succeeded_sources=None):
    tmp_path.mkdir(parents=True, exist_ok=True)
    wikidata = tmp_path / "wikidata.snapshot.json"
    wikidata.write_text('{"b":2,"a":1}')
    osm = tmp_path / "osm.osm.pbf"
    osm.write_text("osm")
    allowlist = tmp_path / "wikidata_class_allowlist.json"
    allowlist.write_text('{"allow":["Q1"]}')
    tags = tmp_path / "osm_candidate_tags.json"
    tags.write_text('{"tags":{"historic":true}}')
    scoring = tmp_path / "scoring.json"
    scoring.write_text('{"rarity_keys":["heritage"]}')
    taxonomy = tmp_path / "taxonomy.json"
    taxonomy.write_text('{"categories":["history"],"uncovered":"other"}')
    reconcile_config = tmp_path / "reconcile.json"
    reconcile_config.write_text('{"fuzzy":{}}')
    redirect_map = tmp_path / "redirects.json"
    redirect_map.write_text('{"redirects":{}}')
    registry = tmp_path / "registry.jsonl"
    registry.write_text("")
    return F.FingerprintInputs(
        region_config=region_config
        or FakeRegionConfig(
            region_id="uk",
            sources={"wikidata": True, "wikipedia": False, "osm": True},
            languages=["en"],
        ),
        snapshots={"wikidata": wikidata, "osm": osm},
        config_paths={
            "wikidata_class_allowlist": allowlist,
            "osm_candidate_tags": tags,
            "scoring_config": scoring,
            "taxonomy_config": taxonomy,
            "reconcile_config": reconcile_config,
            "redirect_map": redirect_map,
            "registry": registry,
        },
        succeeded_sources=succeeded_sources or {"wikidata", "osm"},
        version="20260716T000000Z",
    )


def _insert_source(conn, *, name="A", lat=1.0, lon=2.0, props=None):
    source_record.persist(
        conn,
        source_record.parse(
            "uk",
            "wd",
            "wd:Q1",
            name,
            lat,
            lon,
            props if props is not None else {"x": 1},
        ),
        run_id="r1",
    )


def _insert_place(conn, *, member_refs='["wd:Q1"]', name="Place", lat=1.0, lon=2.0):
    conn.execute(
        """
        INSERT INTO places
            (place_id, region, name, lat, lon, refs_json, member_refs_json, status)
        VALUES ('p1', 'uk', ?, ?, ?, '["wd:Q1"]', ?, 'live')
        """,
        (name, lat, lon, member_refs),
    )
    conn.commit()


def test_schema_migrates_v6_store_to_stage_fingerprints(conn):
    store.init_schema(conn)
    conn.execute(f"DROP TABLE {store.STAGE_FINGERPRINTS_TABLE}")
    conn.execute(f"UPDATE {store.META_TABLE} SET schema_version = ?", (6,))
    conn.commit()

    store._migrate(conn, 6)

    tables = {
        r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
    }
    assert store.STAGE_FINGERPRINTS_TABLE in tables
    columns = {
        r[1]: {"type": r[2], "notnull": bool(r[3]), "pk": bool(r[5])}
        for r in conn.execute(f"PRAGMA table_info({store.STAGE_FINGERPRINTS_TABLE})")
    }
    assert columns["region"]["pk"] is True
    assert columns["stage"]["pk"] is True
    assert columns["fingerprint"] == {"type": "TEXT", "notnull": True, "pk": False}
    assert columns["completed_at"] == {"type": "TEXT", "notnull": True, "pk": False}


def test_reconcile_fingerprint_moves_on_each_source_record_field(tmp_path):
    base_conn = _conn(tmp_path)
    _insert_source(base_conn)
    inputs = _inputs(tmp_path)
    base = F.stage_fingerprint(base_conn, "uk", "reconcile", inputs=inputs)

    for column, value in (
        ("source", "wp"),
        ("source_ref", "wp:1"),
        ("name", "Renamed"),
        ("lat", 9.0),
        ("lon", 8.0),
        ("props_json", json.dumps({"x": 2})),
    ):
        conn = _conn(tmp_path / column)
        _insert_source(conn)
        conn.execute(
            f"UPDATE source_records SET {column} = ? WHERE source_ref = ?",
            (value, "wd:Q1"),
        )
        assert F.stage_fingerprint(conn, "uk", "reconcile", inputs=inputs) != base


def test_reconcile_fingerprint_is_order_and_json_whitespace_stable(tmp_path):
    a = _conn(tmp_path / "a")
    _insert_source(a, props={"x": 1, "y": 2})
    b = _conn(tmp_path / "b")
    _insert_source(b, props={"y": 2, "x": 1})
    b.execute(
        "UPDATE source_records SET props_json = ? WHERE source_ref = ?",
        ('{ "y" : 2, "x" : 1 }', "wd:Q1"),
    )
    inputs = _inputs(tmp_path)

    assert F.stage_fingerprint(a, "uk", "reconcile", inputs=inputs) == F.stage_fingerprint(
        b, "uk", "reconcile", inputs=inputs
    )


def test_extract_fingerprint_moves_on_enabled_sources_languages_and_files(tmp_path):
    inputs = _inputs(tmp_path)
    base = F.stage_fingerprint(_conn(tmp_path / "db"), "uk", "extract", inputs=inputs)

    no_osm = _inputs(
        tmp_path / "no-osm",
        FakeRegionConfig(
            region_id="uk",
            sources={"wikidata": True, "wikipedia": False, "osm": False},
            languages=["en"],
        ),
    )
    assert F.stage_fingerprint(_conn(tmp_path / "db2"), "uk", "extract", inputs=no_osm) != base

    fr = _inputs(
        tmp_path / "fr",
        FakeRegionConfig(
            region_id="uk",
            sources={"wikidata": True, "wikipedia": False, "osm": True},
            languages=["en", "fr"],
        ),
    )
    assert F.stage_fingerprint(_conn(tmp_path / "db3"), "uk", "extract", inputs=fr) != base

    changed_file = _inputs(tmp_path / "changed")
    changed_file.snapshots["wikidata"].write_text('{"a":99}')
    assert (
        F.stage_fingerprint(_conn(tmp_path / "db4"), "uk", "extract", inputs=changed_file)
        != base
    )

    changed_allowlist = _inputs(tmp_path / "changed-allowlist")
    changed_allowlist.config_paths["wikidata_class_allowlist"].write_text(
        '{"allow":["Q2"]}'
    )
    assert (
        F.stage_fingerprint(
            _conn(tmp_path / "db5"),
            "uk",
            "extract",
            inputs=changed_allowlist,
        )
        != base
    )

    changed_tags = _inputs(tmp_path / "changed-tags")
    changed_tags.config_paths["osm_candidate_tags"].write_text(
        '{"tags":{"tourism":true}}'
    )
    assert (
        F.stage_fingerprint(_conn(tmp_path / "db6"), "uk", "extract", inputs=changed_tags)
        != base
    )


def test_reconcile_fingerprint_moves_on_config_redirect_and_registry(tmp_path):
    conn = _conn(tmp_path / "db")
    _insert_source(conn)
    inputs = _inputs(tmp_path)
    base = F.stage_fingerprint(conn, "uk", "reconcile", inputs=inputs)

    for key, text in (
        ("reconcile_config", '{"fuzzy":{"distance":1}}'),
        ("redirect_map", '{"redirects":{"Q2":"Q1"}}'),
        ("registry", '{"place_id":"mt1"}\n'),
    ):
        changed = _inputs(tmp_path / key)
        changed.config_paths[key].write_text(text)
        assert F.stage_fingerprint(conn, "uk", "reconcile", inputs=changed) != base


def test_score_fingerprint_moves_on_places_source_records_and_config(tmp_path):
    conn = _conn(tmp_path / "db")
    _insert_source(conn)
    _insert_place(conn)
    inputs = _inputs(tmp_path)
    base = F.stage_fingerprint(conn, "uk", "score", inputs=inputs)

    changed_source = _conn(tmp_path / "changed-source")
    _insert_source(changed_source, props={"heritage": "listed"})
    _insert_place(changed_source)
    assert F.stage_fingerprint(changed_source, "uk", "score", inputs=inputs) != base

    changed_place = _conn(tmp_path / "changed-place")
    _insert_source(changed_place)
    _insert_place(changed_place, name="Other")
    assert F.stage_fingerprint(changed_place, "uk", "score", inputs=inputs) != base

    changed_config = _inputs(tmp_path / "changed-score-config")
    changed_config.config_paths["scoring_config"].write_text('{"rarity_keys":["other"]}')
    assert F.stage_fingerprint(conn, "uk", "score", inputs=changed_config) != base


def test_categorize_fingerprint_moves_on_source_records_and_configs(tmp_path):
    conn = _conn(tmp_path / "db")
    _insert_source(conn, props={"p31": "Q1"})
    _insert_place(conn)
    inputs = _inputs(tmp_path)
    base = F.stage_fingerprint(conn, "uk", "categorize", inputs=inputs)

    changed_source = _conn(tmp_path / "changed-source")
    _insert_source(changed_source, props={"p31": "Q2"})
    _insert_place(changed_source)
    assert F.stage_fingerprint(changed_source, "uk", "categorize", inputs=inputs) != base

    changed_taxonomy = _inputs(tmp_path / "changed-taxonomy")
    changed_taxonomy.config_paths["taxonomy_config"].write_text(
        '{"categories":["architecture"],"uncovered":"other"}'
    )
    assert F.stage_fingerprint(conn, "uk", "categorize", inputs=changed_taxonomy) != base

    changed_tags = _inputs(tmp_path / "changed-categorize-tags")
    changed_tags.config_paths["osm_candidate_tags"].write_text(
        '{"tags":{"amenity":true}}'
    )
    assert F.stage_fingerprint(conn, "uk", "categorize", inputs=changed_tags) != base


def test_identical_fingerprint_skips_unless_forced(conn, tmp_path):
    store.init_schema(conn)
    fp = F.stage_fingerprint(conn, "uk", "extract", inputs=_inputs(tmp_path))
    F.record(conn, "uk", "extract", fp, completed_at="2026-07-16T00:00:00Z")

    assert F.should_skip(conn, "uk", "extract", fp, force=False) is True
    assert F.should_skip(conn, "uk", "extract", fp, force=True) is False
    assert F.should_skip(conn, "uk", "extract", "other", force=False) is False


def test_every_declared_stage_read_is_fingerprinted():
    for stage, reads in F.STAGE_READS.items():
        assert reads - F.fingerprint_covers(stage) == set()
