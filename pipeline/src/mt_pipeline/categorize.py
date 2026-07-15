"""Apply the A3 taxonomy rules to reconciled places."""

from __future__ import annotations

import json
import pathlib
from collections import Counter
from typing import TypedDict

import mt_contracts

from . import progress, source_record, store
from .extractors import osm

_CONFIG_DIR = pathlib.Path(__file__).resolve().parents[2] / "config"
_TAXONOMY_PATH = _CONFIG_DIR / "taxonomy.json"
_OSM_CANDIDATE_TAGS = _CONFIG_DIR / "osm_candidate_tags.json"
_HEARTBEAT_EVERY_RECORDS = 10_000
_HEARTBEAT_EVERY_SECONDS = progress.HEARTBEAT_EVERY_SECONDS
_PRECEDENCE_KINDS = {"wd_p31", "osm_tag", "hehle", "plaque"}
_REQUIRED_TAXONOMY_KEYS = (
    "categories",
    "uncovered",
    "precedence",
    "class_map",
    "tag_map",
    "source_map",
)


class _Signals(TypedDict):
    wd_p31: set[str]
    osm_tag: set[str]
    hehle: bool
    plaque: bool


class PlacesTableMissingError(RuntimeError):
    """WP-A2 has not created the places table required by categorize."""


def load_taxonomy(path: str | pathlib.Path = _TAXONOMY_PATH) -> dict:
    data = json.loads(pathlib.Path(path).read_text())
    _validate_taxonomy(data)
    return data


def category_for(signals: _Signals, taxonomy: dict) -> str:
    categories = set(taxonomy["categories"])
    uncovered = taxonomy["uncovered"]
    for kind in taxonomy["precedence"]:
        hits: set[str] = set()
        if kind == "wd_p31":
            for qid in sorted(signals.get("wd_p31", set())):
                category = taxonomy["class_map"].get(qid)
                if category in categories:
                    hits.add(category)
        elif kind == "osm_tag":
            for tag in sorted(signals.get("osm_tag", set())):
                category = taxonomy["tag_map"].get(tag)
                if category is None and "=" in tag:
                    key, _value = tag.split("=", 1)
                    category = taxonomy["tag_map"].get(f"{key}=*")
                if category in categories:
                    hits.add(category)
        elif kind in {"hehle", "plaque"} and signals.get(kind) is True:
            category = taxonomy["source_map"].get(kind)
            if category in categories:
                hits.add(category)
        if hits:
            return sorted(hits)[0]
    return uncovered


def run(conn, region: str, *, run_id: str, taxonomy: dict | None = None) -> dict[str, int]:
    taxonomy = taxonomy or load_taxonomy()
    _require_places_table(conn)
    candidate_tags = osm.load_tag_config(_OSM_CANDIDATE_TAGS)
    source_records = _source_records_by_ref(conn, region)
    histogram: Counter[str] = Counter()
    conn.execute(
        f"DELETE FROM {store.PLACE_CATEGORIES_TABLE} WHERE region = ?",
        (region,),
    )
    total_places = conn.execute(
        """
        SELECT COUNT(*)
        FROM places
        WHERE region = ? AND status = 'live'
        """,
        (region,),
    ).fetchone()[0]
    phase = progress.PhaseProgress(
        "categorize.run",
        region=region,
        total=total_places,
        total_label="places",
        heartbeat_every_records=_HEARTBEAT_EVERY_RECORDS,
        heartbeat_every_seconds=_HEARTBEAT_EVERY_SECONDS,
    )
    phase.start()

    rows = conn.execute(
        """
        SELECT place_id, member_refs_json
        FROM places
        WHERE region = ? AND status = 'live'
        ORDER BY place_id
        """,
        (region,),
    )
    processed = 0
    for place_id, member_refs_json in rows:
        processed += 1
        phase.tick(processed)
        member_refs = _load_json_list(member_refs_json)
        signals = _signals_for(member_refs, source_records, candidate_tags)
        category = category_for(signals, taxonomy)
        conn.execute(
            """
            INSERT INTO place_categories (place_id, region, category, run_id)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(place_id) DO UPDATE SET
                region = excluded.region,
                category = excluded.category,
                run_id = excluded.run_id
            """,
            (place_id, region, category, run_id),
        )
        histogram[category] += 1
    conn.commit()
    phase.done(processed)
    return _ordered_histogram(histogram, taxonomy)


