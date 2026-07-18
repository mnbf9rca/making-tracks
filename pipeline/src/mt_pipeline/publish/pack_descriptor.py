"""Assemble the versioned pack descriptor for non-manifest pack objects."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from mt_contracts.validation import validate_instance

_KINDS = (
    ("description_index", "descriptions/10", False, 1),
    ("image_index", "images/10", True, 1),
    ("search_index", "search", False, 1),
)


def assemble_from_staging(staging: Path, *, generated_at: str) -> dict[str, Any]:
    staging = Path(staging)
    region = staging.parent.name
    publish_version = staging.name
    objects = []
    thumb_shas: set[str] = set()
    for kind, relative_root, optional, schema_version in _KINDS:
        root = (staging / relative_root).resolve()
        if not root.exists():
            continue
        for path in sorted(item for item in root.rglob("*") if item.is_file()):
            rel = path.relative_to(staging).as_posix()
            objects.append(
                {
                    "kind": kind,
                    "path": rel,
                    "sha256": _sha256(path),
                    "bytes": path.stat().st_size,
                    "schema_version": schema_version,
                    "optional": optional,
                }
            )
            if kind == "image_index":
                thumb_shas.update(_thumb_shas_in_image_index(path))
    thumb_root = staging.parent.parent / "thumbs"
    for sha in sorted(thumb_shas):
        path = thumb_root / sha[:2] / f"{sha}.webp"
        if not path.is_file():
            raise FileNotFoundError(f"referenced thumbnail missing: {sha}")
        objects.append(
            {
                "kind": "image_thumb",
                "path": path.relative_to(staging.parent.parent).as_posix(),
                "sha256": _sha256(path),
                "bytes": path.stat().st_size,
                "schema_version": 1,
                "optional": True,
            }
        )
    descriptor = {
        "schema_version": 1,
        "min_reader_version": 1,
        "region": region,
        "publish_version": publish_version,
        "generated_at": generated_at,
        "objects": objects,
    }
    validate_instance("pack-descriptor", descriptor)
    return descriptor


def write_pack_descriptor(staging: Path, *, generated_at: str) -> Path:
    staging = Path(staging)
    descriptor = assemble_from_staging(staging, generated_at=generated_at)
    path = staging / "pack-descriptor.json"
    path.write_text(
        json.dumps(descriptor, sort_keys=True, separators=(",", ":")),
        encoding="utf-8",
    )
    return path


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _thumb_shas_in_image_index(path: Path) -> set[str]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    out: set[str] = set()
    for place in payload.get("places", []):
        if isinstance(place, dict):
            sha = place.get("thumb_sha256")
            if isinstance(sha, str) and len(sha) == 64:
                out.add(sha)
    return out
