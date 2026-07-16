"""R2 publish planning and upload guards."""

from __future__ import annotations

import json
import os
import re
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any


_REGION_RE = re.compile(r"^[a-z][a-z0-9_]*$")
_PUBLISH_VERSION_RE = re.compile(r"^[0-9]{8}T[0-9]{6}Z$")
_PRIVATE_KINDS = {"registry", "cache", "feedback", "lock"}
_PUBLIC_KINDS = {"tile", "basemap", "manifest", "current"}


class UnsafePathComponent(ValueError):
    """Raised when a region/version could traverse local or R2 paths."""


class LayoutInvalid(ValueError):
    """Raised when the public/private R2 layout violates invariants."""


class VersionAlreadyLive(ValueError):
    """Raised when upload would overwrite the currently visible version."""


class ExistingVersionPrefix(ValueError):
    """Raised when upload would mutate an existing non-identical version prefix."""


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
    skipped: int = 0
    dry_run: bool = True


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
                    key=f"{prefixes.get('registry', 'registry/')}{region}.json",
                    body=_json_bytes(registry_blob),
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
    uploaded_ledger: set[tuple[str, int, int, str]] | None = None,
) -> PublishResult:
    staging = Path(staging)
    region = staging.parent.name
    publish_version = staging.name
    validate_path_components(region, publish_version)
    tile_ops, basemap_op, manifest_op = _ops_from_staging(staging, layout, region, publish_version)
    plan = PublishPlan(
        layout=layout,
        region=region,
        publish_version=publish_version,
        ops=tuple([*tile_ops, basemap_op, manifest_op, _current_op(layout, region, publish_version)]),
    )
    _validate_layout(layout)
    plan._assert_bucket_invariants()
    if not upload:
        return PublishResult(plan=plan, dry_run=True)

    if client is None:
        client = _default_client()

    _assert_not_live(client, layout, region, publish_version)
    _assert_prefix_absent_or_ledgered(client, layout, region, publish_version, uploaded_ledger)
    lock_key = f"{region}/publish.lock"
    client.put_object(Bucket=layout["private_bucket"], Key=lock_key, Body=b"locked", IfNoneMatch="*")
    uploaded = 0
    skipped = 0
    try:
        for op in plan.ops:
            if op.kind == "tile" and _ledger_contains(uploaded_ledger, publish_version, op):
                skipped += 1
                continue
            body = op.body if op.body is not None else op.source_path.read_bytes()
            client.put_object(Bucket=op.bucket, Key=op.key, Body=body)
            uploaded += 1
    finally:
        client.delete_object(Bucket=layout["private_bucket"], Key=lock_key)
    return PublishResult(plan=plan, uploaded=uploaded, skipped=skipped, dry_run=False)


def _validate_layout(layout: Mapping[str, Any]) -> None:
    if layout["public_bucket"] == layout["private_bucket"]:
        raise LayoutInvalid("public_bucket and private_bucket must be distinct")


def _json_bytes(obj: Any) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8")


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


def _default_client():
    import boto3

    account_id = os.environ["R2_ACCOUNT_ID"]
    return boto3.client(
        "s3",
        endpoint_url=f"https://{account_id}.r2.cloudflarestorage.com",
        aws_access_key_id=os.environ["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"],
    )


def _assert_not_live(client, layout: Mapping[str, Any], region: str, publish_version: str) -> None:
    try:
        obj = client.get_object(Bucket=layout["public_bucket"], Key=f"{region}/current.json")
    except Exception:
        return
    body = obj["Body"].read()
    current = json.loads(body)
    if current.get("publish_version") == publish_version:
        raise VersionAlreadyLive(publish_version)


def _assert_prefix_absent_or_ledgered(
    client,
    layout: Mapping[str, Any],
    region: str,
    publish_version: str,
    uploaded_ledger: set[tuple[str, int, int, str]] | None,
) -> None:
    if uploaded_ledger:
        return
    resp = client.list_objects_v2(
        Bucket=layout["public_bucket"], Prefix=f"{region}/{publish_version}/", MaxKeys=1
    )
    if resp.get("KeyCount", 0) or resp.get("Contents"):
        raise ExistingVersionPrefix(f"{region}/{publish_version}/ already exists")


def _ledger_contains(
    uploaded_ledger: set[tuple[str, int, int, str]] | None,
    publish_version: str,
    op: PublishOp,
) -> bool:
    if not uploaded_ledger or op.body is None:
        return False
    parts = op.key.split("/")
    if len(parts) < 6:
        return False
    try:
        x = int(parts[-2])
        y = int(parts[-1].removesuffix(".json.gz"))
    except ValueError:
        return False
    import hashlib

    return (publish_version, x, y, hashlib.sha256(op.body).hexdigest()) in uploaded_ledger
