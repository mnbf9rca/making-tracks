"""Emit local-search artifacts over the shipped place corpus."""

from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from typing import Any

import mt_contracts
from mt_contracts import caps
from mt_contracts.search import hash_split_shard_key, shard_key_for_token
from mt_contracts.search import split_shard_key_for_token
from mt_contracts.validation import validate_instance
from mt_contracts.versions import SCHEMA_VERSIONS

from mt_pipeline import progress, source_record

_HEARTBEAT_EVERY_RECORDS = 10_000
_HEARTBEAT_EVERY_SECONDS = progress.HEARTBEAT_EVERY_SECONDS
_COMPACT_MAX_TIER = 2  # B9 v1 online index: notable subset only, not full-region search.
_ALT_NAME_KEYS = frozenset({"alt_name", "int_name"})
_SOURCE_REF_CHUNK_SIZE = 500


@dataclass(frozen=True)
class SearchIndexArtifact:
    shard_key: str | None
    index_kind: str
    json_bytes: bytes
    sha256: str
    byte_len: int


@dataclass(frozen=True)
class SearchIndexResult:
    full_artifacts: tuple[SearchIndexArtifact, ...]
    compact_artifact: SearchIndexArtifact


def source_rows_from_db(
    conn,
    region: str,
    refs: Iterable[str],
) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    ref_list = sorted({ref for ref in refs if isinstance(ref, str)})
    for start in range(0, len(ref_list), _SOURCE_REF_CHUNK_SIZE):
        chunk = ref_list[start : start + _SOURCE_REF_CHUNK_SIZE]
        placeholders = ",".join("?" for _ in chunk)
        rows = conn.execute(
            f"""
            SELECT source_ref, props_json
            FROM source_records
            WHERE region = ? AND source_ref IN ({placeholders})
            """,
            (region, *chunk),
        )
        for source_ref, props_json in rows:
            if not isinstance(source_ref, str):
                continue
            if len(str(props_json).encode("utf-8")) > source_record.PROPS_JSON_MAX:
                continue
            try:
                props = json.loads(props_json)
            except (ValueError, RecursionError, TypeError):
                continue
            if isinstance(props, dict):
                out[source_ref] = props
    return out


def emit_search_indexes(
    places: Iterable[Mapping[str, Any]],
    *,
    source_props_by_ref: Mapping[str, Mapping[str, Any]],
    region: str,
    publish_version: str,
    generated_at: str,
) -> SearchIndexResult:
    place_list = [dict(place) for place in places]
    phase = progress.PhaseProgress(
        "publish.search_index_emit",
        region=region,
        total=len(place_list),
        total_label="places",
        heartbeat_every_records=_HEARTBEAT_EVERY_RECORDS,
        heartbeat_every_seconds=_HEARTBEAT_EVERY_SECONDS,
    )
    phase.start()
    entries: list[dict[str, Any]] = []
    for index, place in enumerate(
        sorted(place_list, key=lambda item: str(item["place_id"])), start=1
    ):
        entry = _entry_from_place(place, source_props_by_ref)
        entries.append(entry)
        phase.tick(index)
    phase.done(len(place_list), extra=f" entries={len(entries)}")

    full_artifacts = tuple(
        artifact
        for shard_key, shard_entries in _prefix_shards(entries)
        for artifact in _full_artifacts_for_shard(
            region=region,
            publish_version=publish_version,
            generated_at=generated_at,
            shard_key=shard_key,
            entries=shard_entries,
        )
    )
    compact_entries = [
        entry for entry in entries if int(entry["tier"]) <= _COMPACT_MAX_TIER
    ]
    compact_artifact = _artifact(
        _index_payload(
            region=region,
            publish_version=publish_version,
            generated_at=generated_at,
            index_kind="compact",
            shard_key=None,
            entries=compact_entries,
        )
    )
    return SearchIndexResult(
        full_artifacts=full_artifacts,
        compact_artifact=compact_artifact,
    )


