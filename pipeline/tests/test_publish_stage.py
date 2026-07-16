import json

import pytest

from mt_contracts.registry import RegistryRecord

from mt_pipeline import source_record, stages, store
from mt_pipeline.publish import basemap
from mt_pipeline.publish import publish_stage as P
from mt_pipeline.reconcile.registry_file import LocalRegistryStore


A = "mt1_" + "0" * 26
B = "mt1_" + "1" * 26


def test_publish_stage_builds_local_staging_and_marks_shipped(
    conn, tmp_path, monkeypatch
):
    monkeypatch.chdir(tmp_path)
    _seed_publish_inputs(conn)
    LocalRegistryStore(tmp_path / "registry/malaysia.jsonl").save(
        [
            RegistryRecord(
                place_id=A,
                refs={"wd:Q100", "osm:node/100"},
                mint_anchor="wd:Q100",
                status="live",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            ),
            RegistryRecord(
                place_id=B,
                refs={"wd:Q200"},
                mint_anchor="wd:Q200",
                status="live",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            ),
        ]
    )

    def fake_cut_basemap(region_config, out_path):
        out_path.write_bytes(b"basemap")
        return basemap.BasemapArtifact(
            filename="malaysia.pmtiles",
            maxzoom=14,
            sha256="0" * 64,
            bytes=7,
            bbox=list(region_config["basemap"]["bbox"]),
        )

    monkeypatch.setattr(P.basemap, "cut_basemap", fake_cut_basemap)
    monkeypatch.setattr(P.basemap, "require_pmtiles", lambda: "pmtiles")

    result = P.run(
        conn,
        "malaysia",
        publish_version="20260715T120000Z",
        generated_at="2026-07-15T12:00:00Z",
        scoring_config_version="scoring-v1",
        staging_root=tmp_path / "stage",
    )

    manifest = json.loads((result.staging_dir / "manifest.json").read_text())
    assert manifest["region"] == "malaysia"
    assert manifest["publish_version"] == "20260715T120000Z"
    assert manifest["min_reader_version"] == 2
    assert any(attr["source"] == "osm" for attr in manifest["attribution"])
    assert result.counts.total_published == 1
    assert result.counts.uncategorized_excluded == 1
    assert (result.staging_dir / "tiles/10").exists()
    registry_ops = [
        op for op in result.publish_result.plan.ops if op.kind == "registry"
    ]
    assert len(registry_ops) == 1
    assert registry_ops[0].bucket == "making-tracks-state"
    assert registry_ops[0].key == "registry/malaysia.jsonl"

    saved = LocalRegistryStore(tmp_path / "registry/malaysia.jsonl").load()
    shipped = {record.place_id: record for record in saved}
    assert shipped[A].first_shipped_version == "20260701T000000Z"
    assert shipped[A].last_seen_version == "20260701T000000Z"
    assert shipped[B].last_seen_version == "20260701T000000Z"


