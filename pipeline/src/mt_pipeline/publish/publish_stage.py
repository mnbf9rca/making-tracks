"""Publish stage orchestration over scored and categorized places."""

from __future__ import annotations

import hashlib
import json
import logging
import math
import pathlib
import re
import sys
from dataclasses import dataclass, replace
from typing import Any

from mt_contracts import registry as registry_contract
from mt_contracts.tilecodec import safe_gunzip
from mt_contracts.versions import SCHEMA_VERSIONS

from mt_pipeline import config, progress, runtime_paths
from mt_pipeline.reconcile.registry_file import LocalRegistryStore
from mt_pipeline.score import score_stage

from . import attribution, basemap, descriptions, images, manifest, r2, search_index, staging, tiles, zone_catalog

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
class PublishedTargetResult:
    staging_dir: pathlib.Path
    manifest: dict[str, Any]
    counts: tiles.PublishCounts
    publish_result: r2.PublishResult
    image_index_bytes: int = 0
    description_index_bytes: int = 0
    description_index_dropped: int = 0
    search_index_bytes: int = 0
    search_compact_bytes: int = 0
    thumb_bytes: int = 0


@dataclass(frozen=True)
class PublishStageResult(PublishedTargetResult):
    subregion_results: tuple[PublishedTargetResult, ...] = ()
    region_index: dict[str, Any] | None = None
    region_index_path: pathlib.Path | None = None
    region_index_publish_result: r2.PublishResult | None = None


