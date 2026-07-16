import json

import pytest

from mt_pipeline import categorize, source_record, stages, store
from mt_pipeline.ergonomics import fingerprint as F

from helpers import A2_PLACES_DDL


def test_stage_order_is_the_spec_order():
    assert stages.STAGE_ORDER == ("extract", "reconcile", "score", "categorize", "publish")


def test_predecessor_mapping():
    assert stages.predecessor("extract") is None
    assert stages.predecessor("reconcile") == "extract"
    assert stages.predecessor("publish") == "categorize"


def test_first_stage_runs_without_predecessor(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    assert store.stage_completed(conn, "uk", "extract")


def test_stage_fingerprint_skip_is_loud_and_force_overrides(conn, tmp_path, capsys):
    snapshot = tmp_path / "wikidata.snapshot.json"
    snapshot.write_text("{}")
    allowlist = tmp_path / "wikidata_class_allowlist.json"
    allowlist.write_text("{}")
    tags = tmp_path / "osm_candidate_tags.json"
    tags.write_text("{}")
    inputs = F.FingerprintInputs(
        region_config=type(
            "Cfg",
            (),
            {"sources": {"wikidata": True, "osm": False}, "languages": ["en"]},
        )(),
        snapshots={"wikidata": snapshot},
        config_paths={
            "wikidata_class_allowlist": allowlist,
            "osm_candidate_tags": tags,
        },
    )
    stages.run_stage(conn, "uk", "extract", run_id="r1", fingerprint_inputs=inputs)

    stages.run_stage(conn, "uk", "extract", run_id="r2", fingerprint_inputs=inputs)
    err = capsys.readouterr().err

    assert conn.execute(
        "SELECT run_id FROM stage_runs WHERE region = ? AND stage = ?",
        ("uk", "extract"),
    ).fetchone()[0] == "r1"
    assert "SKIP stage=extract region=uk fingerprint=" in err

    stages.run_stage(
        conn,
        "uk",
        "extract",
        run_id="r2",
        fingerprint_inputs=inputs,
        force=True,
    )
    assert conn.execute(
        "SELECT run_id FROM stage_runs WHERE region = ? AND stage = ?",
        ("uk", "extract"),
    ).fetchone()[0] == "r2"


def test_skipping_immediate_predecessor_is_blocked_even_when_earlier_stage_done(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    with pytest.raises(stages.StageOrderError) as exc:
        stages.run_stage(conn, "uk", "score", run_id="r1")
    assert "reconcile" in str(exc.value)
    assert not store.stage_completed(conn, "uk", "score")


def test_publish_blocked_names_categorize_after_extract_reconcile(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    store.mark_stage_complete(conn, "uk", "reconcile", "r1", "2026-07-15T00:00:00Z")
    with pytest.raises(stages.StageOrderError) as exc:
        stages.run_stage(conn, "uk", "publish", run_id="r1")
    assert "categorize" in str(exc.value)


def test_full_order_runs(conn):
    source_record.persist(
        conn,
        source_record.parse("uk", "wd", "wd:Q1", "Example Place", 51.5, -0.1, {}),
        run_id="r1",
    )
    store.replace_places(
        conn,
        region="uk",
        places=[
            {
                "place_id": "mt:uk:1",
                "name": "Example Place",
                "lat": 51.5,
                "lon": -0.1,
                "refs": ["wd:Q1"],
                "member_refs": ["wd:Q1"],
                "status": "live",
            }
        ],
    )
    for stage in stages.STAGE_ORDER[:-1]:
        if stage == "reconcile":
            store.mark_stage_complete(conn, "uk", "reconcile", "r1", "2026-07-15T00:00:00Z")
            continue
        stages.run_stage(conn, "uk", stage, run_id="r1")
    assert store.stage_completed(conn, "uk", "categorize")
    with pytest.raises(stages.StageVersionError, match="publish-version"):
        stages.run_stage(conn, "uk", "publish", run_id="r1")


def test_score_stage_is_blocked_when_reconcile_has_no_places(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    store.mark_stage_complete(conn, "uk", "reconcile", "r1", "2026-07-15T00:00:00Z")

    with pytest.raises(stages.StageOrderError) as exc:
        stages.run_stage(conn, "uk", "score", run_id="r1")

    assert "no places" in str(exc.value)
    assert not store.stage_completed(conn, "uk", "score")


def test_categorize_stage_dispatches_after_score_predecessor(conn):
    expected_category = categorize.load_taxonomy()["class_map"]["Q33506"]
    conn.execute(A2_PLACES_DDL)
    conn.execute(
        """
        INSERT INTO source_records
            (region, source, source_ref, name, lat, lon, props_json, run_id)
        VALUES ('uk', 'wd', 'wd:Q1', 'Museum', 1, 1, '{"p31":"Q33506"}', 'r')
        """
    )
    conn.execute(
        """
        INSERT INTO places
            (place_id, region, name, lat, lon, refs_json, member_refs_json, status)
        VALUES ('p', 'uk', 'P', 1, 1, '[]', '["wd:Q1"]', 'live')
        """
    )
    for stage in ("extract", "reconcile", "score"):
        store.mark_stage_complete(conn, "uk", stage, "r1", "2026-07-15T00:00:00Z")

    stages.run_stage(conn, "uk", "categorize", run_id="cat1")

    assert store.stage_completed(conn, "uk", "categorize")
    assert conn.execute(
        "SELECT category FROM place_categories WHERE place_id = 'p'"
    ).fetchone()[0] == expected_category


def test_order_is_per_region(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    with pytest.raises(stages.StageOrderError):
        stages.run_stage(
            conn, "malaysia", "reconcile", run_id="r1", version="20260715T000000Z"
        )


def test_reconcile_requires_version(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    with pytest.raises(stages.StageVersionError):
        stages.run_stage(conn, "uk", "reconcile", run_id="r1")


def test_reconcile_stage_writes_places_registry_and_review(conn, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    source_record.persist(
        conn,
        source_record.parse(
            "malaysia",
            "wd",
            "wd:Q42",
            "Example Place",
            3.1,
            101.7,
            {},
        ),
        run_id="real",
    )
    store.record_extract_run_metadata(
        conn,
        region="malaysia",
        run_id="real",
        wikidata_snapshot_date="2026-07-15T00:00:00Z",
        source_statuses={
            "wikidata": {"status": "success", "count": 1},
            "wikipedia": {"status": "disabled"},
            "osm": {"status": "disabled"},
            "open_plaques": {"status": "disabled"},
            "national_register": {"status": "disabled"},
        },
    )
    redirects = tmp_path / ".mt-data" / "malaysia" / "wikidata_redirects.snapshot.json"
    redirects.parent.mkdir(parents=True)
    redirects.write_text(
        '{"_meta":{"complete":true,"retrieved_at":"2026-07-15T00:00:00Z",'
        '"wikidata_retrieved_at":"2026-07-15T00:00:00Z"},"redirects":{}}'
    )
    stages.run_stage(conn, "malaysia", "extract", run_id="real")

    stages.run_stage(
        conn,
        "malaysia",
        "reconcile",
        run_id="real",
        version="20260715T000000Z",
    )
    first_registry = (tmp_path / "registry" / "malaysia.jsonl").read_bytes()
    stages.run_stage(
        conn,
        "malaysia",
        "reconcile",
        run_id="real",
        version="20260715T000000Z",
    )
    second_registry = (tmp_path / "registry" / "malaysia.jsonl").read_bytes()

    rows = conn.execute(
        f"SELECT name, refs_json, member_refs_json FROM {store.PLACES_TABLE}"
    ).fetchall()
    assert rows == [
        ("Example Place", '["wd:Q42"]', '["wd:Q42"]'),
    ]
    assert first_registry == second_registry
    assert (tmp_path / "reconcile-review" / "malaysia.jsonl").exists()
    assert store.stage_completed(conn, "malaysia", "reconcile")


def test_reconcile_stage_resolves_registry_paths_beside_db(conn, tmp_path, monkeypatch):
    other_cwd = tmp_path / "operator-cwd"
    other_cwd.mkdir()
    monkeypatch.chdir(other_cwd)
    source_record.persist(
        conn,
        source_record.parse(
            "malaysia",
            "wd",
            "wd:Q42",
            "Example Place",
            3.1,
            101.7,
            {},
        ),
        run_id="real",
    )
    store.record_extract_run_metadata(
        conn,
        region="malaysia",
        run_id="real",
        wikidata_snapshot_date="2026-07-15T00:00:00Z",
        source_statuses={
            "wikidata": {"status": "success", "count": 1},
            "wikipedia": {"status": "disabled"},
            "osm": {"status": "disabled"},
            "open_plaques": {"status": "disabled"},
            "national_register": {"status": "disabled"},
        },
    )
    redirects = other_cwd / ".mt-data" / "malaysia" / "wikidata_redirects.snapshot.json"
    redirects.parent.mkdir(parents=True)
    redirects.write_text(
        '{"_meta":{"complete":true,"retrieved_at":"2026-07-15T00:00:00Z",'
        '"wikidata_retrieved_at":"2026-07-15T00:00:00Z"},"redirects":{}}'
    )
    stages.run_stage(conn, "malaysia", "extract", run_id="real")

    stages.run_stage(
        conn,
        "malaysia",
        "reconcile",
        run_id="real",
        version="20260715T000000Z",
    )

    assert (tmp_path / "registry" / "malaysia.jsonl").exists()
    assert not (other_cwd / "registry" / "malaysia.jsonl").exists()
    assert (tmp_path / "reconcile-review" / "malaysia.jsonl").exists()


def test_reconcile_stage_review_file_preserves_fuzzy_defer_payload(
    conn, tmp_path, monkeypatch
):
    monkeypatch.chdir(tmp_path)
    source_record.persist(
        conn,
        source_record.parse(
            "malaysia",
            "osm",
            "osm:node/1",
            "Same Place",
            3.1,
            101.7,
            {},
        ),
        run_id="real",
    )
    source_record.persist(
        conn,
        source_record.parse(
            "malaysia",
            "osm",
            "osm:node/2",
            "Same Place",
            3.10001,
            101.7,
            {},
        ),
        run_id="real",
    )
    store.record_extract_run_metadata(
        conn,
        region="malaysia",
        run_id="real",
        wikidata_snapshot_date="2026-07-15T00:00:00Z",
        source_statuses={
            "wikidata": {"status": "disabled"},
            "wikipedia": {"status": "disabled"},
            "osm": {"status": "success", "count": 2},
            "open_plaques": {"status": "disabled"},
            "national_register": {"status": "disabled"},
        },
    )
    redirects = tmp_path / ".mt-data" / "malaysia" / "wikidata_redirects.snapshot.json"
    redirects.parent.mkdir(parents=True)
    redirects.write_text(
        '{"_meta":{"complete":true,"retrieved_at":"2026-07-15T00:00:00Z",'
        '"wikidata_retrieved_at":"2026-07-15T00:00:00Z"},"redirects":{}}'
    )
    stages.run_stage(conn, "malaysia", "extract", run_id="real")

    stages.run_stage(
        conn,
        "malaysia",
        "reconcile",
        run_id="real",
        version="20260715T000000Z",
    )

    rows = (tmp_path / "reconcile-review" / "malaysia.jsonl").read_text().splitlines()
    fuzzy_rows = [json.loads(row) for row in rows if json.loads(row)["kind"] == "fuzzy_defer"]

    assert len(fuzzy_rows) == 1
    assert fuzzy_rows[0]["anchor_a"] == "osm:node/1"
    assert fuzzy_rows[0]["anchor_b"] == "osm:node/2"
    assert fuzzy_rows[0]["sim"] == 1.0
    assert 0.0 < fuzzy_rows[0]["dist_m"] < 2.0


def test_reconcile_stage_refuses_missing_redirect_map(conn, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    stages.run_stage(conn, "malaysia", "extract", run_id="real")
    store.record_extract_run_metadata(
        conn,
        region="malaysia",
        run_id="real",
        wikidata_snapshot_date="2026-07-15T00:00:00Z",
        source_statuses={"wikidata": {"status": "success", "count": 0}},
    )

    with pytest.raises(stages.StageOrderError, match="redirect"):
        stages.run_stage(
            conn,
            "malaysia",
            "reconcile",
            run_id="real",
            version="20260715T000000Z",
        )


def test_reconcile_stage_refuses_stale_redirect_map(conn, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    stages.run_stage(conn, "malaysia", "extract", run_id="real")
    store.record_extract_run_metadata(
        conn,
        region="malaysia",
        run_id="real",
        wikidata_snapshot_date="2026-07-15T00:00:00Z",
        source_statuses={"wikidata": {"status": "success", "count": 0}},
    )
    redirect_path = tmp_path / ".mt-data" / "malaysia" / "wikidata_redirects.snapshot.json"
    redirect_path.parent.mkdir(parents=True)
    redirect_path.write_text(
        json.dumps(
            {
                "_meta": {
                    "complete": True,
                    "retrieved_at": "2026-07-14T00:00:00Z",
                    "wikidata_retrieved_at": "2026-07-15T00:00:00Z",
                },
                "redirects": {},
            }
        )
    )

    with pytest.raises(stages.StageOrderError, match="redirect map"):
        stages.run_stage(
            conn,
            "malaysia",
            "reconcile",
            run_id="real",
            version="20260715T000000Z",
        )

    assert not store.stage_completed(conn, "malaysia", "reconcile")
