import dataclasses

from mt_pipeline import cli, store
from mt_pipeline.ergonomics import fingerprint
from mt_pipeline.eval import report as eval_report
from mt_pipeline.extractors import pageviews


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


def test_cli_publish_missing_pmtiles_is_clean_error(tmp_path, capsys, monkeypatch):
    db = tmp_path / "w.db"
    conn = store.connect(db)
    store.init_schema(conn)
    store.mark_stage_complete(
        conn, "malaysia", "categorize", "cat1", "2026-07-15T00:00:00Z"
    )
    conn.close()
    monkeypatch.setenv("PATH", "")

    rc = cli.main(
        [
            "--region",
            "malaysia",
            "publish",
            "--db",
            str(db),
            "--run-id",
            "real-malaysia-20260715",
            "--publish-version",
            "20260716T000000Z",
            "--generated-at",
            "2026-07-16T00:00:00Z",
        ]
    )

    assert rc == 1
    err = capsys.readouterr().err
    assert "pmtiles" in err
    assert "v1.31.1" in err
    assert "Traceback" not in err


def test_cli_reconcile_requires_version(tmp_path, capsys):
    db = tmp_path / "w.db"
    conn = store.connect(db)
    store.init_schema(conn)
    store.mark_stage_complete(conn, "uk", "extract", "r1", "2026-07-15T00:00:00Z")
    conn.close()

    rc = cli.main(["--region", "uk", "reconcile", "--db", str(db), "--run-id", "r1"])

    assert rc == 1
    assert "--version" in capsys.readouterr().err


def test_cli_rejects_bad_reconcile_version(tmp_path, capsys):
    rc = cli.main(
        [
            "--region",
            "uk",
            "reconcile",
            "--db",
            str(tmp_path / "w.db"),
            "--version",
            "2026-07-15",
        ]
    )

    assert rc == 2
    assert "version" in capsys.readouterr().err.lower()


def test_cli_maps_db_open_failure_to_clean_error(tmp_path, capsys):
    bad = tmp_path / "no_such_dir" / "w.db"
    rc = cli.main(["--region", "uk", "extract", "--db", str(bad)])
    assert rc == 3
    assert "database" in capsys.readouterr().err.lower()


def test_cli_maps_stage_write_failure_to_clean_error(monkeypatch, tmp_path, capsys):
    import sqlite3

    def fail_mark_stage_complete(*_args, **_kwargs):
        raise sqlite3.OperationalError("disk is full")

    monkeypatch.setattr(store, "mark_stage_complete_no_commit", fail_mark_stage_complete)

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


def test_cli_audit_outputs_report_without_marking_stage(tmp_path, capsys):
    db = tmp_path / "w.db"
    conn = store.connect(db)
    store.init_schema(conn)
    conn.execute(
        """
        INSERT INTO source_records
            (region, source, source_ref, name, lat, lon, props_json, run_id)
        VALUES ('uk', 'wd', 'wd:Q1', 'A', 1, 1, '{"p31":"Q16970"}', 'r')
        """
    )
    conn.commit()

    rc = cli.main(["--region", "uk", "audit", "--db", str(db), "--audit-format", "json"])

    assert rc == 0
    assert '"region": "uk"' in capsys.readouterr().out
    assert store.stage_completed(conn, "uk", "audit") is False


def test_cli_accepts_audit_subcommand_shape(tmp_path, capsys):
    db = tmp_path / "w.db"
    conn = store.connect(db)
    store.init_schema(conn)
    conn.execute(
        """
        INSERT INTO source_records
            (region, source, source_ref, name, lat, lon, props_json, run_id)
        VALUES ('uk', 'wd', 'wd:Q1', 'A', 1, 1, '{"p31":"Q16970"}', 'r')
        """
    )
    conn.commit()

    rc = cli.main(["audit", "uk", "--db", str(db), "--audit-format", "json"])

    assert rc == 0
    assert '"region": "uk"' in capsys.readouterr().out


