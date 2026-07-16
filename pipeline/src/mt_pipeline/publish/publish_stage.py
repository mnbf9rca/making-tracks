"""Publish stage orchestration over scored and categorized places."""

from __future__ import annotations

import json
import pathlib
from dataclasses import dataclass
from typing import Any

from mt_contracts import registry as registry_contract
from mt_contracts.tilecodec import safe_gunzip

from mt_pipeline import config
from mt_pipeline.reconcile.registry_file import LocalRegistryStore
from mt_pipeline.score import score_stage

from . import attribution, basemap, manifest, r2, staging, tiles

_PIPELINE_ROOT = pathlib.Path(__file__).resolve().parents[3]
_A1D_SOURCES = _PIPELINE_ROOT / "config" / "a1d_sources.json"
_R2_LAYOUT = _PIPELINE_ROOT / "config" / "r2_layout.json"
_RECONCILE_CONFIG = _PIPELINE_ROOT / "config" / "reconcile.json"
_DEFAULT_STAGING_ROOT = pathlib.Path("publish-staging")


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
    scoring_config_version = scoring_config_version or str(score_stage.load_config()["version"])

    region_config = config.load(region)
    registry_store = LocalRegistryStore(_registry_path(region))
    registry_records = registry_store.load()
    joined = _joined_places(conn, region)
    tile_arts, counts = tiles.emit_tiles(joined, registry_records)
    shipped_places = _places_from_tiles(tile_arts)

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
    publish_result = r2.publish_to_r2(staging_dir, layout, upload=upload)

    shipped_ids = {place["place_id"] for place in shipped_places}
    if shipped_ids:
        registry_store.save(
            registry_contract.mark_shipped(
                registry_records,
                shipped_ids,
                publish_version,
            )
        )

    return PublishStageResult(
        staging_dir=staging_dir,
        manifest=manifest_obj,
        counts=counts,
        publish_result=publish_result,
    )


def _joined_places(conn, region: str) -> list[dict[str, Any]]:
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
        ORDER BY p.place_id
        """,
        (region,),
    ).fetchall()
    out = []
    for place_id, name, lat, lon, member_refs_json, category, tier, score in rows:
        out.append(
            {
                "place_id": place_id,
                "name": name,
                "lat": lat,
                "lon": lon,
                "category": category,
                "tier": tier,
                "score": score,
                "source_refs": _json_list(member_refs_json),
            }
        )
    return out


def _json_list(value: str) -> list[str]:
    try:
        data = json.loads(value)
    except (ValueError, RecursionError) as exc:
        raise PublishStageError("places.member_refs_json is malformed") from exc
    if not isinstance(data, list) or not all(isinstance(item, str) for item in data):
        raise PublishStageError("places.member_refs_json must be a string array")
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


def _registry_path(region: str) -> pathlib.Path:
    reconcile = json.loads(_RECONCILE_CONFIG.read_text())
    return pathlib.Path(reconcile["registry_path"].format(region=region))