def test_publish_stage_emits_phase_heartbeats_for_slow_publish_steps(
    conn, tmp_path, monkeypatch, capsys
):
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(P, "_HEARTBEAT_EVERY_RECORDS", 1, raising=False)
    monkeypatch.setattr(P.tiles, "_HEARTBEAT_EVERY_RECORDS", 1, raising=False)
    _seed_publish_inputs(conn)
    LocalRegistryStore(tmp_path / "registry/malaysia.jsonl").save(
        [
            RegistryRecord(
                place_id=A,
                refs={"wd:Q100", "osm:node/100"},
                mint_anchor="wd:Q100",
                status="live",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            ),
            RegistryRecord(
                place_id=B,
                refs={"wd:Q200"},
                mint_anchor="wd:Q200",
                status="live",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            ),
        ]
    )

    def fake_cut_basemap(region_config, out_path):
        out_path.write_bytes(b"basemap")
        return basemap.BasemapArtifact(
            filename="malaysia.pmtiles",
            maxzoom=14,
            sha256="0" * 64,
            bytes=7,
            bbox=list(region_config["basemap"]["bbox"]),
        )

    monkeypatch.setattr(P.basemap, "cut_basemap", fake_cut_basemap)
    monkeypatch.setattr(P.basemap, "require_pmtiles", lambda: "pmtiles")

    P.run(
        conn,
        "malaysia",
        publish_version="20260715T120000Z",
        generated_at="2026-07-15T12:00:00Z",
        scoring_config_version="scoring-v1",
        staging_root=tmp_path / "stage",
    )

    err = capsys.readouterr().err
    assert "PHASE START publish.registry_load region=malaysia records=unknown" in err
    assert "PHASE HEARTBEAT publish.registry_load region=malaysia processed=1/unknown" in err
    assert "PHASE DONE publish.registry_load region=malaysia processed=2/unknown" in err
    assert "PHASE START publish.db_input_validation region=malaysia places=unknown" in err
    assert "PHASE HEARTBEAT publish.db_input_validation region=malaysia processed=1/unknown" in err
    assert "PHASE DONE publish.db_input_validation region=malaysia processed=2/unknown" in err
    assert "PHASE START publish.joined_place_load region=malaysia places=unknown" in err
    assert "PHASE HEARTBEAT publish.joined_place_load region=malaysia processed=1/unknown" in err
    assert "PHASE DONE publish.joined_place_load region=malaysia processed=2/unknown" in err
    assert "PHASE START publish.coverage_validation region=malaysia places=2" in err
    assert "PHASE HEARTBEAT publish.coverage_validation region=malaysia processed=1/2" in err
    assert "PHASE DONE publish.coverage_validation region=malaysia processed=2/2" in err
    assert "PHASE START publish.tile_emit region=malaysia places=2" in err
    assert "PHASE HEARTBEAT publish.tile_emit region=malaysia processed=1/2" in err
    assert "PHASE DONE publish.tile_emit region=malaysia processed=2/2" in err
    assert "PHASE START publish.tile_group region=malaysia places=1" in err
    assert "PHASE HEARTBEAT publish.tile_group region=malaysia processed=1/1" in err
    assert "PHASE DONE publish.tile_group region=malaysia processed=1/1" in err
    assert "PHASE START publish.tile_write region=malaysia tiles=1" in err
    assert "current_tile=" in err
    assert "gzip_attempt=1" in err
    assert "PHASE HEARTBEAT publish.tile_write region=malaysia processed=1/1" in err
    assert "PHASE DONE publish.tile_write region=malaysia processed=1/1" in err
    assert "tiles=1" in err
    assert "invalid_excluded=0" in err
    assert "uncategorized_excluded=1" in err