def test_cli_accepts_audit_subcommand_shape_from_console_argv(monkeypatch, tmp_path, capsys):
    db = tmp_path / "w.db"
    conn = store.connect(db)
    store.init_schema(conn)
    conn.execute(
        """
        INSERT INTO source_records
            (region, source, source_ref, name, lat, lon, props_json, run_id)
        VALUES ('uk', 'wd', 'wd:Q1', 'A', 1, 1, '{"p31":"Q16970"}', 'r')
        """
    )
    conn.commit()
    monkeypatch.setattr(
        cli.sys,
        "argv",
        ["mt", "audit", "uk", "--db", str(db), "--audit-format", "json"],
    )

    rc = cli.main()

    assert rc == 0
    assert '"region": "uk"' in capsys.readouterr().out


def test_cli_categorize_allows_empty_a2_places_table(tmp_path, capsys):
    db = tmp_path / "w.db"
    conn = store.connect(db)
    store.init_schema(conn)
    for stage in ("extract", "reconcile", "score"):
        store.mark_stage_complete(conn, "uk", stage, "r1", "2026-07-15T00:00:00Z")

    rc = cli.main(["--region", "uk", "categorize", "--db", str(db), "--run-id", "cat1"])

    assert rc == 0
    out = capsys.readouterr().out
    assert "categorize complete for uk" in out


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
        parallel,
        continue_on_source_failure,
        staging_root,
        commit,
    ):
        captured["region"] = region.region_id
        captured["snapshots"] = snapshots
        captured["run_id"] = run_id
        captured["registry"] = registry
        captured["extractor_options"] = extractor_options
        captured["only_source"] = only_source
        captured["parallel"] = parallel
        captured["continue_on_source_failure"] = continue_on_source_failure
        captured["staging_root"] = staging_root
        captured["commit"] = commit
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
    assert captured["parallel"] is True
    assert captured["continue_on_source_failure"] is False
    assert captured["staging_root"] == snapshot_dir.parent
    assert captured["commit"] is False
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


def test_cli_extract_threads_pageview_options_for_wikipedia_only(monkeypatch, tmp_path):
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
        parallel,
        continue_on_source_failure,
        staging_root,
        commit,
    ):
        captured["extractor_options"] = extractor_options
        captured["only_source"] = only_source
        captured["parallel"] = parallel
        status_recorder("wikipedia", {"status": "success", "count": 1})
        conn.execute("SELECT 1")
        return {"wikipedia": 1}

    monkeypatch.setattr(cli.extract_stage, "build_registry", fake_build_registry)
    monkeypatch.setattr(cli.extract_stage, "run_extract", fake_run_extract)

    snapshot_dir = tmp_path / "snapshots"
    snapshot_dir.mkdir()
    (snapshot_dir / "wikipedia.snapshot.json").write_text(
        '{"_meta":{"complete":true,"retrieved_at":"2026-07-15T00:00:00Z"},"pages":[]}'
    )
    pageviews.ensure_manifest(
        snapshot_dir / "pageviews",
        ("2025-07-15", "2026-07-15"),
    )

    rc = cli.main(
        [
            "--region",
            "malaysia",
            "extract",
            "--db",
            str(tmp_path / "w.db"),
            "--snapshot-dir",
            str(snapshot_dir),
            "--only-source",
            "wikipedia",
            "--run-id",
            "real",
        ]
    )

    assert rc == 0
    assert captured["only_source"] == "wikipedia"
    assert captured["parallel"] is True
    assert captured["extractor_options"]["wikipedia"] == {
        "pageview_cache_dir": snapshot_dir / "pageviews",
        "pageview_window": ("2025-07-15", "2026-07-15"),
    }


