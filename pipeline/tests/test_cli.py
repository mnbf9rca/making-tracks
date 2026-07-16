import json

import pytest

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
    assert "fake-curiosity-v1\t" in out


def test_cli_llm_bakeoff_without_live_does_not_construct_nous_provider(tmp_path, capsys, monkeypatch):
    from mt_pipeline.llm.providers import nous

    labeled = tmp_path / "golden.tsv"
    labeled.write_text(
        "\n".join(
            [
                "# Label the 'label' column only: yes; meh; no; blank.",
                "# data_version: v1",
                "place_id\tarea\tactive\tname\tlat\tlon\tcategory\ttier\tscore\tdata_version\tarticle\tllm_curiosity\tlabeled_by\tevidence\tlabel",
                "mt1_00000000000000000000000000\tkl\ttrue\tA\t0\t0\tc\t1\t0\tv1\t0.1\t\trob\t\tyes",
            ]
        )
        + "\n"
    )
    config_path = tmp_path / "scoring.json"
    config_path.write_text('{"weights": {"article": 1.0, "llm_curiosity": 2.0}}')
    models = tmp_path / "models.json"
    models.write_text('{"models":[{"id":"nous-cheap","provider":"nous","api_model_id":"Nous-API-Cheap"}]}')
    pricing = tmp_path / "pricing.json"
    pricing.write_text('{"models":{"nous-cheap":{"provider":"nous","input_per_m":0.15,"output_per_m":0.60}}}')

    def fail_provider_construction(**_kwargs):
        raise AssertionError("NOUS provider must not be constructed without --live")

    monkeypatch.setenv("NOUS_API_KEY", "sk-test")
    monkeypatch.setattr(nous, "NousProvider", fail_provider_construction)

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
        ]
    )

    assert rc == 1
    assert "live bakeoff is blocked on keys" in capsys.readouterr().err


def test_cli_llm_live_bakeoff_requires_max_places(tmp_path, capsys, monkeypatch):
    labeled = tmp_path / "golden.tsv"
    labeled.write_text("")
    config_path = tmp_path / "scoring.json"
    config_path.write_text("{}")
    monkeypatch.setenv("NOUS_API_KEY", "sk-test")

    rc = cli.main(["llm", "bakeoff", "--live", "--labeled", str(labeled), "--config", str(config_path)])

    assert rc == 2
    err = capsys.readouterr().err
    assert "--max-places is required with --live" in err


@pytest.mark.parametrize("max_places", ["0", "-1"])
def test_cli_llm_live_bakeoff_rejects_nonpositive_max_places(tmp_path, capsys, monkeypatch, max_places):
    labeled = tmp_path / "golden.tsv"
    labeled.write_text("")
    config_path = tmp_path / "scoring.json"
    config_path.write_text("{}")
    monkeypatch.setenv("NOUS_API_KEY", "sk-test")

    rc = cli.main(
        [
            "llm",
            "bakeoff",
            "--live",
            "--max-places",
            max_places,
            "--labeled",
            str(labeled),
            "--config",
            str(config_path),
        ]
    )

    assert rc == 2
    assert "--max-places must be positive with --live" in capsys.readouterr().err


def test_cli_llm_live_bakeoff_rejects_empty_nous_key(tmp_path, capsys, monkeypatch):
    labeled = tmp_path / "golden.tsv"
    labeled.write_text("")
    config_path = tmp_path / "scoring.json"
    config_path.write_text("{}")
    monkeypatch.setenv("NOUS_API_KEY", "")

    rc = cli.main(
        [
            "llm",
            "bakeoff",
            "--live",
            "--max-places",
            "1",
            "--labeled",
            str(labeled),
            "--config",
            str(config_path),
        ]
    )

    assert rc == 1
    assert "NOUS_API_KEY is required and must be non-empty" in capsys.readouterr().err


