"""Publish stage orchestration over scored and categorized places."""

from __future__ import annotations

import json
import logging
import pathlib
from dataclasses import dataclass
from typing import Any

from mt_contracts import registry as registry_contract
from mt_contracts.tilecodec import safe_gunzip

from mt_pipeline import config, progress, runtime_paths
from mt_pipeline.reconcile.registry_file import LocalRegistryStore
from mt_pipeline.score import score_stage

from . import attribution, basemap, manifest, r2, staging, tiles

_PIPELINE_ROOT = pathlib.Path(__file__).resolve().parents[3]
_A1D_SOURCES = _PIPELINE_ROOT / "config" / "a1d_sources.json"
_R2_LAYOUT = _PIPELINE_ROOT / "config" / "r2_layout.json"
_RECONCILE_CONFIG = _PIPELINE_ROOT / "config" / "reconcile.json"
_DEFAULT_STAGING_ROOT = pathlib.Path("publish-staging")
_HEARTBEAT_EVERY_RECORDS = 10_000
_HEARTBEAT_EVERY_SECONDS = progress.HEARTBEAT_EVERY_SECONDS
_LOGGER = logging.getLogger(__name__)


class PublishStageError(RuntimeError):
    pass


@dataclass(frozen=True)
class PublishStageResult:
    staging_dir: pathlib.Path
    manifest: dict[str, Any]
    counts: tiles.PublishCounts
    publish_result: r2.PublishResult


def run(
    conn,
    region: str,
    *,
    publish_version: str,
    generated_at: str,
    scoring_config_version: str | None = None,
    upload: bool = False,
    staging_root: str | pathlib.Path = _DEFAULT_STAGING_ROOT,
) -> PublishStageResult:
    r2.validate_path_components(region, publish_version)
    basemap.require_pmtiles()
    if upload:
        r2.require_boto3()
        r2.require_upload_environment()
    scoring_config_version = scoring_config_version or str(score_stage.load_config()["version"])

    region_config = config.load(region)
    registry_path = _registry_path(conn, region)
    registry_store = LocalRegistryStore(registry_path)
    registry_records = _load_registry(registry_store, region)
    _assert_db_inputs(conn, region)
    joined = _joined_places(conn, region)
    _assert_registry_covers_live_inputs(registry_records, joined, registry_path, region)
    tile_arts, counts = tiles.emit_tiles(joined, registry_records, region=region)
    shipped_places = _places_from_tiles(tile_arts)
    shipped_ids = {place["place_id"] for place in shipped_places}
    _assert_registry_covers_shipped(registry_records, shipped_ids, registry_path)
    updated_registry = None
    registry_blob = None
    if shipped_ids:
        updated_registry = registry_contract.mark_shipped(
            registry_records,
            shipped_ids,
            publish_version,
        )
        registry_blob = _registry_jsonl(updated_registry)

    work_root = pathlib.Path(staging_root) / ".work" / region / publish_version
    work_root.mkdir(parents=True, exist_ok=True)
    basemap_path = work_root / f"{region}.pmtiles"
    basemap_art = basemap.cut_basemap(_region_doc(region_config), basemap_path)
    source_meta = json.loads(_A1D_SOURCES.read_text())
    manifest_obj = manifest.assemble_manifest(
        region=region,
        publish_version=publish_version,
        generated_at=generated_at,
        tiles=tile_arts,
        counts=counts,
        basemap=basemap_art,
        scoring_config_version=scoring_config_version,
        attribution=attribution.attribution_for(
            attribution.sources_used(shipped_places),
            source_meta,
        ),
    )
    staging_dir = staging.build_staging(
        pathlib.Path(staging_root),
        region,
        publish_version,
        tile_arts=tile_arts,
        manifest_obj=manifest_obj,
        basemap_path=basemap_path,
    )
    layout = json.loads(_R2_LAYOUT.read_text())
    publish_result = r2.publish_to_r2(
        staging_dir,
        layout,
        upload=upload,
        registry_blob=registry_blob,
    )

    if shipped_ids and upload and not publish_result.dry_run:
        assert updated_registry is not None
        registry_store.save(updated_registry)

    return PublishStageResult(
        staging_dir=staging_dir,
        manifest=manifest_obj,
        counts=counts,
        publish_result=publish_result,
    )


