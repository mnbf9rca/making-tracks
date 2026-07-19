"""Helpers for the published region-index contract."""

from __future__ import annotations

import re
from collections.abc import Iterable, Mapping
from typing import Any

from .validation import validate_instance

_PUBLISH_VERSION_RE = re.compile(r"^[0-9]{8}T[0-9]{6}Z$")


class RegionIndexInvalid(ValueError):
    """Raised when a region-index passes JSON Schema but violates invariants."""


def validate_region_index(instance: Mapping[str, Any]) -> None:
    """Validate region-index schema and cross-entry invariants."""

    validate_instance("region-index", dict(instance))
    regions = list(instance["regions"])
    seen: set[str] = set()
    for entry in regions:
        region_id = str(entry["id"])
        if region_id in seen:
            raise RegionIndexInvalid(f"duplicate region id in region-index: {region_id}")
        seen.add(region_id)
        bbox = [float(value) for value in entry["bbox"]]
        if bbox[0] > bbox[2] or bbox[1] > bbox[3]:
            raise RegionIndexInvalid(f"invalid bbox ordering for region {region_id}")
        compact = entry.get("search_compact")
        if compact is not None:
            expected = f"{region_id}/{entry['publish_version']}/search/compact.json"
            if compact.get("path") != expected:
                raise RegionIndexInvalid(
                    f"search_compact path does not match region publish version for {region_id}"
                )

    for entry in regions:
        parent = entry["parent"]
        if parent is None:
            continue
        if parent == entry["id"]:
            raise RegionIndexInvalid(f"region {entry['id']} cannot be its own parent")
        if parent not in seen:
            raise RegionIndexInvalid(f"region {entry['id']} references unknown parent {parent}")


def dedupe_places_by_publish_version(
    records: Iterable[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    """Return one place per place_id, preferring the highest publish_version."""

    selected: dict[str, dict[str, Any]] = {}
    for record in records:
        place_id = record.get("place_id")
        publish_version = record.get("publish_version")
        if not isinstance(place_id, str) or not place_id:
            raise ValueError("place record missing string place_id")
        if not isinstance(publish_version, str) or not _PUBLISH_VERSION_RE.fullmatch(
            publish_version
        ):
            raise ValueError("place record missing valid publish_version")
        current = selected.get(place_id)
        if current is None or publish_version > current["publish_version"]:
            selected[place_id] = dict(record)
    return [selected[place_id] for place_id in sorted(selected)]
