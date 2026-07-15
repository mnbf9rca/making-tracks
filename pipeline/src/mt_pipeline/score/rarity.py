"""OSM tag-value rarity over a curated categorical allowlist."""

from __future__ import annotations

from collections import Counter
from collections.abc import Iterable, Mapping
import json

RARITY_KEYS = frozenset(
    {
        "amenity",
        "building",
        "historic",
        "leisure",
        "man_made",
        "memorial",
        "natural",
        "tourism",
    }
)


def tag_value_frequency(conn, region: str, *, rarity_keys=RARITY_KEYS) -> dict[str, int]:
    rows = conn.execute(
        """
        SELECT props_json
        FROM source_records
        WHERE region = ? AND source = ?
        ORDER BY source_ref
        """,
        (region, "osm"),
    ).fetchall()
    tagsets = []
    for (props_json,) in rows:
        try:
            props = json.loads(props_json)
        except json.JSONDecodeError:
            props = {}
        tagsets.append(_extract_tags(props))
    return tag_value_frequency_from_tagsets(tagsets, rarity_keys)


def tag_value_frequency_from_tagsets(
    tagsets: Iterable[Mapping[str, object]], rarity_keys=RARITY_KEYS
) -> dict[str, int]:
    allowed = set(rarity_keys)
    counts: Counter[str] = Counter()
    for tags in tagsets:
        for key in sorted(tags):
            if key not in allowed:
                continue
            value = tags[key]
            if value is None:
                continue
            counts[f"{key}={value}"] += 1
    return dict(sorted(counts.items()))


def rarity_score(place_tags, freq: Mapping[str, int], *, rarity_keys=RARITY_KEYS) -> float:
    allowed = set(rarity_keys)
    tags = _normalize_place_tags(place_tags)
    counted = [
        tag
        for tag in sorted(tags)
        if _tag_key(tag) in allowed and _safe_count(freq.get(tag, 0)) > 0
    ]
    if not counted or not freq:
        return 0.0
    max_freq = max(_safe_count(value) for value in freq.values())
    if max_freq <= 0:
        return 0.0
    return max(1.0 - (_safe_count(freq[tag]) / max_freq) for tag in counted)


def _extract_tags(props) -> Mapping[str, object]:
    if not isinstance(props, Mapping):
        return {}
    tags = props.get("tags")
    if isinstance(tags, Mapping):
        return tags
    return props


def _normalize_place_tags(place_tags) -> set[str]:
    if isinstance(place_tags, Mapping):
        return {f"{key}={value}" for key, value in place_tags.items() if value is not None}
    return {str(tag) for tag in place_tags}


def _tag_key(tag: str) -> str:
    return tag.split("=", 1)[0]


def _safe_count(value) -> int:
    try:
        count = int(value)
    except (TypeError, ValueError):
        return 0
    return max(0, count)
