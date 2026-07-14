from mt_pipeline import store


def test_schema_is_idempotent_and_versioned(conn):
    store.init_schema(conn)
    tables = {
        r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
    }
    assert {store.SOURCE_RECORDS_TABLE, store.STAGE_RUNS_TABLE, store.META_TABLE} <= tables
    ver = conn.execute(f"SELECT schema_version FROM {store.META_TABLE}").fetchone()[0]
    assert ver == store.WORKING_STORE_VERSION


def test_stage_completion_ledger(conn):
    assert store.stage_completed(conn, "uk", "extract") is False
    store.mark_stage_complete(
        conn,
        "uk",
        "extract",
        run_id="r1",
        completed_at="2026-07-14T00:00:00Z",
    )
    assert store.stage_completed(conn, "uk", "extract") is True
    assert store.stage_completed(conn, "malaysia", "extract") is False


def test_mark_stage_complete_is_upsert(conn):
    store.mark_stage_complete(conn, "uk", "extract", "r1", "2026-07-14T00:00:00Z")
    store.mark_stage_complete(conn, "uk", "extract", "r2", "2026-07-14T01:00:00Z")
    rows = list(
        conn.execute(
            f"SELECT run_id FROM {store.STAGE_RUNS_TABLE} WHERE region=? AND stage=?",
            ("uk", "extract"),
        )
    )
    assert len(rows) == 1 and rows[0][0] == "r2"
