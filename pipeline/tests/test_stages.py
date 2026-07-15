import json

import pytest

from mt_pipeline import source_record, stages, store


def test_stage_order_is_the_spec_order():
    assert stages.STAGE_ORDER == ("extract", "reconcile", "score", "categorize", "publish")


def test_predecessor_mapping():
    assert stages.predecessor("extract") is None
    assert stages.predecessor("reconcile") == "extract"
    assert stages.predecessor("publish") == "categorize"


def test_first_stage_runs_without_predecessor(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    assert store.stage_completed(conn, "uk", "extract")


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
    for stage in stages.STAGE_ORDER:
        if stage == "reconcile":
            store.mark_stage_complete(conn, "uk", "reconcile", "r1", "2026-07-15T00:00:00Z")
            continue
        stages.run_stage(conn, "uk", stage, run_id="r1")
    assert store.stage_completed(conn, "uk", "publish")


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
