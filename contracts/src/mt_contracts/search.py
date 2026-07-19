"""Shared helpers for the search-index contract."""

from __future__ import annotations

import hashlib
import re

_ASCII_PREFIX_RE = re.compile(r"^[a-z0-9]{1,2}$")
_ASCII_SUFFIX_RE = re.compile(r"^[a-z0-9]$")
_HASH_SUFFIX_RE = re.compile(r"^h[0-9a-f]$")
MAX_HASH_SPLIT_DEPTH = 16


def shard_key_for_token(token: str) -> str:
    """Return the deterministic ASCII shard key for a folded search token."""

    if token == "_":
        return "_"
    prefix = token[:2]
    if _ASCII_PREFIX_RE.fullmatch(prefix):
        return prefix
    return "u_" + hashlib.sha256(token.encode("utf-8")).hexdigest()[:8]


def split_shard_key_for_token(token: str, place_id: str) -> str:
    """Return the deterministic first-level split shard for a token/place pair."""

    base = shard_key_for_token(token)
    return f"{base}_{_split_suffix(token, place_id, base)}"


def hash_split_shard_key(shard_key: str, place_id: str) -> str:
    """Return a deterministic hash split under an already split shard."""

    return f"{shard_key}_{_hash_suffix(place_id, _hash_depth(shard_key))}"


def shard_key_matches_token(shard_key: str, token: str, place_id: str) -> bool:
    """Return whether a full-index shard key may contain token for place_id."""

    base = shard_key_for_token(token)
    if shard_key == base:
        return True
    prefix = f"{base}_"
    if not shard_key.startswith(prefix):
        return False
    suffixes = shard_key[len(prefix) :].split("_")
    if not suffixes:
        return False
    split_key = split_shard_key_for_token(token, place_id)
    if suffixes[0] != split_key[len(prefix) :]:
        return False
    next_hash_depth = 1 if _HASH_SUFFIX_RE.fullmatch(suffixes[0]) else 0
    for index, suffix in enumerate(suffixes[1:], start=next_hash_depth):
        if suffix != _hash_suffix(place_id, index):
            return False
    return True


def _split_suffix(token: str, place_id: str, base: str) -> str:
    if token.startswith(base) and len(token) > len(base):
        suffix = token[len(base)]
        if _ASCII_SUFFIX_RE.fullmatch(suffix):
            return suffix
    return _hash_suffix(place_id, 0)


def _hash_suffix(place_id: str, depth: int) -> str:
    if depth >= MAX_HASH_SPLIT_DEPTH:
        raise ValueError("search shard hash split depth exhausted")
    return "h" + hashlib.sha256(place_id.encode("utf-8")).hexdigest()[depth]


def _hash_depth(shard_key: str) -> int:
    return sum(
        1
        for suffix in shard_key.split("_")[1:]
        if _HASH_SUFFIX_RE.fullmatch(suffix)
    )
