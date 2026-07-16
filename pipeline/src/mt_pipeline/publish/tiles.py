"""Emit deterministic gzipped z10 place tiles."""

from __future__ import annotations

import hashlib
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from typing import Any

from mt_contracts import caps, registry, tilecodec
from mt_contracts.validation import validate_instance

from . import partition


@dataclass(frozen=True)
class PublishCounts:
    total_published: int
    by_tier: tuple[int, int, int, int]
    uncategorized_excluded: int
    invalid_excluded: int
    non_winner_excluded: int
    overflow_dropped: int


@dataclass(frozen=True)
class TileArtifact:
    x: int
    y: int
    gz_bytes: bytes
    sha256: str
    byte_len: int


def _is_valid_place(place: Mapping[str, Any]) -> bool:
    try:
        validate_instance("place", dict(place))
    except Exception:
        return False
    return True


def _live_ids(records: list[registry.RegistryRecord]) -> set[str]:
    return {record.place_id for record in records if record.status == "live"}


def _non_live_ids(records: list[registry.RegistryRecord]) -> set[str]:
    return {record.place_id for record in records if record.status != "live"}


def _count_by_tier(places: Iterable[Mapping[str, Any]]) -> tuple[int, int, int, int]:
    counts = [0, 0, 0, 0]
    for place in places:
        counts[int(place["tier"]) - 1] += 1
    return tuple(counts)


def _gzip_with_reselect(
    tile_obj: dict[str, Any], kept: list[Mapping[str, Any]]
) -> tuple[bytes, list[Mapping[str, Any]]]:
    while kept:
        tile_obj["places"] = list(kept)
        try:
            return tilecodec.gzip_tile(tile_obj), kept
        except ValueError:
            kept = kept[:-1]
    tile_obj["places"] = []
    return tilecodec.gzip_tile(tile_obj), []


def emit_tiles(
    places: Iterable[Mapping[str, Any]],
    registry_records: Iterable[registry.RegistryRecord],
) -> tuple[list[TileArtifact], PublishCounts]:
    records = list(registry_records)
    non_live_ids = _non_live_ids(records)

    valid: list[Mapping[str, Any]] = []
    invalid_excluded = 0
    uncategorized_excluded = 0
    for place in places:
        if not _is_valid_place(place):
            invalid_excluded += 1
            continue
        if place["category"] == "uncategorized":
            uncategorized_excluded += 1
            continue
        valid.append(dict(place))

    ids = [str(place["place_id"]) for place in valid]
    superseded = set(registry.tile_winner_violations(ids, records))
    blocked = superseded | (set(ids) & non_live_ids)
    live_winners = [place for place in valid if place["place_id"] not in blocked]
    non_winner_excluded = len(valid) - len(live_winners)

    grouped = partition.partition_places(live_winners)
    artifacts: list[TileArtifact] = []
    final_places: list[Mapping[str, Any]] = []
    overflow_dropped = 0

    for (x, y), tile_places in grouped.items():
        kept, dropped = caps.select_tile_places(tile_places)
        overflow_dropped += len(dropped)
        tile_obj = {"schema_version": 1, "z": caps.TILE_ZOOM, "x": x, "y": y, "places": list(kept)}
        gz_bytes, final_kept = _gzip_with_reselect(tile_obj, list(kept))
        overflow_dropped += len(kept) - len(final_kept)
        tile_obj["places"] = list(final_kept)
        validate_instance("tile", tile_obj)
        final_places.extend(final_kept)
        artifacts.append(
            TileArtifact(
                x=x,
                y=y,
                gz_bytes=gz_bytes,
                sha256=hashlib.sha256(gz_bytes).hexdigest(),
                byte_len=len(gz_bytes),
            )
        )

    counts = PublishCounts(
        total_published=len(final_places),
        by_tier=_count_by_tier(final_places),
        uncategorized_excluded=uncategorized_excluded,
        invalid_excluded=invalid_excluded,
        non_winner_excluded=non_winner_excluded,
        overflow_dropped=overflow_dropped,
    )
    return sorted(artifacts, key=lambda artifact: (artifact.x, artifact.y)), counts