def test_cli_llm_live_bakeoff_reports_per_place_cache_and_precision(tmp_path, capsys, monkeypatch):
    from mt_pipeline.llm import curiosity
    from mt_pipeline.llm.models import ProviderResponse
    from mt_pipeline.llm.providers import nous

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
    models.write_text('{"models":[{"id":"nous-cheap","provider":"nous","api_model_id":"Nous-API-Cheap"}]}')
    pricing = tmp_path / "pricing.json"
    pricing.write_text('{"models":{"nous-cheap":{"provider":"nous","input_per_m":0.15,"output_per_m":0.60}}}')
    calls = []
    constructed = {"count": 0}

    class StubNousProvider:
        def __init__(self, **_kwargs):
            constructed["count"] += 1
            pass

        async def acomplete_batch(self, reqs):
            calls.extend(req.query_id for req in reqs)
            responses = []
            for req in reqs:
                assert req.model_id == "Nous-API-Cheap"
                value = 0.9 if req.query_id.endswith("0" * 26) else 0.1
                responses.append(
                    ProviderResponse(
                        text=f'{{"curiosity": {value}}}',
                        model_fingerprint=req.model_id,
                        input_tokens=10,
                        output_tokens=2,
                        latency_ms=0,
                        cost_usd=0.00001,
                        app_id=None,
                    )
                )
            return responses

        async def shutdown(self):
            return None

    monkeypatch.setenv("NOUS_API_KEY", "sk-test")
    monkeypatch.setattr(nous, "NousProvider", StubNousProvider)
    cache_dir = tmp_path / "cache"
    argv = [
        "llm",
        "bakeoff",
        "--live",
        "--max-places",
        "2",
        "--labeled",
        str(labeled),
        "--config",
        str(config_path),
        "--models",
        str(models),
        "--pricing",
        str(pricing),
        "--cache-dir",
        str(cache_dir),
        "--k",
        "1",
    ]

    assert cli.main(argv) == 0
    first = capsys.readouterr().out
    assert f"prompt_version\t{curiosity.CURIOSITY_PROMPT_VERSION}" in first
    assert "place_id\tmodel\tcuriosity\tcache_hit\tcost_usd\tcost_source" in first
    assert "mt1_00000000000000000000000000\tnous-cheap\t0.900000\tfalse\t0.00001000\tderived" in first
    assert "mt1_11111111111111111111111111\tnous-cheap\t0.100000\tfalse\t0.00001000\tderived" in first
    assert "total_incremental_cost_usd\t0.00002000" in first
    assert "estimated_total_cost_usd\t" in first
    assert "precision_at_1_llm_on\t1.000" in first
    assert "precision_at_1_llm_off\t0.000" in first
    assert calls == ["mt1_00000000000000000000000000", "mt1_11111111111111111111111111"]
    assert constructed["count"] == 1

    assert cli.main(argv) == 0
    second = capsys.readouterr().out
    assert "mt1_00000000000000000000000000\tnous-cheap\t0.900000\ttrue\t0.00000000\tcache" in second
    assert "mt1_11111111111111111111111111\tnous-cheap\t0.100000\ttrue\t0.00000000\tcache" in second
    assert "cache_hits\t2/2" in second
    assert "total_incremental_cost_usd\t0.00000000" in second
    assert "estimated_total_cost_usd\t" in second
    assert calls == ["mt1_00000000000000000000000000", "mt1_11111111111111111111111111"]
    assert constructed["count"] == 1


def test_cli_llm_live_bakeoff_refuses_when_ledger_plus_estimate_exceeds_cap(tmp_path, capsys, monkeypatch):
    from mt_pipeline.llm.providers import nous

    labeled = tmp_path / "golden.tsv"
    labeled.write_text(
        "\n".join(
            [
                "# Label the 'label' column only: yes; meh; no; blank.",
                "# data_version: v1",
                "place_id\tarea\tactive\tname\tlat\tlon\tcategory\ttier\tscore\tdata_version\tarticle\tllm_curiosity\tlabeled_by\tevidence\tlabel",
                "mt1_00000000000000000000000000\tkl\ttrue\tA\t0\t0\tc\t1\t0\tv1\t0.1\t\trob\t\tyes",
            ]
        )
        + "\n"
    )
    config_path = tmp_path / "scoring.json"
    config_path.write_text('{"weights": {"article": 1.0, "llm_curiosity": 2.0}}')
    models = tmp_path / "models.json"
    models.write_text('{"models":[{"id":"nous-cheap","provider":"nous"}]}')
    pricing = tmp_path / "pricing.json"
    pricing.write_text('{"models":{"nous-cheap":{"provider":"nous","input_per_m":1000.0,"output_per_m":1000.0}}}')
    cache_dir = tmp_path / "cache"
    cache_dir.mkdir()
    (cache_dir.parent / "live-cost-ledger.json").write_text(
        json.dumps({"schema_version": 1, "total_usd": 9.99, "measured_usd": 9.99, "derived_usd": 0.0, "runs": 1})
    )

    def fail_provider_construction(**_kwargs):
        raise AssertionError("NOUS provider must not be constructed after budget refusal")

    monkeypatch.setenv("NOUS_API_KEY", "sk-test")
    monkeypatch.setattr(nous, "NousProvider", fail_provider_construction)

    rc = cli.main(
        [
            "llm",
            "bakeoff",
            "--live",
            "--max-places",
            "1",
            "--budget-cap",
            "10.00",
            "--labeled",
            str(labeled),
            "--config",
            str(config_path),
            "--models",
            str(models),
            "--pricing",
            str(pricing),
            "--cache-dir",
            str(cache_dir),
        ]
    )

    assert rc == 1
    err = capsys.readouterr().err
    assert "budget cap exceeded" in err
    assert "ledger_total_usd=9.99000000" in err


