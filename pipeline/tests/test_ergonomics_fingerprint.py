import json
import pathlib
import inspect
from dataclasses import dataclass, replace

from mt_contracts import place_id as place_id_module
from mt_contracts import registry as registry_module
from mt_contracts import text as text_module
from mt_pipeline import extract_stage, source_record, store
from mt_pipeline.ergonomics import fingerprint as F
from mt_pipeline.ergonomics import merge as merge_module
from mt_pipeline.ergonomics import staging as staging_module
from mt_pipeline.extractors import osm as osm_module
from mt_pipeline.extractors import pageviews
from mt_pipeline.extractors import wikipedia as wikipedia_module


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
            region_id="united-kingdom",
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
            "united-kingdom",
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
        VALUES ('p1', 'united-kingdom', ?, ?, ?, '["wd:Q1"]', ?, 'live')
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
    base = F.stage_fingerprint(base_conn, "united-kingdom", "reconcile", inputs=inputs)

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
        assert F.stage_fingerprint(conn, "united-kingdom", "reconcile", inputs=inputs) != base


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

    assert F.stage_fingerprint(a, "united-kingdom", "reconcile", inputs=inputs) == F.stage_fingerprint(
        b, "united-kingdom", "reconcile", inputs=inputs
    )


def test_content_hash_rejects_unknown_sql_shape(conn):
    store.init_schema(conn)
    malicious_table = "source_records; DROP TABLE source_records;--"
    malicious_cols = ("source", "source_ref) FROM source_records; DROP TABLE places;--")

    for table, cols in (
        (malicious_table, F.SOURCE_RECORD_RECONCILE_COLS),
        ("source_records", malicious_cols),
    ):
        try:
            F.content_hash(conn, "united-kingdom", table, cols)
        except ValueError as exc:
            assert "unsupported content-hash shape" in str(exc)
        else:
            raise AssertionError("content_hash accepted a dynamic SQL shape")

    tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert "source_records" in tables
    assert "places" in tables


