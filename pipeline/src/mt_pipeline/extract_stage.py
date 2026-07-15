"""Production dispatch for source extractors."""

from __future__ import annotations

import pathlib
import shutil
import sqlite3

from . import store
from .extractors import Registry
from .extractors import historic_england, open_plaques
from .extractors import osm as osm_extractor
from .extractors import wikidata
from .extractors.wikipedia import WikipediaExtractor

DEFAULT_OSM_TAG_CONFIG = (
    pathlib.Path(__file__).resolve().parents[2] / "config/osm_candidate_tags.json"
)


class UnregisteredEnabledSourceError(RuntimeError):
    pass


class MissingSnapshotError(RuntimeError):
    pass


class DiskSpaceError(RuntimeError):
    pass


MIN_FREE_BYTES = 8 * 1024 * 1024 * 1024
SOURCE_RECORD_SOURCE_BY_EXTRACTOR = {
    "historic_england": "hehle",
    "open_plaques": "plaque",
    "osm": "osm",
    "wikidata": "wd",
    "wikipedia": "wp",
}


def assert_disk_floor(path, *, min_free_bytes: int = MIN_FREE_BYTES) -> None:
    free = shutil.disk_usage(path).free
    if free < min_free_bytes:
        raise DiskSpaceError(
            f"free disk below floor: {free} bytes < {min_free_bytes} bytes"
        )


def build_registry(allowlist_path, languages: set[str], *, osm_tag_config_path=None) -> Registry:
    registry = Registry()
    registry.register("wikidata", wikidata.make_extractor(allowlist_path))
    registry.register("wikipedia", WikipediaExtractor(languages))
    registry.register(
        "osm", osm_extractor.make_extractor(osm_tag_config_path or DEFAULT_OSM_TAG_CONFIG)
    )
    registry.register("historic_england", historic_england.HistoricEnglandExtractor())
    registry.register("open_plaques", open_plaques.OpenPlaquesExtractor())
    return registry


def _assert_enabled_sources_registered(region_config, registry: Registry) -> None:
    enabled = {
        source
        for source, value in region_config.sources.items()
        if value is True
    }
    missing = enabled - registry.registered_sources()
    if missing:
        raise UnregisteredEnabledSourceError(
            f"enabled sources are not registered: {sorted(missing)}"
        )


def _source_record_source(source: str) -> str:
    return SOURCE_RECORD_SOURCE_BY_EXTRACTOR.get(source, source)


def _replace_source_records(
    conn,
    *,
    region: str,
    source: str,
    staged: sqlite3.Connection,
) -> None:
    stored_source = _source_record_source(source)
    rows = staged.execute(
        """
        SELECT region, source, source_ref, name, lat, lon, props_json, run_id
        FROM source_records
        WHERE region = ? AND source = ?
        ORDER BY source_ref
        """,
        (region, stored_source),
    ).fetchall()
    with conn:
        conn.execute(
            "DELETE FROM source_records WHERE region = ? AND source = ?",
            (region, stored_source),
        )
        conn.executemany(
            """
            INSERT INTO source_records
                (region, source, source_ref, name, lat, lon, props_json, run_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            rows,
        )


def _run_one_extract(
    conn,
    *,
    source: str,
    extractor,
    region_config,
    snapshot_path,
    run_id: str,
    extractor_options: dict,
):
    assert_disk_floor(pathlib.Path(snapshot_path).parent)
    return extractor.extract(
        region_config.region_id,
        snapshot_path,
        conn,
        run_id=run_id,
        **extractor_options.get(source, {}),
    )


def run_extract(
    conn,
    region_config,
    snapshots: dict,
    *,
    run_id: str,
    registry,
    extractor_options: dict | None = None,
    status_recorder=None,
    only_source: str | None = None,
) -> dict:
    _assert_enabled_sources_registered(region_config, registry)
    counts: dict[str, int] = {}
    extractor_options = extractor_options or {}
    enabled_extractors = registry.enabled_for(region_config.sources)
    if only_source is not None:
        enabled_extractors = [
            (source, extractor)
            for source, extractor in enabled_extractors
            if source == only_source
        ]
        if not enabled_extractors:
            raise UnregisteredEnabledSourceError(
                f"source {only_source!r} is not enabled and registered"
            )
    for source, extractor in enabled_extractors:
        snapshot_path = snapshots.get(source)
        if snapshot_path is None:
            if status_recorder is not None:
                status_recorder(
                    source,
                    {"status": "failure", "error": "missing snapshot"},
            )
            raise MissingSnapshotError(f"enabled source {source!r} has no snapshot")
        try:
            if only_source is None:
                counts[source] = _run_one_extract(
                    conn,
                    source=source,
                    extractor=extractor,
                    region_config=region_config,
                    snapshot_path=snapshot_path,
                    run_id=run_id,
                    extractor_options=extractor_options,
                )
            else:
                staged = sqlite3.connect(":memory:")
                try:
                    store.init_schema(staged)
                    counts[source] = _run_one_extract(
                        staged,
                        source=source,
                        extractor=extractor,
                        region_config=region_config,
                        snapshot_path=snapshot_path,
                        run_id=run_id,
                        extractor_options=extractor_options,
                    )
                    _replace_source_records(
                        conn,
                        region=region_config.region_id,
                        source=source,
                        staged=staged,
                    )
                finally:
                    staged.close()
        except Exception as exc:
            if status_recorder is not None:
                status_recorder(
                    source,
                    {
                        "status": "failure",
                        "error": f"{type(exc).__name__}: {exc}"[:500],
                    },
                )
            raise
        if status_recorder is not None:
            status_recorder(source, {"status": "success", "count": counts[source]})
    return counts
