"""Derive manifest attribution from shipped place source refs."""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from typing import Any


PREFIX_TO_SOURCE_KEY = {
    "hehle": "historic_england",
    "plaque": "open_plaques",
    "osm": "osm",
    "wd": "wikidata",
    "wp": "wikipedia",
}


def sources_used(places: Iterable[Mapping[str, Any]]) -> set[str]:
    used: set[str] = set()
    for place in places:
        for ref in place.get("source_refs", ()):
            prefix = str(ref).split(":", 1)[0]
            source_key = PREFIX_TO_SOURCE_KEY.get(prefix)
            if source_key:
                used.add(source_key)
    return used


def attribution_for(
    sources: set[str],
    a1d_sources: Mapping[str, Mapping[str, Any]],
    *,
    includes_osm_basemap: bool = False,
) -> list[dict[str, str]]:
    if includes_osm_basemap:
        sources = set(sources)
        sources.add("osm")
    out = []
    for source in sorted(sources):
        meta = a1d_sources.get(source, {})
        text = meta.get("attribution")
        if not text:
            continue
        out.append(
            {
                "source": source,
                "license": str(meta.get("license", "")),
                "text": str(text),
            }
        )
    return out