def _joined_places(conn, region: str) -> list[dict[str, Any]]:
    phase = progress.PhaseProgress(
        "publish.joined_place_load",
        region=region,
        total=None,
        total_label="places",
        heartbeat_every_records=_HEARTBEAT_EVERY_RECORDS,
        heartbeat_every_seconds=_HEARTBEAT_EVERY_SECONDS,
    )
    phase.start()
    rows = conn.execute(
        """
        SELECT p.place_id, p.name, p.lat, p.lon, p.member_refs_json,
               c.category, s.tier, s.score
        FROM places p
        JOIN place_categories c
          ON c.place_id = p.place_id AND c.region = p.region
        JOIN place_scores s
          ON s.place_id = p.place_id AND s.region = p.region
        WHERE p.region = ? AND p.status = 'live'
        """,
        (region,),
    )
    out = []
    processed = 0
    for place_id, name, lat, lon, member_refs_json, category, tier, score in rows:
        processed += 1
        out.append(
            {
                "place_id": place_id,
                "name": name,
                "lat": lat,
                "lon": lon,
                "category": category,
                "tier": tier,
                "score": score,
                "source_refs": _json_list(
                    member_refs_json,
                    region=region,
                    place_id=str(place_id),
                ),
            }
        )
        phase.tick(processed)
    phase.done(processed)
    return out


def _json_list(value: str, *, region: str, place_id: str) -> list[str]:
    try:
        data = json.loads(value)
    except (ValueError, RecursionError):
        _LOGGER.warning(
            "malformed member_refs_json (parse error) region=%s place_id=%s",
            region,
            place_id,
            exc_info=True,
        )
        return []
    if not isinstance(data, list) or not all(isinstance(item, str) for item in data):
        _LOGGER.warning(
            "malformed member_refs_json (not list[str], got %s) region=%s place_id=%s",
            type(data).__name__,
            region,
            place_id,
        )
        return []
    return data


def _places_from_tiles(tile_arts) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for art in tile_arts:
        out.extend(json.loads(safe_gunzip(art.gz_bytes))["places"])
    return out


def _region_doc(region_config: config.RegionConfig) -> dict[str, Any]:
    data = dict(region_config.raw)
    data["region"] = region_config.region_id
    basemap_cfg = dict(data["basemap"])
    basemap_cfg["bbox"] = list(region_config.bbox)
    data["basemap"] = basemap_cfg
    return data


def _load_registry(
    registry_store: LocalRegistryStore, region: str
) -> list[registry_contract.RegistryRecord]:
    path = registry_store.path
    if not path.exists():
        raise PublishStageError(f"publish registry missing for {region}: {path}")
    phase = progress.PhaseProgress(
        "publish.registry_load",
        region=region,
        total=None,
        total_label="records",
        heartbeat_every_records=_HEARTBEAT_EVERY_RECORDS,
        heartbeat_every_seconds=_HEARTBEAT_EVERY_SECONDS,
    )
    phase.start()
    processed = 0

    def tick_registry_load(done: int) -> None:
        nonlocal processed
        processed = done
        phase.tick(done)

    try:
        records = registry_store.load(progress_tick=tick_registry_load)
    except ValueError as exc:
        phase.done(processed, extra=" error=parse")
        raise PublishStageError(
            f"publish registry rejected for {region}: {path}: {exc}"
        ) from exc
    phase.done(len(records))
    if not records:
        raise PublishStageError(f"publish registry empty for {region}: {path}")
    return records


def _assert_db_inputs(conn, region: str) -> None:
    phase = progress.PhaseProgress(
        "publish.db_input_validation",
        region=region,
        total=None,
        total_label="places",
        heartbeat_every_records=_HEARTBEAT_EVERY_RECORDS,
        heartbeat_every_seconds=_HEARTBEAT_EVERY_SECONDS,
    )
    phase.start()
    rows = conn.execute(
        """
        SELECT p.place_id, s.place_id IS NOT NULL, c.place_id IS NOT NULL
        FROM places p
        LEFT JOIN place_scores s
          ON s.place_id = p.place_id AND s.region = p.region
        LEFT JOIN place_categories c
          ON c.place_id = p.place_id AND c.region = p.region
        WHERE p.region = ? AND p.status = 'live'
        """,
        (region,),
    )
    processed = 0
    missing_scores = 0
    missing_categories = 0
    for _place_id, has_score, has_category in rows:
        processed += 1
        if not has_score:
            missing_scores += 1
        if not has_category:
            missing_categories += 1
        phase.tick(
            processed,
            extra=lambda: (
                f" missing_scores={missing_scores}"
                f" missing_categories={missing_categories}"
            ),
        )
    phase.done(
        processed,
        extra=(
            f" missing_scores={missing_scores}"
            f" missing_categories={missing_categories}"
        ),
    )
    if processed == 0:
        raise PublishStageError(f"publish input has no live places for {region}")
    if missing_scores:
        raise PublishStageError(
            f"publish input has {missing_scores} live {region} place(s) missing place_scores"
        )

    if missing_categories:
        raise PublishStageError(
            f"publish input has {missing_categories} live {region} place(s) missing place_categories"
        )