def run(
    conn,
    region: str,
    *,
    publish_version: str,
    generated_at: str,
    scoring_config_version: str | None = None,
    upload: bool = False,
    staging_root: str | pathlib.Path = _DEFAULT_STAGING_ROOT,
    image_candidate_limit: int | None = None,
    audited_image_completed_jsonl: str | pathlib.Path | None = None,
    audited_image_cache_dir: str | pathlib.Path | None = None,
    no_image_fetch: bool = False,
    no_zone_catalog: bool = False,
    reuse_existing_thumbs: bool = False,
) -> PublishStageResult:
    staging_root = pathlib.Path(staging_root)
    r2.validate_path_components(region, publish_version)
    _assert_upload_content_scope(
        upload=upload,
        image_candidate_limit=image_candidate_limit,
        audited_image_completed_jsonl=audited_image_completed_jsonl,
        audited_image_cache_dir=audited_image_cache_dir,
        no_image_fetch=no_image_fetch,
    )
    basemap.require_pmtiles()
    if upload:
        r2.require_boto3()
        r2.require_upload_environment()
    scoring_config_version = scoring_config_version or str(score_stage.load_config()["version"])

    config.assert_global_region_ids()
    region_config = config.load(region)
    target_region_ids = [region_config.region_id]
    target_region_ids.extend(
        subregion.region_id for subregion in region_config.subregions
    )
    for removed_path in staging.prune_run_staging(staging_root, target_region_ids):
        print(f"PUBLISH_STAGING_PRUNE removed={removed_path}", file=sys.stderr)
    registry_path = _registry_path(conn, region)
    registry_store = LocalRegistryStore(registry_path)
    registry_records = _load_registry(registry_store, region)
    _assert_db_inputs(conn, region)
    joined = _joined_places(conn, region)
    _assert_registry_covers_live_inputs(registry_records, joined, registry_path, region)
    source_description_rows = descriptions.source_rows_from_db(conn, region)
    joined_descriptions = descriptions.descriptions_from_source_records(
        joined,
        source_description_rows,
    )
    joined = _with_inline_blurbs(joined, joined_descriptions)
    tile_arts, counts = tiles.emit_tiles(joined, registry_records, region=region)
    shipped_places = _places_from_tiles(tile_arts)
    shipped_ids = {place["place_id"] for place in shipped_places}
    _assert_registry_covers_shipped(registry_records, shipped_ids, registry_path)
    shipped_by_id = {str(place["place_id"]): place for place in shipped_places}
    image_candidates = images.candidates_from_source_records(conn, region, shipped_places)
    image_candidate_rows = [
        (shipped_by_id[candidate.place_id], candidate)
        for candidate in image_candidates
        if candidate.place_id in shipped_by_id
    ]
    selected_image_candidates = images.select_image_candidates(
        image_candidate_rows,
        limit=image_candidate_limit,
    )
    place_images = _build_place_images(
        selected_image_candidates,
        staging_root=pathlib.Path(staging_root),
        audited_image_completed_jsonl=audited_image_completed_jsonl,
        audited_image_cache_dir=audited_image_cache_dir,
        no_image_fetch=no_image_fetch,
        require_complete_audit=upload,
        require_complete_fetch=upload,
    )
    place_images_by_id = {item.place_id: item for item in place_images}
    source_search_rows = search_index.source_rows_from_db(
        conn,
        region,
        _source_refs_from_places(shipped_places),
    )
    updated_registry = None
    registry_blob = None
    if shipped_ids:
        updated_registry = registry_contract.mark_shipped(
            registry_records,
            shipped_ids,
            publish_version,
        )
        registry_blob = _registry_jsonl(updated_registry)

    source_meta = json.loads(_A1D_SOURCES.read_text())
    layout = json.loads(_R2_LAYOUT.read_text())
    target_results: list[PublishedTargetResult] = []
    parent_result = _publish_target(
        region_config=region_config,
        target_region=region,
        bbox=region_config.bbox,
        tile_arts=tile_arts,
        counts=counts,
        source_meta=source_meta,
        layout=layout,
        publish_version=publish_version,
        generated_at=generated_at,
        scoring_config_version=scoring_config_version,
        staging_root=staging_root,
        registry_blob=registry_blob,
        place_images_by_id=place_images_by_id,
        source_description_rows=source_description_rows,
        source_search_rows=source_search_rows,
        conn=conn,
        no_zone_catalog=no_zone_catalog,
    )
    target_results.append(parent_result)

    subregion_results: list[PublishedTargetResult] = []
    for subregion in region_config.subregions:
        sub_joined = _filter_places_to_bbox(joined, subregion.bbox)
        sub_tile_arts, sub_counts = tiles.emit_tiles(
            sub_joined, registry_records, region=subregion.region_id
        )
        sub_result = _publish_target(
            region_config=region_config,
            target_region=subregion.region_id,
            bbox=subregion.bbox,
            tile_arts=sub_tile_arts,
            counts=sub_counts,
            source_meta=source_meta,
            layout=layout,
            publish_version=publish_version,
            generated_at=generated_at,
            scoring_config_version=scoring_config_version,
            staging_root=staging_root,
            registry_blob=None,
            place_images_by_id=place_images_by_id,
            source_description_rows=source_description_rows,
            source_search_rows=source_search_rows,
            subregion=subregion,
            no_zone_catalog=no_zone_catalog,
        )
        subregion_results.append(sub_result)
        target_results.append(sub_result)

    region_index_obj = _region_index(
        generated_at=generated_at,
        targets=target_results,
        display_names={
            region: region_config.display_name,
            **{
                subregion.region_id: subregion.display_name
                for subregion in region_config.subregions
            },
        },
        parents={
            subregion.region_id: region for subregion in region_config.subregions
        },
    )
    region_index_path = staging.write_region_index(
        staging_root, region_index_obj
    )
    region_index_publish_result = r2.publish_region_index(region_index_path, layout)

    if upload:
        _assert_upload_sidecar_completeness(target_results)
        prepared = r2.publish_prepared_to_r2(
            [target.publish_result.plan for target in target_results],
            region_index_path,
            layout,
            reuse_existing_thumbs=reuse_existing_thumbs,
        )
        parent_result = replace(
            parent_result, publish_result=prepared.target_results[0]
        )
        subregion_results = [
            replace(result, publish_result=prepared_result)
            for result, prepared_result in zip(
                subregion_results, prepared.target_results[1:], strict=True
            )
        ]
        region_index_publish_result = prepared.region_index_result

    if shipped_ids and upload and not parent_result.publish_result.dry_run:
        assert updated_registry is not None
        registry_store.save(updated_registry)

    return PublishStageResult(
        staging_dir=parent_result.staging_dir,
        manifest=parent_result.manifest,
        counts=parent_result.counts,
        publish_result=parent_result.publish_result,
        image_index_bytes=parent_result.image_index_bytes,
        description_index_bytes=parent_result.description_index_bytes,
        description_index_dropped=parent_result.description_index_dropped,
        search_index_bytes=parent_result.search_index_bytes,
        search_compact_bytes=parent_result.search_compact_bytes,
        thumb_bytes=parent_result.thumb_bytes,
        subregion_results=tuple(subregion_results),
        region_index=region_index_obj,
        region_index_path=region_index_path,
        region_index_publish_result=region_index_publish_result,
    )


