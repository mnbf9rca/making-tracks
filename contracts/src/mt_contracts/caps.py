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
WIKIPEDIA_LANG_MAX = 16
DESCRIPTION_EXCERPT_MAX = 500
MAX_DESCRIPTION_INDEX_BYTES = 2 * 1024 * 1024
REF_MAX = 128
SOURCE_REFS_MAX = 64
REGISTRY_REFS_MAX = 256

REGION_ID_MAX = 64
DISPLAY_NAME_MAX = 80
LANGUAGES_MAX = 16
SOURCE_TOGGLES_MAX = 32
SOURCE_PMTILES_URL_MAX = 2048
SUBREGIONS_MAX = 256

TILE_ZOOM = 10
DESCRIPTION_TILE_ZOOM = TILE_ZOOM
BASEMAP_MAXZOOM = 14
MAX_PLACES_PER_TILE = 4000
MAX_TILE_UNCOMPRESSED_BYTES = 8 * 1024 * 1024
MAX_TILE_COMPRESSED_BYTES = 1 * 1024 * 1024
PACK_BUDGET_CEILING_BYTES = 3_221_225_472
TILES_MAX = 1_048_576
BASEMAP_FILENAME_MAX = 128
GENERATED_AT_MAX = 32
PROVENANCE_MIN = 1
PROVENANCE_MAX = 32
MODEL_MAX = 128
PROMPT_VERSION_MAX = 64
ATTRIBUTION_MAX = 32
ATTRIBUTION_SOURCE_MAX = 32
ATTRIBUTION_LICENSE_MAX = 32
ATTRIBUTION_TEXT_MAX = 512