def test_extract_fingerprint_inputs_thread_pageview_window_and_selected_cache_files(tmp_path):
    snapshot_dir = tmp_path / "snapshots"
    snapshot_dir.mkdir()
    wikipedia_snapshot = snapshot_dir / "wikipedia.snapshot.json"
    wikipedia_snapshot.write_text(
        '{"_meta":{"complete":true,"retrieved_at":"2026-07-15T00:00:00Z"},"pages":[{"title":"B"},{"title":"A"}]}'
    )
    pageviews.ensure_manifest(
        snapshot_dir / "pageviews",
        ("2025-07-15", "2026-07-15"),
    )
    region = cli.config.load("malaysia")

    inputs = cli._extract_fingerprint_inputs(
        region,
        cli.acquire.snapshot_paths(snapshot_dir),
        snap_dir=snapshot_dir,
        only_source="wikipedia",
    )

    assert inputs.pageview_window == ("2025-07-15", "2026-07-15")
    assert inputs.pageview_cache_files == (
        pageviews._cache_path(
            snapshot_dir / "pageviews",
            "A",
            ("2025-07-15", "2026-07-15"),
        ),
        pageviews._cache_path(
            snapshot_dir / "pageviews",
            "B",
            ("2025-07-15", "2026-07-15"),
        ),
    )


def test_cli_extract_rejects_mismatched_pageview_manifest(monkeypatch, tmp_path, capsys):
    def fail_run_extract(*_args, **_kwargs):
        raise AssertionError("extract should not start with a stale pageview manifest")

    monkeypatch.setattr(cli.extract_stage, "run_extract", fail_run_extract)

    snapshot_dir = tmp_path / "snapshots"
    snapshot_dir.mkdir()
    (snapshot_dir / "wikipedia.snapshot.json").write_text(
        '{"_meta":{"complete":true,"retrieved_at":"2026-07-15T00:00:00Z"},"pages":[]}'
    )
    pageviews.ensure_manifest(
        snapshot_dir / "pageviews",
        ("2025-07-14", "2026-07-14"),
    )

    rc = cli.main(
        [
            "--region",
            "malaysia",
            "extract",
            "--db",
            str(tmp_path / "w.db"),
            "--snapshot-dir",
            str(snapshot_dir),
            "--only-source",
            "wikipedia",
            "--run-id",
            "real",
        ]
    )

    assert rc == 1
    assert "pageview cache window" in capsys.readouterr().err


def test_cli_extract_skips_matching_stage_fingerprint(monkeypatch, tmp_path, capsys):
    def fail_run_extract(*_args, **_kwargs):
        raise AssertionError("extract should be skipped before source work")

    monkeypatch.setattr(cli.extract_stage, "run_extract", fail_run_extract)

    snapshot_dir = tmp_path / "snapshots"
    snapshot_dir.mkdir()
    wikidata_snapshot = snapshot_dir / "wikidata.snapshot.json"
    wikidata_snapshot.write_text(
        '{"_meta":{"retrieved_at":"2026-07-15T00:00:00Z"}}'
    )
    db = tmp_path / "w.db"
    conn = store.connect(db)
    store.init_schema(conn)
    region = cli.config.load("malaysia")
    snapshots = cli.acquire.snapshot_paths(snapshot_dir)
    fp = fingerprint.stage_fingerprint(
        conn,
        "malaysia",
        "extract",
        inputs=cli._extract_fingerprint_inputs(
            region,
            snapshots,
            only_source="wikidata",
        ),
    )
    fingerprint.record(
        conn,
        "malaysia",
        "extract",
        fp,
        completed_at="2026-07-15T00:00:00Z",
    )
    store.record_extract_run_metadata(
        conn,
        region="malaysia",
        run_id="old",
        wikidata_snapshot_date="2026-07-15T00:00:00Z",
        source_statuses={"wikidata": {"status": "success", "count": 1}},
    )
    store.mark_stage_complete(
        conn,
        "malaysia",
        "extract",
        run_id="old",
        completed_at="2026-07-15T00:00:00Z",
    )
    conn.close()

    rc = cli.main(
        [
            "--region",
            "malaysia",
            "extract",
            "--db",
            str(db),
            "--snapshot-dir",
            str(snapshot_dir),
            "--only-source",
            "wikidata",
            "--run-id",
            "real",
        ]
    )

    assert rc == 0
    captured = capsys.readouterr()
    assert "extract skipped for malaysia" in captured.out
    assert "SKIP stage=extract region=malaysia fingerprint=" in captured.err
    conn = store.connect(db)
    assert store.load_extract_run_metadata(conn, region="malaysia", run_id="real") == {
        "region": "malaysia",
        "run_id": "real",
        "wikidata_snapshot_date": "2026-07-15T00:00:00Z",
        "source_statuses": {"wikidata": {"status": "success", "count": 1}},
    }


