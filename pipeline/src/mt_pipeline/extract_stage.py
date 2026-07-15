"""Production dispatch for source extractors."""

from __future__ import annotations

import pathlib
import shutil

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


def run_extract(
    conn,
    region_config,
    snapshots: dict,
    *,
    run_id: str,
    registry,
    extractor_options: dict | None = None,
    status_recorder=None,
) -> dict:
    _assert_enabled_sources_registered(region_config, registry)
    counts: dict[str, int] = {}
    extractor_options = extractor_options or {}
    for source, extractor in registry.enabled_for(region_config.sources):
        snapshot_path = snapshots.get(source)
        if snapshot_path is None:
            if status_recorder is not None:
                status_recorder(
                    source,
                    {"status": "failure", "error": "missing snapshot"},
                )
            raise MissingSnapshotError(f"enabled source {source!r} has no snapshot")
        try:
            assert_disk_floor(pathlib.Path(snapshot_path).parent)
            counts[source] = extractor.extract(
                region_config.region_id,
                snapshot_path,
                conn,
                run_id=run_id,
                **extractor_options.get(source, {}),
            )
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
