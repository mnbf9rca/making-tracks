import pytest

from mt_pipeline import stages, store

A2_PLACES_DDL = """
CREATE TABLE places (
    place_id         TEXT PRIMARY KEY,
    region           TEXT NOT NULL,
    name             TEXT NOT NULL,
    lat              REAL NOT NULL,
    lon              REAL NOT NULL,
    refs_json        TEXT NOT NULL,
    member_refs_json TEXT NOT NULL,
    status           TEXT NOT NULL
)
"""


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


def test_full_order_runs(conn):
    conn.execute(A2_PLACES_DDL)
    for stage in stages.STAGE_ORDER:
        stages.run_stage(conn, "uk", stage, run_id="r1")
    assert store.stage_completed(conn, "uk", "publish")


def test_order_is_per_region(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    with pytest.raises(stages.StageOrderError):
        stages.run_stage(conn, "malaysia", "reconcile", run_id="r1")