def test_reconcile_fingerprint_inputs_intersect_successes_with_enabled_sources(
    monkeypatch, tmp_path
):
    conn = store.connect(tmp_path / "w.db")
    store.init_schema(conn)
    store.record_extract_run_metadata(
        conn,
        region="uk",
        run_id="r1",
        wikidata_snapshot_date="2026-07-15T00:00:00Z",
        source_statuses={
            "osm": {"status": "success", "count": 1},
            "wikidata": {"status": "success", "count": 1},
        },
    )
    region = dataclasses.replace(
        cli.config.load("uk"),
        sources={**cli.config.load("uk").sources, "osm": False},
    )

    inputs = cli._stage_fingerprint_inputs(
        conn,
        region,
        "reconcile",
        run_id="r1",
        version="20260716T000000Z",
    )

    assert inputs.succeeded_sources == {"wd"}


def test_cli_extract_fails_early_when_snapshot_sidecar_has_no_payload(
    monkeypatch,
    tmp_path,
    capsys,
):
    def fail_run_extract(*_args, **_kwargs):
        raise AssertionError("extract should not start with a missing snapshot payload")

    monkeypatch.setattr(cli.extract_stage, "run_extract", fail_run_extract)

    snapshot_dir = tmp_path / "snapshots"
    snapshot_dir.mkdir()
    (snapshot_dir / "osm.osm.pbf.meta.json").write_text(
        '{"geofabrik_date":"2026-07-15","sha256":"deadbeef","size":123,"source_url":"https://download.geofabrik.de/example.osm.pbf"}'
    )

    rc = cli.main(
        [
            "--region",
            "malaysia",
            "extract",
            "--db",
            str(tmp_path / "w.db"),
            "--snapshot-dir",
            str(snapshot_dir),
            "--only-source",
            "osm",
            "--run-id",
            "real",
        ]
    )

    assert rc == 1
    err = capsys.readouterr().err
    assert "snapshot payload missing" in err
    assert "osm.osm.pbf" in err
    assert "re-run acquire" in err


def test_cli_full_extract_fails_early_when_selected_snapshot_sidecar_has_no_payload(
    monkeypatch,
    tmp_path,
    capsys,
):
    def fail_run_extract(*_args, **_kwargs):
        raise AssertionError("extract should not start with a missing snapshot payload")

    monkeypatch.setattr(cli.extract_stage, "run_extract", fail_run_extract)

    snapshot_dir = tmp_path / "snapshots"
    snapshot_dir.mkdir()
    (snapshot_dir / "wikidata.snapshot.json").write_text(
        '{"_meta":{"retrieved_at":"2026-07-15T00:00:00Z"}}'
    )
    (snapshot_dir / "osm.osm.pbf.meta.json").write_text(
        '{"geofabrik_date":"2026-07-15","sha256":"deadbeef","size":123,"source_url":"https://download.geofabrik.de/example.osm.pbf"}'
    )

    rc = cli.main(
        [
            "--region",
            "malaysia",
            "extract",
            "--db",
            str(tmp_path / "w.db"),
            "--snapshot-dir",
            str(snapshot_dir),
            "--run-id",
            "real",
        ]
    )

    assert rc == 1
    err = capsys.readouterr().err
    assert "snapshot payload missing for osm" in err
    assert "re-run acquire" in err


