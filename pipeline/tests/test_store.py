import json
import sqlite3

import pytest

from mt_pipeline import store


def test_schema_is_idempotent_and_versioned(conn):
    store.init_schema(conn)
    tables = {
        r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
    }
    assert {
        store.SOURCE_RECORDS_TABLE,
        store.STAGE_RUNS_TABLE,
        store.EXTRACT_RUN_METADATA_TABLE,
        store.PLACES_TABLE,
        store.PLACE_CATEGORIES_TABLE,
        store.PLACE_SCORES_TABLE,
        store.META_TABLE,
    } <= tables
    ver = conn.execute(f"SELECT schema_version FROM {store.META_TABLE}").fetchone()[0]
    assert ver == store.WORKING_STORE_VERSION


def test_schema_rejects_stale_version(conn):
    store.init_schema(conn)
    conn.execute(f"UPDATE {store.META_TABLE} SET schema_version = ?", (999,))
    conn.commit()

    with pytest.raises(store.StoreVersionError, match="999"):
        store.init_schema(conn)


def test_schema_migrates_v2_store(conn):
    store.init_schema(conn)
    conn.execute(f"UPDATE {store.META_TABLE} SET schema_version = ?", (2,))
    conn.commit()

    store.init_schema(conn)

    version = conn.execute(f"SELECT schema_version FROM {store.META_TABLE}").fetchone()[0]
    tables = {
        r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
    }
    assert version == store.WORKING_STORE_VERSION
    assert {
        store.EXTRACT_RUN_METADATA_TABLE,
        store.PLACES_TABLE,
        store.PLACE_CATEGORIES_TABLE,
        store.PLACE_SCORES_TABLE,
    } <= tables


def test_schema_migrates_v3_store(conn):
    store.init_schema(conn)
    conn.execute(f"UPDATE {store.META_TABLE} SET schema_version = ?", (3,))
    conn.commit()

    store.init_schema(conn)

    version = conn.execute(f"SELECT schema_version FROM {store.META_TABLE}").fetchone()[0]
    tables = {
        r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
    }
    assert version == store.WORKING_STORE_VERSION
    assert {
        store.PLACES_TABLE,
        store.PLACE_CATEGORIES_TABLE,
        store.PLACE_SCORES_TABLE,
    } <= tables


def test_schema_migrates_v4_store(conn):
    store.init_schema(conn)
    conn.execute(f"UPDATE {store.META_TABLE} SET schema_version = ?", (4,))
    conn.commit()

    store.init_schema(conn)

    version = conn.execute(f"SELECT schema_version FROM {store.META_TABLE}").fetchone()[0]
    tables = {
        r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
    }
    assert version == store.WORKING_STORE_VERSION
    assert store.PLACE_CATEGORIES_TABLE in tables
    assert store.PLACE_SCORES_TABLE in tables


def test_schema_migrates_v5_store(conn):
    store.init_schema(conn)
    conn.execute(f"DROP TABLE {store.PLACE_SCORES_TABLE}")
    conn.execute(f"UPDATE {store.META_TABLE} SET schema_version = ?", (5,))
    conn.commit()

    store._migrate(conn, 5)

    version = conn.execute(f"SELECT schema_version FROM {store.META_TABLE}").fetchone()[0]
    tables = {
        r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
    }
    assert version == store.WORKING_STORE_VERSION
    assert store.PLACE_SCORES_TABLE in tables
    indexes = {
        r[1]
        for r in conn.execute(f"PRAGMA index_list({store.PLACE_SCORES_TABLE})")
    }
    assert "idx_place_scores_region" in indexes
    columns = {
        r[1]: {"type": r[2], "notnull": bool(r[3]), "pk": bool(r[5])}
        for r in conn.execute(f"PRAGMA table_info({store.PLACE_SCORES_TABLE})")
    }
    assert columns["place_id"]["pk"] is True
    assert columns["run_id"] == {"type": "TEXT", "notnull": True, "pk": False}
    assert columns["tier"] == {"type": "INTEGER", "notnull": True, "pk": False}
    assert columns["score"] == {"type": "REAL", "notnull": True, "pk": False}
    assert columns["signals_json"] == {"type": "TEXT", "notnull": True, "pk": False}


