"""Assemble and validate publish manifests."""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from typing import Any

from jsonschema import ValidationError
from mt_contracts import caps
from mt_contracts.validation import validate_instance

from .tiles import PublishCounts


class ManifestInvalid(ValueError):
    """Raised when a manifest cannot satisfy the frozen contract."""


def _get(obj: Any, key: str) -> Any:
    if isinstance(obj, Mapping):
        return obj[key]
    return getattr(obj, key)


def _tile_entry(tile: Any) -> dict[str, Any]:
    if isinstance(tile, Mapping):
        return {
            "x": tile["x"],
            "y": tile["y"],
            "sha256": tile["sha256"],
            "bytes": tile["bytes"],
        }
    return {
        "x": tile.x,
        "y": tile.y,
        "sha256": tile.sha256,
        "bytes": tile.byte_len,
    }


def _basemap_entry(basemap: Any) -> dict[str, Any]:
    return {
        "filename": _get(basemap, "filename"),
        "maxzoom": _get(basemap, "maxzoom"),
        "sha256": _get(basemap, "sha256"),
        "bytes": _get(basemap, "bytes"),
        "bbox": list(_get(basemap, "bbox")),
    }


def assemble_manifest(
    *,
    region: str,
    publish_version: str,
    generated_at: str,
    tiles: Iterable[Any],
    counts: PublishCounts,
    basemap: Any,
    scoring_config_version: str,
    llm_provenance: Iterable[Mapping[str, str]] = (),
    attribution: Iterable[Mapping[str, str]] = (),
) -> dict[str, Any]:
    attr = [dict(item) for item in attribution]
    tile_entries = sorted((_tile_entry(tile) for tile in tiles), key=lambda t: (t["x"], t["y"]))
    by_tier = list(counts.by_tier)
    if counts.total_published != sum(by_tier):
        raise ManifestInvalid("manifest counts total must equal sum(by_tier)")

    manifest = {
        "schema_version": 1,
        "min_reader_version": 2 if attr else 1,
        "region": region,
        "publish_version": publish_version,
        "generated_at": generated_at,
        "tile_z": caps.TILE_ZOOM,
        "tiles": tile_entries,
        "counts": {
            "total": counts.total_published,
            "by_tier": by_tier,
        },
        "basemap": _basemap_entry(basemap),
        "provenance": [
            {
                "task_id": "score",
                "model": "heuristic",
                "prompt_version": scoring_config_version,
            },
            *[dict(item) for item in llm_provenance],
        ],
        "attribution": attr,
    }
    try:
        validate_instance("manifest", manifest)
    except (ValidationError, ValueError) as exc:
        raise ManifestInvalid(str(exc)) from exc
    return manifest
