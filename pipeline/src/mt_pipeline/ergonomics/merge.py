"""Deterministic fixed-order merge from per-source staging stores."""

from __future__ import annotations

import pathlib
import sqlite3
from collections.abc import Iterable, Mapping

STAGING_ORDER = (
    "wikidata",
    "wikipedia",
    "osm",
    "historic_england",
    "open_plaques",
)

SOURCE_RECORD_SOURCE_BY_EXTRACTOR = {
    "historic_england": "hehle",
    "open_plaques": "plaque",
    "osm": "osm",
    "wikidata": "wd",
    "wikipedia": "wp",
}


def stored_source(source: str) -> str:
    return SOURCE_RECORD_SOURCE_BY_EXTRACTOR.get(source, source)


def merge_sources(
    main_conn: sqlite3.Connection,
    staged: Mapping[str, str | pathlib.Path],
    succeeded: set[str],
    *,
    order: Iterable[str] = STAGING_ORDER,
    full: bool,
    region: str | None = None,
) -> None:
    """Merge succeeded staged sources in registry order.

    The caller owns transaction boundaries. `full=True` replaces all region rows
    when `region` is supplied, or all `source_records` rows otherwise.
    """

    if full:
        if region is None:
            main_conn.execute("DELETE FROM source_records")
        else:
            main_conn.execute("DELETE FROM source_records WHERE region = ?", (region,))

    for source in order:
        if source not in succeeded or source not in staged:
            continue
        _merge_one(main_conn, source, pathlib.Path(staged[source]), full=full, region=region)


def _merge_one(
    main_conn: sqlite3.Connection,
    source: str,
    path: pathlib.Path,
    *,
    full: bool,
    region: str | None,
) -> None:
    staged_conn = sqlite3.connect(path)
    try:
        stored = stored_source(source)
        rows = staged_conn.execute(
            """
            SELECT region, source, source_ref, name, lat, lon, props_json, run_id
            FROM source_records
            WHERE source = ?
            ORDER BY source_ref
            """,
            (stored,),
        ).fetchall()
    finally:
        staged_conn.close()

    if not full:
        if region is None:
            regions = sorted({row[0] for row in rows})
            if not regions:
                raise ValueError("region is required for empty partial source merges")
            main_conn.executemany(
                "DELETE FROM source_records WHERE region = ? AND source = ?",
                [(staged_region, stored) for staged_region in regions],
            )
        else:
            main_conn.execute(
                "DELETE FROM source_records WHERE region = ? AND source = ?",
                (region, stored),
            )
    main_conn.executemany(
        """
        INSERT INTO source_records
            (region, source, source_ref, name, lat, lon, props_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        rows,
    )
