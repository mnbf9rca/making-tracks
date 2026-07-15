"""Normalized source-record model and defensive parser."""

from __future__ import annotations

import json
import math
from dataclasses import dataclass

import mt_contracts

NAME_MAX = 300
RAW_TEXT_MAX = 20_000
SOURCE_REF_MAX = 128
PROPS_JSON_MAX = 65_536
PROPS_MAX_DEPTH = 6
PROPS_MAX_ITEMS = 500


class SourceRecordError(ValueError):
    pass


@dataclass(frozen=True)
class SourceRecord:
    region: str
    source: str
    source_ref: str
    name: str
    lat: float
    lon: float
    props: dict


def _clean_text(value, *, field: str) -> str:
    if not isinstance(value, str):
        raise SourceRecordError(f"{field} must be a string")
    if len(value) > RAW_TEXT_MAX:
        raise SourceRecordError(f"{field} exceeds raw length cap")
    return mt_contracts.strip_unsafe_text(value).strip()[:NAME_MAX]


def _spend_props_budget(budget: list[int], count: int = 1) -> None:
    budget[0] -= count
    if budget[0] < 0:
        raise SourceRecordError("props too large")


def _clean_props(node, depth: int = 0, budget: list[int] | None = None):
    if budget is None:
        budget = [PROPS_MAX_ITEMS]
    if depth > PROPS_MAX_DEPTH:
        raise SourceRecordError("props nested too deep")
    if isinstance(node, dict):
        if len(node) > PROPS_MAX_ITEMS:
            raise SourceRecordError("props has too many keys")
        _spend_props_budget(budget, len(node))
        out = {}
        for key, value in node.items():
            if not isinstance(key, str):
                raise SourceRecordError("props keys must be strings")
            clean_key = _clean_text(key, field="props key")
            if not clean_key:
                raise SourceRecordError("props key empty after cleaning")
            if clean_key in out:
                raise SourceRecordError(f"duplicate props key after cleaning: {clean_key!r}")
            out[clean_key] = _clean_props(value, depth + 1, budget)
        return out
    if isinstance(node, list):
        if len(node) > PROPS_MAX_ITEMS:
            raise SourceRecordError("props list too long")
        _spend_props_budget(budget, len(node))
        return [_clean_props(value, depth + 1, budget) for value in node]
    if isinstance(node, str):
        return _clean_text(node, field="props value")
    if node is None or isinstance(node, bool):
        return node
    if isinstance(node, int):
        return node
    if isinstance(node, float):
        if not math.isfinite(node):
            raise SourceRecordError("props contains a non-finite float")
        return node
    raise SourceRecordError(f"unsupported props value type: {type(node).__name__}")


def parse(
    region: str,
    source: str,
    source_ref: str,
    name: str,
    lat: float,
    lon: float,
    props: dict,
) -> SourceRecord:
    if not isinstance(region, str) or not (0 < len(region) <= 64):
        raise SourceRecordError("region invalid")
    if not isinstance(source_ref, str) or len(source_ref) > SOURCE_REF_MAX:
        raise SourceRecordError("source_ref missing or too long")
    if not mt_contracts.is_canonical_ref(source_ref):
        raise SourceRecordError(f"non-canonical source_ref: {source_ref!r}")
    if source_ref.split(":", 1)[0] != source:
        raise SourceRecordError(
            f"source {source!r} does not match source_ref {source_ref!r}"
        )
    try:
        lat = float(lat)
        lon = float(lon)
    except (TypeError, ValueError) as exc:
        raise SourceRecordError("lat/lon not numeric") from exc
    if not math.isfinite(lat) or not math.isfinite(lon):
        raise SourceRecordError("lat/lon must be finite")
    if not (-90.0 <= lat <= 90.0) or not (-180.0 <= lon <= 180.0):
        raise SourceRecordError(f"coordinates out of range: {lat},{lon}")

    clean_name = _clean_text(name, field="name")
    if not clean_name:
        raise SourceRecordError("name empty after cleaning")
    if not isinstance(props, dict):
        raise SourceRecordError("props must be a dict")
    clean_props = _clean_props(props)
    serialized = json.dumps(
        clean_props, sort_keys=True, ensure_ascii=False, allow_nan=False
    )
    if len(serialized.encode("utf-8")) > PROPS_JSON_MAX:
        raise SourceRecordError("props too large after cleaning")
    return SourceRecord(
        region=region,
        source=source,
        source_ref=source_ref,
        name=clean_name,
        lat=lat,
        lon=lon,
        props=clean_props,
    )


def persist(conn, record: SourceRecord, *, run_id: str) -> None:
    conn.execute(
        """
        INSERT INTO source_records
            (region, source, source_ref, name, lat, lon, props_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            record.region,
            record.source,
            record.source_ref,
            record.name,
            record.lat,
            record.lon,
            json.dumps(record.props, sort_keys=True, ensure_ascii=False, allow_nan=False),
            run_id,
        ),
    )
    conn.commit()