def test_extract_fingerprint_moves_on_enabled_sources_languages_and_files(tmp_path):
    inputs = _inputs(tmp_path)
    base = F.stage_fingerprint(_conn(tmp_path / "db"), "united-kingdom", "extract", inputs=inputs)

    no_osm = _inputs(
        tmp_path / "no-osm",
        FakeRegionConfig(
            region_id="united-kingdom",
            sources={"wikidata": True, "wikipedia": False, "osm": False},
            languages=["en"],
        ),
    )
    assert F.stage_fingerprint(_conn(tmp_path / "db2"), "united-kingdom", "extract", inputs=no_osm) != base

    fr = _inputs(
        tmp_path / "fr",
        FakeRegionConfig(
            region_id="united-kingdom",
            sources={"wikidata": True, "wikipedia": False, "osm": True},
            languages=["en", "fr"],
        ),
    )
    assert F.stage_fingerprint(_conn(tmp_path / "db3"), "united-kingdom", "extract", inputs=fr) != base

    changed_file = _inputs(tmp_path / "changed")
    changed_file.snapshots["wikidata"].write_text('{"a":99}')
    assert (
        F.stage_fingerprint(_conn(tmp_path / "db4"), "united-kingdom", "extract", inputs=changed_file)
        != base
    )

    changed_allowlist = _inputs(tmp_path / "changed-allowlist")
    changed_allowlist.config_paths["wikidata_class_allowlist"].write_text(
        '{"allow":["Q2"]}'
    )
    assert (
        F.stage_fingerprint(
            _conn(tmp_path / "db5"),
            "united-kingdom",
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
        F.stage_fingerprint(_conn(tmp_path / "db6"), "united-kingdom", "extract", inputs=changed_tags)
        != base
    )


def test_extract_fingerprint_moves_on_pageview_cache_contents(tmp_path):
    wikipedia_snapshot = tmp_path / "wikipedia.snapshot.json"
    wikipedia_snapshot.write_text(
        '{"_meta":{"complete":true,"retrieved_at":"2026-07-15T00:00:00Z"},"pages":[]}'
    )
    allowlist = tmp_path / "wikidata_class_allowlist.json"
    allowlist.write_text('{"allow":["Q1"]}')
    tags = tmp_path / "osm_candidate_tags.json"
    tags.write_text('{"tags":{"historic":true}}')
    cache = tmp_path / "pageviews"
    cache.mkdir()
    window = ("2025-07-15", "2026-07-15")
    cache_file = pageviews._cache_path(cache, "A", window)
    cache_file.write_text(
        '{"daily":[1],"title":"A","window":["2025-07-15","2026-07-15"]}'
    )
    inputs = F.FingerprintInputs(
        region_config=FakeRegionConfig(
            region_id="malaysia-singapore-brunei",
            sources={"wikipedia": True},
            languages=["en"],
        ),
        snapshots={"wikipedia": wikipedia_snapshot},
        config_paths={
            "wikidata_class_allowlist": allowlist,
            "osm_candidate_tags": tags,
        },
        pageview_cache_files=(cache_file,),
        pageview_window=window,
    )
    base = F.stage_fingerprint(_conn(tmp_path / "db"), "malaysia-singapore-brunei", "extract", inputs=inputs)

    cache_file.write_text(
        '{"daily":[2],"title":"A","window":["2025-07-15","2026-07-15"]}'
    )

    assert F.stage_fingerprint(_conn(tmp_path / "db2"), "malaysia-singapore-brunei", "extract", inputs=inputs) != base


def test_extract_fingerprint_moves_on_pageview_window(tmp_path):
    cache = tmp_path / "pageviews"
    cache.mkdir()
    window = ("2025-07-15", "2026-07-15")
    cache_file = pageviews._cache_path(cache, "A", window)
    cache_file.write_text(
        '{"daily":[1],"title":"A","window":["2025-07-15","2026-07-15"]}'
    )
    inputs = _inputs(
        tmp_path,
        FakeRegionConfig(
            region_id="malaysia-singapore-brunei",
            sources={"wikipedia": True},
            languages=["en"],
        ),
    )
    inputs = replace(
        inputs,
        snapshots={"wikipedia": tmp_path / "wikidata.snapshot.json"},
        pageview_cache_files=(cache_file,),
        pageview_window=window,
    )
    base = F.stage_fingerprint(_conn(tmp_path / "db"), "malaysia-singapore-brunei", "extract", inputs=inputs)

    changed = replace(inputs, pageview_window=("2024-07-15", "2025-07-15"))

    assert F.stage_fingerprint(_conn(tmp_path / "db2"), "malaysia-singapore-brunei", "extract", inputs=changed) != base


def test_extract_fingerprint_ignores_unselected_source_configs_for_wikipedia_only(tmp_path):
    cache = tmp_path / "pageviews"
    cache.mkdir()
    window = ("2025-07-15", "2026-07-15")
    cache_file = pageviews._cache_path(cache, "A", window)
    cache_file.write_text(
        '{"daily":[1],"title":"A","window":["2025-07-15","2026-07-15"]}'
    )
    inputs = _inputs(
        tmp_path,
        FakeRegionConfig(
            region_id="malaysia-singapore-brunei",
            sources={"wikidata": True, "wikipedia": True, "osm": True},
            languages=["en"],
        ),
    )
    wikipedia_snapshot = tmp_path / "wikipedia.snapshot.json"
    wikipedia_snapshot.write_text(
        '{"_meta":{"complete":true,"retrieved_at":"2026-07-15T00:00:00Z"},"pages":[]}'
    )
    inputs = replace(
        inputs,
        snapshots={**inputs.snapshots, "wikipedia": wikipedia_snapshot},
        only_source="wikipedia",
        pageview_cache_files=(cache_file,),
        pageview_window=window,
    )
    base = F.stage_fingerprint(_conn(tmp_path / "db"), "malaysia-singapore-brunei", "extract", inputs=inputs)

    inputs.config_paths["wikidata_class_allowlist"].write_text('{"allow":["Q2"]}')
    inputs.config_paths["osm_candidate_tags"].write_text('{"tags":{"tourism":true}}')

    assert F.stage_fingerprint(_conn(tmp_path / "db2"), "malaysia-singapore-brunei", "extract", inputs=inputs) == base


def test_extract_fingerprint_ignores_unselected_pageview_cache_files(tmp_path):
    cache = tmp_path / "pageviews"
    cache.mkdir()
    window = ("2025-07-15", "2026-07-15")
    selected = pageviews._cache_path(cache, "A", window)
    selected.write_text(
        '{"daily":[1],"title":"A","window":["2025-07-15","2026-07-15"]}'
    )
    inputs = _inputs(
        tmp_path,
        FakeRegionConfig(
            region_id="malaysia-singapore-brunei",
            sources={"wikipedia": True},
            languages=["en"],
        ),
    )
    inputs = replace(
        inputs,
        snapshots={"wikipedia": tmp_path / "wikidata.snapshot.json"},
        pageview_cache_files=(selected,),
        pageview_window=window,
    )
    base = F.stage_fingerprint(_conn(tmp_path / "db"), "malaysia-singapore-brunei", "extract", inputs=inputs)

    (cache / "unrelated.json").write_text('{"daily":[99]}')

    assert F.stage_fingerprint(_conn(tmp_path / "db2"), "malaysia-singapore-brunei", "extract", inputs=inputs) == base


def test_extract_fingerprint_does_not_follow_pageview_cache_symlink(tmp_path):
    cache = tmp_path / "pageviews"
    cache.mkdir()
    target = tmp_path / "target.json"
    target.write_text('{"daily":[1]}')
    selected = cache / "selected.json"
    selected.symlink_to(target)
    inputs = _inputs(
        tmp_path,
        FakeRegionConfig(
            region_id="malaysia-singapore-brunei",
            sources={"wikipedia": True},
            languages=["en"],
        ),
    )
    inputs = replace(
        inputs,
        snapshots={"wikipedia": tmp_path / "wikidata.snapshot.json"},
        pageview_cache_files=(selected,),
        pageview_window=("2025-07-15", "2026-07-15"),
    )
    base = F.stage_fingerprint(_conn(tmp_path / "db"), "malaysia-singapore-brunei", "extract", inputs=inputs)

    target.write_text('{"daily":[2]}')

    assert F.stage_fingerprint(_conn(tmp_path / "db2"), "malaysia-singapore-brunei", "extract", inputs=inputs) == base


def test_extract_fingerprint_moves_on_merge_bookkeeping_code_change(
    monkeypatch, tmp_path
):
    merge_path = pathlib.Path(merge_module.__file__).resolve()
    changed = False

    def fake_file_hash(path):
        resolved = pathlib.Path(path).resolve()
        if resolved == merge_path and changed:
            return "changed-merge-code"
        return f"hash:{resolved}"

    monkeypatch.setattr(F, "_file_hash", fake_file_hash)
    conn = _conn(tmp_path / "db")
    inputs = _inputs(tmp_path)
    base = F.stage_fingerprint(conn, "united-kingdom", "extract", inputs=inputs)
    F.record(conn, "united-kingdom", "extract", base, completed_at="2026-07-16T00:00:00Z")

    changed = True
    next_fp = F.stage_fingerprint(conn, "united-kingdom", "extract", inputs=inputs)

    assert next_fp != base
    assert F.should_skip(conn, "united-kingdom", "extract", next_fp, force=False) is False


def test_extract_fingerprint_moves_on_staging_bookkeeping_code_change(
    monkeypatch, tmp_path
):
    staging_path = pathlib.Path(staging_module.__file__).resolve()
    changed = False

    def fake_file_hash(path):
        resolved = pathlib.Path(path).resolve()
        if resolved == staging_path and changed:
            return "changed-staging-code"
        return f"hash:{resolved}"

    monkeypatch.setattr(F, "_file_hash", fake_file_hash)
    conn = _conn(tmp_path / "db")
    inputs = _inputs(tmp_path)
    base = F.stage_fingerprint(conn, "united-kingdom", "extract", inputs=inputs)
    F.record(conn, "united-kingdom", "extract", base, completed_at="2026-07-16T00:00:00Z")

    changed = True
    next_fp = F.stage_fingerprint(conn, "united-kingdom", "extract", inputs=inputs)

    assert next_fp != base
    assert F.should_skip(conn, "united-kingdom", "extract", next_fp, force=False) is False


def test_extract_module_marker_covers_extractor_source(monkeypatch):
    wikipedia_path = pathlib.Path(wikipedia_module.__file__).resolve()
    changed = False

    def fake_file_hash(path):
        resolved = pathlib.Path(path).resolve()
        if resolved == wikipedia_path and changed:
            return "changed-wikipedia-code"
        return f"hash:{resolved}"

    monkeypatch.setattr(F, "_file_hash", fake_file_hash)

    base = F.module_marker("extract")
    changed = True

    assert F.module_marker("extract") != base


def test_extract_module_marker_covers_contract_ref_and_text_semantics(monkeypatch):
    contracts_root = pathlib.Path(place_id_module.__file__).resolve().parents[2]
    for dependency in (
        pathlib.Path(place_id_module.__file__).resolve(),
        pathlib.Path(text_module.__file__).resolve(),
        contracts_root / "versions.json",
    ):
        _assert_module_marker_moves_when_path_hash_changes(
            monkeypatch,
            "extract",
            dependency,
        )


def test_reconcile_module_marker_covers_place_id_contract(monkeypatch):
    _assert_module_marker_moves_when_path_hash_changes(
        monkeypatch,
        "reconcile",
        pathlib.Path(place_id_module.__file__).resolve(),
    )


def test_reconcile_module_marker_covers_registry_contract(monkeypatch):
    _assert_module_marker_moves_when_path_hash_changes(
        monkeypatch,
        "reconcile",
        pathlib.Path(registry_module.__file__).resolve(),
    )


def test_reconcile_module_marker_covers_registry_schema(monkeypatch):
    contracts_root = pathlib.Path(registry_module.__file__).resolve().parents[2]

    _assert_module_marker_moves_when_path_hash_changes(
        monkeypatch,
        "reconcile",
        contracts_root / "schemas" / "registry-record.schema.json",
    )


def test_score_module_marker_covers_source_record_limits(monkeypatch):
    _assert_module_marker_moves_when_path_hash_changes(
        monkeypatch,
        "score",
        pathlib.Path(source_record.__file__).resolve(),
    )


def test_categorize_module_marker_covers_osm_candidate_helper(monkeypatch):
    _assert_module_marker_moves_when_path_hash_changes(
        monkeypatch,
        "categorize",
        pathlib.Path(osm_module.__file__).resolve(),
    )


def test_categorize_module_marker_covers_contract_text_semantics(monkeypatch):
    _assert_module_marker_moves_when_path_hash_changes(
        monkeypatch,
        "categorize",
        pathlib.Path(text_module.__file__).resolve(),
    )


def test_code_marker_keys_are_repo_relative_for_contract_dependencies():
    key = F._code_path_key(pathlib.Path(place_id_module.__file__).resolve())

    assert key == "contracts/src/mt_contracts/place_id.py"


def test_python_file_discovery_includes_nested_helpers(tmp_path):
    root = tmp_path / "pkg"
    root.mkdir()
    top = root / "top.py"
    top.write_text("")
    nested_dir = root / "nested"
    nested_dir.mkdir()
    nested = nested_dir / "helper.py"
    nested.write_text("")

    assert F._py_files(root) == (nested, top)


def _assert_module_marker_moves_when_path_hash_changes(monkeypatch, stage, changed_path):
    changed = False

    def fake_file_hash(path):
        resolved = pathlib.Path(path).resolve()
        if resolved == changed_path and changed:
            return f"changed-{stage}-dependency-code"
        return f"hash:{resolved}"

    monkeypatch.setattr(F, "_file_hash", fake_file_hash)

    base = F.module_marker(stage)
    changed = True

    assert F.module_marker(stage) != base


def test_reconcile_fingerprint_moves_on_config_redirect_and_registry(tmp_path):
    conn = _conn(tmp_path / "db")
    _insert_source(conn)
    inputs = _inputs(tmp_path)
    base = F.stage_fingerprint(conn, "united-kingdom", "reconcile", inputs=inputs)

    for key, text in (
        ("reconcile_config", '{"fuzzy":{"distance":1}}'),
        ("redirect_map", '{"redirects":{"Q2":"Q1"}}'),
        ("registry", '{"place_id":"mt1"}\n'),
    ):
        changed = _inputs(tmp_path / key)
        changed.config_paths[key].write_text(text)
        assert F.stage_fingerprint(conn, "united-kingdom", "reconcile", inputs=changed) != base


def test_score_fingerprint_moves_on_places_source_records_and_config(tmp_path):
    conn = _conn(tmp_path / "db")
    _insert_source(conn)
    _insert_place(conn)
    inputs = _inputs(tmp_path)
    base = F.stage_fingerprint(conn, "united-kingdom", "score", inputs=inputs)

    changed_source = _conn(tmp_path / "changed-source")
    _insert_source(changed_source, props={"heritage": "listed"})
    _insert_place(changed_source)
    assert F.stage_fingerprint(changed_source, "united-kingdom", "score", inputs=inputs) != base

    changed_place = _conn(tmp_path / "changed-place")
    _insert_source(changed_place)
    _insert_place(changed_place, name="Other")
    assert F.stage_fingerprint(changed_place, "united-kingdom", "score", inputs=inputs) != base

    changed_config = _inputs(tmp_path / "changed-score-config")
    changed_config.config_paths["scoring_config"].write_text('{"rarity_keys":["other"]}')
    assert F.stage_fingerprint(conn, "united-kingdom", "score", inputs=changed_config) != base


def test_categorize_fingerprint_moves_on_source_records_and_configs(tmp_path):
    conn = _conn(tmp_path / "db")
    _insert_source(conn, props={"p31": "Q1"})
    _insert_place(conn)
    inputs = _inputs(tmp_path)
    base = F.stage_fingerprint(conn, "united-kingdom", "categorize", inputs=inputs)

    changed_source = _conn(tmp_path / "changed-source")
    _insert_source(changed_source, props={"p31": "Q2"})
    _insert_place(changed_source)
    assert F.stage_fingerprint(changed_source, "united-kingdom", "categorize", inputs=inputs) != base

    for column, value in (
        ("member_refs_json", '["wd:Q2"]'),
        ("status", "tombstoned"),
    ):
        changed_place = _conn(tmp_path / f"changed-categorize-place-{column}")
        _insert_source(changed_place, props={"p31": "Q1"})
        _insert_place(changed_place)
        changed_place.execute(
            f"UPDATE places SET {column} = ? WHERE place_id = ?",
            (value, "p1"),
        )
        assert F.stage_fingerprint(changed_place, "united-kingdom", "categorize", inputs=inputs) != base

    changed_taxonomy = _inputs(tmp_path / "changed-taxonomy")
    changed_taxonomy.config_paths["taxonomy_config"].write_text(
        '{"categories":["architecture"],"uncovered":"other"}'
    )
    assert F.stage_fingerprint(conn, "united-kingdom", "categorize", inputs=changed_taxonomy) != base

    changed_tags = _inputs(tmp_path / "changed-categorize-tags")
    changed_tags.config_paths["osm_candidate_tags"].write_text(
        '{"tags":{"amenity":true}}'
    )
    assert F.stage_fingerprint(conn, "united-kingdom", "categorize", inputs=changed_tags) != base


def test_identical_fingerprint_skips_unless_forced(conn, tmp_path):
    store.init_schema(conn)
    fp = F.stage_fingerprint(conn, "united-kingdom", "extract", inputs=_inputs(tmp_path))
    F.record(conn, "united-kingdom", "extract", fp, completed_at="2026-07-16T00:00:00Z")

    assert F.should_skip(conn, "united-kingdom", "extract", fp, force=False) is True
    assert F.should_skip(conn, "united-kingdom", "extract", fp, force=True) is False
    assert F.should_skip(conn, "united-kingdom", "extract", "other", force=False) is False


def test_fingerprint_covers_tracks_actual_component_presence(conn, tmp_path):
    components = F.fingerprint_components(conn, "united-kingdom", "extract", inputs=_inputs(tmp_path))

    assert "languages" in F.fingerprint_covers("extract", components)

    without_languages = dict(components)
    without_languages.pop("languages")
    assert "languages" not in F.fingerprint_covers("extract", without_languages)


def test_extract_fingerprint_covers_build_registry_inputs(conn, tmp_path):
    parameter_to_read = {
        "allowlist_path": "wikidata_class_allowlist",
        "languages": "languages",
        "osm_tag_config_path": "osm_candidate_tags",
    }
    ignored_parameters = {"self", "cls"}
    signature = inspect.signature(extract_stage.build_registry)
    unmapped = set(signature.parameters) - set(parameter_to_read) - ignored_parameters
    assert unmapped == set()
    required_reads = {
        parameter_to_read[name]
        for name in signature.parameters
    }
    components = F.fingerprint_components(conn, "united-kingdom", "extract", inputs=_inputs(tmp_path))

    assert required_reads == set(parameter_to_read.values())
    assert required_reads <= F.STAGE_READS["extract"]
    assert required_reads <= F.fingerprint_covers("extract", components)


def test_unselected_extract_source_configs_are_not_claimed_as_fingerprinted(conn, tmp_path):
    inputs = _inputs(
        tmp_path,
        FakeRegionConfig(
            region_id="malaysia-singapore-brunei",
            sources={"wikipedia": True},
            languages=["en"],
        ),
    )
    inputs = replace(
        inputs,
        snapshots={"wikipedia": tmp_path / "wikidata.snapshot.json"},
        pageview_window=("2025-07-15", "2026-07-15"),
    )
    components = F.fingerprint_components(conn, "malaysia-singapore-brunei", "extract", inputs=inputs)
    covered = F.fingerprint_covers("extract", components)

    assert "wikidata_class_allowlist" not in components
    assert "osm_candidate_tags" not in components
    assert "wikidata_class_allowlist" not in covered
    assert "osm_candidate_tags" not in covered


def test_every_declared_stage_read_is_fingerprinted(conn, tmp_path):
    _insert_source(conn)
    _insert_place(conn)
    inputs = _inputs(
        tmp_path,
        FakeRegionConfig(
            region_id="united-kingdom",
            sources={"wikidata": True, "wikipedia": True, "osm": True},
            languages=["en"],
        ),
    )
    inputs = replace(inputs, pageview_window=("2025-07-15", "2026-07-15"))
    for stage, reads in F.STAGE_READS.items():
        components = F.fingerprint_components(conn, "united-kingdom", stage, inputs=inputs)
        assert reads - F.fingerprint_covers(stage, components) == set()
