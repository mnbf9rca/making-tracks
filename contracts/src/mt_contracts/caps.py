"""Named, versioned size caps and deterministic tile overflow selection."""

from __future__ import annotations

CAPS_VERSION = 1

NAME_MAX = 200
ALT_NAMES_MAX = 8
CATEGORY_MAX = 64
BLURB_MAX = 600
IMAGE_URL_MAX = 2048
WIKIPEDIA_TITLE_MAX = 300
SOURCE_REFS_MAX = 64

TILE_ZOOM = 10
MAX_PLACES_PER_TILE = 4000
MAX_TILE_UNCOMPRESSED_BYTES = 4 * 1024 * 1024


def select_tile_places(places, max_per_tile: int = MAX_PLACES_PER_TILE):
    """Return (kept, dropped) using the A7 deterministic overflow rule."""
    ordered = sorted(places, key=lambda p: (p["tier"], -p["score"], p["place_id"]))
    return ordered[:max_per_tile], ordered[max_per_tile:]
