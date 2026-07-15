"""Pure signal functions for heuristic scoring."""

from __future__ import annotations

import math
from collections.abc import Mapping, Sequence
from statistics import median

ARTICLE_FULL_LEN = 300
SITELINK_SAT = 100
PAGEVIEW_SAT = 10000
HERITAGE_GRADES = {"I": 1.0, "II*": 0.7, "II": 0.5}


def article(sig: Mapping[str, object]) -> float:
    wp = _mapping(sig.get("wp"))
    if not wp:
        return 0.0
    extract = wp.get("extract")
    if not isinstance(extract, str):
        return 0.0
    return _clamp01(len(extract) / ARTICLE_FULL_LEN)


def sitelinks(sig: Mapping[str, object]) -> float:
    wd = _mapping(sig.get("wd"))
    n = _number(wd.get("sitelinks"), default=0.0)
    n = max(0.0, n)
    return _clamp01(math.log1p(n) / math.log1p(SITELINK_SAT))


def heritage(sig: Mapping[str, object], grades: Mapping[str, float] | None = None) -> float:
    table = grades or HERITAGE_GRADES
    for key in ("hehle", "heritage"):
        member = _mapping(sig.get(key))
        if member:
            return _clamp01(table.get(str(member.get("grade")), 0.0))
    return 0.0


def plaque(sig: Mapping[str, object]) -> float:
    return 1.0 if sig.get("plaque") else 0.0


def image(sig: Mapping[str, object]) -> float:
    wd = _mapping(sig.get("wd"))
    return 1.0 if wd.get("image") else 0.0


def class_penalty(
    sig: Mapping[str, object], penalties: Mapping[str, float] | None = None
) -> float:
    table = penalties or {}
    classes = _classes(sig)
    matching = [_clamp01(table[qid]) for qid in classes if qid in table]
    return min(matching) if matching else 1.0


def pageviews(sig: Mapping[str, object]) -> float | None:
    values = sig.get("pageviews")
    if values is None:
        return None
    if isinstance(values, Sequence) and not isinstance(values, (str, bytes, bytearray)):
        clamped = [max(0.0, _number(value, default=0.0)) for value in values]
        if not clamped:
            return None
        return _clamp01(math.log1p(median(clamped)) / math.log1p(PAGEVIEW_SAT))
    value = max(0.0, _number(values, default=0.0))
    return _clamp01(math.log1p(value) / math.log1p(PAGEVIEW_SAT))


def llm_curiosity(sig: Mapping[str, object]) -> float | None:
    value = sig.get("llm_curiosity")
    if value is None:
        return None
    return _clamp01(value)


def _classes(sig: Mapping[str, object]) -> set[str]:
    wd = _mapping(sig.get("wd"))
    raw = wd.get("classes", wd.get("p31", wd.get("P31", ())))
    if isinstance(raw, str):
        return {raw}
    if isinstance(raw, Sequence):
        return {str(value) for value in raw}
    return set()


def _mapping(value) -> Mapping[str, object]:
    return value if isinstance(value, Mapping) else {}


def _number(value, *, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _clamp01(value) -> float:
    number = _number(value, default=0.0)
    if math.isnan(number):
        return 0.0
    if math.isinf(number):
        return 1.0 if number > 0 else 0.0
    if number < 0.0:
        return 0.0
    if number > 1.0:
        return 1.0
    return number