def test_cli_llm_live_bakeoff_allows_cached_run_near_cap_without_provider(tmp_path, monkeypatch):
    from mt_pipeline.llm.models import ProviderResponse
    from mt_pipeline.llm.providers import nous

    labeled = tmp_path / "golden.tsv"
    labeled.write_text(
        "\n".join(
            [
                "# Label the 'label' column only: yes; meh; no; blank.",
                "# data_version: v1",
                "place_id\tarea\tactive\tname\tlat\tlon\tcategory\ttier\tscore\tdata_version\tarticle\tllm_curiosity\tlabeled_by\tevidence\tlabel",
                "mt1_00000000000000000000000000\tkl\ttrue\tA\t0\t0\tc\t1\t0\tv1\t0.1\t\trob\t\tyes",
            ]
        )
        + "\n"
    )
    config_path = tmp_path / "scoring.json"
    config_path.write_text('{"weights": {"article": 1.0, "llm_curiosity": 2.0}}')
    models = tmp_path / "models.json"
    models.write_text('{"models":[{"id":"nous-cheap","provider":"nous"}]}')
    pricing = tmp_path / "pricing.json"
    pricing.write_text('{"models":{"nous-cheap":{"provider":"nous","input_per_m":1000.0,"output_per_m":1000.0}}}')
    cache_dir = tmp_path / "cache"

    class FirstRunProvider:
        def __init__(self, **_kwargs):
            pass

        async def acomplete_batch(self, _reqs):
            return [
                ProviderResponse(
                    text='{"curiosity": 0.9}',
                    model_fingerprint="nous-cheap",
                    input_tokens=10,
                    output_tokens=2,
                    latency_ms=0,
                    cost_usd=0.00001,
                    cost_source="measured",
                    app_id=None,
                )
            ]

        async def shutdown(self):
            return None

    argv = [
        "llm",
        "bakeoff",
        "--live",
        "--max-places",
        "1",
        "--budget-cap",
        "10.00",
        "--labeled",
        str(labeled),
        "--config",
        str(config_path),
        "--models",
        str(models),
        "--pricing",
        str(pricing),
        "--cache-dir",
        str(cache_dir),
    ]
    monkeypatch.setenv("NOUS_API_KEY", "sk-test")
    monkeypatch.setattr(nous, "NousProvider", FirstRunProvider)
    assert cli.main(argv) == 0
    (cache_dir.parent / "live-cost-ledger.json").write_text(
        json.dumps({"schema_version": 1, "total_usd": 9.99, "measured_usd": 9.99, "derived_usd": 0.0, "runs": 1})
    )

    def fail_provider_construction(**_kwargs):
        raise AssertionError("cached run must not construct provider")

    monkeypatch.setattr(nous, "NousProvider", fail_provider_construction)

    assert cli.main(argv) == 0


