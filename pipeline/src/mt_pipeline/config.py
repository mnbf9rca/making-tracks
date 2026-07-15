"""Resolve a region id to a schema-validated A0 region config."""

from __future__ import annotations

from dataclasses import dataclass

import mt_contracts

_FIELDS = ("region_id", "display_name", "bbox", "languages", "sources", "basemap")


class UnknownRegionError(ValueError):
    pass


class ConfigError(ValueError):
    pass


@dataclass(frozen=True)
class RegionConfig:
    region_id: str
    display_name: str
    bbox: tuple
    languages: tuple
    sources: dict
    basemap: dict
    raw: dict

    @classmethod
    def from_dict(cls, data: dict) -> "RegionConfig":
        missing = [field for field in _FIELDS if field not in data]
        if missing:
            raise ConfigError(f"region config missing fields: {missing}")
        return cls(
            region_id=data["region_id"],
            display_name=data["display_name"],
            bbox=tuple(data["bbox"]),
            languages=tuple(data["languages"]),
            sources=data["sources"],
            basemap=data["basemap"],
            raw=data,
        )


def load(region_id: str) -> RegionConfig:
    available = mt_contracts.available_regions()
    if region_id not in available:
        raise UnknownRegionError(
            f"unknown region {region_id!r}; available: {', '.join(sorted(available))}"
        )
    data = mt_contracts.load_region_config(region_id)
    return RegionConfig.from_dict(data)
