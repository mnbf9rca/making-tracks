"""SQLite working store for deterministic between-stage state."""

from __future__ import annotations

import pathlib
import sqlite3
import json

WORKING_STORE_VERSION = 4
SOURCE_RECORDS_TABLE = "source_records"
STAGE_RUNS_TABLE = "stage_runs"
EXTRACT_RUN_METADATA_TABLE = "extract_run_metadata"
PLACES_TABLE = "places"
META_TABLE = "meta"

_SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (
    id             INTEGER PRIMARY KEY CHECK (id = 1),
    schema_version INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS source_records (
    id         INTEGER PRIMARY KEY,
    region     TEXT NOT NULL,
    source     TEXT NOT NULL,
    source_ref TEXT NOT NULL,
    name       TEXT NOT NULL,
    lat        REAL NOT NULL,
    lon        REAL NOT NULL,
    props_json TEXT NOT NULL,
    run_id     TEXT NOT NULL,
    UNIQUE (source, source_ref)
);
CREATE INDEX IF NOT EXISTS idx_source_records_region
    ON source_records(region);
CREATE TABLE IF NOT EXISTS stage_runs (
    region       TEXT NOT NULL,
    stage        TEXT NOT NULL,
    run_id       TEXT NOT NULL,
    completed_at TEXT NOT NULL,
    PRIMARY KEY (region, stage)
);
CREATE TABLE IF NOT EXISTS extract_run_metadata (
    region                 TEXT NOT NULL,
    run_id                 TEXT NOT NULL,
    wikidata_snapshot_date TEXT NOT NULL,
    source_status_json     TEXT NOT NULL,
    PRIMARY KEY (region, run_id)
);
CREATE TABLE IF NOT EXISTS places (
    place_id         TEXT PRIMARY KEY,
    region           TEXT NOT NULL,
    name             TEXT NOT NULL,
    lat              REAL NOT NULL,
    lon              REAL NOT NULL,
    refs_json        TEXT NOT NULL,
    member_refs_json TEXT NOT NULL,
    status           TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_places_region
    ON places(region);
"""


class StoreVersionError(sqlite3.DatabaseError):
    pass


def connect(db_path: str | pathlib.Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(_SCHEMA)
    try:
        rows = conn.execute("SELECT id, schema_version FROM meta").fetchall()
    except sqlite3.OperationalError as exc:
        raise StoreVersionError("working-store meta table has stale shape") from exc
    if not rows:
        conn.execute(
            "INSERT INTO meta (id, schema_version) VALUES (?, ?)",
            (1, WORKING_STORE_VERSION),
        )
    elif len(rows) != 1:
        raise StoreVersionError(f"expected one working-store schema row, found {len(rows)}")
    elif rows[0][0] != 1:
        raise StoreVersionError(f"unexpected working-store schema row id {rows[0][0]}")
    else:
        _migrate(conn, rows[0][1])
    conn.commit()


def _migrate(conn: sqlite3.Connection, current_version: int) -> None:
    if current_version > WORKING_STORE_VERSION:
        raise StoreVersionError(
            f"working-store schema version {current_version} "
            f"does not match expected {WORKING_STORE_VERSION}"
        )
    while current_version < WORKING_STORE_VERSION:
        if current_version == 2:
            current_version = 3
        elif current_version == 3:
            current_version = 4
        else:
            raise StoreVersionError(
                f"working-store schema version {current_version} "
                f"does not match expected {WORKING_STORE_VERSION}"
            )
        conn.execute(
            "UPDATE meta SET schema_version = ? WHERE id = 1",
            (current_version,),
        )


def mark_stage_complete(
    conn: sqlite3.Connection,
    region: str,
    stage: str,
    run_id: str,
    completed_at: str,
) -> None:
    conn.execute(
        """
        INSERT INTO stage_runs (region, stage, run_id, completed_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(region, stage) DO UPDATE SET
            run_id = excluded.run_id,
            completed_at = excluded.completed_at
        """,
        (region, stage, run_id, completed_at),
    )
    conn.commit()


def stage_completed(conn: sqlite3.Connection, region: str, stage: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM stage_runs WHERE region = ? AND stage = ?",
        (region, stage),
    ).fetchone()
    return row is not None


def record_extract_run_metadata(
    conn: sqlite3.Connection,
    *,
    region: str,
    run_id: str,
    wikidata_snapshot_date: str,
    source_statuses: dict,
) -> None:
    conn.execute(
        """
        INSERT INTO extract_run_metadata
            (region, run_id, wikidata_snapshot_date, source_status_json)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(region, run_id) DO UPDATE SET
            wikidata_snapshot_date = excluded.wikidata_snapshot_date,
            source_status_json = excluded.source_status_json
        """,
        (
            region,
            run_id,
            wikidata_snapshot_date,
            json.dumps(source_statuses, sort_keys=True),
        ),
    )
    conn.commit()


def load_extract_run_metadata(
    conn: sqlite3.Connection,
    *,
    region: str,
    run_id: str,
) -> dict | None:
    row = conn.execute(
        """
        SELECT wikidata_snapshot_date, source_status_json
        FROM extract_run_metadata
        WHERE region = ? AND run_id = ?
        """,
        (region, run_id),
    ).fetchone()
    if row is None:
        return None
    return {
        "region": region,
        "run_id": run_id,
        "wikidata_snapshot_date": row[0],
        "source_statuses": json.loads(row[1]),
    }


def replace_places(conn: sqlite3.Connection, *, region: str, places: list[dict]) -> None:
    conn.execute("DELETE FROM places WHERE region = ?", (region,))
    conn.executemany(
        """
        INSERT INTO places
            (place_id, region, name, lat, lon, refs_json, member_refs_json, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
            (
                place["place_id"],
                region,
                place["name"],
                place["lat"],
                place["lon"],
                json.dumps(place["refs"], sort_keys=True),
                json.dumps(place["member_refs"], sort_keys=True),
                place["status"],
            )
            for place in places
        ],
    )
    conn.commit()