def test_cli_llm_live_bakeoff_rejects_inconsistent_cost_ledger(tmp_path, capsys, monkeypatch):
    labeled = tmp_path / "golden.tsv"
    labeled.write_text(
        "\n".join(
            [
                "# Label the 'label' column only: yes; meh; no; blank.",
                "# data_version: v1",
                "place_id\tarea\tactive\tname\tlat\tlon\tcategory\ttier\tscore\tdata_version\tarticle\tllm_curiosity\tlabeled_by\tevidence\tlabel",
                "mt1_00000000000000000000000000\tkl\ttrue\tA\t0\t0\tc\t1\t0\tv1\t0.1\t\trob\t\tyes",
            ]
        )
        + "\n"
    )
    config_path = tmp_path / "scoring.json"
    config_path.write_text('{"weights": {"article": 1.0, "llm_curiosity": 2.0}}')
    models = tmp_path / "models.json"
    models.write_text('{"models":[{"id":"nous-cheap","provider":"nous"}]}')
    pricing = tmp_path / "pricing.json"
    pricing.write_text('{"models":{"nous-cheap":{"provider":"nous","input_per_m":0.15,"output_per_m":0.60}}}')
    cache_dir = tmp_path / "cache"
    cache_dir.mkdir()
    (cache_dir.parent / "live-cost-ledger.json").write_text(
        json.dumps({"schema_version": 1, "total_usd": 0.0, "measured_usd": 9.99, "derived_usd": 0.0, "runs": 1})
    )
    monkeypatch.setenv("NOUS_API_KEY", "sk-test")

    rc = cli.main(
        [
            "llm",
            "bakeoff",
            "--live",
            "--max-places",
            "1",
            "--budget-cap",
            "10.00",
            "--labeled",
            str(labeled),
            "--config",
            str(config_path),
            "--models",
            str(models),
            "--pricing",
            str(pricing),
            "--cache-dir",
            str(cache_dir),
        ]
    )

    assert rc == 1
    assert "total_usd must equal measured_usd + derived_usd" in capsys.readouterr().err


def test_cli_llm_live_bakeoff_updates_and_prints_cost_ledger(tmp_path, capsys, monkeypatch):
    from mt_pipeline.llm.models import ProviderResponse
    from mt_pipeline.llm.providers import nous

    labeled = tmp_path / "golden.tsv"
    labeled.write_text(
        "\n".join(
            [
                "# Label the 'label' column only: yes; meh; no; blank.",
                "# data_version: v1",
                "place_id\tarea\tactive\tname\tlat\tlon\tcategory\ttier\tscore\tdata_version\tarticle\tllm_curiosity\tlabeled_by\tevidence\tlabel",
                "mt1_00000000000000000000000000\tkl\ttrue\tA\t0\t0\tc\t1\t0\tv1\t0.1\t\trob\t\tyes",
            ]
        )
        + "\n"
    )
    config_path = tmp_path / "scoring.json"
    config_path.write_text('{"weights": {"article": 1.0, "llm_curiosity": 2.0}}')
    models = tmp_path / "models.json"
    models.write_text('{"models":[{"id":"nous-cheap","provider":"nous"}]}')
    pricing = tmp_path / "pricing.json"
    pricing.write_text('{"models":{"nous-cheap":{"provider":"nous","input_per_m":0.15,"output_per_m":0.60}}}')
    cache_dir = tmp_path / "cache"

    class MeasuredCostNousProvider:
        def __init__(self, **_kwargs):
            pass

        async def acomplete_batch(self, reqs):
            return [
                ProviderResponse(
                    text='{"curiosity": 0.9}',
                    model_fingerprint=reqs[0].model_id,
                    input_tokens=10,
                    output_tokens=2,
                    latency_ms=0,
                    cost_usd=0.000123,
                    cost_source="measured",
                    app_id=None,
                )
            ]

        async def shutdown(self):
            return None

    monkeypatch.setenv("NOUS_API_KEY", "sk-test")
    monkeypatch.setattr(nous, "NousProvider", MeasuredCostNousProvider)

    rc = cli.main(
        [
            "llm",
            "bakeoff",
            "--live",
            "--max-places",
            "1",
            "--budget-cap",
            "10.00",
            "--labeled",
            str(labeled),
            "--config",
            str(config_path),
            "--models",
            str(models),
            "--pricing",
            str(pricing),
            "--cache-dir",
            str(cache_dir),
        ]
    )

    assert rc == 0
    out = capsys.readouterr().out
    assert "place_id\tmodel\tcuriosity\tcache_hit\tcost_usd\tcost_source" in out
    assert "total_incremental_cost_usd\t0.00012300" in out
    assert "ledger_total_usd\t0.00012300" in out
    assert "ledger_budget_cap_usd\t10.00000000" in out
    ledger = json.loads((cache_dir.parent / "live-cost-ledger.json").read_text())
    assert ledger["total_usd"] == pytest.approx(0.000123)
    assert ledger["measured_usd"] == pytest.approx(0.000123)
    assert ledger["derived_usd"] == pytest.approx(0.0)
    assert ledger["runs"] == 1


