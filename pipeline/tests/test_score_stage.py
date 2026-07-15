import json

import pytest

from mt_pipeline import source_record, stages, store
from mt_pipeline.eval import golden as G
from mt_pipeline.score import SIGNAL_NAMES
from mt_pipeline.score import composite, score_stage, signals as signal_funcs, tiers

A = "mt1_" + "0" * 26
B = "mt1_" + "1" * 26
STALE = "mt1_" + "2" * 26


def test_score_stage_writes_real_scores_that_eval_dump_accepts(conn):
    _seed_score_inputs(conn)
    store.mark_stage_complete(conn, "malaysia", "extract", "r1", "2026-07-15T00:00:00Z")
    store.mark_stage_complete(conn, "malaysia", "reconcile", "r1", "2026-07-15T00:00:00Z")

    stages.run_stage(conn, "malaysia", "score", run_id="score1")

    rows = conn.execute(
        """
        SELECT place_id, region, run_id, tier, score, signals_json
        FROM place_scores
        WHERE region = ?
        ORDER BY score DESC, place_id
        """,
        ("malaysia",),
    ).fetchall()
    assert [row[0] for row in rows] == [A, B]
    assert all(row[1] == "malaysia" and row[2] == "score1" for row in rows)
    assert all(row[3] in (1, 2, 3, 4) and 0.0 <= row[4] <= 1.0 for row in rows)

    signals = {
        place_id: json.loads(signals_json)
        for place_id, *_rest, signals_json in rows
    }
    cfg = score_stage.load_config()
    by_place = {row[0]: row for row in rows}
    assert by_place[A][4] == pytest.approx(composite.score(signals[A], cfg))
    assert by_place[A][3] == tiers.tier_for(by_place[A][4], cfg)
    assert by_place[B][4] == pytest.approx(composite.score(signals[B], cfg))
    assert by_place[B][3] == tiers.tier_for(by_place[B][4], cfg)
    assert set(signals[A]) == set(SIGNAL_NAMES)
    assert signals[A]["article"] > 0
    assert signals[A]["heritage"] == 1.0
    assert signals[A]["image"] == 1.0
    assert signals[A]["pageviews"] == pytest.approx(
        signal_funcs.pageviews({"pageviews": [1000, 2000, 3000]})
    )
    assert signals[A]["tag_rarity"] > signals[B]["tag_rarity"]
    assert signals[A]["llm_curiosity"] is None
    assert signals[B]["class_penalty"] == 0.3

    _insert_categories(conn, run_id="cat1")
    dumped = G.dump_area(conn, "kl", [101.65, 3.05, 101.75, 3.20], data_version="score1")

    assert [row.place_id for row in dumped] == [A, B]
    assert dumped[0].signals == signals[A]

    first_rows = conn.execute(
        """
        SELECT place_id, region, run_id, tier, score, signals_json
        FROM place_scores
        WHERE region = ?
        ORDER BY place_id
        """,
        ("malaysia",),
    ).fetchall()
    stages.run_stage(conn, "malaysia", "score", run_id="score1")
    second_rows = conn.execute(
        """
        SELECT place_id, region, run_id, tier, score, signals_json
        FROM place_scores
        WHERE region = ?
        ORDER BY place_id
        """,
        ("malaysia",),
    ).fetchall()
    assert second_rows == first_rows


