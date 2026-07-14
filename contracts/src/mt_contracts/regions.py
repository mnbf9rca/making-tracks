"""Region config package-data accessors."""

from __future__ import annotations

import json
import pathlib
from importlib import resources


_ROOT_REGIONS_DIR = pathlib.Path(__file__).resolve().parents[2] / "regions"


def _package_regions_dir():
    candidate = resources.files("mt_contracts").joinpath("regions")
    if candidate.is_dir():
        return candidate
    return None


def _region_resource(region_id: str):
    if not region_id or "/" in region_id or "\\" in region_id or region_id.startswith("."):
        raise ValueError(f"invalid region_id: {region_id!r}")
    filename = f"{region_id}.json"
    packaged = _package_regions_dir()
    if packaged is not None:
        return packaged.joinpath(filename)
    return _ROOT_REGIONS_DIR / filename


def available_regions() -> list[str]:
    packaged = _package_regions_dir()
    if packaged is not None:
        names = [
            item.name[:-5]
            for item in packaged.iterdir()
            if item.is_file() and item.name.endswith(".json")
        ]
    else:
        names = [path.stem for path in _ROOT_REGIONS_DIR.glob("*.json")]
    return sorted(names)


def load_region_config(region_id: str) -> dict:
    resource = _region_resource(region_id)
    if not resource.is_file():
        raise FileNotFoundError(f"unknown region config: {region_id}")
    cfg = json.loads(resource.read_text())
    if cfg.get("region_id") != region_id:
        raise ValueError(f"region config id mismatch: {region_id!r}")
    from .validation import validate_instance

    validate_instance("region-config", cfg)
    return cfg
