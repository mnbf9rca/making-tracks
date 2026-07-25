"""Resolve a region id to a schema-validated A0 region config."""

from __future__ import annotations

import math
from dataclasses import dataclass

import mt_contracts

_FIELDS = ("region_id", "display_name", "bbox", "languages", "sources", "basemap")
_SUBREGION_FIELDS = ("id", "bbox")


class UnknownRegionError(ValueError):
    pass


class ConfigError(ValueError):
    pass


@dataclass(frozen=True)
class SubregionConfig:
    id: str
    region_id: str
    display_name: str
    bbox: tuple
    size_budget_bytes: int | None = None
    measured_archive_bytes: int | None = None
    raw: dict | None = None


@dataclass(frozen=True)
class RegionConfig:
    region_id: str
    display_name: str
    bbox: tuple
    languages: tuple
    sources: dict
    basemap: dict
    subregions: tuple[SubregionConfig, ...]
    raw: dict

    @classmethod
    def from_dict(cls, data: dict) -> "RegionConfig":
        missing = [field for field in _FIELDS if field not in data]
        if missing:
            raise ConfigError(f"region config missing fields: {missing}")
        bbox = _validate_bbox(data["bbox"], label=data["region_id"])
        subregions = _subregions_from_basemap(data["region_id"], data["basemap"])
        return cls(
            region_id=data["region_id"],
            display_name=data["display_name"],
            bbox=bbox,
            languages=tuple(data["languages"]),
            sources=data["sources"],
            basemap=data["basemap"],
            subregions=subregions,
            raw=data,
        )


def _subregions_from_basemap(
    parent_region_id: str, basemap: dict
) -> tuple[SubregionConfig, ...]:
    out: list[SubregionConfig] = []
    seen = {parent_region_id}
    for item in basemap.get("subregions", ()):
        missing = [field for field in _SUBREGION_FIELDS if field not in item]
        if missing:
            raise ConfigError(f"subregion config missing fields: {missing}")
        short_id = item["id"]
        region_id = f"{parent_region_id}_{short_id}"
        if region_id in seen:
            raise ConfigError(f"duplicate region/subregion id: {region_id}")
        seen.add(region_id)
        display_name = item.get("display_name") or _default_subregion_display_name(
            short_id
        )
        out.append(
            SubregionConfig(
                id=short_id,
                region_id=region_id,
                display_name=display_name,
                bbox=_validate_bbox(item["bbox"], label=region_id),
                size_budget_bytes=item.get("size_budget_bytes"),
                measured_archive_bytes=item.get("measured_archive_bytes"),
                raw=item,
            )
        )
    return tuple(out)


def _default_subregion_display_name(short_id: str) -> str:
    return short_id.replace("_", " ").title()


def _validate_bbox(values, *, label: str) -> tuple[float, float, float, float]:
    try:
        raw = [float(value) for value in values]
    except (TypeError, ValueError) as exc:
        raise ConfigError(f"{label} bbox must contain four finite numbers") from exc
    if len(raw) != 4:
        raise ConfigError(f"{label} bbox must contain four finite numbers")
    west, south, east, north = raw
    bbox = (west, south, east, north)
    if not all(math.isfinite(value) for value in bbox):
        raise ConfigError(f"{label} bbox must contain four finite numbers")
    if not (-180.0 <= west <= 180.0 and -180.0 <= east <= 180.0):
        raise ConfigError(
            f"{label} bbox longitude values must be between -180 and 180"
        )
    if not (-90.0 <= south <= 90.0 and -90.0 <= north <= 90.0):
        raise ConfigError(f"{label} bbox latitude values must be between -90 and 90")
    if west > east or south > north:
        raise ConfigError(f"{label} bbox has invalid west/east or south/north ordering")
    return bbox


def load(region_id: str) -> RegionConfig:
    available = mt_contracts.available_regions()
    if region_id not in available:
        raise UnknownRegionError(
            f"unknown region {region_id!r}; available: {', '.join(sorted(available))}"
        )
    data = mt_contracts.load_region_config(region_id)
    cfg = RegionConfig.from_dict(data)
    _assert_global_subregion_ids(cfg, available)
    return cfg


def _assert_global_subregion_ids(cfg: RegionConfig, available: list[str]) -> None:
    available_ids = set(available)
    conflicts = sorted(
        subregion.region_id
        for subregion in cfg.subregions
        if subregion.region_id in available_ids
    )
    if conflicts:
        raise ConfigError(
            "subregion id collides with configured region id(s): "
            + ", ".join(conflicts)
        )


def assert_global_region_ids() -> None:
    available = mt_contracts.available_regions()
    seen: dict[str, str] = {}
    duplicates: list[str] = []
    for region_id in available:
        cfg = RegionConfig.from_dict(mt_contracts.load_region_config(region_id))
        for composed_id in [
            cfg.region_id,
            *(sub.region_id for sub in cfg.subregions),
        ]:
            owner = seen.setdefault(composed_id, region_id)
            if owner != region_id:
                duplicates.append(composed_id)
    if duplicates:
        raise ConfigError(
            "duplicate configured region/subregion id(s): "
            + ", ".join(sorted(set(duplicates)))
        )
