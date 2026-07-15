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


def test_cli_extract_uses_snapshot_dir_and_osm_index_type(monkeypatch, tmp_path):
    captured = {}

    def fake_build_registry(*_args, **_kwargs):
        return object()

    def fake_run_extract(
        conn,
        region,
        snapshots,
        *,
        run_id,
        registry,
        extractor_options,
        status_recorder,
    ):
        captured["region"] = region.region_id
        captured["snapshots"] = snapshots
        captured["run_id"] = run_id
        captured["registry"] = registry
        captured["extractor_options"] = extractor_options
        status_recorder("wikidata", {"status": "success", "count": 1})
        status_recorder("wikipedia", {"status": "success", "count": 2})
        status_recorder("osm", {"status": "success", "count": 3})
        conn.execute("SELECT 1")
        return {"osm": 2}

    monkeypatch.setattr(cli.extract_stage, "build_registry", fake_build_registry)
    monkeypatch.setattr(cli.extract_stage, "run_extract", fake_run_extract)

    snapshot_dir = tmp_path / "snapshots"
    snapshot_dir.mkdir()
    (snapshot_dir / "wikidata.snapshot.json").write_text(
        '{"_meta":{"retrieved_at":"2026-07-15T00:00:00Z"}}'
    )
    db = tmp_path / "w.db"
    rc = cli.main(
        [
            "--region",
            "malaysia",
            "extract",
            "--db",
            str(db),
            "--snapshot-dir",
            str(snapshot_dir),
            "--osm-index-type",
            "sparse_file_array,/tmp/osm.idx",
            "--run-id",
            "real",
        ]
    )

    assert rc == 0
    assert captured["region"] == "malaysia"
    assert captured["snapshots"]["wikidata"] == snapshot_dir / "wikidata.snapshot.json"
    assert captured["snapshots"]["wikipedia"] == snapshot_dir / "wikipedia.snapshot.json"
    assert captured["snapshots"]["osm"] == snapshot_dir / "osm.osm.pbf"
    assert captured["run_id"] == "real"
    assert captured["extractor_options"] == {
        "osm": {"index_type": "sparse_file_array,/tmp/osm.idx"}
    }
    conn = store.connect(db)
    assert store.stage_completed(conn, "malaysia", "extract")
    assert store.load_extract_run_metadata(conn, region="malaysia", run_id="real") == {
        "region": "malaysia",
        "run_id": "real",
        "wikidata_snapshot_date": "2026-07-15T00:00:00Z",
        "source_statuses": {
            "historic_england": {"status": "disabled"},
            "national_register": {"status": "disabled"},
            "open_plaques": {"status": "disabled"},
            "osm": {"status": "success", "count": 3},
            "wikidata": {"status": "success", "count": 1},
            "wikipedia": {"status": "success", "count": 2},
        },
    }
