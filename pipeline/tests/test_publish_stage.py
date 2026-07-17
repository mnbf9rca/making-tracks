import json

import pytest

from mt_contracts.registry import RegistryRecord

from mt_pipeline import source_record, stages, store
from mt_pipeline.publish import basemap
from mt_pipeline.publish import publish_stage as P
from mt_pipeline.reconcile.registry_file import LocalRegistryStore


A = "mt1_" + "0" * 26
B = "mt1_" + "1" * 26
C = "mt1_" + "2" * 26


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


def test_publish_stage_manifest_includes_osm_attribution_for_basemap_without_osm_places(
    conn, tmp_path, monkeypatch
):
    monkeypatch.chdir(tmp_path)
    _seed_publish_inputs(conn)
    conn.execute(
        "UPDATE places SET member_refs_json = ? WHERE place_id = ?",
        (json.dumps(["wd:Q100"], sort_keys=True), A),
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
    assert [attr["source"] for attr in manifest["attribution"]] == ["osm"]


def test_publish_stage_emits_bbox_subregion_shard_without_subregion_registry(
    conn, tmp_path, monkeypatch
):
    monkeypatch.chdir(tmp_path)
    _seed_publish_inputs(conn)
    _seed_publish_input_outside_central_subregion(conn)
    _write_malaysia_registry(tmp_path)
    _use_test_subregion_config(monkeypatch)

    def fake_cut_basemap(region_config, out_path):
        out_path.write_bytes(f"basemap:{out_path.name}".encode("utf-8"))
        return basemap.BasemapArtifact(
            filename=out_path.name,
            maxzoom=14,
            sha256="0" * 64,
            bytes=out_path.stat().st_size,
            bbox=list(region_config["basemap"]["bbox"]),
        )

    monkeypatch.setattr(P.basemap, "cut_basemap", fake_cut_basemap)
    monkeypatch.setattr(P.basemap, "require_pmtiles", lambda: "pmtiles")

    result = P.run(
        conn,
        "malaysia",
        publish_version="20260717T120000Z",
        generated_at="2026-07-17T12:00:00Z",
        scoring_config_version="scoring-v1",
        staging_root=tmp_path / "stage",
    )

    assert result.counts.total_published == 2
    assert len(result.subregion_results) == 1
    sub = result.subregion_results[0]
    assert sub.manifest["region"] == "malaysia_central"
    assert sub.counts.total_published == 1
    assert sub.manifest["basemap"]["bbox"] == [101.6, 3.0, 101.8, 3.2]
    assert sub.staging_dir == tmp_path / "stage/malaysia_central/20260717T120000Z"

    parent_registry_ops = [
        op for op in result.publish_result.plan.ops if op.kind == "registry"
    ]
    subregion_registry_ops = [
        op for op in sub.publish_result.plan.ops if op.kind == "registry"
    ]
    assert [op.key for op in parent_registry_ops] == ["registry/malaysia.jsonl"]
    assert subregion_registry_ops == []

    index = json.loads((tmp_path / "stage/regions.json").read_text())
    assert [entry["id"] for entry in index["regions"]] == [
        "malaysia",
        "malaysia_central",
    ]
    assert index["regions"][1]["parent"] == "malaysia"
    assert index["regions"][1]["display_name"] == "Central Malaysia"
    assert index["regions"][1]["publish_version"] == "20260717T120000Z"
    assert index["regions"][1]["tile_count"] == len(sub.manifest["tiles"])
    assert isinstance(index["regions"][1]["bytes_without_thumbs"], int)
    assert (
        index["regions"][1]["bytes_with_thumbs"]
        == index["regions"][1]["bytes_without_thumbs"]
    )


def test_publish_stage_writes_region_index_after_all_current_flips(
    conn, tmp_path, monkeypatch
):
    monkeypatch.chdir(tmp_path)
    _seed_publish_inputs(conn)
    _seed_publish_input_outside_central_subregion(conn)
    _write_malaysia_registry(tmp_path)
    _use_test_subregion_config(monkeypatch)
    order = []
    real_publish_to_r2 = P.r2.publish_to_r2
    real_publish_region_index = P.r2.publish_region_index

    def spy_publish_to_r2(staging_dir, layout, **kwargs):
        result = real_publish_to_r2(staging_dir, layout, **kwargs)
        order.extend(op.key for op in result.plan.ops if op.kind == "current")
        return result

    def spy_publish_region_index(region_index_path, layout, **kwargs):
        result = real_publish_region_index(region_index_path, layout, **kwargs)
        order.append(result.plan.ops[-1].key)
        return result

    def fake_cut_basemap(region_config, out_path):
        out_path.write_bytes(b"basemap")
        return basemap.BasemapArtifact(
            filename=out_path.name,
            maxzoom=14,
            sha256="0" * 64,
            bytes=7,
            bbox=list(region_config["basemap"]["bbox"]),
        )

    monkeypatch.setattr(P.r2, "publish_to_r2", spy_publish_to_r2)
    monkeypatch.setattr(P.r2, "publish_region_index", spy_publish_region_index)
    monkeypatch.setattr(P.basemap, "cut_basemap", fake_cut_basemap)
    monkeypatch.setattr(P.basemap, "require_pmtiles", lambda: "pmtiles")

    result = P.run(
        conn,
        "malaysia",
        publish_version="20260717T120000Z",
        generated_at="2026-07-17T12:00:00Z",
        scoring_config_version="scoring-v1",
        staging_root=tmp_path / "stage",
    )

    assert order == [
        "malaysia/current.json",
        "malaysia_central/current.json",
        "regions.json",
    ]
    assert result.region_index_publish_result.plan.ops[-1].kind == "region_index"


def test_publish_stage_upload_builds_all_targets_before_any_upload(
    conn, tmp_path, monkeypatch
):
    monkeypatch.chdir(tmp_path)
    _seed_publish_inputs(conn)
    _seed_publish_input_outside_central_subregion(conn)
    _write_malaysia_registry(tmp_path)
    _use_test_subregion_config(monkeypatch)
    monkeypatch.setattr(P.basemap, "require_pmtiles", lambda: "pmtiles")
    monkeypatch.setattr(P.r2, "_import_module", lambda name: object())
    monkeypatch.setenv("R2_S3_ENDPOINT", "https://example.r2.cloudflarestorage.com")
    monkeypatch.setenv("R2_ACCESS_KEY_ID", "access")
    monkeypatch.setenv("R2_SECRET_ACCESS_KEY", "secret")
    calls = []

    def fake_cut_basemap(region_config, out_path):
        if out_path.name == "malaysia_central.pmtiles":
            raise RuntimeError("subregion basemap failed")
        out_path.write_bytes(b"basemap")
        return basemap.BasemapArtifact(
            filename=out_path.name,
            maxzoom=14,
            sha256="0" * 64,
            bytes=7,
            bbox=list(region_config["basemap"]["bbox"]),
        )

    def fail_upload(*args, **kwargs):
        calls.append((args, kwargs))
        raise AssertionError("upload should wait for every target to stage")

    monkeypatch.setattr(P.basemap, "cut_basemap", fake_cut_basemap)
    monkeypatch.setattr(P.r2, "publish_prepared_to_r2", fail_upload)

    with pytest.raises(RuntimeError, match="subregion basemap failed"):
        P.run(
            conn,
            "malaysia",
            publish_version="20260717T120000Z",
            generated_at="2026-07-17T12:00:00Z",
            scoring_config_version="scoring-v1",
            upload=True,
            staging_root=tmp_path / "stage",
        )

    assert calls == []


def test_subregion_bbox_filter_keeps_invalid_coordinates_for_tile_quarantine():
    places = [
        {"place_id": A, "lat": 3.1, "lon": 101.7},
        {"place_id": B, "lat": 5.0, "lon": 110.0},
        {"place_id": C, "lat": "not-a-number", "lon": 101.7},
    ]

    filtered = P._filter_places_to_bbox(places, (101.6, 3.0, 101.8, 3.2))

    assert [place["place_id"] for place in filtered] == [A, C]


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


def _write_malaysia_registry(tmp_path):
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
            RegistryRecord(
                place_id=C,
                refs={"wd:Q300"},
                mint_anchor="wd:Q300",
                status="live",
                first_shipped_version="20260701T000000Z",
                last_seen_version="20260701T000000Z",
            ),
        ]
    )


