"""Local-first LLM cache with validate-on-read semantics."""

from __future__ import annotations

from collections.abc import Callable, Mapping
import hashlib
import json
import os
from pathlib import Path
from urllib.parse import quote

from .curiosity import CURIOSITY_TASK_ID

PROJECT_ROOT = Path(__file__).resolve().parents[4]
MAX_CACHE_BLOB_BYTES = 262_144


class LlmCacheCorrupt(Exception):
    """Raised when a cache blob is present but cannot be trusted."""


def cache_key(task_id: str, model: str, prompt_version: str, input_hash: str) -> str:
    return "/".join(_encode_component(component) for component in (task_id, model, prompt_version, input_hash))


def _encode_component(component: str) -> str:
    if component == "":
        raise ValueError("cache key components must be non-empty")
    return quote(component, safe="").replace(".", "%2E")


def input_hash(*, task_id: str, prompt_version: str, rendered_prompt: str) -> str:
    payload = json.dumps([task_id, prompt_version, rendered_prompt], ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


class LlmCache:
    def __init__(self, root: str | Path, *, validators: Mapping[str, Callable[[dict[str, object]], object]]) -> None:
        self.root = Path(root)
        self.validators = dict(validators)

    def _path(self, key: str) -> Path:
        root = self.root.resolve()
        path = (root / key).resolve()
        if path != root and root not in path.parents:
            raise ValueError("cache key escapes root")
        return path

    def put(self, key: str, blob: Mapping[str, object]) -> None:
        path = self._path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = json.dumps(blob, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")
        tmp = path.with_name(path.name + ".tmp")
        tmp.write_bytes(payload)
        os.replace(tmp, path)

    def get(self, task_id: str, model: str, prompt_version: str, input_hash: str) -> object | None:
        key = cache_key(task_id, model, prompt_version, input_hash)
        path = self._path(key)
        if not path.exists():
            return None
        try:
            raw = path.read_bytes()
            if len(raw) > MAX_CACHE_BLOB_BYTES:
                raise ValueError("cache blob exceeds byte limit")
            blob = json.loads(raw)
            if not isinstance(blob, dict):
                raise ValueError("cache blob must be an object")
            validator = self.validators.get(task_id)
            if validator is None:
                raise ValueError(f"no validator for task_id {task_id!r}")
            return validator(blob)
        except Exception as exc:
            raise LlmCacheCorrupt(key) from exc
