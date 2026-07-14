"""Schema loading and validation for contract artifacts."""

from __future__ import annotations

import functools
import json
import pathlib

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

_SCHEMA_DIR = pathlib.Path(__file__).resolve().parents[2] / "schemas"


@functools.lru_cache
def load_schema(name: str) -> dict:
    return json.loads((_SCHEMA_DIR / f"{name}.schema.json").read_text())


@functools.lru_cache
def _registry() -> Registry:
    registry = Registry()
    for path in _SCHEMA_DIR.glob("*.schema.json"):
        schema = json.loads(path.read_text())
        registry = registry.with_resource(schema["$id"], Resource.from_contents(schema))
    return registry


@functools.lru_cache
def validator_for(name: str) -> Draft202012Validator:
    return Draft202012Validator(load_schema(name), registry=_registry())


def validate_instance(name: str, instance: dict) -> None:
    validator_for(name).validate(instance)


def is_valid(name: str, instance: dict) -> bool:
    return validator_for(name).is_valid(instance)