def test_cli_extract_ignores_sidecars_for_disabled_sources(
    monkeypatch,
    tmp_path,
):
    captured = {}

    def fake_build_registry(*_args, **_kwargs):
        return object()

    def fake_run_extract(
        _conn,
        _region,
        _snapshots,
        *,
        run_id,
        registry,
        extractor_options,
        status_recorder,
        only_source,
        parallel,
        continue_on_source_failure,
        staging_root,
        commit,
    ):
        captured["parallel"] = parallel
        status_recorder("wikidata", {"status": "success", "count": 1})
        return {"wikidata": 1}

    monkeypatch.setattr(cli.extract_stage, "build_registry", fake_build_registry)
    monkeypatch.setattr(cli.extract_stage, "run_extract", fake_run_extract)

    snapshot_dir = tmp_path / "snapshots"
    snapshot_dir.mkdir()
    (snapshot_dir / "wikidata.snapshot.json").write_text(
        '{"_meta":{"retrieved_at":"2026-07-15T00:00:00Z"}}'
    )
    (snapshot_dir / "historic_england.snapshot.meta.json").write_text(
        '{"sha256":"deadbeef"}'
    )

    rc = cli.main(
        [
            "--region",
            "malaysia",
            "extract",
            "--db",
            str(tmp_path / "w.db"),
            "--snapshot-dir",
            str(snapshot_dir),
            "--only-source",
            "wikidata",
            "--run-id",
            "real",
        ]
    )

    assert rc == 0
    assert captured["parallel"] is True


def test_cli_only_source_osm_preserves_previous_wikidata_date_without_wikidata_payload(
    monkeypatch,
    tmp_path,
):
    def fake_build_registry(*_args, **_kwargs):
        return object()

    def fake_run_extract(
        _conn,
        _region,
        _snapshots,
        *,
        run_id,
        registry,
        extractor_options,
        status_recorder,
        only_source,
        parallel,
        continue_on_source_failure,
        staging_root,
        commit,
    ):
        assert only_source == "osm"
        status_recorder("osm", {"status": "success", "count": 1})
        return {"osm": 1}

    monkeypatch.setattr(cli.extract_stage, "build_registry", fake_build_registry)
    monkeypatch.setattr(cli.extract_stage, "run_extract", fake_run_extract)

    snapshot_dir = tmp_path / "snapshots"
    snapshot_dir.mkdir()
    (snapshot_dir / "osm.osm.pbf").write_bytes(b"osm")
    db = tmp_path / "w.db"
    conn = store.connect(db)
    store.init_schema(conn)
    store.record_extract_run_metadata(
        conn,
        region="malaysia",
        run_id="old",
        wikidata_snapshot_date="2026-07-15T00:00:00Z",
        source_statuses={"wikidata": {"status": "success", "count": 1}},
    )
    store.mark_stage_complete(
        conn,
        "malaysia",
        "extract",
        run_id="old",
        completed_at="2026-07-15T00:00:00Z",
    )
    conn.close()

    rc = cli.main(
        [
            "--region",
            "malaysia",
            "extract",
            "--db",
            str(db),
            "--snapshot-dir",
            str(snapshot_dir),
            "--only-source",
            "osm",
            "--run-id",
            "real",
        ]
    )

    assert rc == 0
    conn = store.connect(db)
    assert store.load_extract_run_metadata(conn, region="malaysia", run_id="real")[
        "wikidata_snapshot_date"
    ] == "2026-07-15T00:00:00Z"


