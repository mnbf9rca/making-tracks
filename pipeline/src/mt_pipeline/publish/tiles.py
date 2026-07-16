"""Emit deterministic gzipped z10 place tiles."""

from __future__ import annotations

import hashlib
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass
from typing import Any

from mt_contracts import caps, registry, tilecodec
from mt_contracts.validation import validate_instance
from mt_pipeline import progress

from . import partition

_HEARTBEAT_EVERY_RECORDS = 10_000
_HEARTBEAT_EVERY_SECONDS = progress.HEARTBEAT_EVERY_SECONDS


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
    tile_obj: dict[str, Any],
    kept: list[Mapping[str, Any]],
    *,
    heartbeat: Callable[[int, int], None] | None = None,
) -> tuple[bytes, list[Mapping[str, Any]]]:
    attempt = 0
    while kept:
        attempt += 1
        if heartbeat is not None:
            heartbeat(attempt, len(kept))
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
    *,
    region: str | None = None,
) -> tuple[list[TileArtifact], PublishCounts]:
    records = list(registry_records)
    non_live_ids = _non_live_ids(records)
    place_list = list(places)
    phase = None
    if region is not None:
        phase = progress.PhaseProgress(
            "publish.tile_emit",
            region=region,
            total=len(place_list),
            total_label="places",
            heartbeat_every_records=_HEARTBEAT_EVERY_RECORDS,
            heartbeat_every_seconds=_HEARTBEAT_EVERY_SECONDS,
        )
        phase.start()

    valid: list[Mapping[str, Any]] = []
    invalid_excluded = 0
    uncategorized_excluded = 0
    processed = 0
    for place in place_list:
        processed += 1
        if not _is_valid_place(place):
            invalid_excluded += 1
            _tick_tile_progress(
                phase,
                processed,
                invalid_excluded=invalid_excluded,
                uncategorized_excluded=uncategorized_excluded,
            )
            continue
        if place["category"] == "uncategorized":
            uncategorized_excluded += 1
            _tick_tile_progress(
                phase,
                processed,
                invalid_excluded=invalid_excluded,
                uncategorized_excluded=uncategorized_excluded,
            )
            continue
        valid.append(dict(place))
        _tick_tile_progress(
            phase,
            processed,
            invalid_excluded=invalid_excluded,
            uncategorized_excluded=uncategorized_excluded,
        )

    ids = [str(place["place_id"]) for place in valid]
    superseded = set(registry.tile_winner_violations(ids, records))
    blocked = superseded | (set(ids) & non_live_ids)
    live_winners = [place for place in valid if place["place_id"] not in blocked]
    non_winner_excluded = len(valid) - len(live_winners)

    grouped = _group_tile_places(live_winners, region)
    artifacts: list[TileArtifact] = []
    final_places: list[Mapping[str, Any]] = []
    overflow_dropped = 0
    write_phase = None
    if region is not None:
        write_phase = progress.PhaseProgress(
            "publish.tile_write",
            region=region,
            total=len(grouped),
            total_label="tiles",
            heartbeat_every_records=_HEARTBEAT_EVERY_RECORDS,
            heartbeat_every_seconds=_HEARTBEAT_EVERY_SECONDS,
        )
        write_phase.start()

    tiles_written = 0
    for (x, y), tile_places in grouped.items():
        _tick_tile_write_start(
            write_phase,
            tiles_written,
            x=x,
            y=y,
            tile_places=len(tile_places),
            invalid_excluded=invalid_excluded,
            uncategorized_excluded=uncategorized_excluded,
            non_winner_excluded=non_winner_excluded,
            overflow_dropped=overflow_dropped,
        )
        kept, dropped = caps.select_tile_places(tile_places)
        overflow_dropped += len(dropped)
        tile_obj = {
            "schema_version": 1,
            "z": caps.TILE_ZOOM,
            "x": x,
            "y": y,
            "places": list(kept),
        }
        gz_bytes, final_kept = _gzip_with_reselect(
            tile_obj,
            list(kept),
            heartbeat=lambda attempt, kept_count: _tick_tile_write_gzip_attempt(
                write_phase,
                tiles_written + 1,
                attempt=attempt,
                kept_count=kept_count,
                invalid_excluded=invalid_excluded,
                uncategorized_excluded=uncategorized_excluded,
                non_winner_excluded=non_winner_excluded,
                overflow_dropped=overflow_dropped,
            ),
        )
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
        tiles_written += 1
        _tick_tile_write_progress(
            write_phase,
            tiles_written,
            invalid_excluded=invalid_excluded,
            uncategorized_excluded=uncategorized_excluded,
            non_winner_excluded=non_winner_excluded,
            overflow_dropped=overflow_dropped,
        )

    counts = PublishCounts(
        total_published=len(final_places),
        by_tier=_count_by_tier(final_places),
        uncategorized_excluded=uncategorized_excluded,
        invalid_excluded=invalid_excluded,
        non_winner_excluded=non_winner_excluded,
        overflow_dropped=overflow_dropped,
    )
    if phase is not None:
        phase.done(
            processed,
            extra=_tile_progress_extra(
                invalid_excluded=invalid_excluded,
                uncategorized_excluded=uncategorized_excluded,
                non_winner_excluded=non_winner_excluded,
                overflow_dropped=overflow_dropped,
                tiles_written=len(artifacts),
            ),
        )
    if write_phase is not None:
        write_phase.done(
            tiles_written,
            extra=_tile_progress_extra(
                invalid_excluded=invalid_excluded,
                uncategorized_excluded=uncategorized_excluded,
                non_winner_excluded=non_winner_excluded,
                overflow_dropped=overflow_dropped,
                tiles_written=tiles_written,
            ),
        )
    return sorted(artifacts, key=lambda artifact: (artifact.x, artifact.y)), counts


