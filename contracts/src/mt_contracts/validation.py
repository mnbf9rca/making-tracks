"""Schema loading and validation for contract artifacts."""

from __future__ import annotations

import functools
import json
import math
import pathlib
import re
from importlib import resources
from urllib.parse import urlparse

from jsonschema import Draft202012Validator, ValidationError
from referencing import Registry, Resource

from .place_id import assert_canonical_ref
from .search import shard_key_matches_token

_ROOT_SCHEMA_DIR = pathlib.Path(__file__).resolve().parents[2] / "schemas"
_PACK_PATHS = {
    "basemap_cell": (re.compile(r"^basemap/10/[0-9]{1,4}/[0-9]{1,4}\.pmtiles$"), False),
    "basemap_midzoom": (re.compile(r"^basemap/midzoom/[A-Za-z0-9._/-]+\.pmtiles$"), False),
    "description_index": (re.compile(r"^descriptions/10/[0-9]{1,4}/[0-9]{1,4}\.json$"), False),
    "image_index": (re.compile(r"^images/10/[0-9]{1,4}/[0-9]{1,4}\.json$"), True),
    "image_thumb": (re.compile(r"^thumbs/[0-9a-f]{2}/[0-9a-f]{64}\.webp$"), True),
    "search_index": (re.compile(r"^search/full/[a-z0-9_]{1,16}\.json$"), False),
}


def _package_schema_dir():
    candidate = resources.files("mt_contracts").joinpath("schemas")
    if candidate.is_dir():
        return candidate
    return None


def _schema_resource(name: str):
    filename = f"{name}.schema.json"
    packaged = _package_schema_dir()
    if packaged is not None:
        return packaged.joinpath(filename)
    return _ROOT_SCHEMA_DIR / filename


def _schema_resources():
    packaged = _package_schema_dir()
    if packaged is not None:
        return [
            item
            for item in packaged.iterdir()
            if item.is_file() and item.name.endswith(".schema.json")
        ]
    return sorted(_ROOT_SCHEMA_DIR.glob("*.schema.json"))


@functools.lru_cache
def load_schema(name: str) -> dict:
    return json.loads(_schema_resource(name).read_text())


@functools.lru_cache
def _registry() -> Registry:
    registry = Registry()
    for path in _schema_resources():
        schema = json.loads(path.read_text())
        registry = registry.with_resource(schema["$id"], Resource.from_contents(schema))
    return registry


@functools.lru_cache
def validator_for(name: str) -> Draft202012Validator:
    return Draft202012Validator(load_schema(name), registry=_registry())


def _reject_non_finite(node) -> None:
    if isinstance(node, float) and not math.isfinite(node):
        raise ValueError("non-finite float (NaN/Infinity) is not permitted")
    if isinstance(node, dict):
        for value in node.values():
            _reject_non_finite(value)
    elif isinstance(node, list):
        for value in node:
            _reject_non_finite(value)


def _reject_noncanonical_refs(name: str, instance: dict) -> None:
    if name == "place":
        for ref in instance.get("source_refs", []):
            assert_canonical_ref(ref)
    elif name == "tile":
        for place in instance.get("places", []):
            for ref in place.get("source_refs", []):
                assert_canonical_ref(ref)
    elif name == "registry-record":
        for ref in instance.get("refs", []):
            assert_canonical_ref(ref)
        if "mint_anchor" in instance:
            assert_canonical_ref(instance["mint_anchor"])
            if instance["mint_anchor"] not in instance.get("refs", []):
                raise ValueError("registry mint_anchor must be present in refs")


def _reject_description_mismatches(name: str, instance: dict) -> None:
    if name != "description-index":
        return
    for place in instance.get("places", []):
        lang = str(place.get("wikipedia_lang", ""))
        source_url = str(place.get("source_url", ""))
        if urlparse(source_url).hostname != f"{lang}.wikipedia.org":
            raise ValueError("description source_url host must match wikipedia_lang")


