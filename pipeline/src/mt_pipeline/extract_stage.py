"""Production dispatch for source extractors."""

from __future__ import annotations

import pathlib

from .extractors import Registry
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


def build_registry(allowlist_path, languages: set[str], *, osm_tag_config_path=None) -> Registry:
    registry = Registry()
    registry.register("wikidata", wikidata.make_extractor(allowlist_path))
    registry.register("wikipedia", WikipediaExtractor(languages))
    registry.register(
        "osm", osm_extractor.make_extractor(osm_tag_config_path or DEFAULT_OSM_TAG_CONFIG)
    )
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


def run_extract(conn, region_config, snapshots: dict, *, run_id: str, registry) -> dict:
    _assert_enabled_sources_registered(region_config, registry)
    counts: dict[str, int] = {}
    for source, extractor in registry.enabled_for(region_config.sources):
        snapshot_path = snapshots.get(source)
        if snapshot_path is None:
            raise MissingSnapshotError(f"enabled source {source!r} has no snapshot")
        counts[source] = extractor.extract(
            region_config.region_id, snapshot_path, conn, run_id=run_id
        )
    return counts