def _build_place_images(
    selected_candidates: list[images.ImageCandidate],
    *,
    staging_root: pathlib.Path,
    audited_image_completed_jsonl: str | pathlib.Path | None,
    audited_image_cache_dir: str | pathlib.Path | None,
    no_image_fetch: bool,
    require_complete_audit: bool = False,
    require_complete_fetch: bool = False,
) -> list[images.PlaceImage]:
    audit_args = [audited_image_completed_jsonl, audited_image_cache_dir]
    if any(value is not None for value in audit_args):
        if not all(value is not None for value in audit_args):
            raise PublishStageError(
                "audited image reuse requires both "
                "--audited-image-completed-jsonl and --audited-image-cache-dir"
            )
        assert audited_image_completed_jsonl is not None
        assert audited_image_cache_dir is not None
        selected_candidates = images.exclude_cached_rejects(
            selected_candidates,
            cache_dir=pathlib.Path(audited_image_cache_dir),
        )
        return images.build_place_images_from_audit(
            selected_candidates,
            completed_jsonl=pathlib.Path(audited_image_completed_jsonl),
            audited_cache_dir=pathlib.Path(audited_image_cache_dir),
            require_complete=require_complete_audit,
        )
    if no_image_fetch:
        print(
            "IMAGE_FETCH_DISABLED "
            f"candidates={len(selected_candidates)} selected=0"
        )
        return []
    place_images = images.build_place_images(
        selected_candidates,
        cache_dir=staging_root / ".image-cache",
    )
    if require_complete_fetch:
        expected = {candidate.place_id for candidate in selected_candidates}
        actual = {place_image.place_id for place_image in place_images}
        missing = sorted(expected - actual)
        if missing:
            raise PublishStageError(
                "upload publish image fetch did not produce all scoped images: "
                f"missing={len(missing)}"
            )
    return place_images


def _assert_upload_sidecar_completeness(
    target_results: list[PublishedTargetResult],
) -> None:
    dropped = [
        (target.manifest["region"], target.description_index_dropped)
        for target in target_results
        if target.description_index_dropped
    ]
    if dropped:
        detail = ", ".join(
            f"{region}:{count}" for region, count in sorted(dropped)
        )
        raise PublishStageError(
            "upload publish description sidecars dropped scoped blurbs: "
            f"{detail}"
        )