def _require_places_table(conn) -> None:
    row = conn.execute(
        """
        SELECT 1
        FROM sqlite_master
        WHERE type = 'table' AND name = 'places'
        """
    ).fetchone()
    if row is None:
        raise PlacesTableMissingError(
            "categorize requires the A2 places table "
            "(place_id, region, name, lat, lon, refs_json, member_refs_json, status)"
        )


def _source_records_by_ref(conn, region: str) -> dict[str, tuple[str, dict]]:
    rows = conn.execute(
        """
        SELECT source, source_ref, props_json
        FROM source_records
        WHERE region = ?
        ORDER BY source_ref
        """,
        (region,),
    )
    records: dict[str, tuple[str, dict]] = {}
    for source, source_ref, props_json in rows:
        records[source_ref] = (source, _load_json_dict(props_json))
    return records


def _signals_for(
    member_refs: list[str],
    source_records: dict[str, tuple[str, dict]],
    candidate_tags: dict,
) -> _Signals:
    signals: _Signals = {
        "wd_p31": set(),
        "osm_tag": set(),
        "hehle": False,
        "plaque": False,
    }
    for source_ref in sorted(member_refs):
        record = source_records.get(source_ref)
        if record is None:
            continue
        source, props = record
        if source == "wd":
            p31 = props.get("p31")
            if isinstance(p31, str) and p31:
                signals["wd_p31"].add(p31)
        elif source == "osm":
            for key in sorted(props):
                value = props[key]
                if isinstance(key, str) and isinstance(value, str):
                    tag = {key: value}
                    if osm.is_candidate(tag, candidate_tags):
                        signals["osm_tag"].add(f"{key}={value}")
        elif source == "hehle" and isinstance(props.get("grade"), str) and props["grade"]:
            signals["hehle"] = True
        elif source == "plaque":
            signals["plaque"] = True
    return signals


def _validate_taxonomy(data: dict) -> None:
    missing = [key for key in _REQUIRED_TAXONOMY_KEYS if key not in data]
    if missing:
        raise ValueError(f"taxonomy missing required keys: {missing}")
    categories = data.get("categories")
    uncovered = data.get("uncovered")
    if not isinstance(categories, list) or not (5 <= len(categories) <= 7):
        raise ValueError("taxonomy categories must be a 5-7 item list")
    if uncovered in categories:
        raise ValueError("taxonomy uncovered marker must not be a category")
    for label in [*categories, uncovered]:
        if not isinstance(label, str) or not (0 < len(label) <= 64):
            raise ValueError(f"invalid taxonomy label: {label!r}")
        if mt_contracts.strip_unsafe_text(label) != label:
            raise ValueError(f"unsafe taxonomy label: {label!r}")
    for key in ("class_map", "tag_map", "source_map"):
        mapping = data[key]
        if not isinstance(mapping, dict):
            raise ValueError(f"taxonomy {key} must be an object")
        invalid = sorted({value for value in mapping.values() if value not in categories})
        if invalid:
            raise ValueError(f"taxonomy {key} maps to unknown categories: {invalid}")
    if not isinstance(data["precedence"], list):
        raise ValueError("taxonomy precedence must be a list")
    unknown_precedence = [
        kind for kind in data["precedence"] if kind not in _PRECEDENCE_KINDS
    ]
    if unknown_precedence:
        raise ValueError(
            f"taxonomy precedence contains unsupported kinds: {unknown_precedence}; "
            f"allowed kinds are: {sorted(_PRECEDENCE_KINDS)}"
        )


def _load_json_dict(value: str) -> dict:
    if len(value.encode("utf-8")) > source_record.PROPS_JSON_MAX:
        return {}
    try:
        data = json.loads(value)
    except (ValueError, RecursionError):
        return {}
    return data if isinstance(data, dict) else {}


def _load_json_list(value: str) -> list[str]:
    if len(value.encode("utf-8")) > source_record.PROPS_JSON_MAX:
        return []
    try:
        data = json.loads(value)
    except (ValueError, RecursionError):
        return []
    if not isinstance(data, list):
        return []
    return [item for item in data if isinstance(item, str)]


def _ordered_histogram(histogram: Counter[str], taxonomy: dict) -> dict[str, int]:
    ordered: dict[str, int] = {}
    for category in taxonomy["categories"]:
        if category in histogram:
            ordered[category] = histogram[category]
    uncovered = taxonomy["uncovered"]
    if uncovered in histogram:
        ordered[uncovered] = histogram[uncovered]
    for category, count in sorted(histogram.items()):
        if category not in ordered:
            ordered[category] = count
    return ordered