def test_cli_extract_keeps_typed_error_for_enabled_source_without_snapshot_mapping(
    monkeypatch,
    tmp_path,
    capsys,
):
    class FutureRegion:
        region_id = "future"
        display_name = "Future"
        bbox = (0.0, 0.0, 1.0, 1.0)
        languages = ("en",)
        sources = {"national_register": True}

    monkeypatch.setattr(cli.config, "load", lambda _region: FutureRegion())

    snapshot_dir = tmp_path / "snapshots"
    snapshot_dir.mkdir()

    rc = cli.main(
        [
            "--region",
            "future",
            "extract",
            "--db",
            str(tmp_path / "w.db"),
            "--snapshot-dir",
            str(snapshot_dir),
            "--run-id",
            "real",
        ]
    )

    assert rc == 1
    assert "national_register" in capsys.readouterr().err


def test_cli_parallel_extract_rolls_back_merge_metadata_and_stage_together(
    monkeypatch,
    tmp_path,
    capsys,
):
    def fake_build_registry(*_args, **_kwargs):
        return object()

    def fake_run_extract(
        conn,
        region,
        _snapshots,
        *,
        run_id,
        registry,
        extractor_options,
        status_recorder,
        only_source,
        parallel,
        continue_on_source_failure,
        staging_root,
        commit,
    ):
        assert parallel is True
        assert commit is False
        status_recorder("wikidata", {"status": "success", "count": 1})
        conn.execute(
            """
            INSERT INTO source_records
                (region, source, source_ref, name, lat, lon, props_json, run_id)
            VALUES (?, 'wd', 'wd:Q1', 'A', 1, 1, '{}', ?)
            """,
            (region.region_id, run_id),
        )
        return {"wikidata": 1}

    def fail_mark_stage(*_args, **_kwargs):
        import sqlite3

        raise sqlite3.OperationalError("stage write failed")

    monkeypatch.setattr(cli.extract_stage, "build_registry", fake_build_registry)
    monkeypatch.setattr(cli.extract_stage, "run_extract", fake_run_extract)
    monkeypatch.setattr(store, "mark_stage_complete_no_commit", fail_mark_stage)

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
            "--only-source",
            "wikidata",
            "--run-id",
            "real",
        ]
    )

    assert rc == 3
    assert "stage write failed" in capsys.readouterr().err
    conn = store.connect(db)
    assert conn.execute("SELECT COUNT(*) FROM source_records").fetchone()[0] == 0
    assert (
        store.load_extract_run_metadata(conn, region="malaysia", run_id="real")
        is None
    )
    assert not store.stage_completed(conn, "malaysia", "extract")


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


def test_cli_llm_cost_reads_jsonl_and_reports_keyless_cost(tmp_path, capsys):
    corpus = tmp_path / "golden.jsonl"
    corpus.write_text(
        '{"place_id":"mt1_00000000000000000000000000","name":"Old Windmill",'
        '"category":"historic","evidence":"",'
        '"signals":{"article":1.0,"tag_rarity":0.5}}\n'
    )
    models = tmp_path / "models.json"
    models.write_text('{"models":[{"id":"fake-curiosity-v1","provider":"fake"}]}')
    pricing = tmp_path / "pricing.json"
    pricing.write_text('{"models":{"fake-curiosity-v1":{"input_per_m":0.15,"output_per_m":0.60}}}')

    rc = cli.main(["llm", "cost", "--corpus", str(corpus), "--models", str(models), "--pricing", str(pricing)])

    assert rc == 0
    out = capsys.readouterr().out
    assert "model\tprovider\tinput_tokens\toutput_token_cap\ttotal_usd\ttoken_source" in out
    assert "fake-curiosity-v1\tfake\t" in out
    assert "byte-estimate" in out


def _write_llm_cost_inputs(tmp_path):
    corpus = tmp_path / "golden.jsonl"
    corpus.write_text(
        '{"place_id":"mt1_00000000000000000000000000","name":"Old Windmill",'
        '"category":"historic","evidence":"",'
        '"signals":{"article":1.0,"tag_rarity":0.5}}\n'
    )
    models = tmp_path / "models.json"
    models.write_text('{"models":[{"id":"fake-curiosity-v1","provider":"fake"}]}')
    pricing = tmp_path / "pricing.json"
    pricing.write_text('{"models":{"fake-curiosity-v1":{"input_per_m":0.15,"output_per_m":0.60}}}')
    return corpus, models, pricing