CAPS_SCHEMA_MAP = {
    ("place", ("properties", "name"), "maxLength"): "NAME_MAX",
    ("place", ("properties", "alt_names"), "maxItems"): "ALT_NAMES_MAX",
    ("place", ("properties", "alt_names", "items"), "maxLength"): "NAME_MAX",
    ("place", ("properties", "category"), "maxLength"): "CATEGORY_MAX",
    ("place", ("properties", "blurb"), "maxLength"): "BLURB_MAX",
    ("place", ("properties", "image_url"), "maxLength"): "IMAGE_URL_MAX",
    ("place", ("properties", "wikipedia_title"), "maxLength"): "WIKIPEDIA_TITLE_MAX",
    ("place", ("properties", "source_refs"), "maxItems"): "SOURCE_REFS_MAX",
    ("place", ("properties", "source_refs", "items"), "maxLength"): "REF_MAX",
    ("registry-record", ("properties", "refs"), "maxItems"): "REGISTRY_REFS_MAX",
    ("registry-record", ("properties", "refs", "items"), "maxLength"): "REF_MAX",
    ("registry-record", ("properties", "mint_anchor"), "maxLength"): "REF_MAX",
    ("tile", ("properties", "z"), "const"): "TILE_ZOOM",
    ("tile", ("properties", "places"), "maxItems"): "MAX_PLACES_PER_TILE",
    ("manifest", ("properties", "tile_z"), "const"): "TILE_ZOOM",
    ("manifest", ("properties", "generated_at"), "maxLength"): "GENERATED_AT_MAX",
    ("manifest", ("properties", "tiles"), "maxItems"): "TILES_MAX",
    ("manifest", ("properties", "tiles", "items", "properties", "bytes"), "maximum"): "MAX_TILE_COMPRESSED_BYTES",
    ("manifest", ("properties", "basemap", "properties", "filename"), "maxLength"): "BASEMAP_FILENAME_MAX",
    ("manifest", ("properties", "basemap", "properties", "maxzoom"), "const"): "BASEMAP_MAXZOOM",
    ("manifest", ("properties", "basemap", "properties", "bytes"), "maximum"): "PACK_BUDGET_CEILING_BYTES",
    ("manifest", ("properties", "provenance"), "minItems"): "PROVENANCE_MIN",
    ("manifest", ("properties", "provenance"), "maxItems"): "PROVENANCE_MAX",
    ("manifest", ("properties", "provenance", "items", "properties", "model"), "maxLength"): "MODEL_MAX",
    ("manifest", ("properties", "provenance", "items", "properties", "prompt_version"), "maxLength"): "PROMPT_VERSION_MAX",
    ("manifest", ("properties", "attribution"), "maxItems"): "ATTRIBUTION_MAX",
    ("manifest", ("properties", "attribution", "items", "properties", "source"), "maxLength"): "ATTRIBUTION_SOURCE_MAX",
    ("manifest", ("properties", "attribution", "items", "properties", "license"), "maxLength"): "ATTRIBUTION_LICENSE_MAX",
    ("manifest", ("properties", "attribution", "items", "properties", "text"), "maxLength"): "ATTRIBUTION_TEXT_MAX",
    ("description-index", ("properties", "z"), "const"): "DESCRIPTION_TILE_ZOOM",
    ("description-index", ("properties", "places"), "maxItems"): "MAX_PLACES_PER_TILE",
    ("description-index", ("properties", "places", "items", "properties", "wikipedia_lang"), "maxLength"): "WIKIPEDIA_LANG_MAX",
    ("description-index", ("properties", "places", "items", "properties", "wikipedia_title"), "maxLength"): "WIKIPEDIA_TITLE_MAX",
    ("description-index", ("properties", "places", "items", "properties", "excerpt"), "maxLength"): "DESCRIPTION_EXCERPT_MAX",
    ("description-index", ("properties", "places", "items", "properties", "source_ref"), "maxLength"): "REF_MAX",
    ("region-config", ("properties", "region_id"), "maxLength"): "REGION_ID_MAX",
    ("region-config", ("properties", "display_name"), "maxLength"): "DISPLAY_NAME_MAX",
    ("region-config", ("properties", "languages"), "maxItems"): "LANGUAGES_MAX",
    ("region-config", ("properties", "sources"), "maxProperties"): "SOURCE_TOGGLES_MAX",
    ("region-config", ("properties", "sources", "additionalProperties", "oneOf", 1, "properties", "id"), "maxLength"): "REGION_ID_MAX",
    ("region-config", ("properties", "basemap", "properties", "source_pmtiles"), "maxLength"): "SOURCE_PMTILES_URL_MAX",
    ("region-config", ("properties", "basemap", "properties", "maxzoom"), "const"): "BASEMAP_MAXZOOM",
    ("region-config", ("properties", "basemap", "properties", "subregions"), "maxItems"): "SUBREGIONS_MAX",
    ("region-config", ("properties", "basemap", "properties", "subregions", "items", "properties", "id"), "maxLength"): "REGION_ID_MAX",
    ("region-config", ("properties", "basemap", "properties", "size_budget_bytes"), "maximum"): "PACK_BUDGET_CEILING_BYTES",
    ("region-config", ("properties", "basemap", "properties", "measured_archive_bytes"), "maximum"): "PACK_BUDGET_CEILING_BYTES",
}


def select_tile_places(
    places,
    max_per_tile: int = MAX_PLACES_PER_TILE,
    byte_budget: int = MAX_TILE_UNCOMPRESSED_BYTES,
):
    """Return (kept, dropped) using the A7 deterministic overflow rule."""
    ordered = sorted(places, key=lambda p: (p["tier"], -p["score"], p["place_id"]))
    kept = []
    running_bytes = 2  # len(b"[]")
    for place in ordered[:max_per_tile]:
        place_bytes = len(
            json.dumps(place, separators=(",", ":")).encode("utf-8")
        )
        candidate_bytes = running_bytes + place_bytes + (1 if kept else 0)
        if candidate_bytes > byte_budget:
            break
        kept.append(place)
        running_bytes = candidate_bytes
    return kept, ordered[len(kept):]
