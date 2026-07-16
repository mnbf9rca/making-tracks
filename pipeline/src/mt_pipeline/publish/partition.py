"""Partition place rows into z10 Web-Mercator tiles."""

from __future__ import annotations

import math
from collections import defaultdict
from collections.abc import Iterable, Mapping
from typing import Any

from mt_contracts.caps import TILE_ZOOM


def _clamp_tile(value: int) -> int:
    upper = (2**TILE_ZOOM) - 1
    return min(upper, max(0, value))


def lonlat_to_z10(lat: float, lon: float) -> tuple[int, int]:
    """Return the clamped z10 slippy tile for a latitude/longitude pair."""

    n = 2**TILE_ZOOM
    lat_rad = math.radians(lat)
    x = int((lon + 180.0) / 360.0 * n)
    y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return _clamp_tile(x), _clamp_tile(y)


def partition_places(
    places: Iterable[Mapping[str, Any]],
) -> dict[tuple[int, int], list[Mapping[str, Any]]]:
    grouped: dict[tuple[int, int], list[Mapping[str, Any]]] = defaultdict(list)
    for place in sorted(places, key=lambda p: str(p["place_id"])):
        grouped[lonlat_to_z10(float(place["lat"]), float(place["lon"]))].append(place)
    return {key: grouped[key] for key in sorted(grouped)}