def test_cli_llm_cost_invalid_jsonl_reports_error(tmp_path, capsys):
    corpus, models, pricing = _write_llm_cost_inputs(tmp_path)
    corpus.write_text(corpus.read_text() + "not-json\n")

    rc = cli.main(["llm", "cost", "--corpus", str(corpus), "--models", str(models), "--pricing", str(pricing)])

    assert rc == 1
    assert "llm cost error:" in capsys.readouterr().err


def test_cli_llm_cost_models_missing_or_not_list_reports_error(tmp_path, capsys):
    corpus, models, pricing = _write_llm_cost_inputs(tmp_path)
    models.write_text('{"not_models":[{"id":"fake-curiosity-v1","provider":"fake"}]}')

    rc = cli.main(["llm", "cost", "--corpus", str(corpus), "--models", str(models), "--pricing", str(pricing)])

    assert rc == 1
    assert "llm cost error:" in capsys.readouterr().err

    models.write_text('{"models":{"id":"fake-curiosity-v1","provider":"fake"}}')
    rc = cli.main(["llm", "cost", "--corpus", str(corpus), "--models", str(models), "--pricing", str(pricing)])

    assert rc == 1
    assert "llm cost error:" in capsys.readouterr().err


def test_cli_llm_cost_pricing_models_not_dict_reports_error(tmp_path, capsys):
    corpus, models, pricing = _write_llm_cost_inputs(tmp_path)
    pricing.write_text('{"models":[{"fake-curiosity-v1":{"input_per_m":0.15,"output_per_m":0.60}}]}')

    rc = cli.main(["llm", "cost", "--corpus", str(corpus), "--models", str(models), "--pricing", str(pricing)])

    assert rc == 1
    assert "llm cost error:" in capsys.readouterr().err


def test_cli_llm_bakeoff_runs_keyless_fake_provider(tmp_path, capsys):
    labeled = tmp_path / "golden.tsv"
    labeled.write_text(
        "\n".join(
            [
                "# Label the 'label' column only: yes; meh; no; blank.",
                "# data_version: v1",
                "place_id\tarea\tactive\tname\tlat\tlon\tcategory\ttier\tscore\tdata_version\tarticle\tllm_curiosity\tlabeled_by\tevidence\tlabel",
                "mt1_00000000000000000000000000\tkl\ttrue\tA\t0\t0\tc\t1\t0\tv1\t0.1\t\trob\t\tyes",
                "mt1_11111111111111111111111111\tkl\ttrue\tB\t0\t0\tc\t1\t0\tv1\t0.9\t\trob\t\tno",
            ]
        )
        + "\n"
    )
    config_path = tmp_path / "scoring.json"
    config_path.write_text('{"weights": {"article": 1.0, "llm_curiosity": 2.0}}')
    models = tmp_path / "models.json"
    models.write_text('{"models":[{"id":"fake-curiosity-v1","provider":"fake"}]}')
    pricing = tmp_path / "pricing.json"
    pricing.write_text('{"models":{"fake-curiosity-v1":{"input_per_m":0.15,"output_per_m":0.60}}}')

    rc = cli.main(
        [
            "llm",
            "bakeoff",
            "--labeled",
            str(labeled),
            "--config",
            str(config_path),
            "--models",
            str(models),
            "--pricing",
            str(pricing),
            "--k",
            "1",
        ]
    )

    assert rc == 0
    out = capsys.readouterr().out
    assert "model\tprovider\tprecision_at_k_llm_on" in out
    assert "inflation_resistance\tdeflation_resistance\thonest_suppression_rate\ttwo_sided_injection_resistance\tinjection_floor_passed" in out
    assert "fake-curiosity-v1\t" in out