def _entry_from_place(
    place: Mapping[str, Any],
    source_props_by_ref: Mapping[str, Mapping[str, Any]],
) -> dict[str, Any]:
    name = _safe_text(place.get("name", ""), max_chars=caps.NAME_MAX)
    alt_names = _alt_names(place, source_props_by_ref, primary_name=name)
    tokens = _tokens([name, *alt_names])
    return {
        "kind": "place",
        "place_id": str(place["place_id"]),
        "name": name,
        "alt_names": alt_names,
        "tokens": tokens,
        "lat": float(place["lat"]),
        "lon": float(place["lon"]),
        "tier": int(place["tier"]),
        "category": _safe_text(place.get("category", ""), max_chars=caps.CATEGORY_MAX),
    }


def _alt_names(
    place: Mapping[str, Any],
    source_props_by_ref: Mapping[str, Mapping[str, Any]],
    *,
    primary_name: str,
) -> list[str]:
    candidates: list[str] = []
    for ref in place.get("source_refs", []):
        props = source_props_by_ref.get(str(ref))
        if not isinstance(props, Mapping):
            continue
        for key in sorted(props):
            value = props[key]
            if key.startswith("name:") or key in _ALT_NAME_KEYS:
                candidates.extend(_split_alt_value(value))
    primary_folded = _fold(primary_name)
    by_folded: dict[str, str] = {}
    for candidate in candidates:
        clean = _safe_text(candidate, max_chars=caps.NAME_MAX)
        folded = _fold(clean)
        if not clean or folded == primary_folded:
            continue
        by_folded.setdefault(folded, clean)
    return [
        by_folded[key]
        for key in sorted(by_folded)
    ][: caps.ALT_NAMES_MAX]


def _split_alt_value(value: Any) -> list[str]:
    if not isinstance(value, str):
        return []
    parts = re.split(r"[;/|]", value)
    return [part.strip() for part in parts if part.strip()]


def _tokens(values: Iterable[str]) -> list[str]:
    seen: dict[str, None] = {}
    for value in values:
        folded = _fold(value)
        for token in _word_tokens(folded):
            token = token[: caps.SEARCH_TOKEN_MAX]
            if token:
                seen.setdefault(token, None)
            if _needs_ngram(token) and len(token) > 2:
                for index in range(len(token) - 1):
                    seen.setdefault(token[index : index + 2], None)
    return list(seen)[: caps.SEARCH_TOKENS_MAX] or ["_"]


def _prefix_shards(entries: list[dict[str, Any]]) -> list[tuple[str, list[dict[str, Any]]]]:
    shards: dict[str, dict[str, dict[str, Any]]] = {}
    for entry in entries:
        place_id = str(entry["place_id"])
        for token in entry["tokens"]:
            shard_key = shard_key_for_token(str(token))
            shards.setdefault(shard_key, {}).setdefault(place_id, entry)
    return [
        (key, sorted(value.values(), key=lambda entry: str(entry["place_id"])))
        for key, value in sorted(shards.items())
    ]


def _full_artifacts_for_shard(
    *,
    region: str,
    publish_version: str,
    generated_at: str,
    shard_key: str,
    entries: list[dict[str, Any]],
) -> tuple[SearchIndexArtifact, ...]:
    payload = _index_payload(
        region=region,
        publish_version=publish_version,
        generated_at=generated_at,
        index_kind="full",
        shard_key=shard_key,
        entries=entries,
    )
    body = _json_bytes(payload)
    if len(body) <= caps.MAX_SEARCH_INDEX_BYTES:
        validate_instance("search-index", payload)
        return (_artifact_from_payload(payload, body),)
    return tuple(
        artifact
        for split_key, split_entries in _split_shards(shard_key, entries)
        for artifact in _bounded_split_artifacts(
            region=region,
            publish_version=publish_version,
            generated_at=generated_at,
            shard_key=split_key,
            entries=split_entries,
        )
    )