def _assert_registry_covers_shipped(
    registry_records: list[registry_contract.RegistryRecord],
    shipped_ids: set[str],
    registry_path: pathlib.Path,
) -> None:
    missing = shipped_ids - {record.place_id for record in registry_records}
    if missing:
        sample = ", ".join(sorted(missing)[:20])
        suffix = (
            "" if len(missing) <= 20 else f", ... (+{len(missing) - 20} more)"
        )
        raise PublishStageError(
            f"publish registry {registry_path} is missing {len(missing)} shipped "
            f"place_id(s): {sample}{suffix}"
        )


def _assert_registry_covers_live_inputs(
    registry_records: list[registry_contract.RegistryRecord],
    joined_places: list[dict[str, Any]],
    registry_path: pathlib.Path,
    region: str,
) -> None:
    phase = progress.PhaseProgress(
        "publish.coverage_validation",
        region=region,
        total=len(joined_places),
        total_label="places",
        heartbeat_every_records=_HEARTBEAT_EVERY_RECORDS,
        heartbeat_every_seconds=_HEARTBEAT_EVERY_SECONDS,
    )
    phase.start()
    by_id = {record.place_id: record for record in registry_records}
    missing_ids: list[str] = []
    non_live_ids: list[str] = []
    missing_refs: dict[str, set[str]] = {}
    processed = 0
    for place in joined_places:
        processed += 1
        place_id = str(place["place_id"])
        record = by_id.get(place_id)
        if record is None:
            missing_ids.append(place_id)
            phase.tick(
                processed,
                extra=lambda: _coverage_progress_extra(
                    missing_ids,
                    non_live_ids,
                    missing_refs,
                ),
            )
            continue
        if record.status != "live" or record.superseded_by:
            non_live_ids.append(place_id)
        refs = set(place["source_refs"])
        missing = refs - set(record.refs)
        if missing:
            missing_refs[place_id] = missing
        phase.tick(
            processed,
            extra=lambda: _coverage_progress_extra(
                missing_ids,
                non_live_ids,
                missing_refs,
            ),
        )

    phase.done(
        processed,
        extra=_coverage_progress_extra(missing_ids, non_live_ids, missing_refs),
    )

    if missing_ids:
        sample = ", ".join(sorted(missing_ids)[:20])
        suffix = (
            ""
            if len(missing_ids) <= 20
            else f", ... (+{len(missing_ids) - 20} more)"
        )
        raise PublishStageError(
            f"publish registry {registry_path} is missing {len(missing_ids)} live "
            f"place_id(s): {sample}{suffix}"
        )
    if non_live_ids:
        sample = ", ".join(sorted(non_live_ids)[:20])
        suffix = (
            ""
            if len(non_live_ids) <= 20
            else f", ... (+{len(non_live_ids) - 20} more)"
        )
        raise PublishStageError(
            f"publish registry {registry_path} marks {len(non_live_ids)} live DB "
            f"place_id(s) non-live/superseded: {sample}{suffix}"
        )
    if missing_refs:
        place_id = sorted(missing_refs)[0]
        refs = ", ".join(sorted(missing_refs[place_id])[:20])
        raise PublishStageError(
            f"publish registry {registry_path} record {place_id} missing refs from "
            f"live DB input: {refs}"
        )


def _coverage_progress_extra(
    missing_ids: list[str],
    non_live_ids: list[str],
    missing_refs: dict[str, set[str]],
) -> str:
    return (
        f" missing_ids={len(missing_ids)}"
        f" non_live_ids={len(non_live_ids)}"
        f" missing_ref_places={len(missing_refs)}"
    )


def _registry_path(conn, region: str) -> pathlib.Path:
    reconcile = json.loads(_RECONCILE_CONFIG.read_text())
    return runtime_paths.resolve_near_db(
        conn, reconcile["registry_path"].format(region=region)
    )


def _registry_jsonl(records) -> bytes:
    rows = []
    for record in sorted(records, key=lambda item: item.place_id):
        rows.append(
            json.dumps(
                {
                    "first_shipped_version": record.first_shipped_version,
                    "last_seen_version": record.last_seen_version,
                    "mint_anchor": record.mint_anchor,
                    "place_id": record.place_id,
                    "refs": sorted(record.refs),
                    "schema_version": record.schema_version,
                    "status": record.status,
                    "superseded_by": record.superseded_by,
                },
                sort_keys=True,
                separators=(",", ":"),
            )
        )
    return ("\n".join(rows) + ("\n" if rows else "")).encode("utf-8")
