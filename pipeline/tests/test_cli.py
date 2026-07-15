from mt_pipeline import cli, store
from mt_pipeline.eval import report as eval_report


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
        only_source,
    ):
        captured["region"] = region.region_id
        captured["snapshots"] = snapshots
        captured["run_id"] = run_id
        captured["registry"] = registry
        captured["extractor_options"] = extractor_options
        captured["only_source"] = only_source
        status_recorder("wikidata", {"status": "success", "count": 1})
        conn.execute("SELECT 1")
        return {"wikidata": 1}

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
            "--only-source",
            "wikidata",
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
    assert captured["only_source"] == "wikidata"
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
            "osm": {"status": "preserved"},
            "wikidata": {"status": "success", "count": 1},
            "wikipedia": {"status": "preserved"},
        },
    }


def test_cli_eval_report_reads_labeled_tsv_and_config(monkeypatch, tmp_path, capsys):
    labeled = tmp_path / "golden.tsv"
    labeled.write_text(
        "\n".join(
            [
                "# Label the 'label' column only: yes; meh; no; blank.",
                "# data_version: v1",
                "place_id\tname\tlat\tlon\tcategory\ttier\tscore\theritage\tlabel",
                "mt1_00000000000000000000000000\tX\t0\t0\tc\t1\t0\t1\tyes",
            ]
        )
        + "\n"
    )
    config_path = tmp_path / "scoring.json"
    config_path.write_text('{"heritage": 1.0}')
    baseline_path = tmp_path / "baseline.json"
    baseline_path.write_text('{"all.llm_on.strict@5": 1.0}')
    captured = {}

    def fake_eval_report(rows, config, *, score_fn=None):
        captured["rows"] = rows
        captured["config"] = config
        return eval_report.EvalReport({"all.llm_on.strict@5": 1.0})

    def fake_assert_no_regression(rows, config, baseline, *, score_fn=None):
        captured["baseline"] = baseline

    monkeypatch.setattr(cli.eval_report, "eval_report", fake_eval_report)
    monkeypatch.setattr(cli.eval_report, "assert_no_regression", fake_assert_no_regression)
    rc = cli.main(
        [
            "eval",
            "report",
            str(labeled),
            "--config",
            str(config_path),
            "--baseline",
            str(baseline_path),
        ]
    )

    assert rc == 0
    assert captured["rows"][0].place_id == "mt1_00000000000000000000000000"
    assert captured["config"] == {"heritage": 1.0}
    assert captured["baseline"] == {"all.llm_on.strict@5": 1.0}
    assert "all.llm_on.strict@5\t1.000" in capsys.readouterr().out


def test_cli_eval_report_returns_nonzero_on_regression(monkeypatch, tmp_path, capsys):
    labeled = tmp_path / "golden.tsv"
    labeled.write_text(
        "\n".join(
            [
                "# Label the 'label' column only: yes; meh; no; blank.",
                "# data_version: v1",
                "place_id\tname\tlat\tlon\tcategory\ttier\tscore\theritage\tlabel",
                "mt1_00000000000000000000000000\tX\t0\t0\tc\t1\t0\t1\tyes",
            ]
        )
        + "\n"
    )
    config_path = tmp_path / "scoring.json"
    config_path.write_text('{"heritage": 0.0}')
    baseline_path = tmp_path / "baseline.json"
    baseline_path.write_text('{"all.llm_on.strict@5": 1.0}')

    def fake_eval_report(rows, config, *, score_fn=None):
        return eval_report.EvalReport({"all.llm_on.strict@5": 0.0})

    def fail_regression(rows, config, baseline, *, score_fn=None):
        raise AssertionError("ranking regression: all.llm_on.strict@5")

    monkeypatch.setattr(cli.eval_report, "eval_report", fake_eval_report)
    monkeypatch.setattr(cli.eval_report, "assert_no_regression", fail_regression)

    rc = cli.main(
        [
            "eval",
            "report",
            str(labeled),
            "--config",
            str(config_path),
            "--baseline",
            str(baseline_path),
        ]
    )

    assert rc == 1
    assert "ranking regression" in capsys.readouterr().err


def test_cli_eval_report_surfaces_parse_skips_loudly(tmp_path, capsys):
    labeled = tmp_path / "bad.tsv"
    labeled.write_text(
        "\n".join(
            [
                "# Label the 'label' column only: yes; meh; no; blank.",
                "# data_version: v1",
                "place_id\tname\tlat\tlon\tcategory\ttier\tscore\theritage\tlabel",
                "mt1_BADID\tX\t0\t0\tc\t1\t0\t1\tyes",
            ]
        )
        + "\n"
    )
    config_path = tmp_path / "scoring.json"
    config_path.write_text("{}")

    rc = cli.main(["eval", "report", str(labeled), "--config", str(config_path)])

    assert rc == 1
    err = capsys.readouterr().err
    assert "skipped" in err
    assert "invalid place_id" in err


def test_cli_eval_dump_is_blocked_until_a2_a3_a4_tables_land(tmp_path, capsys):
    db = tmp_path / "w.db"
    rc = cli.main(["eval", "dump", "london", "--db", str(db), "--run-id", "v1"])

    assert rc == 1
    assert "BLOCKED-ON A2/A3/A4" in capsys.readouterr().err


def test_cli_eval_dump_rejects_unsafe_filename_tokens(tmp_path, capsys):
    db = tmp_path / "w.db"
    rc = cli.main(["eval", "dump", "london", "--db", str(db), "--run-id", "../escape"])

    assert rc == 1
    assert "safe filename token" in capsys.readouterr().err