def _use_test_subregion_config(monkeypatch):
    monkeypatch.setattr(
        P.config,
        "load",
        lambda region: P.config.RegionConfig.from_dict(
            {
                "schema_version": 1,
                "region_id": region,
                "display_name": "Malaysia",
                "bbox": [99.64, 0.85, 119.27, 7.36],
                "languages": ["en"],
                "sources": {"wikidata": True, "osm": True},
                "basemap": {
                    "source_pmtiles": "https://build.protomaps.com/20260714.pmtiles",
                    "maxzoom": 14,
                    "pack_granularity": "subregion",
                    "size_budget_bytes": 500000000,
                    "measured_archive_bytes": 223155574,
                    "subregions": [
                        {
                            "id": "central",
                            "display_name": "Central Malaysia",
                            "bbox": [101.6, 3.0, 101.8, 3.2],
                            "measured_archive_bytes": 12345,
                        }
                    ],
                },
            }
        ),
    )


def _seed_publish_input_outside_central_subregion(conn):
    source_record.persist(
        conn,
        source_record.parse(
            "malaysia",
            "wd",
            "wd:Q300",
            "Outside",
            5.0,
            110.0,
            {"classes": ["Q839954"]},
        ),
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
            {
                "place_id": C,
                "name": "Outside",
                "lat": 5.0,
                "lon": 110.0,
                "refs": ["wd:Q300"],
                "member_refs": ["wd:Q300"],
                "status": "live",
            },
        ],
    )
    conn.execute(
        """
        INSERT INTO place_scores (place_id, region, score, tier, signals_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (C, "malaysia", 0.8, 2, "{}", "score1"),
    )
    conn.execute(
        """
        INSERT INTO place_categories (place_id, region, category, run_id)
        VALUES (?, ?, ?, ?)
        """,
        (C, "malaysia", "history", "cat1"),
    )
    conn.commit()


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