def test_publish_stage_reports_registry_load_progress_before_parse_error(
    conn, tmp_path, monkeypatch, capsys
):
    monkeypatch.setattr(P, "_HEARTBEAT_EVERY_RECORDS", 1, raising=False)
    _seed_publish_inputs(conn)
    registry_path = tmp_path / "registry/malaysia.jsonl"
    registry_path.parent.mkdir(parents=True)
    registry_path.write_text(
        json.dumps(
            {
                "first_shipped_version": "20260701T000000Z",
                "last_seen_version": "20260701T000000Z",
                "mint_anchor": "wd:Q100",
                "place_id": A,
                "refs": ["wd:Q100", "osm:node/100"],
                "schema_version": 1,
                "status": "live",
                "superseded_by": None,
            },
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n{not-json}\n"
    )

    monkeypatch.setattr(P.basemap, "require_pmtiles", lambda: "pmtiles")

    with pytest.raises(P.PublishStageError, match="publish registry rejected"):
        P.run(
            conn,
            "malaysia",
            publish_version="20260715T120000Z",
            generated_at="2026-07-15T12:00:00Z",
            scoring_config_version="scoring-v1",
            staging_root=tmp_path / "stage",
        )

    err = capsys.readouterr().err
    assert "PHASE START publish.registry_load region=malaysia records=unknown" in err
    assert "PHASE HEARTBEAT publish.registry_load region=malaysia processed=1/unknown" in err
    assert "PHASE DONE publish.registry_load region=malaysia processed=1/unknown" in err
    assert "error=parse" in err


def test_publish_stage_dispatch_requires_publish_version(conn):
    store.mark_stage_complete(conn, "malaysia", "categorize", "r1", "2026-07-15T00:00:00Z")

    try:
        stages.run_stage(conn, "malaysia", "publish", run_id="r1")
    except stages.StageVersionError as exc:
        assert "--publish-version" in str(exc)
    else:
        raise AssertionError("publish without version should fail")


def test_publish_stage_checks_pmtiles_before_staging(conn, tmp_path, monkeypatch):
    monkeypatch.setenv("PATH", "")

    with pytest.raises(basemap.PmtilesUnavailable):
        P.run(
            conn,
            "malaysia",
            publish_version="20260715T120000Z",
            generated_at="2026-07-15T12:00:00Z",
            scoring_config_version="scoring-v1",
            staging_root=tmp_path / "stage",
        )

    assert not (tmp_path / "stage").exists()


def test_publish_stage_checks_boto3_before_staging_when_upload_requested(
    conn, tmp_path, monkeypatch
):
    _seed_publish_inputs(conn)
    monkeypatch.setattr(P.basemap, "require_pmtiles", lambda: "pmtiles")

    def missing_boto3(name):
        if name == "boto3":
            raise ModuleNotFoundError("No module named 'boto3'")
        raise AssertionError(f"unexpected import check for {name}")

    monkeypatch.setattr(P.r2, "_import_module", missing_boto3, raising=False)

    def fail_registry_path(_conn, _region):
        raise AssertionError("registry path should wait for boto3 upload preflight")

    monkeypatch.setattr(P, "_registry_path", fail_registry_path)

    with pytest.raises(P.r2.Boto3Unavailable) as excinfo:
        P.run(
            conn,
            "malaysia",
            publish_version="20260715T120000Z",
            generated_at="2026-07-15T12:00:00Z",
            scoring_config_version="scoring-v1",
            upload=True,
            staging_root=tmp_path / "stage",
        )

    assert "boto3" in str(excinfo.value)
    assert "--upload" in str(excinfo.value)
    assert "boto3>=1.34" in str(excinfo.value)
    assert not (tmp_path / "stage").exists()


def test_publish_stage_checks_r2_env_before_staging_when_upload_requested(
    conn, tmp_path, monkeypatch
):
    _seed_publish_inputs(conn)
    monkeypatch.setattr(P.basemap, "require_pmtiles", lambda: "pmtiles")
    monkeypatch.setattr(P.r2, "_import_module", lambda name: object())
    monkeypatch.delenv("R2_S3_ENDPOINT", raising=False)
    monkeypatch.delenv("R2_ACCESS_KEY_ID", raising=False)
    monkeypatch.delenv("R2_SECRET_ACCESS_KEY", raising=False)
    monkeypatch.delenv("R2_ACCOUNT_ID", raising=False)

    def fail_registry_path(_conn, _region):
        raise AssertionError("registry path should wait for R2 env upload preflight")

    monkeypatch.setattr(P, "_registry_path", fail_registry_path)

    with pytest.raises(P.r2.R2EnvironmentUnavailable) as excinfo:
        P.run(
            conn,
            "malaysia",
            publish_version="20260715T120000Z",
            generated_at="2026-07-15T12:00:00Z",
            scoring_config_version="scoring-v1",
            upload=True,
            staging_root=tmp_path / "stage",
        )

    message = str(excinfo.value)
    assert "R2_S3_ENDPOINT" in message
    assert "R2_ACCESS_KEY_ID" in message
    assert "R2_SECRET_ACCESS_KEY" in message
    assert "R2_ACCOUNT_ID" not in message
    assert not (tmp_path / "stage").exists()


def test_publish_stage_resolves_relative_registry_path_beside_db(
    conn, tmp_path, monkeypatch
):
    other_cwd = tmp_path / "operator-cwd"
    other_cwd.mkdir()
    monkeypatch.chdir(other_cwd)
    _seed_publish_inputs(conn)
    LocalRegistryStore(tmp_path / "registry/malaysia.jsonl").save(
        [
            RegistryRecord(
                place_id=A,
                refs={"wd:Q100", "osm:node/100"},
                mint_anchor="wd:Q100",
                status="live",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            ),
            RegistryRecord(
                place_id=B,
                refs={"wd:Q200"},
                mint_anchor="wd:Q200",
                status="live",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            ),
        ]
    )

    def fake_cut_basemap(region_config, out_path):
        out_path.write_bytes(b"basemap")
        return basemap.BasemapArtifact(
            filename="malaysia.pmtiles",
            maxzoom=14,
            sha256="0" * 64,
            bytes=7,
            bbox=list(region_config["basemap"]["bbox"]),
        )

    monkeypatch.setattr(P.basemap, "cut_basemap", fake_cut_basemap)
    monkeypatch.setattr(P.basemap, "require_pmtiles", lambda: "pmtiles")

    result = P.run(
        conn,
        "malaysia",
        publish_version="20260715T120000Z",
        generated_at="2026-07-15T12:00:00Z",
        scoring_config_version="scoring-v1",
        staging_root=tmp_path / "stage",
    )

    assert result.counts.total_published == 1


def test_publish_stage_requires_registry_before_basemap_cut(conn, tmp_path, monkeypatch):
    _seed_publish_inputs(conn)
    called = False

    def fail_cut_basemap(_region_config, _out_path):
        nonlocal called
        called = True
        raise AssertionError("basemap cut should wait for registry preflight")

    monkeypatch.setattr(P.basemap, "cut_basemap", fail_cut_basemap)
    monkeypatch.setattr(P.basemap, "require_pmtiles", lambda: "pmtiles")

    with pytest.raises(P.PublishStageError) as excinfo:
        P.run(
            conn,
            "malaysia",
            publish_version="20260715T120000Z",
            generated_at="2026-07-15T12:00:00Z",
            scoring_config_version="scoring-v1",
            staging_root=tmp_path / "stage",
        )

    assert "registry" in str(excinfo.value)
    assert str(tmp_path / "registry/malaysia.jsonl") in str(excinfo.value)
    assert called is False


def test_publish_stage_checks_registry_coverage_before_basemap_cut(
    conn, tmp_path, monkeypatch
):
    _seed_publish_inputs(conn)
    LocalRegistryStore(tmp_path / "registry/malaysia.jsonl").save(
        [
            RegistryRecord(
                place_id=B,
                refs={"wd:Q200"},
                mint_anchor="wd:Q200",
                status="live",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            )
        ]
    )
    called = False

    def fail_cut_basemap(_region_config, _out_path):
        nonlocal called
        called = True
        raise AssertionError("basemap cut should wait for registry coverage")

    monkeypatch.setattr(P.basemap, "cut_basemap", fail_cut_basemap)
    monkeypatch.setattr(P.basemap, "require_pmtiles", lambda: "pmtiles")

    with pytest.raises(P.PublishStageError) as excinfo:
        P.run(
            conn,
            "malaysia",
            publish_version="20260715T120000Z",
            generated_at="2026-07-15T12:00:00Z",
            scoring_config_version="scoring-v1",
            staging_root=tmp_path / "stage",
        )

    message = str(excinfo.value)
    assert "registry" in message
    assert str(tmp_path / "registry/malaysia.jsonl") in message
    assert A in message
    assert called is False


def test_publish_stage_checks_joined_db_inputs_before_basemap_cut(
    conn, tmp_path, monkeypatch
):
    store.replace_places(
        conn,
        region="malaysia",
        places=[
            {
                "place_id": A,
                "name": "Fort",
                "lat": 3.10,
                "lon": 101.70,
                "refs": ["wd:Q100"],
                "member_refs": ["wd:Q100"],
                "status": "live",
            }
        ],
    )
    LocalRegistryStore(tmp_path / "registry/malaysia.jsonl").save(
        [
            RegistryRecord(
                place_id=A,
                refs={"wd:Q100"},
                mint_anchor="wd:Q100",
                status="live",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            )
        ]
    )
    called = False

    def fail_cut_basemap(_region_config, _out_path):
        nonlocal called
        called = True
        raise AssertionError("basemap cut should wait for DB preflight")

    monkeypatch.setattr(P.basemap, "cut_basemap", fail_cut_basemap)
    monkeypatch.setattr(P.basemap, "require_pmtiles", lambda: "pmtiles")

    with pytest.raises(P.PublishStageError) as excinfo:
        P.run(
            conn,
            "malaysia",
            publish_version="20260715T120000Z",
            generated_at="2026-07-15T12:00:00Z",
            scoring_config_version="scoring-v1",
            staging_root=tmp_path / "stage",
        )

    assert "place_scores" in str(excinfo.value)
    assert called is False


def test_publish_stage_requires_scores_for_all_live_places_before_basemap_cut(
    conn, tmp_path, monkeypatch
):
    _seed_publish_inputs(conn)
    conn.execute(
        "DELETE FROM place_scores WHERE region = ? AND place_id = ?",
        ("malaysia", B),
    )
    conn.commit()
    LocalRegistryStore(tmp_path / "registry/malaysia.jsonl").save(
        [
            RegistryRecord(
                place_id=A,
                refs={"wd:Q100", "osm:node/100"},
                mint_anchor="wd:Q100",
                status="live",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            ),
            RegistryRecord(
                place_id=B,
                refs={"wd:Q200"},
                mint_anchor="wd:Q200",
                status="live",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            ),
        ]
    )
    called = False

    def fail_cut_basemap(_region_config, _out_path):
        nonlocal called
        called = True
        raise AssertionError("basemap cut should wait for DB coverage")

    monkeypatch.setattr(P.basemap, "cut_basemap", fail_cut_basemap)
    monkeypatch.setattr(P.basemap, "require_pmtiles", lambda: "pmtiles")

    with pytest.raises(P.PublishStageError) as excinfo:
        P.run(
            conn,
            "malaysia",
            publish_version="20260715T120000Z",
            generated_at="2026-07-15T12:00:00Z",
            scoring_config_version="scoring-v1",
            staging_root=tmp_path / "stage",
        )

    assert "1 live malaysia place(s) missing place_scores" in str(excinfo.value)
    assert called is False


def test_publish_stage_rejects_non_live_registry_for_live_db_place_before_basemap_cut(
    conn, tmp_path, monkeypatch
):
    _seed_publish_inputs(conn)
    LocalRegistryStore(tmp_path / "registry/malaysia.jsonl").save(
        [
            RegistryRecord(
                place_id=A,
                refs={"wd:Q100", "osm:node/100"},
                mint_anchor="wd:Q100",
                status="tombstoned",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            ),
            RegistryRecord(
                place_id=B,
                refs={"wd:Q200"},
                mint_anchor="wd:Q200",
                status="live",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            ),
        ]
    )
    called = False

    def fail_cut_basemap(_region_config, _out_path):
        nonlocal called
        called = True
        raise AssertionError("basemap cut should wait for live registry preflight")

    monkeypatch.setattr(P.basemap, "cut_basemap", fail_cut_basemap)
    monkeypatch.setattr(P.basemap, "require_pmtiles", lambda: "pmtiles")

    with pytest.raises(P.PublishStageError) as excinfo:
        P.run(
            conn,
            "malaysia",
            publish_version="20260715T120000Z",
            generated_at="2026-07-15T12:00:00Z",
            scoring_config_version="scoring-v1",
            staging_root=tmp_path / "stage",
        )

    message = str(excinfo.value)
    assert str(tmp_path / "registry/malaysia.jsonl") in message
    assert "non-live" in message
    assert A in message
    assert called is False


def test_publish_stage_requires_registry_ref_coverage_before_basemap_cut(
    conn, tmp_path, monkeypatch
):
    _seed_publish_inputs(conn)
    LocalRegistryStore(tmp_path / "registry/malaysia.jsonl").save(
        [
            RegistryRecord(
                place_id=A,
                refs={"wd:Q100"},
                mint_anchor="wd:Q100",
                status="live",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            ),
            RegistryRecord(
                place_id=B,
                refs={"wd:Q200"},
                mint_anchor="wd:Q200",
                status="live",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            ),
        ]
    )
    called = False

    def fail_cut_basemap(_region_config, _out_path):
        nonlocal called
        called = True
        raise AssertionError("basemap cut should wait for registry refs preflight")

    monkeypatch.setattr(P.basemap, "cut_basemap", fail_cut_basemap)
    monkeypatch.setattr(P.basemap, "require_pmtiles", lambda: "pmtiles")

    with pytest.raises(P.PublishStageError) as excinfo:
        P.run(
            conn,
            "malaysia",
            publish_version="20260715T120000Z",
            generated_at="2026-07-15T12:00:00Z",
            scoring_config_version="scoring-v1",
            staging_root=tmp_path / "stage",
        )

    message = str(excinfo.value)
    assert str(tmp_path / "registry/malaysia.jsonl") in message
    assert "missing refs" in message
    assert "osm:node/100" in message
    assert called is False


def test_publish_stage_quarantines_malformed_member_refs_json(
    conn, tmp_path, monkeypatch, caplog
):
    result = _run_with_member_refs_json(
        conn, tmp_path, monkeypatch, caplog, member_refs_json="not-json"
    )

    assert result.counts.invalid_excluded == 1
    assert result.counts.total_published == 0
    assert any(
        "malformed member_refs_json (parse error)" in record.message
        and "place_id=mt1_" in record.message
        and "region=malaysia" in record.message
        and record.exc_info is not None
        for record in caplog.records
    )


def test_publish_stage_warns_on_non_list_member_refs_json(
    conn, tmp_path, monkeypatch, caplog
):
    result = _run_with_member_refs_json(
        conn, tmp_path, monkeypatch, caplog, member_refs_json='{"ref":"wd:Q100"}'
    )

    assert result.counts.invalid_excluded == 1
    assert result.counts.total_published == 0
    assert any(
        "malformed member_refs_json (not list[str], got dict)" in record.message
        and "place_id=mt1_" in record.message
        and "region=malaysia" in record.message
        and record.exc_info is None
        for record in caplog.records
    )


def _run_with_member_refs_json(
    conn, tmp_path, monkeypatch, caplog, *, member_refs_json: str
):
    monkeypatch.chdir(tmp_path)
    _seed_publish_inputs(conn)
    conn.execute(
        "UPDATE places SET member_refs_json = ? WHERE place_id = ?",
        (member_refs_json, A),
    )
    conn.commit()
    LocalRegistryStore(tmp_path / "registry/malaysia.jsonl").save(
        [
            RegistryRecord(
                place_id=A,
                refs={"wd:Q100", "osm:node/100"},
                mint_anchor="wd:Q100",
                status="live",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            ),
            RegistryRecord(
                place_id=B,
                refs={"wd:Q200"},
                mint_anchor="wd:Q200",
                status="live",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            ),
        ]
    )

    def fake_cut_basemap(region_config, out_path):
        out_path.write_bytes(b"basemap")
        return basemap.BasemapArtifact(
            filename="malaysia.pmtiles",
            maxzoom=14,
            sha256="0" * 64,
            bytes=7,
            bbox=list(region_config["basemap"]["bbox"]),
        )

    monkeypatch.setattr(P.basemap, "cut_basemap", fake_cut_basemap)
    monkeypatch.setattr(P.basemap, "require_pmtiles", lambda: "pmtiles")

    caplog.set_level("WARNING")
    return P.run(
        conn,
        "malaysia",
        publish_version="20260715T120000Z",
        generated_at="2026-07-15T12:00:00Z",
        scoring_config_version="scoring-v1",
        staging_root=tmp_path / "stage",
    )


def _seed_publish_inputs(conn):
    for source, source_ref, props in [
        ("wd", "wd:Q100", {"classes": ["Q839954"]}),
        ("osm", "osm:node/100", {"tags": {"historic": "fort"}}),
        ("wd", "wd:Q200", {"classes": ["Q532"]}),
    ]:
        source_record.persist(
            conn,
            source_record.parse("malaysia", source, source_ref, "Place", 3.1, 101.7, props),
            run_id="extract1",
        )
    store.replace_places(
        conn,
        region="malaysia",
        places=[
            {
                "place_id": A,
                "name": "Fort",
                "lat": 3.10,
                "lon": 101.70,
                "refs": ["wd:Q100"],
                "member_refs": ["wd:Q100", "osm:node/100"],
                "status": "live",
            },
            {
                "place_id": B,
                "name": "Residue",
                "lat": 3.11,
                "lon": 101.71,
                "refs": ["wd:Q200"],
                "member_refs": ["wd:Q200"],
                "status": "live",
            },
        ],
    )
    conn.executemany(
        """
        INSERT INTO place_scores (place_id, region, score, tier, signals_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [
            (A, "malaysia", 0.9, 1, "{}", "score1"),
            (B, "malaysia", 0.2, 4, "{}", "score1"),
        ],
    )
    conn.executemany(
        """
        INSERT INTO place_categories (place_id, region, category, run_id)
        VALUES (?, ?, ?, ?)
        """,
        [(A, "malaysia", "history", "cat1"), (B, "malaysia", "uncategorized", "cat1")],
    )
    conn.commit()
