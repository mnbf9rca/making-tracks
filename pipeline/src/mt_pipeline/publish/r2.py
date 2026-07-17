"""R2 publish planning and upload guards."""

from __future__ import annotations

import json
import os
import re
import time
from importlib import import_module as _import_module
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from mt_contracts.region_index import validate_region_index


_REGION_RE = re.compile(r"^[a-z][a-z0-9_]*$")
_PUBLISH_VERSION_RE = re.compile(r"^[0-9]{8}T[0-9]{6}Z$")
_PRIVATE_KINDS = {"registry", "cache", "feedback", "lock"}
_PUBLIC_KINDS = {"tile", "basemap", "manifest", "current", "region_index"}
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
        registry_blob: Any | None = None,
        cache_blob: Any | None = None,
        feedback_blob: Any | None = None,
    ) -> "PublishPlan":
        validate_path_components(region, publish_version)
        _validate_layout(layout)
        public = str(layout["public_bucket"])
        private = str(layout["private_bucket"])
        ops: list[PublishOp] = []
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
                    {"schema_version": 1, "publish_version": publish_version},
                    sort_keys=True,
                    separators=(",", ":"),
                ).encode("utf-8"),
            )
        )
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

    _assert_not_live(client, layout, region, publish_version)
    _assert_prefix_absent(client, layout, region, publish_version)
    lock_key = f"{region}/publish.lock"
    lock_etag = _acquire_lock(client, layout, region, publish_version, lock_key)
    uploaded = 0
    try:
        for op in plan.ops:
            _upload_op(client, op)
            uploaded += 1
    finally:
        _release_lock(client, layout, lock_key, lock_etag)
    return PublishResult(plan=plan, uploaded=uploaded, dry_run=False)


def publish_prepared_to_r2(
    plans: Iterable[PublishPlan],
    region_index_path: Path,
    layout: Mapping[str, Any],
    *,
    client=None,
) -> PreparedPublishResult:
    plan_list = list(plans)
    if not plan_list:
        raise ValueError("prepared publish requires at least one target plan")
    _validate_layout(layout)
    for plan in plan_list:
        plan._assert_bucket_invariants()
    if client is None:
        client = _default_client()

    for plan in plan_list:
        _assert_not_live(client, layout, plan.region, plan.publish_version)
        _assert_prefix_absent(client, layout, plan.region, plan.publish_version)

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

        region_index_op = _region_index_op_for_upload(
            client, layout, region_index_path
        )
        public_content = [
            op
            for plan in plan_list
            for op in plan.ops
            if op.kind in {"tile", "basemap", "manifest"}
        ]
        current_ops = [
            op for plan in plan_list for op in plan.ops if op.kind == "current"
        ]
        private_ops = [
            op for plan in plan_list for op in plan.ops if op.kind in _PRIVATE_KINDS
        ]
        for op in [*public_content, *current_ops, region_index_op, *private_ops]:
            _upload_op(client, op)
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
    if op.body is not None:
        client.put_object(Bucket=op.bucket, Key=op.key, Body=op.body)
        return
    if op.source_path is None:
        raise ValueError(f"publish op {op.kind!r} has no body or source_path")
    with op.source_path.open("rb") as body:
        client.put_object(Bucket=op.bucket, Key=op.key, Body=body)


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
    tile_ops, basemap_op, manifest_op = _ops_from_staging(
        staging, layout, region, publish_version
    )
    ops = [
        *tile_ops,
        basemap_op,
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
        validate_region_index(existing)
        merged = _merge_region_indexes(existing, new_index)
    validate_region_index(merged)
    return PublishOp(
        kind="region_index",
        bucket=str(layout["public_bucket"]),
        key="regions.json",
        body=_json_bytes(merged),
    )


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
    by_id = {str(entry["id"]): dict(entry) for entry in existing.get("regions", [])}
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
        body=_json_bytes({"schema_version": 1, "publish_version": publish_version}),
    )


def _ops_from_staging(
    staging: Path, layout: Mapping[str, Any], region: str, publish_version: str
) -> tuple[list[PublishOp], PublishOp, PublishOp]:
    public = str(layout["public_bucket"])
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
    manifest = staging / "manifest.json"
    return (
        tile_ops,
        PublishOp(kind="basemap", bucket=public, key=f"{region}/{publish_version}/{region}.pmtiles", source_path=basemap),
        PublishOp(kind="manifest", bucket=public, key=f"{region}/{publish_version}/manifest.json", source_path=manifest),
    )


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
