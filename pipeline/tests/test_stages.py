import pytest

from mt_pipeline import stages, store

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


def test_skipping_immediate_predecessor_is_blocked_even_when_earlier_stage_done(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    with pytest.raises(stages.StageOrderError) as exc:
        stages.run_stage(conn, "uk", "score", run_id="r1")
    assert "reconcile" in str(exc.value)
    assert not store.stage_completed(conn, "uk", "score")


def test_publish_blocked_names_categorize_after_extract_reconcile(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    stages.run_stage(conn, "uk", "reconcile", run_id="r1")
    with pytest.raises(stages.StageOrderError) as exc:
        stages.run_stage(conn, "uk", "publish", run_id="r1")
    assert "categorize" in str(exc.value)


def test_score_stage_is_explicitly_blocked_until_a2_places_land(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    stages.run_stage(conn, "uk", "reconcile", run_id="r1")

    with pytest.raises(stages.StageOrderError) as exc:
        stages.run_stage(conn, "uk", "score", run_id="r1")

    assert "blocked until A2" in str(exc.value)
    assert not store.stage_completed(conn, "uk", "score")


def test_categorize_stage_dispatches_after_score_predecessor(conn):
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
    ).fetchone()[0] == "culture"


def test_order_is_per_region(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    with pytest.raises(stages.StageOrderError):
        stages.run_stage(conn, "malaysia", "reconcile", run_id="r1")
