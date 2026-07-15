"""Score to tier bucketing."""

from __future__ import annotations

from collections.abc import Mapping


def tier_for(score, cfg) -> int:
    tiers = _get(cfg, "tiers")
    value = _clamp01(score)
    if value >= float(tiers["t1_min"]):
        return 1
    if value >= float(tiers["t2_min"]):
        return 2
    if value >= float(tiers["t3_min"]):
        return 3
    return 4


def _get(cfg, key: str):
    if isinstance(cfg, Mapping):
        return cfg[key]
    return getattr(cfg, key)


def _clamp01(value) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return 0.0
    if number < 0.0:
        return 0.0
    if number > 1.0:
        return 1.0
    return number
