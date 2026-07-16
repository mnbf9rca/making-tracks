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
    conn, tmp_path, monkeypatch
):
    monkeypatch.chdir(tmp_path)
    _seed_publish_inputs(conn)
    conn.execute(
        "UPDATE places SET member_refs_json = ? WHERE place_id = ?",
        ("not-json", A),
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

    result = P.run(
        conn,
        "malaysia",
        publish_version="20260715T120000Z",
        generated_at="2026-07-15T12:00:00Z",
        scoring_config_version="scoring-v1",
        staging_root=tmp_path / "stage",
    )

    assert result.counts.invalid_excluded == 1
    assert result.counts.total_published == 0


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
