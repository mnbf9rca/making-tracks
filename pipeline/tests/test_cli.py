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
