"""R2 publish planning and upload guards."""

from __future__ import annotations

import json
import os
import re
import time
import hashlib
from importlib import import_module as _import_module
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from mt_contracts.caps import DESCRIPTION_TILE_ZOOM
from mt_contracts.region_index import validate_region_index
from mt_contracts.validation import validate_instance
from mt_contracts.versions import SCHEMA_VERSIONS


_REGION_RE = re.compile(r"^[a-z][a-z0-9_-]*$")
_PUBLISH_VERSION_RE = re.compile(r"^[0-9]{8}T[0-9]{6}Z$")
_LEGACY_REGION_IDS = frozenset({"uk", "malaysia"})
_PRIVATE_KINDS = {"registry", "cache", "feedback", "lock"}
_PUBLIC_KINDS = {
    "tile",
    "image",
    "description",
    "thumb",
    "basemap",
    "zone_catalog",
    "zone_catalog_proposal",
    "search_index",
    "search_compact",
    "pack_descriptor",
    "manifest",
    "current",
    "catalog_current",
    "region_index",
}
_NON_REGION_ROOT_PREFIXES = frozenset({"catalog", "regions", "thumbs"})
_CURRENT_POINTER_MAX_BYTES = 256 * 1024
_R2_UPLOAD_ENV_VARS = ("R2_S3_ENDPOINT", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY")


class UnsafePathComponent(ValueError):
    """Raised when a region/version could traverse local or R2 paths."""


class LayoutInvalid(ValueError):
    """Raised when the public/private R2 layout violates invariants."""


class VersionAlreadyLive(ValueError):
    """Raised when upload would overwrite the currently visible version."""


class ExistingVersionPrefix(ValueError):
    """Raised when upload would mutate an existing non-identical version prefix."""


class CurrentPointerUnavailable(RuntimeError):
    """Raised when the live-version guard cannot determine current state."""


class PublishLockUnavailable(RuntimeError):
    """Raised when the per-region publish lock cannot be acquired."""


class RegistryBlobInvalid(TypeError):
    """Raised when a registry JSONL upload body is not bytes."""


class Boto3Unavailable(RuntimeError):
    """Raised when R2 upload is requested without the boto3 dependency."""


class R2EnvironmentUnavailable(RuntimeError):
    """Raised when R2 upload is requested without the required env vars."""


@dataclass(frozen=True)
class PublishOp:
    kind: str
    bucket: str
    key: str
    body: bytes | None = None
    source_path: Path | None = None


@dataclass(frozen=True)
class PublishResult:
    plan: "PublishPlan"
    uploaded: int = 0
    dry_run: bool = True


@dataclass(frozen=True)
class ThumbReuseStats:
    staged: int
    existing: int
    missing: int
    uploaded: int
    skipped: int


@dataclass(frozen=True)
class PreparedPublishResult:
    target_results: tuple[PublishResult, ...]
    region_index_result: PublishResult


@dataclass(frozen=True)
class PublishPlan:
    layout: Mapping[str, Any]
    region: str
    publish_version: str
    ops: tuple[PublishOp, ...]

    @classmethod
    def for_version(
        cls,
        layout: Mapping[str, Any],
        region: str,
        publish_version: str,
        tile_arts: Iterable[Any],
        *,
        basemap: bool,
        image_index_arts: Iterable[Any] = (),
        description_index_arts: Iterable[Any] = (),
        search_index_arts: Iterable[Any] = (),
        search_compact_art: Any | None = None,
        thumb_arts: Iterable[Any] = (),
        registry_blob: Any | None = None,
        cache_blob: Any | None = None,
        feedback_blob: Any | None = None,
    ) -> "PublishPlan":
        validate_path_components(region, publish_version)
        _validate_layout(layout)
        public = str(layout["public_bucket"])
        private = str(layout["private_bucket"])
        ops: list[PublishOp] = []
        for thumb in sorted(thumb_arts, key=lambda art: art.sha256):
            ops.append(
                PublishOp(
                    kind="thumb",
                    bucket=public,
                    key=f"thumbs/{thumb.sha256[:2]}/{thumb.sha256}.webp",
                    body=getattr(thumb, "webp_bytes", None),
                )
            )
        for image in sorted(image_index_arts, key=lambda art: (art.x, art.y)):
            ops.append(
                PublishOp(
                    kind="image",
                    bucket=public,
                    key=f"{region}/{publish_version}/images/10/{image.x}/{image.y}.json",
                    body=getattr(image, "json_bytes", None),
                )
            )
        for desc in sorted(description_index_arts, key=lambda art: (art.x, art.y)):
            ops.append(
                PublishOp(
                    kind="description",
                    bucket=public,
                    key=(
                        f"{region}/{publish_version}/descriptions/"
                        f"{DESCRIPTION_TILE_ZOOM}/{desc.x}/{desc.y}.json"
                    ),
                    body=getattr(desc, "json_bytes", None),
                )
            )
        for search in sorted(search_index_arts, key=lambda art: str(art.shard_key)):
            ops.append(
                PublishOp(
                    kind="search_index",
                    bucket=public,
                    key=f"{region}/{publish_version}/search/full/{search.shard_key}.json",
                    body=getattr(search, "json_bytes", None),
                )
            )
        if search_compact_art is not None:
            ops.append(
                PublishOp(
                    kind="search_compact",
                    bucket=public,
                    key=f"{region}/{publish_version}/search/compact.json",
                    body=getattr(search_compact_art, "json_bytes", None),
                )
            )
        for tile in sorted(tile_arts, key=lambda art: (art.x, art.y)):
            ops.append(
                PublishOp(
                    kind="tile",
                    bucket=public,
                    key=f"{region}/{publish_version}/tiles/10/{tile.x}/{tile.y}.json.gz",
                    body=getattr(tile, "gz_bytes", None),
                )
            )
        if basemap:
            ops.append(
                PublishOp(
                    kind="basemap",
                    bucket=public,
                    key=f"{region}/{publish_version}/{region}.pmtiles",
                )
            )
        ops.append(
            PublishOp(
                kind="pack_descriptor",
                bucket=public,
                key=f"{region}/{publish_version}/pack-descriptor.json",
            )
        )
        ops.append(
            PublishOp(
                kind="manifest",
                bucket=public,
                key=f"{region}/{publish_version}/manifest.json",
            )
        )
        ops.append(
            PublishOp(
                kind="current",
                bucket=public,
                key=f"{region}/current.json",
                body=json.dumps(
                    {
                        "schema_version": SCHEMA_VERSIONS["current"],
                        "publish_version": publish_version,
                    },
                    sort_keys=True,
                    separators=(",", ":"),
                ).encode("utf-8"),
            )
        )
        ops.append(_current_catalog_op(layout))
        prefixes = layout.get("private_prefixes", {})
        if registry_blob is not None:
            ops.append(
                PublishOp(
                    kind="registry",
                    bucket=private,
                    key=f"{prefixes.get('registry', 'registry/')}{region}.jsonl",
                    body=_registry_blob_bytes(registry_blob),
                )
            )
        if cache_blob is not None:
            ops.append(
                PublishOp(
                    kind="cache",
                    bucket=private,
                    key=f"{prefixes.get('llm_cache', 'llm-cache/')}{region}.json",
                    body=_json_bytes(cache_blob),
                )
            )
        if feedback_blob is not None:
            ops.append(
                PublishOp(
                    kind="feedback",
                    bucket=private,
                    key=f"{prefixes.get('feedback', 'feedback/')}{region}.json",
                    body=_json_bytes(feedback_blob),
                )
            )
        plan = cls(layout=layout, region=region, publish_version=publish_version, ops=tuple(ops))
        plan._assert_bucket_invariants()
        return plan

    def manifest_index(self) -> int:
        for index, op in enumerate(self.ops):
            if op.kind == "manifest":
                return index
        raise ValueError("publish plan has no manifest op")

    def _assert_bucket_invariants(self) -> None:
        public = self.layout["public_bucket"]
        private = self.layout["private_bucket"]
        for op in self.ops:
            if op.kind in _PRIVATE_KINDS and op.bucket != private:
                raise LayoutInvalid(f"{op.kind} op targets non-private bucket")
            if op.kind in _PUBLIC_KINDS and op.bucket != public:
                raise LayoutInvalid(f"{op.kind} op targets non-public bucket")


def validate_path_components(region: str, publish_version: str) -> None:
    if not _REGION_RE.fullmatch(region):
        raise UnsafePathComponent(f"unsafe region: {region!r}")
    if not _PUBLISH_VERSION_RE.fullmatch(publish_version):
        raise UnsafePathComponent(f"unsafe publish_version: {publish_version!r}")


def publish_to_r2(
    staging: Path,
    layout: Mapping[str, Any],
    *,
    client=None,
    upload: bool = False,
    registry_blob: bytes | None = None,
) -> PublishResult:
    staging = Path(staging)
    region = staging.parent.name
    publish_version = staging.name
    validate_path_components(region, publish_version)
    plan = _plan_from_staging(staging, layout, registry_blob=registry_blob)
    _validate_layout(layout)
    plan._assert_bucket_invariants()
    if not upload:
        return PublishResult(plan=plan, dry_run=True)

    if client is None:
        client = _default_client()

    live_version = _current_publish_version(client, layout, region)
    repair_only = live_version == publish_version
    if repair_only:
        _assert_manifest_available(client, layout, region, publish_version)
    else:
        _assert_prefix_absent(client, layout, region, publish_version)
    lock_key = f"{region}/publish.lock"
    lock_etag = _acquire_lock(client, layout, region, publish_version, lock_key)
    uploaded = 0
    try:
        live_version = _current_publish_version(client, layout, region)
        repair_only = live_version == publish_version
        if repair_only:
            _assert_manifest_available(client, layout, region, publish_version)
            repair_ops = [_current_catalog_op(layout)]
            if registry_blob is not None:
                repair_ops.append(
                    PublishOp(
                        kind="registry",
                        bucket=str(layout["private_bucket"]),
                        key=(
                            f"{layout.get('private_prefixes', {}).get('registry', 'registry/')}"
                            f"{region}.jsonl"
                        ),
                        body=registry_blob,
                    )
                )
            repair_plan = PublishPlan(
                layout=layout,
                region=region,
                publish_version=publish_version,
                ops=tuple(repair_ops),
            )
            repair_plan._assert_bucket_invariants()
            uploaded += _upload_catalog_current_locked(
                client, layout, {region: publish_version}
            )
            if registry_blob is not None:
                _upload_op(client, repair_ops[-1])
                uploaded += 1
            return PublishResult(plan=repair_plan, uploaded=uploaded, dry_run=False)

        _assert_prefix_absent(client, layout, region, publish_version)
        for op in _ordered_ops_for_visibility(plan.ops):
            if op.kind == "catalog_current":
                continue
            _upload_op(client, op)
            uploaded += 1
        uploaded += _upload_catalog_current_locked(
            client, layout, {region: publish_version}
        )
    finally:
        _release_lock(client, layout, lock_key, lock_etag)
    return PublishResult(plan=plan, uploaded=uploaded, dry_run=False)


def publish_prepared_to_r2(
    plans: Iterable[PublishPlan],
    region_index_path: Path,
    layout: Mapping[str, Any],
    *,
    client=None,
    reuse_existing_thumbs: bool = False,
) -> PreparedPublishResult:
    plan_list = list(plans)
    if not plan_list:
        raise ValueError("prepared publish requires at least one target plan")
    _validate_layout(layout)
    for plan in plan_list:
        plan._assert_bucket_invariants()
    if client is None:
        client = _default_client()

    _prepared_repair_regions(client, layout, plan_list)

    max_publish_version = max(plan.publish_version for plan in plan_list)
    lock_keys = [
        (plan.region, plan.publish_version, f"{plan.region}/publish.lock")
        for plan in plan_list
    ]
    lock_keys.append(("regions", max_publish_version, "regions/publish.lock"))
    acquired: list[tuple[str, str | None]] = []
    try:
        for lock_region, lock_version, lock_key in sorted(lock_keys):
            etag = _acquire_lock(client, layout, lock_region, lock_version, lock_key)
            acquired.append((lock_key, etag))

        repair_regions = _prepared_repair_regions(client, layout, plan_list)
        upload_plans = [
            plan for plan in plan_list if plan.region not in repair_regions
        ]

        region_index_op = _region_index_op_for_upload(
            client, layout, region_index_path
        )
        thumb_content = _dedupe_ops_by_bucket_key(
            op for plan in upload_plans for op in plan.ops if op.kind == "thumb"
        )
        if reuse_existing_thumbs:
            thumb_content, stats = _reuse_existing_thumb_ops(
                client, layout, thumb_content
            )
            print(
                "THUMB_UPLOAD_REUSE "
                f"staged={stats.staged} existing={stats.existing} "
                f"missing={stats.missing} uploaded={stats.uploaded} "
                f"skipped={stats.skipped}"
            )
        public_content = [
            op
            for plan in upload_plans
            for op in plan.ops
            if op.kind
            in {
                "image",
                "description",
                "tile",
                "basemap",
                "zone_catalog_proposal",
                "zone_catalog",
                "search_index",
                "search_compact",
                "pack_descriptor",
                "manifest",
            }
        ]
        current_ops = [
            op for plan in upload_plans for op in plan.ops if op.kind == "current"
        ]
        private_ops = [
            op for plan in upload_plans for op in plan.ops if op.kind in _PRIVATE_KINDS
        ]
        for op in [*thumb_content, *public_content, *private_ops, *current_ops]:
            _upload_op(client, op)
        _upload_catalog_current_locked(
            client,
            layout,
            {plan.region: plan.publish_version for plan in plan_list},
        )
        _upload_op(client, region_index_op)
    finally:
        for lock_key, etag in reversed(acquired):
            _release_lock(client, layout, lock_key, etag)

    return PreparedPublishResult(
        target_results=tuple(
            PublishResult(plan=plan, uploaded=len(plan.ops), dry_run=False)
            for plan in plan_list
        ),
        region_index_result=PublishResult(
            plan=PublishPlan(
                layout=layout,
                region="regions",
                publish_version=max_publish_version,
                ops=(
                    PublishOp(
                        kind="region_index",
                        bucket=str(layout["public_bucket"]),
                        key="regions.json",
                        body=region_index_op.body,
                    ),
                ),
            ),
            uploaded=1,
            dry_run=False,
        ),
    )


def publish_region_index(
    region_index_path: Path,
    layout: Mapping[str, Any],
    *,
    client=None,
    upload: bool = False,
) -> PublishResult:
    region_index_path = Path(region_index_path)
    index_obj = _load_region_index(region_index_path)
    publish_version = max(
        str(entry["publish_version"]) for entry in index_obj["regions"]
    )
    _validate_layout(layout)
    if not upload:
        op = (
            _region_index_op_for_upload(client, layout, region_index_path)
            if client is not None
            else _region_index_op_from_file(layout, region_index_path)
        )
        plan = PublishPlan(
            layout=layout,
            region="regions",
            publish_version=publish_version,
            ops=(op,),
        )
        plan._assert_bucket_invariants()
        return PublishResult(plan=plan, dry_run=True)
    if client is None:
        client = _default_client()
    lock_key = "regions/publish.lock"
    lock_etag = _acquire_lock(client, layout, "regions", publish_version, lock_key)
    try:
        op = _region_index_op_for_upload(client, layout, region_index_path)
        _upload_op(client, op)
    finally:
        _release_lock(client, layout, lock_key, lock_etag)
    merged_plan = PublishPlan(
        layout=layout,
        region="regions",
        publish_version=publish_version,
        ops=(op,),
    )
    return PublishResult(plan=merged_plan, uploaded=1, dry_run=False)


def _load_region_index(region_index_path: Path) -> dict[str, Any]:
    index_obj = json.loads(Path(region_index_path).read_text(encoding="utf-8"))
    validate_region_index(index_obj)
    return index_obj


def _validate_layout(layout: Mapping[str, Any]) -> None:
    if layout["public_bucket"] == layout["private_bucket"]:
        raise LayoutInvalid("public_bucket and private_bucket must be distinct")


def _upload_op(client, op: PublishOp) -> None:
    if op.kind == "thumb":
        body = _op_body_bytes(op)
        _validate_thumb_body(op.key, body)
        try:
            client.put_object(Bucket=op.bucket, Key=op.key, Body=body, IfNoneMatch="*")
        except Exception as exc:
            if _is_precondition_failed(exc):
                return
            raise
        return
    if op.body is not None:
        client.put_object(
            Bucket=op.bucket,
            Key=op.key,
            Body=op.body,
            **_immutable_write_kwargs(op),
        )
        return
    if op.source_path is None:
        raise ValueError(f"publish op {op.kind!r} has no body or source_path")
    with op.source_path.open("rb") as body:
        client.put_object(
            Bucket=op.bucket,
            Key=op.key,
            Body=body,
            **_immutable_write_kwargs(op),
        )


def _immutable_write_kwargs(op: PublishOp) -> dict[str, str]:
    return {"IfNoneMatch": "*"} if _is_immutable_public_object(op) else {}


def _is_immutable_public_object(op: PublishOp) -> bool:
    return op.kind in {
        "image",
        "description",
        "tile",
        "basemap",
        "zone_catalog_proposal",
        "zone_catalog",
        "search_index",
        "search_compact",
        "pack_descriptor",
        "manifest",
    }


def _ordered_ops_for_visibility(ops: Iterable[PublishOp]) -> list[PublishOp]:
    private_ops = [op for op in ops if op.kind in _PRIVATE_KINDS]
    current_ops = [op for op in ops if op.kind == "current"]
    public_ops = [
        op for op in ops if op.kind not in _PRIVATE_KINDS and op.kind != "current"
    ]
    return [*public_ops, *private_ops, *current_ops]


def _op_body_bytes(op: PublishOp) -> bytes:
    if op.body is not None:
        return op.body
    if op.source_path is None:
        raise ValueError(f"publish op {op.kind!r} has no body or source_path")
    return op.source_path.read_bytes()


def _validate_thumb_body(key: str, body: bytes) -> None:
    match = re.fullmatch(r"thumbs/([0-9a-f]{2})/([0-9a-f]{64})\.webp", key)
    if match is None:
        raise ValueError(f"invalid thumb key: {key!r}")
    prefix, expected = match.groups()
    actual = hashlib.sha256(body).hexdigest()
    if prefix != expected[:2] or actual != expected:
        raise ValueError("thumb content hash mismatch")


def _plan_from_staging(
    staging: Path,
    layout: Mapping[str, Any],
    *,
    registry_blob: bytes | None = None,
) -> PublishPlan:
    staging = Path(staging)
    region = staging.parent.name
    publish_version = staging.name
    validate_path_components(region, publish_version)
    (
        thumb_ops,
        image_ops,
        description_ops,
        tile_ops,
        basemap_op,
        zone_catalog_ops,
        search_ops,
        pack_descriptor_op,
        manifest_op,
    ) = _ops_from_staging(
        staging, layout, region, publish_version
    )
    ops = [
        *thumb_ops,
        *image_ops,
        *description_ops,
        *tile_ops,
        basemap_op,
        *zone_catalog_ops,
        *search_ops,
        pack_descriptor_op,
        manifest_op,
        _current_op(layout, region, publish_version),
    ]
    if registry_blob is not None:
        ops.append(
            PublishOp(
                kind="registry",
                bucket=str(layout["private_bucket"]),
                key=(
                    f"{layout.get('private_prefixes', {}).get('registry', 'registry/')}"
                    f"{region}.jsonl"
                ),
                body=registry_blob,
            )
        )
    plan = PublishPlan(
        layout=layout,
        region=region,
        publish_version=publish_version,
        ops=tuple(ops),
    )
    plan._assert_bucket_invariants()
    return plan


def _region_index_op_for_upload(
    client,
    layout: Mapping[str, Any],
    region_index_path: Path,
) -> PublishOp:
    new_index = _load_region_index(region_index_path)
    try:
        obj = client.get_object(Bucket=layout["public_bucket"], Key="regions.json")
    except FileNotFoundError:
        merged = new_index
    except Exception as exc:
        if not _is_missing_key(exc):
            raise CurrentPointerUnavailable("could not read existing region index") from exc
        merged = new_index
    else:
        existing = json.loads(obj["Body"].read())
        existing = _validate_existing_region_index_for_merge(existing)
        merged = _merge_region_indexes(existing, new_index)
    validate_region_index(merged)
    return PublishOp(
        kind="region_index",
        bucket=str(layout["public_bucket"]),
        key="regions.json",
        body=_json_bytes(merged),
    )


def _prepared_repair_regions(
    client,
    layout: Mapping[str, Any],
    plans: Iterable[PublishPlan],
) -> set[str]:
    repair_regions: set[str] = set()
    for plan in plans:
        live_version = _current_publish_version(client, layout, plan.region)
        if live_version is None:
            _assert_prefix_absent(client, layout, plan.region, plan.publish_version)
            continue
        if live_version == plan.publish_version:
            _assert_manifest_available(
                client, layout, plan.region, plan.publish_version
            )
            repair_regions.add(plan.region)
            continue
        _assert_prefix_absent(client, layout, plan.region, plan.publish_version)
    return repair_regions


def _current_catalog_op(
    layout: Mapping[str, Any],
    publish_versions: Mapping[str, str] | None = None,
) -> PublishOp:
    payload = None
    if publish_versions is not None:
        payload = {
            "schema_version": SCHEMA_VERSIONS["current_catalog"],
            "publish_versions": dict(publish_versions),
        }
        validate_instance("current-catalog", payload)
    return PublishOp(
        kind="catalog_current",
        bucket=str(layout["public_bucket"]),
        key="catalog/current.json",
        body=(
            None
            if payload is None
            else _json_bytes(payload)
        ),
    )


def _upload_catalog_current_locked(
    client,
    layout: Mapping[str, Any],
    publish_versions: Mapping[str, str],
) -> int:
    if not publish_versions:
        return 0
    publish_version = max(publish_versions.values())
    catalog_lock_key = "catalog/publish.lock"
    catalog_lock_etag = _acquire_lock(
        client, layout, "catalog", publish_version, catalog_lock_key
    )
    try:
        catalog_versions = _merged_current_catalog(client, layout, publish_versions)
        op = _current_catalog_op(layout, catalog_versions)
        _upload_op(client, op)
        return 1
    finally:
        _release_lock(client, layout, catalog_lock_key, catalog_lock_etag)


def _merged_current_catalog(
    client,
    layout: Mapping[str, Any],
    publish_versions: Mapping[str, str],
) -> dict[str, str]:
    versions = _read_current_catalog(client, layout)
    versions.update(_read_region_current_pointers(client, layout))
    versions.update(publish_versions)
    if len(versions) > 1024:
        raise CurrentPointerUnavailable("current catalog has too many regions")
    return versions


def _read_current_catalog(client, layout: Mapping[str, Any]) -> dict[str, str]:
    try:
        obj = client.get_object(Bucket=layout["public_bucket"], Key="catalog/current.json")
    except FileNotFoundError:
        return {}
    except Exception as exc:
        if _is_missing_key(exc):
            return {}
        raise CurrentPointerUnavailable("could not read current catalog pointer") from exc
    try:
        catalog = json.loads(_read_current_pointer_body(obj["Body"]))
        if (
            not isinstance(catalog, dict)
            or set(catalog) != {"schema_version", "publish_versions"}
            or catalog["schema_version"] != SCHEMA_VERSIONS["current_catalog"]
            or not isinstance(catalog["publish_versions"], dict)
        ):
            raise ValueError("invalid current catalog")
        validate_instance("current-catalog", catalog)
        versions: dict[str, str] = {}
        for catalog_region, catalog_version in catalog["publish_versions"].items():
            if (
                not isinstance(catalog_region, str)
                or not _REGION_RE.fullmatch(catalog_region)
                or not isinstance(catalog_version, str)
                or not _PUBLISH_VERSION_RE.fullmatch(catalog_version)
            ):
                raise ValueError("invalid current catalog")
            versions[catalog_region] = catalog_version
        return versions
    except Exception as exc:
        raise CurrentPointerUnavailable("invalid current catalog pointer") from exc


def _read_region_current_pointers(client, layout: Mapping[str, Any]) -> dict[str, str]:
    versions: dict[str, str] = {}
    kwargs: dict[str, Any] = {
        "Bucket": layout["public_bucket"],
        "Prefix": "",
        "MaxKeys": 1024,
        "Delimiter": "/",
    }
    while True:
        response = client.list_objects_v2(**kwargs)
        for item in response.get("CommonPrefixes", []):
            prefix = item.get("Prefix") if isinstance(item, Mapping) else None
            if not isinstance(prefix, str) or not prefix.endswith("/"):
                continue
            region = prefix.removesuffix("/")
            if "/" in region or not _REGION_RE.fullmatch(region):
                continue
            try:
                current_version = _current_publish_version(client, layout, region)
            except CurrentPointerUnavailable:
                if region in _NON_REGION_ROOT_PREFIXES:
                    continue
                raise
            if current_version is not None:
                versions[region] = current_version
        token = response.get("NextContinuationToken")
        if not response.get("IsTruncated") or not isinstance(token, str) or token == "":
            break
        kwargs["ContinuationToken"] = token
    return versions


def _current_publish_version(
    client, layout: Mapping[str, Any], region: str
) -> str | None:
    try:
        obj = client.get_object(Bucket=layout["public_bucket"], Key=f"{region}/current.json")
    except FileNotFoundError:
        return None
    except Exception as exc:
        if _is_missing_key(exc):
            return None
        raise CurrentPointerUnavailable("could not read current publish pointer") from exc
    try:
        return _decode_region_current(_read_current_pointer_body(obj["Body"]))
    except Exception as exc:
        raise CurrentPointerUnavailable("invalid current publish pointer") from exc


def _read_current_pointer_body(body) -> bytes:
    data = body.read(_CURRENT_POINTER_MAX_BYTES + 1)
    if len(data) > _CURRENT_POINTER_MAX_BYTES:
        raise CurrentPointerUnavailable("current pointer exceeds byte cap")
    return data


def _decode_region_current(body: bytes) -> str:
    current = json.loads(body)
    if (
        not isinstance(current, dict)
        or set(current) != {"schema_version", "publish_version"}
        or current["schema_version"] != SCHEMA_VERSIONS["current"]
        or not isinstance(current["publish_version"], str)
        or _PUBLISH_VERSION_RE.fullmatch(current["publish_version"]) is None
    ):
        raise ValueError("invalid current pointer")
    return current["publish_version"]


def _assert_manifest_available(
    client, layout: Mapping[str, Any], region: str, publish_version: str
) -> None:
    try:
        client.head_object(
            Bucket=layout["public_bucket"],
            Key=f"{region}/{publish_version}/manifest.json",
        )
    except Exception as exc:
        raise CurrentPointerUnavailable("could not verify repaired manifest") from exc


def _region_index_op_from_file(
    layout: Mapping[str, Any], region_index_path: Path
) -> PublishOp:
    return PublishOp(
        kind="region_index",
        bucket=str(layout["public_bucket"]),
        key="regions.json",
        body=_json_bytes(_load_region_index(region_index_path)),
    )


def _merge_region_indexes(
    existing: Mapping[str, Any], new_index: Mapping[str, Any]
) -> dict[str, Any]:
    by_id = {
        str(entry["id"]): dict(entry)
        for entry in existing.get("regions", [])
        if not _is_legacy_region_id(str(entry["id"]))
        and not _is_legacy_region_id(str(entry.get("parent") or ""))
        and (
            int(new_index["schema_version"]) < 3
            or "search_compact" in entry
        )
    }
    for entry in new_index["regions"]:
        by_id[str(entry["id"])] = dict(entry)
    return {
        "schema_version": int(new_index["schema_version"]),
        "min_reader_version": max(
            int(existing["min_reader_version"]),
            int(new_index["min_reader_version"]),
        ),
        "generated_at": new_index["generated_at"],
        "regions": [by_id[region_id] for region_id in sorted(by_id)],
    }


def _validate_existing_region_index_for_merge(existing: Mapping[str, Any]) -> dict[str, Any]:
    current_version = SCHEMA_VERSIONS["region_index"]
    if int(existing.get("schema_version", 0)) == current_version:
        normalised = dict(existing)
        validate_region_index(normalised)
        return normalised
    elif int(existing.get("schema_version", 0)) in {1, 2}:
        normalised = dict(existing)
        normalised["schema_version"] = current_version
    else:
        normalised = dict(existing)
    return normalised


def _is_legacy_region_id(region_id: str) -> bool:
    return region_id in _LEGACY_REGION_IDS or any(
        region_id.startswith(f"{legacy}_") for legacy in _LEGACY_REGION_IDS
    )


def _json_bytes(obj: Any) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8")


def _registry_blob_bytes(obj: Any) -> bytes:
    if isinstance(obj, bytes):
        return obj
    if isinstance(obj, bytearray):
        return bytes(obj)
    raise RegistryBlobInvalid("registry JSONL blob must be bytes")


def _current_op(layout: Mapping[str, Any], region: str, publish_version: str) -> PublishOp:
    return PublishOp(
        kind="current",
        bucket=str(layout["public_bucket"]),
        key=f"{region}/current.json",
        body=_json_bytes(
            {
                "schema_version": SCHEMA_VERSIONS["current"],
                "publish_version": publish_version,
            }
        ),
    )


def _ops_from_staging(
    staging: Path, layout: Mapping[str, Any], region: str, publish_version: str
) -> tuple[
    list[PublishOp],
    list[PublishOp],
    list[PublishOp],
    list[PublishOp],
    PublishOp,
    list[PublishOp],
    list[PublishOp],
    PublishOp,
    PublishOp,
]:
    public = str(layout["public_bucket"])
    staging_root = staging.parent.parent
    thumb_ops = [
        PublishOp(
            kind="thumb",
            bucket=public,
            key=f"thumbs/{path.parent.name}/{path.name}",
            source_path=path,
        )
        for path in sorted((staging_root / "thumbs").glob("*/*.webp"))
    ]
    image_ops = [
        PublishOp(
            kind="image",
            bucket=public,
            key=f"{region}/{publish_version}/images/10/{path.parent.name}/{path.stem}.json",
            source_path=path,
        )
        for path in sorted((staging / "images/10").glob("*/*.json"))
    ]
    description_ops = [
        PublishOp(
            kind="description",
            bucket=public,
            key=(
                f"{region}/{publish_version}/descriptions/"
                f"{DESCRIPTION_TILE_ZOOM}/{path.parent.name}/{path.stem}.json"
            ),
            source_path=path,
        )
        for path in sorted(
            (staging / "descriptions" / str(DESCRIPTION_TILE_ZOOM)).glob("*/*.json")
        )
    ]
    tile_ops = [
        PublishOp(
            kind="tile",
            bucket=public,
            key=f"{region}/{publish_version}/tiles/10/{path.parent.name}/{path.stem.removesuffix('.json')}.json.gz",
            source_path=path,
        )
        for path in sorted((staging / "tiles/10").glob("*/*.json.gz"))
    ]
    basemap = staging / f"{region}.pmtiles"
    zone_catalog_ops = []
    proposal = staging / "zone-catalog.proposal.json"
    if proposal.exists():
        zone_catalog_ops.append(
            PublishOp(
                kind="zone_catalog_proposal",
                bucket=public,
                key=f"{region}/{publish_version}/zone-catalog.proposal.json",
                source_path=proposal,
            )
        )
    catalog = staging / "zone-catalog.json"
    if catalog.exists():
        zone_catalog_ops.append(
            PublishOp(
                kind="zone_catalog",
                bucket=public,
                key=f"{region}/{publish_version}/zone-catalog.json",
                source_path=catalog,
            )
        )
    search_ops = [
        PublishOp(
            kind="search_index",
            bucket=public,
            key=f"{region}/{publish_version}/search/full/{path.stem}.json",
            source_path=path,
        )
        for path in sorted((staging / "search/full").glob("*.json"))
    ]
    compact = staging / "search" / "compact.json"
    if compact.exists():
        search_ops.append(
            PublishOp(
                kind="search_compact",
                bucket=public,
                key=f"{region}/{publish_version}/search/compact.json",
                source_path=compact,
            )
        )
    pack_descriptor = staging / "pack-descriptor.json"
    manifest = staging / "manifest.json"
    return (
        thumb_ops,
        image_ops,
        description_ops,
        tile_ops,
        PublishOp(kind="basemap", bucket=public, key=f"{region}/{publish_version}/{region}.pmtiles", source_path=basemap),
        zone_catalog_ops,
        search_ops,
        PublishOp(kind="pack_descriptor", bucket=public, key=f"{region}/{publish_version}/pack-descriptor.json", source_path=pack_descriptor),
        PublishOp(kind="manifest", bucket=public, key=f"{region}/{publish_version}/manifest.json", source_path=manifest),
    )


def _dedupe_ops_by_bucket_key(ops: Iterable[PublishOp]) -> list[PublishOp]:
    by_key: dict[tuple[str, str], PublishOp] = {}
    for op in ops:
        by_key.setdefault((op.bucket, op.key), op)
    return [by_key[key] for key in sorted(by_key)]


def _reuse_existing_thumb_ops(
    client,
    layout: Mapping[str, Any],
    thumb_ops: Iterable[PublishOp],
) -> tuple[list[PublishOp], ThumbReuseStats]:
    ops = list(thumb_ops)
    for op in ops:
        _validate_thumb_body(op.key, _op_body_bytes(op))
    existing_keys = _existing_public_thumb_keys(client, layout)
    missing = [op for op in ops if op.key not in existing_keys]
    existing_count = len(ops) - len(missing)
    return missing, ThumbReuseStats(
        staged=len(ops),
        existing=existing_count,
        missing=len(missing),
        uploaded=len(missing),
        skipped=existing_count,
    )


def _existing_public_thumb_keys(client, layout: Mapping[str, Any]) -> set[str]:
    bucket = str(layout["public_bucket"])
    keys: set[str] = set()
    token: str | None = None
    while True:
        kwargs = {"Bucket": bucket, "Prefix": "thumbs/"}
        if token is not None:
            kwargs["ContinuationToken"] = token
        response = client.list_objects_v2(**kwargs)
        for item in response.get("Contents", ()):
            key = item.get("Key") if isinstance(item, Mapping) else None
            if isinstance(key, str):
                keys.add(key)
        if not response.get("IsTruncated"):
            return keys
        token = response.get("NextContinuationToken")
        if not isinstance(token, str) or not token:
            return keys


def require_boto3() -> None:
    try:
        _import_module("boto3")
    except ImportError as exc:
        raise Boto3Unavailable(
            "boto3>=1.34 is required for publish --upload; install the "
            "pipeline package dependencies before retrying"
        ) from exc


def require_upload_environment() -> None:
    missing = [name for name in _R2_UPLOAD_ENV_VARS if not os.environ.get(name, "").strip()]
    invalid = []
    if "R2_S3_ENDPOINT" not in missing and not _valid_r2_s3_endpoint(
        os.environ["R2_S3_ENDPOINT"]
    ):
        invalid.append("R2_S3_ENDPOINT")
    rejected = [*missing, *invalid]
    if rejected:
        raise R2EnvironmentUnavailable(
            "publish --upload requires valid R2 env var(s): "
            f"{', '.join(rejected)}; run via op run --env-file=.env.tpl"
        )


def _valid_r2_s3_endpoint(value: str) -> bool:
    if value != value.strip() or value.startswith("op:"):
        return False
    parsed = urlparse(value)
    try:
        port = parsed.port
    except ValueError:
        return False
    host = parsed.hostname
    if parsed.scheme != "https" or host is None or port is not None:
        return False
    if parsed.username is not None or parsed.password is not None:
        return False
    if parsed.path not in ("", "/") or parsed.params or parsed.query or parsed.fragment:
        return False
    suffix = ".r2.cloudflarestorage.com"
    return host.endswith(suffix) and len(host) > len(suffix)


def _default_client():
    require_boto3()
    require_upload_environment()
    boto3 = _import_module("boto3")

    return boto3.client(
        "s3",
        endpoint_url=os.environ["R2_S3_ENDPOINT"],
        aws_access_key_id=os.environ["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"],
    )


def _assert_not_live(client, layout: Mapping[str, Any], region: str, publish_version: str) -> None:
    try:
        obj = client.get_object(Bucket=layout["public_bucket"], Key=f"{region}/current.json")
    except FileNotFoundError:
        return
    except Exception as exc:
        if _is_missing_key(exc):
            return
        raise CurrentPointerUnavailable("could not read current publish pointer") from exc
    body = obj["Body"].read()
    current = json.loads(body)
    if current.get("publish_version") == publish_version:
        raise VersionAlreadyLive(publish_version)


def _assert_prefix_absent(
    client,
    layout: Mapping[str, Any],
    region: str,
    publish_version: str,
) -> None:
    resp = client.list_objects_v2(
        Bucket=layout["public_bucket"], Prefix=f"{region}/{publish_version}/", MaxKeys=1
    )
    if resp.get("KeyCount", 0) or resp.get("Contents"):
        raise ExistingVersionPrefix(f"{region}/{publish_version}/ already exists")


def _acquire_lock(
    client,
    layout: Mapping[str, Any],
    region: str,
    publish_version: str,
    key: str,
) -> str | None:
    now = int(time.time())
    body = _json_bytes(
        {
            "schema_version": 1,
            "region": region,
            "publish_version": publish_version,
            "acquired_at": now,
            "expires_at": now + 30 * 60,
        }
    )
    try:
        response = client.put_object(
            Bucket=layout["private_bucket"], Key=key, Body=body, IfNoneMatch="*"
        )
        return _etag(response)
    except Exception as exc:
        if not _is_precondition_failed(exc):
            raise PublishLockUnavailable("could not acquire publish lock") from exc
        if not _delete_if_stale_lock(client, layout, key, now):
            raise PublishLockUnavailable("publish lock is held") from exc
        try:
            response = client.put_object(
                Bucket=layout["private_bucket"], Key=key, Body=body, IfNoneMatch="*"
            )
            return _etag(response)
        except Exception as retry_exc:
            if _is_precondition_failed(retry_exc):
                raise PublishLockUnavailable("publish lock is held") from retry_exc
            raise PublishLockUnavailable("could not acquire publish lock") from retry_exc


def _delete_if_stale_lock(client, layout: Mapping[str, Any], key: str, now: int) -> bool:
    try:
        obj = client.get_object(Bucket=layout["private_bucket"], Key=key)
        data = json.loads(obj["Body"].read())
    except Exception:
        return False
    etag = _etag(obj)
    if etag is None:
        return False
    expires_at = data.get("expires_at")
    if isinstance(expires_at, int | float) and expires_at < now:
        try:
            client.delete_object(Bucket=layout["private_bucket"], Key=key, IfMatch=etag)
        except Exception as exc:
            if _is_precondition_failed(exc):
                return False
            raise PublishLockUnavailable("could not delete stale publish lock") from exc
        return True
    return False


def _release_lock(
    client,
    layout: Mapping[str, Any],
    key: str,
    etag: str | None,
) -> None:
    kwargs = {"Bucket": layout["private_bucket"], "Key": key}
    if etag is not None:
        kwargs["IfMatch"] = etag
    try:
        client.delete_object(**kwargs)
    except Exception as exc:
        if _is_precondition_failed(exc):
            return
        raise


def _etag(response: Any) -> str | None:
    if not isinstance(response, Mapping):
        return None
    value = response.get("ETag")
    return str(value) if value is not None else None


def _error_code(exc: Exception) -> str | None:
    response = getattr(exc, "response", None)
    if isinstance(response, Mapping):
        error = response.get("Error")
        if isinstance(error, Mapping):
            code = error.get("Code")
            return str(code) if code is not None else None
    return None


def _is_missing_key(exc: Exception) -> bool:
    return _error_code(exc) in {"NoSuchKey", "404", "NotFound"}


def _is_precondition_failed(exc: Exception) -> bool:
    return _error_code(exc) in {"PreconditionFailed", "412"}
