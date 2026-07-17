"""Write publish artifacts into the local R2-shaped staging layout."""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

from . import r2


def build_staging(
    root: Path,
    region: str,
    publish_version: str,
    *,
    tile_arts,
    image_index_arts=(),
    thumb_arts=(),
    manifest_obj: dict[str, Any],
    basemap_path: Path,
) -> Path:
    r2.validate_path_components(region, publish_version)
    version_root = Path(root) / region / publish_version
    for art in tile_arts:
        tile_path = version_root / "tiles" / "10" / str(art.x) / f"{art.y}.json.gz"
        tile_path.parent.mkdir(parents=True, exist_ok=True)
        tile_path.write_bytes(art.gz_bytes)
    for art in image_index_arts:
        image_path = version_root / "images" / "10" / str(art.x) / f"{art.y}.json"
        image_path.parent.mkdir(parents=True, exist_ok=True)
        image_path.write_bytes(art.json_bytes)
    for art in thumb_arts:
        thumb_path = Path(root) / "thumbs" / art.sha256[:2] / f"{art.sha256}.webp"
        thumb_path.parent.mkdir(parents=True, exist_ok=True)
        thumb_path.write_bytes(art.webp_bytes)
    version_root.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(basemap_path, version_root / f"{region}.pmtiles")
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
