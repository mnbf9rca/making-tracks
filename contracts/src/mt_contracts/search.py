"""Shared helpers for the search-index contract."""

from __future__ import annotations

import hashlib
import re

_ASCII_PREFIX_RE = re.compile(r"^[a-z0-9]{1,2}$")


def shard_key_for_token(token: str) -> str:
    """Return the deterministic ASCII shard key for a folded search token."""

    if token == "_":
        return "_"
    prefix = token[:2]
    if _ASCII_PREFIX_RE.fullmatch(prefix):
        return prefix
    return "u_" + hashlib.sha256(token.encode("utf-8")).hexdigest()[:8]
