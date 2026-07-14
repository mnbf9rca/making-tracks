"""Schema loading and validation for contract artifacts."""

from __future__ import annotations

import functools
import json
import math
import pathlib

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

from .place_id import assert_canonical_ref

_PACKAGE_SCHEMA_DIR = pathlib.Path(__file__).with_name("schemas")
_ROOT_SCHEMA_DIR = pathlib.Path(__file__).resolve().parents[2] / "schemas"


def _schema_dir() -> pathlib.Path:
    if _PACKAGE_SCHEMA_DIR.exists():
        return _PACKAGE_SCHEMA_DIR
    return _ROOT_SCHEMA_DIR


@functools.lru_cache
def load_schema(name: str) -> dict:
    return json.loads((_schema_dir() / f"{name}.schema.json").read_text())


@functools.lru_cache
def _registry() -> Registry:
    registry = Registry()
    for path in _schema_dir().glob("*.schema.json"):
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


def validate_instance(name: str, instance: dict) -> None:
    _reject_non_finite(instance)
    validator_for(name).validate(instance)
    _reject_noncanonical_refs(name, instance)


def is_valid(name: str, instance: dict) -> bool:
    try:
        validate_instance(name, instance)
    except Exception:
        return False
    return True
