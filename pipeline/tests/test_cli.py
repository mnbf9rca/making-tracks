from mt_pipeline import cli, store


def test_cli_runs_a_stage(tmp_path):
    db = tmp_path / "w.db"
    assert cli.main(["--region", "uk", "extract", "--db", str(db)]) == 0
    conn = store.connect(db)
    assert store.stage_completed(conn, "uk", "extract")


def test_cli_rejects_unknown_region_without_traceback(tmp_path, capsys):
    rc = cli.main(["--region", "atlantis", "extract", "--db", str(tmp_path / "w.db")])
    assert rc == 2
    assert "atlantis" in capsys.readouterr().err


def test_cli_enforces_stage_order(tmp_path, capsys):
    rc = cli.main(["--region", "uk", "publish", "--db", str(tmp_path / "w.db")])
    assert rc == 1
    assert "categorize" in capsys.readouterr().err


def test_cli_maps_db_open_failure_to_clean_error(tmp_path, capsys):
    bad = tmp_path / "no_such_dir" / "w.db"
    rc = cli.main(["--region", "uk", "extract", "--db", str(bad)])
    assert rc == 3
    assert "database" in capsys.readouterr().err.lower()


def test_cli_maps_stage_write_failure_to_clean_error(monkeypatch, tmp_path, capsys):
    import sqlite3

    def fail_mark_stage_complete(*_args, **_kwargs):
        raise sqlite3.OperationalError("disk is full")

    monkeypatch.setattr(store, "mark_stage_complete", fail_mark_stage_complete)

    rc = cli.main(["--region", "uk", "extract", "--db", str(tmp_path / "w.db")])

    assert rc == 3
    err = capsys.readouterr().err.lower()
    assert "database" in err
    assert "disk is full" in err


def test_cli_run_id_is_parameterized(tmp_path):
    db = tmp_path / "w.db"
    hostile = "r1'); DROP TABLE stage_runs;--"

    assert cli.main(["--region", "uk", "extract", "--db", str(db), "--run-id", hostile]) == 0

    conn = store.connect(db)
    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert store.STAGE_RUNS_TABLE in tables
    row = conn.execute(f"SELECT run_id FROM {store.STAGE_RUNS_TABLE}").fetchone()
    assert row[0] == hostile
