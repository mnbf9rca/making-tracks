"""Config-weighted composite score."""

from __future__ import annotations

from collections.abc import Mapping
import math
from statistics import fmean

from . import ADDITIVE_SIGNAL_NAMES


def score(signal_values: Mapping[str, float | None], cfg) -> float:
    """Return a score in [0, 1], renormalizing over present additive signals."""

    weights = _get(cfg, "weights")
    numerator = 0.0
    denominator = 0.0
    for name in ADDITIVE_SIGNAL_NAMES:
        value = signal_values.get(name)
        if value is None:
            continue
        weight = float(weights.get(name, 0.0))
        if weight <= 0:
            continue
        numerator += weight * _clamp01(value)
        denominator += weight
    base = numerator / denominator if denominator else 0.0

    evidence_values = [
        _clamp01(signal_values[name])
        for name in ("heritage", "plaque", "article")
        if signal_values.get(name) is not None
    ]
    evidence = fmean(evidence_values) if evidence_values else 0.0
    pageviews = signal_values.get("pageviews") or 0.0
    base += float(_get(cfg, "boost_weight", 0.0)) * (1.0 - _clamp01(pageviews)) * evidence

    class_penalty = _clamp01(signal_values.get("class_penalty", 1.0))
    return _clamp01(base * class_penalty)


def _get(cfg, key: str, default=None):
    if isinstance(cfg, Mapping):
        return cfg.get(key, default)
    return getattr(cfg, key, default)


def _clamp01(value) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return 0.0
    if math.isnan(number):
        return 0.0
    if math.isinf(number):
        return 1.0 if number > 0 else 0.0
    if number < 0.0:
        return 0.0
    if number > 1.0:
        return 1.0
    return number