def _bounded_split_artifacts(
    *,
    region: str,
    publish_version: str,
    generated_at: str,
    shard_key: str,
    entries: list[dict[str, Any]],
) -> tuple[SearchIndexArtifact, ...]:
    payload = _index_payload(
        region=region,
        publish_version=publish_version,
        generated_at=generated_at,
        index_kind="full",
        shard_key=shard_key,
        entries=entries,
    )
    body = _json_bytes(payload)
    if len(body) <= caps.MAX_SEARCH_INDEX_BYTES:
        validate_instance("search-index", payload)
        return (_artifact_from_payload(payload, body),)
    return tuple(
        _artifact(
            _index_payload(
                region=region,
                publish_version=publish_version,
                generated_at=generated_at,
                index_kind="full",
                shard_key=hash_key,
                entries=hash_entries,
            )
        )
        for hash_key, hash_entries in _hash_split_shards(shard_key, entries)
    )


def _split_shards(
    shard_key: str,
    entries: list[dict[str, Any]],
) -> list[tuple[str, list[dict[str, Any]]]]:
    shards: dict[str, dict[str, dict[str, Any]]] = {}
    for entry in entries:
        place_id = str(entry["place_id"])
        for token in entry["tokens"]:
            if shard_key_for_token(str(token)) != shard_key:
                continue
            split_key = split_shard_key_for_token(str(token), place_id)
            shards.setdefault(split_key, {}).setdefault(place_id, entry)
    return [
        (key, sorted(value.values(), key=lambda entry: str(entry["place_id"])))
        for key, value in sorted(shards.items())
    ]


def _hash_split_shards(
    shard_key: str,
    entries: list[dict[str, Any]],
) -> list[tuple[str, list[dict[str, Any]]]]:
    shards: dict[str, dict[str, dict[str, Any]]] = {}
    for entry in entries:
        place_id = str(entry["place_id"])
        hash_key = hash_split_shard_key(shard_key, place_id)
        shards.setdefault(hash_key, {}).setdefault(place_id, entry)
    return [
        (key, sorted(value.values(), key=lambda entry: str(entry["place_id"])))
        for key, value in sorted(shards.items())
    ]


def _index_payload(
    *,
    region: str,
    publish_version: str,
    generated_at: str,
    index_kind: str,
    shard_key: str | None,
    entries: list[dict[str, Any]],
) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSIONS["search_index"],
        "min_reader_version": 1,
        "region": region,
        "publish_version": publish_version,
        "generated_at": generated_at,
        "index_kind": index_kind,
        "shard_key": shard_key,
        "entries": entries,
    }


def _artifact(payload: dict[str, Any]) -> SearchIndexArtifact:
    body = _json_bytes(payload)
    if len(body) > caps.MAX_SEARCH_INDEX_BYTES:
        shard = payload.get("shard_key")
        raise ValueError(
            f"search-index artifact exceeds {caps.MAX_SEARCH_INDEX_BYTES} bytes: "
            f"kind={payload.get('index_kind')} shard={shard!r}"
        )
    validate_instance("search-index", payload)
    return _artifact_from_payload(payload, body)


def _json_bytes(payload: dict[str, Any]) -> bytes:
    return json.dumps(
        payload,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")


def _artifact_from_payload(
    payload: dict[str, Any],
    body: bytes,
) -> SearchIndexArtifact:
    return SearchIndexArtifact(
        shard_key=payload.get("shard_key"),
        index_kind=str(payload["index_kind"]),
        json_bytes=body,
        sha256=hashlib.sha256(body).hexdigest(),
        byte_len=len(body),
    )


def _safe_text(value: Any, *, max_chars: int) -> str:
    clean = mt_contracts.strip_unsafe_text(" ".join(str(value).split())).strip()
    return clean[:max_chars]


def _fold(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold()
    stripped = "".join(
        char for char in unicodedata.normalize("NFKD", normalized)
        if unicodedata.category(char) != "Mn"
    )
    return mt_contracts.strip_unsafe_text(stripped)


def _word_tokens(value: str) -> list[str]:
    out: list[str] = []
    current: list[str] = []
    for char in value:
        if char.isalnum():
            current.append(char)
        elif current:
            out.append("".join(current))
            current = []
    if current:
        out.append("".join(current))
    return out


def _needs_ngram(value: str) -> bool:
    return any(ord(char) > 127 for char in value)
