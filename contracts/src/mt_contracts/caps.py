"""Named, versioned size caps and deterministic tile overflow selection."""

from __future__ import annotations

import json

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
MAX_TILE_UNCOMPRESSED_BYTES = 8 * 1024 * 1024
MAX_TILE_COMPRESSED_BYTES = 1 * 1024 * 1024
PACK_BUDGET_CEILING_BYTES = 3_221_225_472

CAPS_SCHEMA_MAP = {
    ("place", ("properties", "name"), "maxLength"): "NAME_MAX",
    ("place", ("properties", "alt_names"), "maxItems"): "ALT_NAMES_MAX",
    ("place", ("properties", "category"), "maxLength"): "CATEGORY_MAX",
    ("place", ("properties", "blurb"), "maxLength"): "BLURB_MAX",
    ("place", ("properties", "image_url"), "maxLength"): "IMAGE_URL_MAX",
    ("place", ("properties", "wikipedia_title"), "maxLength"): "WIKIPEDIA_TITLE_MAX",
    ("place", ("properties", "source_refs"), "maxItems"): "SOURCE_REFS_MAX",
    ("tile", ("properties", "places"), "maxItems"): "MAX_PLACES_PER_TILE",
}


def select_tile_places(
    places,
    max_per_tile: int = MAX_PLACES_PER_TILE,
    byte_budget: int = MAX_TILE_UNCOMPRESSED_BYTES,
):
    """Return (kept, dropped) using the A7 deterministic overflow rule."""
    ordered = sorted(places, key=lambda p: (p["tier"], -p["score"], p["place_id"]))
    kept = []
    for place in ordered[:max_per_tile]:
        candidate = kept + [place]
        if len(json.dumps(candidate, separators=(",", ":")).encode("utf-8")) > byte_budget:
            break
        kept.append(place)
    return kept, ordered[len(kept):]