def test_score_stage_replaces_existing_region_scores_and_emits_progress(
    conn,
    capsys,
    monkeypatch,
):
    _seed_score_inputs(conn)
    monkeypatch.setattr(score_stage, "_HEARTBEAT_EVERY_RECORDS", 1)
    conn.execute(
        """
        INSERT INTO place_scores (place_id, region, score, tier, signals_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (STALE, "malaysia", 0.9, 1, json.dumps({"article": 0.9}), "old"),
    )
    conn.execute(
        """
        INSERT INTO place_scores (place_id, region, score, tier, signals_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        ("other-region", "uk", 0.9, 1, json.dumps({"article": 0.9}), "old"),
    )
    conn.commit()
    store.mark_stage_complete(conn, "malaysia", "extract", "r1", "2026-07-15T00:00:00Z")
    store.mark_stage_complete(conn, "malaysia", "reconcile", "r1", "2026-07-15T00:00:00Z")

    stages.run_stage(conn, "malaysia", "score", run_id="score2")

    rows = conn.execute(
        """
        SELECT place_id, run_id
        FROM place_scores
        ORDER BY region, place_id
        """
    ).fetchall()
    assert rows == [(A, "score2"), (B, "score2"), ("other-region", "old")]
    captured = capsys.readouterr()
    assert "PHASE START score.run region=malaysia places=2" in captured.err
    assert "PHASE HEARTBEAT score.run region=malaysia processed=1/2" in captured.err
    assert "PHASE DONE score.run region=malaysia processed=2/2" in captured.err


def test_score_stage_rejects_corrupt_member_refs(conn):
    _seed_score_inputs(conn)
    conn.execute(
        """
        UPDATE places
        SET member_refs_json = ?
        WHERE place_id = ?
        """,
        ("not-json", A),
    )
    conn.commit()
    store.mark_stage_complete(conn, "malaysia", "extract", "r1", "2026-07-15T00:00:00Z")
    store.mark_stage_complete(conn, "malaysia", "reconcile", "r1", "2026-07-15T00:00:00Z")

    with pytest.raises(stages.StageOrderError, match="member_refs_json"):
        stages.run_stage(conn, "malaysia", "score", run_id="score1")

    assert not store.stage_completed(conn, "malaysia", "score")


def test_score_stage_rejects_missing_member_source_record(conn):
    _seed_score_inputs(conn)
    conn.execute(
        """
        DELETE FROM source_records
        WHERE source_ref = ?
        """,
        ("hehle:100",),
    )
    conn.commit()
    store.mark_stage_complete(conn, "malaysia", "extract", "r1", "2026-07-15T00:00:00Z")
    store.mark_stage_complete(conn, "malaysia", "reconcile", "r1", "2026-07-15T00:00:00Z")

    with pytest.raises(stages.StageOrderError, match="missing source record"):
        stages.run_stage(conn, "malaysia", "score", run_id="score1")

    assert not store.stage_completed(conn, "malaysia", "score")


def test_score_stage_rejects_corrupt_source_props(conn):
    _seed_score_inputs(conn)
    conn.execute(
        """
        UPDATE source_records
        SET props_json = ?
        WHERE source_ref = ?
        """,
        ("not-json", "wd:Q100"),
    )
    conn.commit()
    store.mark_stage_complete(conn, "malaysia", "extract", "r1", "2026-07-15T00:00:00Z")
    store.mark_stage_complete(conn, "malaysia", "reconcile", "r1", "2026-07-15T00:00:00Z")

    with pytest.raises(stages.StageOrderError, match="props_json"):
        stages.run_stage(conn, "malaysia", "score", run_id="score1")

    assert not store.stage_completed(conn, "malaysia", "score")


def _seed_score_inputs(conn):
    records = [
        (
            "wd",
            "wd:Q100",
            "Fort",
            3.10,
            101.70,
            {"sitelinks": 25, "image": "Fort.jpg", "classes": ["Q839954"]},
        ),
        (
            "wp",
            "wp:12345",
            "Fort",
            3.10,
            101.70,
            {"extract": "A layered fort history. " * 20, "pageviews": 1},
        ),
        (
            "wp",
            "wp:12346",
            "Fort",
            3.10,
            101.70,
            {"extract": "Short.", "pageviews": [1000, 2000, 3000]},
        ),
        (
            "osm",
            "osm:node/100",
            "Fort",
            3.10,
            101.70,
            {"tags": {"historic": "fort"}},
        ),
        ("hehle", "hehle:100", "Fort", 3.10, 101.70, {"grade": "I"}),
        (
            "wd",
            "wd:Q200",
            "Bench",
            3.11,
            101.71,
            {"sitelinks": 0, "classes": ["Q532"]},
        ),
        (
            "osm",
            "osm:node/200",
            "Bench",
            3.11,
            101.71,
            {"tags": {"amenity": "bench"}},
        ),
        (
            "osm",
            "osm:node/201",
            "Other Bench",
            3.12,
            101.72,
            {"tags": {"amenity": "bench"}},
        ),
    ]
    for source, source_ref, name, lat, lon, props in records:
        source_record.persist(
            conn,
            source_record.parse("malaysia", source, source_ref, name, lat, lon, props),
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
                "member_refs": [
                    "wd:Q100",
                    "wp:12345",
                    "wp:12346",
                    "osm:node/100",
                    "hehle:100",
                ],
                "status": "live",
            },
            {
                "place_id": B,
                "name": "Bench",
                "lat": 3.11,
                "lon": 101.71,
                "refs": ["wd:Q200"],
                "member_refs": ["wd:Q200", "osm:node/200"],
                "status": "live",
            },
        ],
    )


def _insert_categories(conn, *, run_id: str) -> None:
    conn.executemany(
        """
        INSERT INTO place_categories (place_id, region, category, run_id)
        VALUES (?, ?, ?, ?)
        """,
        [(A, "malaysia", "history", run_id), (B, "malaysia", "misc", run_id)],
    )
    conn.commit()
