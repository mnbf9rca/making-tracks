"""place_id: the immutable place identity contract."""

from __future__ import annotations

import hashlib
import re
from collections.abc import Iterable

from .versions import SCHEMA_VERSIONS

_ID_SCHEME_VERSION = SCHEMA_VERSIONS["id_scheme"]
KNOWN_ID_SCHEMES = frozenset({1})
assert _ID_SCHEME_VERSION in KNOWN_ID_SCHEMES, "current mint scheme must be known"
PLACE_ID_PREFIX = f"mt{_ID_SCHEME_VERSION}_"

_CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
_BODY_LEN = 26
_SCHEMES_ALT = "|".join(str(v) for v in sorted(KNOWN_ID_SCHEMES))
PLACE_ID_RE = re.compile(rf"^mt(?:{_SCHEMES_ALT})_[{_CROCKFORD}]{{{_BODY_LEN}}}$")

_SOURCE_PRIORITY = {"wd": 0, "osm": 1, "hehle": 2, "plaque": 3}
_OSM_TYPE_RANK = {"node": 0, "way": 1, "relation": 2}

MINT_KEY_RE = re.compile(
    r"^(wd:Q[0-9]+"
    r"|osm:(?:node|way|relation)/[0-9]+"
    r"|hehle:[0-9]+"
    r"|plaque:openplaques/[0-9]+)$"
)


def canonical_ref(source: str, ident: str) -> str:
    return f"{source}:{ident}"


def assert_canonical_mint_key(mint_key: str) -> None:
    if not MINT_KEY_RE.fullmatch(mint_key):
        raise ValueError(f"non-canonical mint_key: {mint_key!r}")


def _anchor_sort_key(ref: str):
    source, _, ident = ref.partition(":")
    priority = _SOURCE_PRIORITY.get(source, 99)
    if source == "osm":
        osm_type, _, num = ident.partition("/")
        num_key = int(num) if num.isdigit() else float("inf")
        return (priority, _OSM_TYPE_RANK.get(osm_type, 9), num_key, ref)
    if source == "wd":
        num_key = int(ident[1:]) if ident[1:].isdigit() else float("inf")
        return (priority, 0, num_key, ref)
    return (priority, 0, float("inf"), ref)


def select_mint_anchor(refs: Iterable[str]) -> str:
    refs = list(refs)
    if not refs:
        raise ValueError("cannot select a mint anchor from an empty ref set")
    return min(refs, key=_anchor_sort_key)


def _crockford(data: bytes, n_chars: int) -> str:
    value = int.from_bytes(data, "big")
    out = []
    for _ in range(n_chars):
        out.append(_CROCKFORD[value & 0x1F])
        value >>= 5
    return "".join(reversed(out))


def mint_place_id(mint_key: str) -> str:
    assert_canonical_mint_key(mint_key)
    digest = hashlib.sha256(mint_key.encode("ascii")).digest()
    return PLACE_ID_PREFIX + _crockford(digest[-16:], _BODY_LEN)


def is_valid_place_id(value: str) -> bool:
    return bool(PLACE_ID_RE.fullmatch(value))