def _group_tile_places(
    places: list[Mapping[str, Any]], region: str | None
) -> dict[tuple[int, int], list[Mapping[str, Any]]]:
    phase = None
    if region is not None:
        phase = progress.PhaseProgress(
            "publish.tile_group",
            region=region,
            total=len(places),
            total_label="places",
            heartbeat_every_records=_HEARTBEAT_EVERY_RECORDS,
            heartbeat_every_seconds=_HEARTBEAT_EVERY_SECONDS,
        )
        phase.start()
    grouped: dict[tuple[int, int], list[Mapping[str, Any]]] = {}
    processed = 0
    for place in sorted(places, key=lambda p: str(p["place_id"])):
        processed += 1
        tile = partition.lonlat_to_z10(float(place["lat"]), float(place["lon"]))
        grouped.setdefault(tile, []).append(place)
        if phase is not None:
            phase.tick(processed)
    if phase is not None:
        phase.done(processed, extra=f" tiles={len(grouped)}")
    return {key: grouped[key] for key in sorted(grouped)}


def _tick_tile_progress(
    phase: progress.PhaseProgress | None,
    processed: int,
    *,
    invalid_excluded: int,
    uncategorized_excluded: int,
) -> None:
    if phase is None:
        return
    phase.tick(
        processed,
        extra=lambda: _tile_progress_extra(
            invalid_excluded=invalid_excluded,
            uncategorized_excluded=uncategorized_excluded,
            non_winner_excluded=0,
            overflow_dropped=0,
            tiles_written=0,
        ),
    )


def _tick_tile_write_progress(
    phase: progress.PhaseProgress | None,
    processed: int,
    *,
    invalid_excluded: int,
    uncategorized_excluded: int,
    non_winner_excluded: int,
    overflow_dropped: int,
) -> None:
    if phase is None:
        return
    phase.tick(
        processed,
        extra=lambda: _tile_progress_extra(
            invalid_excluded=invalid_excluded,
            uncategorized_excluded=uncategorized_excluded,
            non_winner_excluded=non_winner_excluded,
            overflow_dropped=overflow_dropped,
            tiles_written=processed,
        ),
    )


def _tick_tile_write_start(
    phase: progress.PhaseProgress | None,
    processed: int,
    *,
    x: int,
    y: int,
    tile_places: int,
    invalid_excluded: int,
    uncategorized_excluded: int,
    non_winner_excluded: int,
    overflow_dropped: int,
) -> None:
    if phase is None:
        return
    phase.tick(
        processed,
        extra=lambda: (
            f" current_tile={x}/{y}"
            f" tile_places={tile_places}"
            + _tile_progress_extra(
                invalid_excluded=invalid_excluded,
                uncategorized_excluded=uncategorized_excluded,
                non_winner_excluded=non_winner_excluded,
                overflow_dropped=overflow_dropped,
                tiles_written=processed,
            )
        ),
        force=True,
    )


def _tick_tile_write_gzip_attempt(
    phase: progress.PhaseProgress | None,
    processed: int,
    *,
    attempt: int,
    kept_count: int,
    invalid_excluded: int,
    uncategorized_excluded: int,
    non_winner_excluded: int,
    overflow_dropped: int,
) -> None:
    if phase is None:
        return
    phase.tick(
        processed,
        extra=lambda: (
            f" gzip_attempt={attempt}"
            f" kept={kept_count}"
            + _tile_progress_extra(
                invalid_excluded=invalid_excluded,
                uncategorized_excluded=uncategorized_excluded,
                non_winner_excluded=non_winner_excluded,
                overflow_dropped=overflow_dropped,
                tiles_written=max(0, processed - 1),
            )
        ),
        force=attempt == 1,
    )


def _tile_progress_extra(
    *,
    invalid_excluded: int,
    uncategorized_excluded: int,
    non_winner_excluded: int,
    overflow_dropped: int,
    tiles_written: int,
) -> str:
    return (
        f" invalid_excluded={invalid_excluded}"
        f" uncategorized_excluded={uncategorized_excluded}"
        f" non_winner_excluded={non_winner_excluded}"
        f" overflow_dropped={overflow_dropped}"
        f" tiles={tiles_written}"
    )