def _assert_upload_content_scope(
    *,
    upload: bool,
    image_candidate_limit: int | None,
    audited_image_completed_jsonl: str | pathlib.Path | None,
    audited_image_cache_dir: str | pathlib.Path | None,
    no_image_fetch: bool,
) -> None:
    if not upload:
        return
    if image_candidate_limit is not None:
        raise PublishStageError(
            "upload publish must not use --image-candidate-limit; "
            "offline bundles must include all image candidates in scope"
        )
    has_audit = (
        audited_image_completed_jsonl is not None
        and audited_image_cache_dir is not None
    )
    if no_image_fetch and not has_audit:
        raise PublishStageError(
            "upload publish must not use --no-image-fetch without complete audited image reuse"
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
        SELECT p.place_id, p.name, p.lat, p.lon, p.refs_json, p.member_refs_json,
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
    for place_id, name, lat, lon, refs_json, member_refs_json, category, tier, score in rows:
        processed += 1
        parsed_member_refs = _json_list(
            member_refs_json,
            region=region,
            place_id=str(place_id),
        )
        parsed_refs = _json_list(
            refs_json,
            region=region,
            place_id=str(place_id),
            field_name="refs_json",
        )
        source_refs = (
            []
            if parsed_member_refs is None or parsed_refs is None
            else _publish_source_refs(parsed_member_refs, parsed_refs)
        )
        out.append(
            {
                "place_id": place_id,
                "name": name,
                "lat": lat,
                "lon": lon,
                "category": category,
                "tier": tier,
                "score": score,
                "source_refs": source_refs,
            }
        )
        phase.tick(processed)
    phase.done(processed)
    return out


def _publish_source_refs(member_refs: list[str], refs: list[str]) -> list[str]:
    source_refs = list(member_refs)
    seen = set(source_refs)
    for ref in refs:
        if re.fullmatch(r"wd:Q[0-9]+", ref) and ref not in seen:
            source_refs.append(ref)
            seen.add(ref)
    return sorted(source_refs)


def _json_list(
    value: str,
    *,
    region: str,
    place_id: str,
    field_name: str = "member_refs_json",
) -> list[str] | None:
    try:
        data = json.loads(value)
    except (ValueError, RecursionError):
        _LOGGER.warning(
            "malformed %s (parse error) region=%s place_id=%s",
            field_name,
            region,
            place_id,
            exc_info=True,
        )
        return None
    if not isinstance(data, list) or not all(isinstance(item, str) for item in data):
        _LOGGER.warning(
            "malformed %s (not list[str], got %s) region=%s place_id=%s",
            field_name,
            type(data).__name__,
            region,
            place_id,
        )
        return None
    return data


def _places_from_tiles(tile_arts) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for art in tile_arts:
        out.extend(json.loads(safe_gunzip(art.gz_bytes))["places"])
    return out


def _with_inline_blurbs(
    places: list[dict[str, Any]],
    place_descriptions: list[descriptions.PlaceDescription],
) -> list[dict[str, Any]]:
    by_id = {desc.place_id: desc.excerpt for desc in place_descriptions}
    out: list[dict[str, Any]] = []
    for place in places:
        blurb = by_id.get(str(place["place_id"]))
        out.append({**place, "blurb": blurb} if blurb else dict(place))
    return out


def _source_refs_from_places(places) -> set[str]:
    refs: set[str] = set()
    for place in places:
        for ref in place.get("source_refs", []):
            if isinstance(ref, str):
                refs.add(ref)
    return refs


def _publish_target(
    *,
    region_config: config.RegionConfig,
    target_region: str,
    bbox: tuple,
    tile_arts: list[tiles.TileArtifact],
    counts: tiles.PublishCounts,
    source_meta: dict[str, Any],
    layout: dict[str, Any],
    publish_version: str,
    generated_at: str,
    scoring_config_version: str,
    staging_root: pathlib.Path,
    registry_blob: bytes | None,
    place_images_by_id: dict[str, images.PlaceImage],
    source_description_rows: list[dict[str, Any]],
    source_search_rows: dict[str, dict[str, Any]],
    subregion: config.SubregionConfig | None = None,
    conn=None,
    no_zone_catalog: bool = False,
) -> PublishedTargetResult:
    work_root = pathlib.Path(staging_root) / ".work" / target_region / publish_version
    work_root.mkdir(parents=True, exist_ok=True)
    basemap_path = work_root / f"{target_region}.pmtiles"
    basemap_art = basemap.cut_basemap(
        _region_doc(
            region_config,
            target_region=target_region,
            bbox=bbox,
            subregion=subregion,
        ),
        basemap_path,
    )
    shipped_places = _places_from_tiles(tile_arts)
    shipped_place_images = [
        place_images_by_id[str(place["place_id"])]
        for place in shipped_places
        if str(place["place_id"]) in place_images_by_id
    ]
    image_index_arts, thumb_arts = images.emit_image_artifacts(shipped_place_images)
    place_descriptions = descriptions.descriptions_from_source_records(
        shipped_places,
        source_description_rows,
    )
    description_result = descriptions.emit_description_result(
        place_descriptions,
        region=target_region,
    )
    description_index_arts = description_result.artifacts
    search_result = search_index.emit_search_indexes(
        shipped_places,
        source_props_by_ref=source_search_rows,
        region=target_region,
        publish_version=publish_version,
        generated_at=generated_at,
    )
    manifest_obj = manifest.assemble_manifest(
        region=target_region,
        publish_version=publish_version,
        generated_at=generated_at,
        tiles=tile_arts,
        counts=counts,
        basemap=basemap_art,
        scoring_config_version=scoring_config_version,
        attribution=attribution.attribution_for(
            attribution.sources_used(shipped_places),
            source_meta,
            includes_osm_basemap=True,
        ),
    )
    staging_dir = staging.build_staging(
        staging_root,
        target_region,
        publish_version,
        tile_arts=tile_arts,
        image_index_arts=image_index_arts,
        description_index_arts=description_index_arts,
        search_index_arts=search_result.full_artifacts,
        search_compact_art=search_result.compact_artifact,
        thumb_arts=thumb_arts,
        manifest_obj=manifest_obj,
        basemap_path=basemap_path,
    )
    if (
        conn is not None
        and subregion is None
        and region_config.zone_levels
        and no_zone_catalog
    ):
        print(
            "NOZONE_DISABLE "
            f"region={target_region} "
            f"previous_zone_levels={sorted(region_config.zone_levels)} "
            f"previous_allowlist={len(region_config.zone_allowlist)}"
        )
    elif conn is not None and subregion is None and region_config.zone_levels:
        proposal_catalog, pruned_catalog = zone_catalog.materialize_catalogs(
            conn,
            region_config,
            publish_version=publish_version,
            generated_at=generated_at,
            cell_sizes=_zone_cell_sizes(
                tile_arts,
                description_index_arts,
                image_index_arts,
            ),
        )
        staging.write_zone_catalogs(
            staging_dir,
            proposal_obj=proposal_catalog,
            pruned_obj=pruned_catalog if region_config.zone_allowlist else None,
        )
    publish_result = r2.publish_to_r2(
        staging_dir,
        layout,
        upload=False,
        registry_blob=registry_blob,
    )
    return PublishedTargetResult(
        staging_dir=staging_dir,
        manifest=manifest_obj,
        counts=counts,
        publish_result=publish_result,
        image_index_bytes=sum(art.byte_len for art in image_index_arts),
        description_index_bytes=sum(art.byte_len for art in description_index_arts),
        description_index_dropped=description_result.dropped_count,
        search_index_bytes=sum(art.byte_len for art in search_result.full_artifacts),
        search_compact_bytes=search_result.compact_artifact.byte_len,
        thumb_bytes=sum(art.byte_len for art in thumb_arts),
    )


def _zone_cell_sizes(
    tile_arts,
    description_index_arts,
    image_index_arts,
) -> dict[tuple[int, int], zone_catalog.CellSize]:
    without: dict[tuple[int, int], int] = {}
    with_thumbs: dict[tuple[int, int], int] = {}
    for art in tile_arts:
        key = (int(art.x), int(art.y))
        without[key] = without.get(key, 0) + int(art.byte_len)
        with_thumbs[key] = with_thumbs.get(key, 0) + int(art.byte_len)
    for art in description_index_arts:
        key = (int(art.x), int(art.y))
        without[key] = without.get(key, 0) + int(art.byte_len)
        with_thumbs[key] = with_thumbs.get(key, 0) + int(art.byte_len)
    for art in image_index_arts:
        key = (int(art.x), int(art.y))
        with_thumbs[key] = with_thumbs.get(key, 0) + int(art.byte_len)
        seen_thumb_shas: set[str] = set()
        for place in json.loads(art.json_bytes).get("places", []):
            if isinstance(place, dict) and place.get("thumb_sha256") not in seen_thumb_shas:
                seen_thumb_shas.add(str(place.get("thumb_sha256")))
                with_thumbs[key] += int(place.get("bytes", 0))
    return {
        key: zone_catalog.CellSize(
            bytes_without_thumbs=without.get(key, 0),
            bytes_with_thumbs=with_thumbs.get(key, without.get(key, 0)),
        )
        for key in sorted(set(without) | set(with_thumbs))
    }


def _region_doc(
    region_config: config.RegionConfig,
    *,
    target_region: str | None = None,
    bbox: tuple | None = None,
    subregion: config.SubregionConfig | None = None,
) -> dict[str, Any]:
    data = dict(region_config.raw)
    data["region"] = target_region or region_config.region_id
    basemap_cfg = dict(data["basemap"])
    basemap_cfg["bbox"] = list(bbox or region_config.bbox)
    if subregion is not None:
        if subregion.size_budget_bytes is not None:
            basemap_cfg["size_budget_bytes"] = subregion.size_budget_bytes
        if subregion.measured_archive_bytes is not None:
            basemap_cfg["measured_archive_bytes"] = subregion.measured_archive_bytes
    data["basemap"] = basemap_cfg
    return data


def _filter_places_to_bbox(
    places: list[dict[str, Any]], bbox: tuple
) -> list[dict[str, Any]]:
    west, south, east, north = [float(value) for value in bbox]
    return [
        place
        for place in places
        if _place_in_bbox(place, west, south, east, north)
    ]


def _place_in_bbox(
    place: dict[str, Any],
    west: float,
    south: float,
    east: float,
    north: float,
) -> bool:
    try:
        lat = float(place["lat"])
        lon = float(place["lon"])
    except (KeyError, TypeError, ValueError):
        return False
    if not math.isfinite(lat) or not math.isfinite(lon):
        return False
    return west <= lon <= east and south <= lat <= north


def _region_index(
    *,
    generated_at: str,
    targets: list[PublishedTargetResult],
    display_names: dict[str, str],
    parents: dict[str, str],
) -> dict[str, Any]:
    entries = []
    for target in targets:
        manifest_obj = target.manifest
        region = str(manifest_obj["region"])
        tile_bytes = sum(int(tile["bytes"]) for tile in manifest_obj["tiles"])
        basemap_bytes = int(manifest_obj["basemap"]["bytes"])
        # Region-pack bytes without thumbnails include core map payloads plus
        # description text sidecars. Image indexes stay with thumbnail payloads
        # because they are only useful when thumbnails are present.
        bytes_without_thumbs = (
            basemap_bytes
            + tile_bytes
            + target.description_index_bytes
            + target.search_index_bytes
        )
        bytes_with_thumbs = (
            bytes_without_thumbs + target.image_index_bytes + target.thumb_bytes
        )
        entries.append(
            {
                "id": region,
                "display_name": display_names[region],
                "parent": parents.get(region),
                "bbox": list(manifest_obj["basemap"]["bbox"]),
                "search_compact": _search_compact_entry(target),
                "basemap_bytes": basemap_bytes,
                "tile_count": len(manifest_obj["tiles"]),
                "bytes_without_thumbs": bytes_without_thumbs,
                "bytes_with_thumbs": bytes_with_thumbs,
            }
        )
    return {
        "schema_version": SCHEMA_VERSIONS["region_index"],
        "min_reader_version": 1,
        "generated_at": generated_at,
        "regions": entries,
    }


def _search_compact_entry(target: PublishedTargetResult) -> dict[str, Any]:
    path = target.staging_dir / "search" / "compact.json"
    return {
        "path": path.relative_to(target.staging_dir.parent.parent).as_posix(),
        "sha256": _sha256_file(path),
        "bytes": path.stat().st_size,
        "schema_version": SCHEMA_VERSIONS["search_index"],
    }


def _sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with pathlib.Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


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
