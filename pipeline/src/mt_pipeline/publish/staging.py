"""Write publish artifacts into the local R2-shaped staging layout."""

from __future__ import annotations

import json
import re
import shutil
from collections.abc import Iterable
from pathlib import Path
from typing import Any

from mt_contracts.caps import DESCRIPTION_TILE_ZOOM

from . import pack_descriptor, r2

_PUBLISH_VERSION_RE = re.compile(r"^[0-9]{8}T[0-9]{6}Z$")


def prune_run_staging(root: Path, regions: Iterable[str]) -> list[Path]:
    """Remove reproducible publish staging from prior runs."""
    root = Path(root)
    removed: list[Path] = []
    work_root = root / ".work"
    if work_root.is_symlink() or work_root.is_file():
        work_root.unlink()
        removed.append(work_root)
    elif work_root.exists():
        shutil.rmtree(work_root)
        removed.append(work_root)
    if not root.exists():
        return removed
    for region in sorted(set(regions)):
        r2.validate_path_components(region, "19700101T000000Z")
        parent = root / region
        if parent.is_symlink() or not parent.is_dir():
            continue
        for version_root in sorted(parent.iterdir(), key=lambda item: item.name):
            if not _PUBLISH_VERSION_RE.fullmatch(version_root.name):
                continue
            if version_root.is_symlink() or version_root.is_file():
                version_root.unlink()
                removed.append(version_root)
            elif version_root.is_dir():
                shutil.rmtree(version_root)
                removed.append(version_root)
    return removed


def build_staging(
    root: Path,
    region: str,
    publish_version: str,
    *,
    tile_arts,
    image_index_arts=(),
    description_index_arts=(),
    search_index_arts=(),
    search_compact_art=None,
    thumb_arts=(),
    manifest_obj: dict[str, Any],
    basemap_path: Path,
) -> Path:
    r2.validate_path_components(region, publish_version)
    version_root = Path(root) / region / publish_version
    if version_root.exists():
        shutil.rmtree(version_root)
    for art in tile_arts:
        tile_path = version_root / "tiles" / "10" / str(art.x) / f"{art.y}.json.gz"
        tile_path.parent.mkdir(parents=True, exist_ok=True)
        tile_path.write_bytes(art.gz_bytes)
    for art in image_index_arts:
        image_path = version_root / "images" / "10" / str(art.x) / f"{art.y}.json"
        image_path.parent.mkdir(parents=True, exist_ok=True)
        image_path.write_bytes(art.json_bytes)
    for art in description_index_arts:
        desc_path = (
            version_root
            / "descriptions"
            / str(DESCRIPTION_TILE_ZOOM)
            / str(art.x)
            / f"{art.y}.json"
        )
        desc_path.parent.mkdir(parents=True, exist_ok=True)
        desc_path.write_bytes(art.json_bytes)
    for art in search_index_arts:
        if art.shard_key is None:
            raise ValueError("full search-index artifact missing shard_key")
        search_path = version_root / "search" / "full" / f"{art.shard_key}.json"
        search_path.parent.mkdir(parents=True, exist_ok=True)
        search_path.write_bytes(art.json_bytes)
    if search_compact_art is not None:
        compact_path = version_root / "search" / "compact.json"
        compact_path.parent.mkdir(parents=True, exist_ok=True)
        compact_path.write_bytes(search_compact_art.json_bytes)
    for art in thumb_arts:
        thumb_path = Path(root) / "thumbs" / art.sha256[:2] / f"{art.sha256}.webp"
        thumb_path.parent.mkdir(parents=True, exist_ok=True)
        thumb_path.write_bytes(art.webp_bytes)
    version_root.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(basemap_path, version_root / f"{region}.pmtiles")
    pack_descriptor.write_pack_descriptor(
        version_root,
        generated_at=str(manifest_obj.get("generated_at", "1970-01-01T00:00:00Z")),
    )
    (version_root / "manifest.json").write_text(
        json.dumps(manifest_obj, sort_keys=True, separators=(",", ":")),
        encoding="utf-8",
    )
    return version_root


def write_region_index(root: Path, region_index_obj: dict[str, Any]) -> Path:
    path = Path(root) / "regions.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(region_index_obj, sort_keys=True, separators=(",", ":")),
        encoding="utf-8",
    )
    return path


def write_zone_catalogs(
    version_root: Path,
    *,
    proposal_obj: dict[str, Any],
    pruned_obj: dict[str, Any] | None,
) -> tuple[Path, Path | None]:
    version_root = Path(version_root)
    proposal_path = version_root / "zone-catalog.proposal.json"
    proposal_path.write_text(
        json.dumps(proposal_obj, sort_keys=True, separators=(",", ":")),
        encoding="utf-8",
    )
    pruned_path = None
    if pruned_obj is not None:
        pruned_path = version_root / "zone-catalog.json"
        pruned_path.write_text(
            json.dumps(pruned_obj, sort_keys=True, separators=(",", ":")),
            encoding="utf-8",
        )
    return proposal_path, pruned_path