def test_replace_places_replaces_only_target_region_and_sorts_refs(conn):
    store.init_schema(conn)
    conn.execute(
        f"""
        INSERT INTO {store.PLACES_TABLE}
            (place_id, region, name, lat, lon, refs_json, member_refs_json, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        ("uk-old", "uk", "Old UK", 51.5, -0.1, '["wd:Q1"]', '["wd:Q1"]', "active"),
    )
    conn.execute(
        f"""
        INSERT INTO {store.PLACES_TABLE}
            (place_id, region, name, lat, lon, refs_json, member_refs_json, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        ("my-existing", "malaysia", "Existing MY", 3.1, 101.7, "[]", "[]", "active"),
    )
    conn.commit()

    store.replace_places(
        conn,
        region="uk",
        places=[
            {
                "place_id": "uk-new",
                "name": "New UK",
                "lat": 52.0,
                "lon": -1.0,
                "refs": ["wp:New_UK", "wd:Q2"],
                "member_refs": ["plaque:2", "osm:node/1"],
                "status": "active",
            }
        ],
    )

    rows = conn.execute(
        f"""
        SELECT region, place_id, name, refs_json, member_refs_json
        FROM {store.PLACES_TABLE}
        ORDER BY region, place_id
        """
    ).fetchall()
    assert rows == [
        ("malaysia", "my-existing", "Existing MY", "[]", "[]"),
        (
            "uk",
            "uk-new",
            "New UK",
            '["wd:Q2", "wp:New_UK"]',
            '["osm:node/1", "plaque:2"]',
        ),
    ]
    assert json.loads(rows[1][3]) == ["wd:Q2", "wp:New_UK"]
    assert json.loads(rows[1][4]) == ["osm:node/1", "plaque:2"]


def test_replace_places_commits_replacement(conn):
    store.init_schema(conn)
    conn.execute(
        f"""
        INSERT INTO {store.PLACES_TABLE}
            (place_id, region, name, lat, lon, refs_json, member_refs_json, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        ("uk-old", "uk", "Old UK", 51.5, -0.1, "[]", "[]", "active"),
    )
    conn.commit()

    store.replace_places(
        conn,
        region="uk",
        places=[
            {
                "place_id": "uk-new",
                "name": "New UK",
                "lat": 52.0,
                "lon": -1.0,
                "refs": [],
                "member_refs": [],
                "status": "active",
            }
        ],
    )
    conn.rollback()

    rows = conn.execute(
        f"""
        SELECT region, place_id, name
        FROM {store.PLACES_TABLE}
        WHERE region = ?
        ORDER BY place_id
        """,
        ("uk",),
    ).fetchall()
    assert rows == [("uk", "uk-new", "New UK")]


def test_meta_table_enforces_single_schema_row(conn):
    store.init_schema(conn)

    with pytest.raises(sqlite3.IntegrityError):
        conn.execute(
            f"INSERT INTO {store.META_TABLE} (id, schema_version) VALUES (?, ?)",
            (2, store.WORKING_STORE_VERSION),
        )


def test_stage_completion_ledger(conn):
    assert store.stage_completed(conn, "uk", "extract") is False
    store.mark_stage_complete(
        conn,
        "uk",
        "extract",
        run_id="r1",
        completed_at="2026-07-14T00:00:00Z",
    )
    assert store.stage_completed(conn, "uk", "extract") is True
    assert store.stage_completed(conn, "malaysia", "extract") is False


def test_stage_run_id_is_parameterized(conn):
    hostile = "r1'); DROP TABLE stage_runs;--"
    store.mark_stage_complete(
        conn,
        "uk",
        "extract",
        run_id=hostile,
        completed_at="2026-07-14T00:00:00Z",
    )

    tables = {
        r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
    }
    assert store.STAGE_RUNS_TABLE in tables
    row = conn.execute(f"SELECT run_id FROM {store.STAGE_RUNS_TABLE}").fetchone()
    assert row[0] == hostile


def test_mark_stage_complete_is_upsert(conn):
    store.mark_stage_complete(conn, "uk", "extract", "r1", "2026-07-14T00:00:00Z")
    store.mark_stage_complete(conn, "uk", "extract", "r2", "2026-07-14T01:00:00Z")
    rows = list(
        conn.execute(
            f"SELECT run_id FROM {store.STAGE_RUNS_TABLE} WHERE region=? AND stage=?",
            ("uk", "extract"),
        )
    )
    assert len(rows) == 1 and rows[0][0] == "r2"


def test_extract_run_metadata_is_upserted(conn):
    store.record_extract_run_metadata(
        conn,
        region="uk",
        run_id="r1",
        wikidata_snapshot_date="2026-07-15T00:00:00Z",
        source_statuses={
            "wikidata": {"status": "success", "count": 3},
            "open_plaques": {"status": "failure", "error": "boom"},
        },
    )
    store.record_extract_run_metadata(
        conn,
        region="uk",
        run_id="r1",
        wikidata_snapshot_date="2026-07-15T00:00:01Z",
        source_statuses={"wikidata": {"status": "success", "count": 4}},
    )

    assert store.load_extract_run_metadata(conn, region="uk", run_id="r1") == {
        "region": "uk",
        "run_id": "r1",
        "wikidata_snapshot_date": "2026-07-15T00:00:01Z",
        "source_statuses": {"wikidata": {"status": "success", "count": 4}},
    }
    assert store.load_extract_run_metadata(conn, region="uk", run_id="missing") is None