def test_cli_llm_live_bakeoff_shuts_down_provider_when_batch_raises(tmp_path, monkeypatch):
    from mt_pipeline.llm.providers import nous

    labeled = tmp_path / "golden.tsv"
    labeled.write_text(
        "\n".join(
            [
                "# Label the 'label' column only: yes; meh; no; blank.",
                "# data_version: v1",
                "place_id\tarea\tactive\tname\tlat\tlon\tcategory\ttier\tscore\tdata_version\tarticle\tllm_curiosity\tlabeled_by\tevidence\tlabel",
                "mt1_00000000000000000000000000\tkl\ttrue\tA\t0\t0\tc\t1\t0\tv1\t0.1\t\trob\t\tyes",
            ]
        )
        + "\n"
    )
    config_path = tmp_path / "scoring.json"
    config_path.write_text('{"weights": {"article": 1.0, "llm_curiosity": 2.0}}')
    models = tmp_path / "models.json"
    models.write_text('{"models":[{"id":"nous-cheap","provider":"nous"}]}')
    pricing = tmp_path / "pricing.json"
    pricing.write_text('{"models":{"nous-cheap":{"provider":"nous","input_per_m":0.15,"output_per_m":0.60}}}')
    torn_down = {"value": False}

    class RaisingNousProvider:
        def __init__(self, **_kwargs):
            pass

        async def acomplete_batch(self, _reqs):
            raise RuntimeError("network failed")

        async def shutdown(self):
            torn_down["value"] = True
            return 0.0

    monkeypatch.setenv("NOUS_API_KEY", "sk-test")
    monkeypatch.setattr(nous, "NousProvider", RaisingNousProvider)

    rc = cli.main(
        [
            "llm",
            "bakeoff",
            "--live",
            "--max-places",
            "1",
            "--labeled",
            str(labeled),
            "--config",
            str(config_path),
            "--models",
            str(models),
            "--pricing",
            str(pricing),
            "--cache-dir",
            str(tmp_path / "cache"),
        ]
    )

    assert rc == 1
    assert torn_down["value"] is True


def test_cli_llm_live_bakeoff_shuts_down_provider_when_response_parse_fails(tmp_path, monkeypatch):
    from mt_pipeline.llm.models import ProviderResponse
    from mt_pipeline.llm.providers import nous

    labeled = tmp_path / "golden.tsv"
    labeled.write_text(
        "\n".join(
            [
                "# Label the 'label' column only: yes; meh; no; blank.",
                "# data_version: v1",
                "place_id\tarea\tactive\tname\tlat\tlon\tcategory\ttier\tscore\tdata_version\tarticle\tllm_curiosity\tlabeled_by\tevidence\tlabel",
                "mt1_00000000000000000000000000\tkl\ttrue\tA\t0\t0\tc\t1\t0\tv1\t0.1\t\trob\t\tyes",
            ]
        )
        + "\n"
    )
    config_path = tmp_path / "scoring.json"
    config_path.write_text('{"weights": {"article": 1.0, "llm_curiosity": 2.0}}')
    models = tmp_path / "models.json"
    models.write_text('{"models":[{"id":"nous-cheap","provider":"nous"}]}')
    pricing = tmp_path / "pricing.json"
    pricing.write_text('{"models":{"nous-cheap":{"provider":"nous","input_per_m":0.15,"output_per_m":0.60}}}')
    torn_down = {"value": False}

    class BadJsonNousProvider:
        def __init__(self, **_kwargs):
            pass

        async def acomplete_batch(self, _reqs):
            return [
                ProviderResponse(
                    text='{"curiosity": true}',
                    model_fingerprint="nous-cheap",
                    input_tokens=10,
                    output_tokens=2,
                    latency_ms=0,
                    cost_usd=0.00001,
                    app_id=None,
                )
            ]

        async def shutdown(self):
            torn_down["value"] = True
            return 0.0

    monkeypatch.setenv("NOUS_API_KEY", "sk-test")
    monkeypatch.setattr(nous, "NousProvider", BadJsonNousProvider)

    rc = cli.main(
        [
            "llm",
            "bakeoff",
            "--live",
            "--max-places",
            "1",
            "--labeled",
            str(labeled),
            "--config",
            str(config_path),
            "--models",
            str(models),
            "--pricing",
            str(pricing),
            "--cache-dir",
            str(tmp_path / "cache"),
        ]
    )

    assert rc == 1
    assert torn_down["value"] is True
    ledger = json.loads((tmp_path / "live-cost-ledger.json").read_text())
    assert ledger["derived_usd"] == pytest.approx(0.00001)
    assert ledger["runs"] == 1