def _reject_zone_catalog_mismatches(name: str, instance: dict) -> None:
    if name != "zone-catalog":
        return
    seen: set[str] = set()
    by_id: dict[str, dict] = {}
    for zone in instance.get("zones", []):
        zone_id = str(zone.get("zone_id", ""))
        if zone_id in seen:
            raise ValueError(f"duplicate zone_id: {zone_id}")
        seen.add(zone_id)
        by_id[zone_id] = zone
    for zone in instance.get("zones", []):
        zone_id = str(zone.get("zone_id", ""))
        parent = zone.get("parent")
        if parent is not None:
            if parent == zone_id:
                raise ValueError("zone parent cannot reference itself")
            if parent not in seen:
                raise ValueError(f"zone parent not present in catalog: {parent}")
            if int(by_id[str(parent)]["admin_level"]) >= int(zone["admin_level"]):
                raise ValueError("zone parent admin_level must be smaller than child")
        cell_set = zone.get("cell_set", {})
        count = 0
        for item in cell_set.get("ranges", []):
            x, y_start, y_end = (int(item[0]), int(item[1]), int(item[2]))
            if y_start > y_end:
                raise ValueError(f"zone cell range is reversed for x={x}")
            count += y_end - y_start + 1
        if count != int(cell_set.get("cell_count", -1)):
            raise ValueError("zone cell_count does not match ranges")
    for zone_id in by_id:
        visited: set[str] = set()
        current = zone_id
        while by_id[current].get("parent") is not None:
            parent = str(by_id[current]["parent"])
            if parent in visited:
                raise ValueError("zone parent cycle")
            visited.add(parent)
            current = parent


def _reject_pack_descriptor_mismatches(name: str, instance: dict) -> None:
    if name != "pack-descriptor":
        return
    seen: set[tuple[str, str]] = set()
    for obj in instance.get("objects", []):
        kind = str(obj.get("kind", ""))
        path = str(obj.get("path", ""))
        key = (kind, path)
        if key in seen:
            raise ValueError(f"duplicate pack object: {kind} {path}")
        seen.add(key)
        pattern, optional = _PACK_PATHS[kind]
        if pattern.fullmatch(path) is None:
            raise ValueError(f"pack object path does not match kind {kind}: {path}")
        if bool(obj.get("optional")) is not optional:
            raise ValueError(f"pack object optional flag does not match kind {kind}")
        if kind == "image_thumb":
            sha = str(obj.get("sha256", ""))
            expected = f"thumbs/{sha[:2]}/{sha}.webp"
            if path != expected:
                raise ValueError("thumbnail path must match sha256")


def _reject_search_index_mismatches(name: str, instance: dict) -> None:
    if name != "search-index":
        return
    index_kind = instance.get("index_kind")
    shard_key = instance.get("shard_key")
    if index_kind == "full" and not isinstance(shard_key, str):
        raise ValueError("full search-index requires shard_key")
    if index_kind == "compact" and shard_key is not None:
        raise ValueError("compact search-index shard_key must be null")
    seen_ids: set[str] = set()
    for entry in instance.get("entries", []):
        tokens = entry.get("tokens", [])
        place_id = entry.get("place_id")
        if (
            index_kind == "full"
            and isinstance(shard_key, str)
            and not any(
                isinstance(place_id, str)
                and shard_key_matches_token(shard_key, str(token), place_id)
                for token in tokens
            )
        ):
            raise ValueError("full search-index entry does not belong to shard_key")
        if index_kind == "compact" and int(entry.get("tier", 999)) > 2:
            raise ValueError("compact search-index entries must be tier 1 or 2")
        if entry.get("kind") == "place":
            if not isinstance(place_id, str):
                raise ValueError("place search entry requires place_id")
            if place_id in seen_ids:
                raise ValueError(f"duplicate search place_id: {place_id}")
            seen_ids.add(place_id)
        elif entry.get("place_id") is not None:
            raise ValueError("zone search entry place_id must be null")


def validate_instance(name: str, instance: dict) -> None:
    _reject_non_finite(instance)
    validator_for(name).validate(instance)
    _reject_noncanonical_refs(name, instance)
    _reject_description_mismatches(name, instance)
    _reject_zone_catalog_mismatches(name, instance)
    _reject_pack_descriptor_mismatches(name, instance)
    _reject_search_index_mismatches(name, instance)


def is_valid(name: str, instance: dict) -> bool:
    try:
        validate_instance(name, instance)
    except (ValidationError, ValueError):
        return False
    return True
