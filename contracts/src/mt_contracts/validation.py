"""Schema loading and validation for contract artifacts."""

from __future__ import annotations

import functools
import json
import pathlib

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

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


def validate_instance(name: str, instance: dict) -> None:
    validator_for(name).validate(instance)


def is_valid(name: str, instance: dict) -> bool:
    return validator_for(name).is_valid(instance)
