# WP-A0 (Contracts) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce the authoritative, executable cross-track contracts — `place_id` format, place JSON, place-tile, manifest, region-config schemas, the versioning policy, and the measured basemap pack budget — that every other work package builds against, before any of them starts.

**Architecture:** Contracts are made *executable*, not just prose. A standalone Python package `mt-contracts` under `contracts/` ships (a) language-neutral JSON Schema 2020-12 files, (b) golden fixtures (valid + invalid) that both the Python pipeline and the Swift app validate their encoders/decoders against, (c) a reference `place_id` mint/validate implementation with a *frozen golden-vector tripwire* enforcing Principle 7, and (d) a version registry encoding the §5.6 compatibility policy. A human-readable `CONTRACTS.md` ties them together and records what each downstream WP consumes. The basemap pack budget is fixed from **real measurements** taken against the live Protomaps planet build.

**Tech Stack:** Python 3.11+, `jsonschema>=4.21` + `referencing>=0.34` (2020-12, cross-file `$ref`), `pytest`, `pmtiles` CLI (measurement only, already run). JSON Schema draft 2020-12. Crockford base32 for `place_id`.

## Global Constraints

Every task's requirements implicitly include these. Values are copied verbatim from the spec / PRINCIPLES.md.

- **Python 3.11+.** Package is `src`-layout, name `mt-contracts`, import root `mt_contracts`.
- **Path convention.** In this plan `contracts/…` is the repo-relative top-level `contracts/` directory. Every shell command runs from the repo root and uses `cd contracts` — never the absolute `/contracts`.
- **`place_id` is forever (Principle 7).** Once shipped, never reassigned or reformatted. The frozen golden-vector test (Task 2) is the tripwire. Immutability applies to **validation** as well as minting: an id minted under one scheme must validate forever, even after minting advances to a later scheme.
- **Everything that crosses a boundary is versioned (Principle 11 / §5.6).** Manifest, tile, place, region-config, and the ID registry each carry a `schema_version`; readers declare a max understood version and a documented back-compat floor, then degrade — never silently misread newer/older data.
- **Determinism (Principle 12).** No wall-clock or randomness in any *output* value. `manifest.generated_at` is metadata only and never feeds an id, hash, or ordering. `place_id` derivation is a pure function of a frozen mint key. Tiles are gzipped with `mtime=0` so identical content yields identical bytes and a stable per-tile `sha256` across builds (a wall-clock gzip header would flip checksums and break cache invalidation).
- **All source data is untrusted (Principle 10 / §5.5).** Schemas enforce, on **every** source- or LLM-derived string (including nullable ones like `blurb`/`wikipedia_title`): a length cap; the shared **`SAFE_TEXT`** guard (rejects C0 controls, DEL, C1, line/paragraph separators U+2028/2029, bidi overrides+isolates U+202A–202E/2066–2069, and zero-width U+200B/FEFF — but **not** LRM/RLM U+200E/200F, so legitimate RTL names such as Jawi survive); coordinate bounds; `https://`-only URLs with no control/whitespace in the body; bounded array sizes; and the shared **canonical-ref** grammar on every source-ref field. Non-finite floats (`NaN`/`Infinity`) — which `json.loads` accepts and JSON Schema `minimum`/`maximum` cannot catch — are rejected at the Python validation layer. The app treats even our own tiles as untrusted (defence in depth): tiles are decompressed by a **bomb-safe streaming decoder** bounded by `MAX_TILE_UNCOMPRESSED_BYTES`, never `gzip.decompress` (which expands fully before any size check).
- **Caps are named, versioned constants (fable ratification, addition 4).** Every size cap lives in `mt_contracts.caps` as a named constant, single-sourced; the JSON Schemas' literal numbers are asserted equal to the constants by test (no drift), and a meta-test asserts every `*_MAX` constant is covered. Changing a cap requires a `schema_version` bump. No cap truncates silently: where a cap can be exceeded (places-per-tile), a deterministic overflow rule drops the excess and returns the dropped set for the caller to log.
- **Region *and source* modularity (Principle 17).** No schema hard-enums the region set or the source set; region ids and source prefixes match `^[a-z][a-z0-9_]*$`. Adding a region or a source (e.g. Malaysia's heritage register) is additive — one new entry, never a reformat of shipped data.
- **Test-first.** Every schema lands with a failing fixture test before the schema exists; the ID-stability invariants have regression tests (§7) that genuinely fail a plausible broken implementation.
- **Regions in scope:** `uk`, `malaysia`. **Recall language:** English-only for now (`languages` is per-region config so Malay etc. enable later without structural change).

**Shared patterns** (defined once; every schema references these exact strings — copy them verbatim):
- `SAFE_TEXT` = `^[^\u0000-\u001f\u007f-\u009f\u200b\u2028\u2029\u202a-\u202e\u2066-\u2069\ufeff]*$` (as written in the JSON schemas, with doubled backslashes)
 ‪-‮⁦-⁩﻿]*$`
- `CANONICAL_REF` = `^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9._/-]*$`
- `HTTPS_URL` = `^https://[^\u0000-\u001f\u007f-\u009f\s]+$`
- `PLACE_ID` (schema v1) = `^mt1_[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$`
- `SHA256_HEX` = `^[0-9a-f]{64}$`
- `PUBLISH_VERSION` = `^[0-9]{8}T[0-9]{6}Z$`

**Ratified by the design lead.** The `place_id` scheme, anchor priority, and soft-supersede model were confirmed by fable on AMQ thread `wp/a0`, with additions folded in (incl. ambiguity-raises and append-only source grammar). This plan additionally incorporates the fixes surviving a five-critic adversarial review (see the closing Review Record). Rob retains override until the plan is approved.

---

## File Structure

Language-neutral contract artifacts and the reference implementation live together under a new top-level `contracts/` directory (consumed by both `/pipeline` and `/ios`; A1 later depends on this package rather than redefining it).

```
contracts/
  pyproject.toml                      # standalone installable package `mt-contracts`
  README.md                           # one-paragraph pointer to CONTRACTS.md
  CONTRACTS.md                        # AUTHORITATIVE human-readable doc (Task 7)
  versions.json                       # single source of truth for every schema_version (Task 1)
  basemap-budget.json                 # measured pmtiles sweep + pack decision (Task 6)
  schemas/
    place.schema.json                 # Task 3
    tile.schema.json                  # Task 4
    manifest.schema.json              # Task 5
    region-config.schema.json         # Task 6
    registry-record.schema.json       # Task 2
  fixtures/
    place/{valid,invalid}/*.json      # Task 3
    tile/{valid,invalid}/*.json       # Task 4
    manifest/{valid,invalid}/*.json   # Task 5
    place_id/frozen_vectors.json      # Task 2 — the immutability tripwire
  regions/
    uk.json                           # Task 6 — real region config, measured
    malaysia.json                     # Task 6 — real region config, measured
  src/mt_contracts/
    __init__.py
    versions.py                       # version constants + §5.6 compatibility policy (Task 1)
    caps.py                           # named, versioned size caps + tile-overflow rule (Task 4)
    tilecodec.py                      # deterministic gzip (mtime=0) + bomb-safe gunzip (Task 4)
    place_id.py                       # mint / validate / anchor-selection / canonicalization (Task 2)
    registry.py                       # RegistryRecord + resolve_by_refs + supersede-chain (Task 2)
    validation.py                     # schema loader + validate_* helpers (finite-float guard) (Task 3)
    checksums.py                      # sha256_hex reference helper (Task 5)
  tests/
    conftest.py                       # contracts_root fixture path helper
    test_versions.py                  # Task 1
    test_place_id.py                  # Task 2
    test_registry.py                  # Task 2
    test_place_schema.py              # Task 3
    test_caps.py                      # Task 4
    test_tile_schema.py               # Task 4
    test_manifest_schema.py           # Task 5
    test_region_config_schema.py      # Task 6
    test_basemap_budget.py            # Task 6
```

Each `*.schema.json` has one responsibility. Fixtures live beside the schema they exercise. The reference `.py` modules are small and single-purpose so a reviewer can reject one artifact without touching its neighbours.

---

### Task 1: Contracts package scaffold + version registry + §5.6 compatibility policy

**Files:**
- Create: `contracts/pyproject.toml`, `contracts/src/mt_contracts/__init__.py`
- Create: `contracts/versions.json`, `contracts/src/mt_contracts/versions.py`
- Create: `contracts/tests/conftest.py`, `contracts/tests/test_versions.py`

**Interfaces:**
- Consumes: nothing (WP-A0 has no dependencies).
- Produces:
  - `versions.SCHEMA_VERSIONS: dict[str,int]` — keys `place`, `tile`, `manifest`, `region_config`, `registry_record`, `id_scheme`.
  - `versions.MIN_SUPPORTED_VERSIONS: dict[str,int]` — the documented §5.6 back-compat floor per artifact (today all `1`).
  - `versions.Compat` — `Enum{OK, TOO_NEW, TOO_OLD}`; `versions.check_version(reader_max, data_version, min_supported) -> Compat`.
  - `conftest.py` fixture `contracts_root: pathlib.Path`.

- [ ] **Step 1: Write `conftest.py` and the failing test**

`contracts/tests/conftest.py`:
```python
import pathlib
import pytest

@pytest.fixture(scope="session")
def contracts_root() -> pathlib.Path:
    # the contracts/ dir: parents[0]=tests/, parents[1]=contracts/
    return pathlib.Path(__file__).resolve().parents[1]
```

`contracts/tests/test_versions.py`:
```python
import json
from mt_contracts.versions import SCHEMA_VERSIONS, MIN_SUPPORTED_VERSIONS, Compat, check_version

REQUIRED_KEYS = {"place", "tile", "manifest", "region_config", "registry_record", "id_scheme"}

def test_versions_json_matches_module(contracts_root):
    on_disk = json.loads((contracts_root / "versions.json").read_text())
    assert on_disk == SCHEMA_VERSIONS

def test_all_version_keys_present():
    assert REQUIRED_KEYS <= set(SCHEMA_VERSIONS)
    assert all(isinstance(v, int) and v >= 1 for v in SCHEMA_VERSIONS.values())

def test_min_supported_floor_is_documented_for_every_artifact():
    # §5.6 window floor is explicit per artifact, never implicit; today [1,1].
    assert set(MIN_SUPPORTED_VERSIONS) == set(SCHEMA_VERSIONS)
    assert all(1 <= MIN_SUPPORTED_VERSIONS[k] <= SCHEMA_VERSIONS[k] for k in SCHEMA_VERSIONS)

def test_check_version_equal_is_ok():
    assert check_version(reader_max=1, data_version=1, min_supported=1) is Compat.OK

def test_check_version_newer_data_is_too_new():
    assert check_version(reader_max=1, data_version=2, min_supported=1) is Compat.TOO_NEW

def test_check_version_older_within_window_is_ok():
    assert check_version(reader_max=3, data_version=2, min_supported=2) is Compat.OK

def test_check_version_older_below_window_is_too_old():
    assert check_version(reader_max=3, data_version=1, min_supported=2) is Compat.TOO_OLD
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd contracts && python -m pytest tests/test_versions.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_contracts'`.

- [ ] **Step 3: Create the package scaffold**

`contracts/pyproject.toml`:
```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "mt-contracts"
version = "0.1.0"
description = "Making Tracks cross-track contracts (schemas, place_id, versioning)."
requires-python = ">=3.11"
dependencies = ["jsonschema>=4.21", "referencing>=0.34"]

[project.optional-dependencies]
dev = ["pytest>=8"]

[tool.hatch.build.targets.wheel]
packages = ["src/mt_contracts"]

[tool.pytest.ini_options]
pythonpath = ["src"]
testpaths = ["tests"]
```

`contracts/src/mt_contracts/__init__.py`:
```python
"""Making Tracks cross-track contracts. See contracts/CONTRACTS.md."""
```

- [ ] **Step 4: Write `versions.json` and `versions.py`**

`contracts/versions.json`:
```json
{
  "place": 1,
  "tile": 1,
  "manifest": 1,
  "region_config": 1,
  "registry_record": 1,
  "id_scheme": 1
}
```

`contracts/src/mt_contracts/versions.py`:
```python
"""Schema version registry and the §5.6 reader-compatibility policy.

A reader declares the maximum artifact version it understands (`reader_max`) and
the oldest it still accepts (`min_supported`). check_version() classifies data so
a reader can refuse or degrade — never silently misread. (Principle 11.)
"""
from __future__ import annotations

import enum
import json
import pathlib

_VERSIONS_PATH = pathlib.Path(__file__).resolve().parents[2] / "versions.json"

# Loaded once at import; the file is the single source of truth so schemas and
# code can never drift (test_versions_json_matches_module enforces equality).
SCHEMA_VERSIONS: dict[str, int] = json.loads(_VERSIONS_PATH.read_text())

# The documented §5.6 back-compat window FLOOR per artifact: the oldest version a
# current reader still accepts. Today every artifact is v1 so the window is
# [1, 1]. When a schema bumps, this floor is raised deliberately (and documented
# in CONTRACTS.md) — never implicitly.
MIN_SUPPORTED_VERSIONS: dict[str, int] = {k: 1 for k in SCHEMA_VERSIONS}


class Compat(enum.Enum):
    OK = "ok"           # data understood; render/serve it
    TOO_NEW = "too_new" # data newer than reader: keep cached older; prompt app update
    TOO_OLD = "too_old" # data older than the back-compat window: refuse


def check_version(reader_max: int, data_version: int, min_supported: int) -> Compat:
    if data_version > reader_max:
        return Compat.TOO_NEW
    if data_version < min_supported:
        return Compat.TOO_OLD
    return Compat.OK
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd contracts && pip install -e '.[dev]' && python -m pytest tests/test_versions.py -q`
Expected: PASS (7 passed).

- [ ] **Step 6: Commit**

```bash
git add contracts/pyproject.toml contracts/src/mt_contracts/__init__.py \
        contracts/versions.json contracts/src/mt_contracts/versions.py \
        contracts/tests/conftest.py contracts/tests/test_versions.py
git commit -m "Add contracts package scaffold, version registry, and §5.6 compatibility policy"
```

---

### Task 2: `place_id` format + reference implementation + registry record shape

The highest-stakes artifact in the project. It resolves the spec's tension (§5.2 "derived from anchor ref" vs "never re-mint when the anchor changes"): **derivation seeds the *first* mint only; the ID registry is authoritative forever after.** `mint_place_id()` runs only for a genuinely new cluster; every later run looks a place up by union-of-refs and reuses the frozen id.

**Files:**
- Create: `contracts/src/mt_contracts/place_id.py`, `contracts/src/mt_contracts/registry.py`
- Create: `contracts/schemas/registry-record.schema.json`, `contracts/fixtures/place_id/frozen_vectors.json`
- Test: `contracts/tests/test_place_id.py`, `contracts/tests/test_registry.py`

**Interfaces:**
- Consumes: `versions.SCHEMA_VERSIONS`.
- Produces:
  - `place_id.KNOWN_ID_SCHEMES: frozenset[int]` (monotonic), `place_id.PLACE_ID_PREFIX` (current mint scheme, `"mt1_"`), `place_id.PLACE_ID_RE`, `place_id._build_place_id_re(schemes) -> re.Pattern`.
  - `place_id.MINT_KEY_RE`, `place_id.assert_canonical_mint_key(mint_key) -> None`, `place_id.canonical_ref(source, ident) -> str`.
  - `place_id.select_mint_anchor(refs) -> str`, `place_id.mint_place_id(mint_key) -> str` (raises `ValueError` on non-canonical key), `place_id.is_valid_place_id(value) -> bool`.
  - `registry.RegistryRecord`, `registry.AmbiguousRefsError` (carries `.place_ids`), `registry.resolve_by_refs(records, incoming_refs) -> str | None` (raises on ambiguity), `registry.resolve_superseded(records, place_id) -> str`, `registry.assert_no_supersede_cycles(records) -> None`, `registry.tile_winner_violations(tile_place_ids, records) -> list[str]`.

- [ ] **Step 1: Write the failing `place_id` tests**

`contracts/tests/test_place_id.py`:
```python
import json
import pytest
from mt_contracts.place_id import (
    PLACE_ID_PREFIX, canonical_ref, select_mint_anchor,
    mint_place_id, is_valid_place_id,
)

def test_format_and_prefix():
    pid = mint_place_id("wd:Q42")
    assert pid.startswith(PLACE_ID_PREFIX)
    assert is_valid_place_id(pid)
    assert len(pid) == len(PLACE_ID_PREFIX) + 26

def test_mint_is_deterministic():
    assert mint_place_id("wd:Q42") == mint_place_id("wd:Q42")

def test_distinct_keys_distinct_ids():
    assert mint_place_id("wd:Q42") != mint_place_id("wd:Q43")

def test_rejects_malformed_ids():
    assert not is_valid_place_id("mt1_short")
    assert not is_valid_place_id("Q42")
    assert not is_valid_place_id("mt1_" + "I" * 26)   # I is not in the Crockford alphabet
    assert not is_valid_place_id("mt2_" + "0" * 26)    # scheme 2 not yet a KNOWN scheme

def test_validation_regex_is_derived_from_known_schemes_not_current():
    # Principle 7 applies to VALIDATION, not just minting: the validator must
    # cover EVERY known scheme, so a future bump to mt2_ cannot invalidate a
    # shipped mt1_ id. Test the mechanism directly (monkeypatching the current
    # scheme would be tautological — PLACE_ID_RE never reads it).
    from mt_contracts.place_id import _build_place_id_re
    both = _build_place_id_re(frozenset({1, 2}))
    assert both.fullmatch("mt1_" + "0" * 26)   # shipped scheme-1 id still valid
    assert both.fullmatch("mt2_" + "0" * 26)   # and the new scheme too
    only1 = _build_place_id_re(frozenset({1}))
    assert only1.fullmatch("mt1_" + "0" * 26)
    assert not only1.fullmatch("mt2_" + "0" * 26)  # scheme 2 not yet known → rejected

def test_current_mint_scheme_is_a_known_scheme():
    from mt_contracts.place_id import KNOWN_ID_SCHEMES, _ID_SCHEME_VERSION
    assert _ID_SCHEME_VERSION in KNOWN_ID_SCHEMES

def test_independent_frozen_vector_cross_check():
    # A hand-computed value (from an INDEPENDENT sha256+Crockford implementation)
    # pins the algorithm against a subtly-wrong day-one impl that would otherwise
    # freeze its own error into frozen_vectors.json (generated by the impl under
    # test). Lower 128 bits of sha256(b"wd:Q42"), 26 Crockford chars.
    assert mint_place_id("wd:Q42") == "mt1_1Q831BXYQ8GP7ZXKVQZH87G0R5"

def test_canonical_ref():
    assert canonical_ref("wd", "Q42") == "wd:Q42"

def test_mint_rejects_noncanonical_key():
    # Canonicalization is part of the frozen scheme: an unpinned key format is a
    # silent second version of the scheme (fable ratification, addition 1).
    for bad in ["WD:Q42", "wd: Q42", "wd:Q42 ", "osm:Way/456", "wd:Qé", "foo:1", "wd:Q42\n"]:
        with pytest.raises(ValueError):
            mint_place_id(bad)

def test_conformance_vectors_cover_every_source_type(contracts_root):
    vectors = json.loads((contracts_root / "fixtures/place_id/frozen_vectors.json").read_text())
    prefixes = {row["mint_key"].split(":", 1)[0] for row in vectors}
    assert {"wd", "osm", "hehle", "plaque"} <= prefixes

def test_anchor_priority_prefers_wikidata():
    assert select_mint_anchor(["osm:way/10", "wd:Q7", "plaque:openplaques/3"]) == "wd:Q7"

def test_anchor_priority_osm_type_and_numeric_order():
    # node < way < relation; numeric (not lexical) within type
    assert select_mint_anchor(["osm:way/2", "osm:node/100", "osm:node/9"]) == "osm:node/9"

def test_anchor_is_order_independent():
    a = select_mint_anchor(["wd:Q9", "osm:node/1", "hehle:5"])
    b = select_mint_anchor(["hehle:5", "osm:node/1", "wd:Q9"])
    assert a == b == "wd:Q9"

def test_frozen_vectors_never_change(contracts_root):
    # Principle 7 tripwire: these (mint_key -> place_id) pairs are shipped
    # contract. If this fails the mint algorithm changed and would reassign
    # already-shipped ids. The change is wrong.
    vectors = json.loads((contracts_root / "fixtures/place_id/frozen_vectors.json").read_text())
    for row in vectors:
        assert mint_place_id(row["mint_key"]) == row["place_id"], row["mint_key"]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd contracts && python -m pytest tests/test_place_id.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_contracts.place_id'`.

- [ ] **Step 3: Implement `place_id.py`**

`contracts/src/mt_contracts/place_id.py`:
```python
"""place_id: the immutable place identity contract (Principle 7).

Scheme `mt1_<26 Crockford base32>` where the body is the lower 128 bits of
sha256(mint_key). `mt` = namespace; `1` = ID-SCHEME version (a future scheme
mints *new* ids under `mt2_` without ever reformatting shipped `mt1_` ids).

The id is derived from a FROZEN mint anchor and then owned by the ID registry.
mint_place_id() runs only for a brand-new cluster; thereafter a place is found
by union-of-refs (registry.resolve_by_refs) and its id reused unchanged, so a
Wikidata QID merge or an OSM tag change never re-mints. (See CONTRACTS.md §2.)
"""
from __future__ import annotations

import hashlib
import re
from collections.abc import Iterable

from .versions import SCHEMA_VERSIONS

_ID_SCHEME_VERSION = SCHEMA_VERSIONS["id_scheme"]  # CURRENT scheme — used ONLY for minting
# Every scheme ever shipped. Grows monotonically, NEVER shrinks: once mt1_ ids
# ship they must validate forever, even after minting advances (Principle 7
# applies to validation, not just minting). A scheme bump adds the new number
# here AND to id_scheme in versions.json — it never removes one.
KNOWN_ID_SCHEMES = frozenset({1})
assert _ID_SCHEME_VERSION in KNOWN_ID_SCHEMES, "current mint scheme must be a known scheme"
PLACE_ID_PREFIX = f"mt{_ID_SCHEME_VERSION}_"  # minting emits the current scheme only

# Crockford base32 alphabet: no I, L, O, U (ambiguity-free, case-insensitive).
_CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
_BODY_LEN = 26  # 26 * 5 = 130 bits carrying the lower 128 bits of the digest


def _build_place_id_re(schemes: "frozenset[int]") -> "re.Pattern[str]":
    """Validation regex covering EVERY given scheme prefix.

    Derived from the (only-growing) known-scheme set, NOT the current mint
    scheme, so once mt1_ ids ship they validate forever even after minting moves
    to mt2_. Factored out so the mechanism is directly testable.
    """
    alt = "|".join(str(v) for v in sorted(schemes))
    return re.compile(rf"^mt(?:{alt})_[{_CROCKFORD}]{{{_BODY_LEN}}}$")


PLACE_ID_RE = _build_place_id_re(KNOWN_ID_SCHEMES)

# Anchor selection: fixed source priority, then a total order within source so
# the same cluster always mints the same id regardless of ingest order. This
# ordering exists SOLELY for mint-time determinism; it carries no meaning after
# mint, so nothing downstream should ever "re-select" an anchor. (Ratification 2.)
# Unknown sources sort deterministically AFTER known ones (via the ref string
# tie-break), so adding a source never reorders existing anchors (Principle 17).
_SOURCE_PRIORITY = {"wd": 0, "osm": 1, "hehle": 2, "plaque": 3}
_OSM_TYPE_RANK = {"node": 0, "way": 1, "relation": 2}

# Canonical mint-key grammar is part of the FROZEN scheme (ratification 1). Each
# source pins its own EXACT ident grammar; lowercase prefix, exact separator,
# ASCII, no whitespace. hehle = Historic England List Entry.
#
# APPEND-ONLY (fable ratification): the SET of sources grows additively — a new
# source (e.g. Malaysia's register) is a NEW alternative in this dict plus a new
# priority entry plus new conformance vectors, and NOTHING ELSE. Adding a source
# NEVER alters the canonical form or minted id of any existing source's keys, and
# the frozen vectors remain untouched forever. Never edit or remove an existing
# entry. (Principles 7 + 17.)
_SOURCE_IDENT_GRAMMAR = {
    "wd": r"Q[0-9]+",
    "osm": r"(?:node|way|relation)/[0-9]+",
    "hehle": r"[0-9]+",
    "plaque": r"openplaques/[0-9]+",
}
MINT_KEY_RE = re.compile(
    "^(?:" + "|".join(f"{src}:{grm}" for src, grm in _SOURCE_IDENT_GRAMMAR.items()) + ")$"
)


def canonical_ref(source: str, ident: str) -> str:
    return f"{source}:{ident}"


def assert_canonical_mint_key(mint_key: str) -> None:
    if not MINT_KEY_RE.fullmatch(mint_key):
        raise ValueError(f"non-canonical mint_key: {mint_key!r}")


def _anchor_sort_key(ref: str):
    source, _, ident = ref.partition(":")
    prio = _SOURCE_PRIORITY.get(source, 99)
    if source == "osm":
        otype, _, num = ident.partition("/")
        num_key = int(num) if num.isdigit() else float("inf")
        return (prio, _OSM_TYPE_RANK.get(otype, 9), num_key, ref)
    if source == "wd":
        num_key = int(ident[1:]) if ident[1:].isdigit() else float("inf")
        return (prio, 0, num_key, ref)
    return (prio, 0, float("inf"), ref)


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
    """Deterministically derive a place_id from a canonical mint anchor ref.

    Call ONLY for a genuinely new cluster. Existing places are resolved via the
    registry and keep their frozen id.
    """
    assert_canonical_mint_key(mint_key)  # canonicalization is frozen contract
    digest = hashlib.sha256(mint_key.encode("ascii")).digest()
    return PLACE_ID_PREFIX + _crockford(digest[-16:], _BODY_LEN)  # lower 128 bits


def is_valid_place_id(value: str) -> bool:
    return bool(PLACE_ID_RE.fullmatch(value))
```

- [ ] **Step 4: Generate the frozen-vector fixture from the reference impl**

Run once and hand-commit the output (the vectors become immutable contract):
```bash
cd contracts && python - <<'PY'
import json, pathlib
from mt_contracts.place_id import mint_place_id
keys = ["wd:Q42", "osm:node/9", "osm:way/456", "hehle:1234567", "plaque:openplaques/9876"]
rows = [{"mint_key": k, "place_id": mint_place_id(k)} for k in keys]
p = pathlib.Path("fixtures/place_id"); p.mkdir(parents=True, exist_ok=True)
(p / "frozen_vectors.json").write_text(json.dumps(rows, indent=2) + "\n")
print(json.dumps(rows, indent=2))
PY
```
Expected: 5 rows, each a valid `mt1_…` id; `wd:Q42` must equal `mt1_1Q831BXYQ8GP7ZXKVQZH87G0R5` (the independent cross-check). **Never regenerate this file after Task 2 ships**, and never edit an existing source's grammar (append-only).

- [ ] **Step 5: Run the `place_id` tests to verify they pass**

Run: `cd contracts && python -m pytest tests/test_place_id.py -q`
Expected: PASS (all place_id tests green, incl. the scheme-derivation, canonicalization-rejection, and independent-cross-check tests).

- [ ] **Step 6: Write the failing registry tests**

`contracts/tests/test_registry.py`:
```python
import pytest
from mt_contracts.registry import RegistryRecord, resolve_by_refs, AmbiguousRefsError

def _rec(pid, refs, status="live", superseded_by=None):
    # anchor is deliberately the FIRST sorted ref; tests below share a NON-anchor
    # ref so an anchor-only implementation cannot pass them.
    return RegistryRecord(
        place_id=pid, refs=set(refs), mint_anchor=sorted(refs)[0],
        status=status, superseded_by=superseded_by,
        first_shipped_version="20260714T000000Z",
        last_seen_version="20260714T000000Z",
    )

def test_resolve_rides_a_non_anchor_ref():
    # refs sorted -> anchor "osm:node/5"; incoming shares ONLY the non-anchor
    # "wd:Q100". An anchor-only impl returns None; union-of-refs returns the id.
    pid = "mt1_" + "0" * 26
    records = [_rec(pid, ["wd:Q100", "osm:node/5"])]
    assert records[0].mint_anchor == "osm:node/5"
    assert resolve_by_refs(records, {"wd:Q100"}) == pid

def test_qid_merge_keeps_place_id_stable():
    # Place shipped with refs {Q100, osm:way/9}; anchor = "osm:way/9". Upstream
    # merges Q100 -> Q200 and the OSM feature drops its tag, so the ONLY overlap
    # with the incoming (redirect-resolved) union is the non-anchor Q100. The
    # place must keep its id, NOT re-mint. (§7 mandated regression test — and it
    # now fails an anchor-only lookup, which a naive impl would pass.)
    pid = "mt1_" + "1" * 26
    records = [_rec(pid, ["wd:Q100", "osm:way/9"])]
    assert records[0].mint_anchor == "osm:way/9"
    assert resolve_by_refs(records, {"wd:Q100", "wd:Q200"}) == pid

def test_unknown_refs_resolve_to_none():
    records = [_rec("mt1_" + "0" * 26, ["wd:Q100"])]
    assert resolve_by_refs(records, {"wd:Q999"}) is None

def test_ambiguous_refs_raise_and_carry_candidates():
    # Incoming refs overlap TWO distinct shipped places. The contract must refuse
    # (Principle 9: never a silent, order-dependent false merge) and hand A2 the
    # candidate ids to adjudicate.
    p1 = _rec("mt1_" + "a" * 26, ["wd:Q1"])
    p2 = _rec("mt1_" + "b" * 26, ["wd:Q2"])
    with pytest.raises(AmbiguousRefsError) as exc:
        resolve_by_refs([p1, p2], {"wd:Q1", "wd:Q2"})
    assert exc.value.place_ids == {"mt1_" + "a" * 26, "mt1_" + "b" * 26}

def test_tombstoned_record_still_resolves_and_is_never_reassigned():
    pid = "mt1_" + "2" * 26
    records = [_rec(pid, ["wd:Q7"], status="tombstoned")]
    # A vanished place is tombstoned, not deleted; its refs still resolve to it
    # so the id can never be reassigned to a different place.
    assert resolve_by_refs(records, {"wd:Q7"}) == pid

def test_superseded_by_points_at_a_valid_place_id():
    from mt_contracts.place_id import is_valid_place_id
    dup = _rec("mt1_" + "4" * 26, ["wd:Q8"], superseded_by="mt1_" + "3" * 26)
    assert is_valid_place_id(dup.superseded_by)

def test_resolve_superseded_is_transitive():
    from mt_contracts.registry import resolve_superseded
    a, b, c = ("mt1_" + ch * 26 for ch in "567")
    records = [_rec(a, ["wd:Q1"], superseded_by=b),
               _rec(b, ["wd:Q2"], superseded_by=c),
               _rec(c, ["wd:Q3"])]  # terminal winner
    assert resolve_superseded(records, a) == c   # A -> B -> C
    assert resolve_superseded(records, c) == c

def test_supersede_cycle_is_rejected_at_write():
    from mt_contracts.registry import assert_no_supersede_cycles
    a, b = ("mt1_" + ch * 26 for ch in "89")
    records = [_rec(a, ["wd:Q1"], superseded_by=b), _rec(b, ["wd:Q2"], superseded_by=a)]
    with pytest.raises(ValueError):
        assert_no_supersede_cycles(records)

def test_tile_winner_violations_flags_superseded_ids():
    from mt_contracts.registry import tile_winner_violations
    winner = "mt1_" + "3" * 26
    loser = "mt1_" + "4" * 26
    records = [_rec(loser, ["wd:Q8"], superseded_by=winner), _rec(winner, ["wd:Q9"])]
    assert tile_winner_violations([winner], records) == []      # winner is fine
    assert tile_winner_violations([loser], records) == [loser]  # loser must not ship
```

- [ ] **Step 7: Implement `registry.py` and `registry-record.schema.json`**

`contracts/src/mt_contracts/registry.py`:
```python
"""ID registry record shape + the union-of-refs lookup contract.

A0 pins the *shape* and the *invariants*; the clustering/redirect algorithm is
WP-A2. The registry is the authoritative owner of place identity: a place is
found by ANY source ref it has ever carried, so upstream churn (QID merges, OSM
tag changes) never mints a new id for an already-shipped place. (Principles 7,8,9.)
"""
from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass


class AmbiguousRefsError(Exception):
    """Incoming refs match two or more DISTINCT existing places.

    The conservative-reconciliation trip (Principle 9: a false merge corrupts
    user data, a false split is merely ugly). A0's lookup contract REFUSES to
    silently pick one; A2 must resolve it conservatively (keep the places split,
    or soft-supersede — never auto-merge two shipped ids). The candidate ids are
    carried on `.place_ids` so A2's adjudication path has what it needs.
    """

    def __init__(self, place_ids: set[str]):
        self.place_ids = place_ids
        super().__init__(f"refs match multiple places: {sorted(place_ids)}")


@dataclass
class RegistryRecord:
    place_id: str                    # immutable, minted once (place_id.mint_place_id)
    refs: set[str]                   # union of every canonical ref ever clustered here
    mint_anchor: str                 # the frozen ref used to mint (audit trail)
    status: str                      # "live" | "tombstoned"
    superseded_by: str | None = None # soft de-dup: both ids stay valid forever
    first_shipped_version: str = ""  # publish_version at first ship
    last_seen_version: str = ""      # last publish_version the place was live
    schema_version: int = 1


def resolve_by_refs(records: Iterable[RegistryRecord], incoming_refs: set[str]) -> str | None:
    """Return the place_id of the record sharing ANY ref with `incoming_refs`.

    The match is on the full ref UNION, not the anchor: a place is found by any
    ref it has ever carried, so a Wikidata QID merge (Q100->Q200, both in the
    redirect-resolved incoming union) keeps its id. Returns None when nothing
    matches (A2 mints a new id). Raises AmbiguousRefsError (carrying the candidate
    place_ids) when the refs match two or more DISTINCT places — the contract
    never silently first-wins, because that would be an order-dependent
    (non-deterministic) false merge. `incoming_refs` must already be
    redirect-resolved by the caller (A2).
    """
    matches = {rec.place_id for rec in records if rec.refs & incoming_refs}
    if len(matches) > 1:
        raise AmbiguousRefsError(matches)
    return next(iter(matches), None)


def resolve_superseded(records: Iterable[RegistryRecord], place_id: str) -> str:
    """Follow the superseded_by chain to its terminal winner (transitive, A->B->C).

    The winner is the id that appears in published tiles; superseded (loser) ids
    stay valid forever in the registry and in user place_snapshots and resolve
    for rendering with no app-side special case (ratification 3b/3c). Raises on a
    cycle (defence in depth; assert_no_supersede_cycles guards writes).
    """
    by_id = {r.place_id: r for r in records}
    seen: set[str] = set()
    current = place_id
    while True:
        rec = by_id.get(current)
        nxt = rec.superseded_by if rec else None
        if not nxt:
            return current
        if nxt in seen:
            raise ValueError(f"superseded_by cycle at {nxt}")
        seen.add(current)
        current = nxt


def assert_no_supersede_cycles(records: Iterable[RegistryRecord]) -> None:
    """Registry write-time invariant: the superseded_by graph is acyclic."""
    records = list(records)
    for rec in records:
        resolve_superseded(records, rec.place_id)  # raises on a cycle


def tile_winner_violations(tile_place_ids: Iterable[str], records: Iterable[RegistryRecord]) -> list[str]:
    """Return any tile place_ids that are NOT terminal supersede winners.

    Published tiles must carry the winner id only (ratification 3b): a place_id
    whose record has a non-null superseded_by must never appear in a tile. A7
    calls this as a publish-time guard; an empty list means the tile is clean.
    """
    records = list(records)
    return [pid for pid in tile_place_ids if resolve_superseded(records, pid) != pid]
```

`contracts/schemas/registry-record.schema.json`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://contracts.making-tracks.app/registry-record/1",
  "title": "RegistryRecord",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "place_id", "refs", "mint_anchor", "status"],
  "properties": {
    "schema_version": {"type": "integer", "const": 1},
    "place_id": {"type": "string", "pattern": "^mt1_[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$"},
    "refs": {
      "type": "array", "minItems": 1, "maxItems": 256, "uniqueItems": true,
      "items": {"type": "string", "maxLength": 128, "pattern": "^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9._/-]*$"}
    },
    "mint_anchor": {"type": "string", "maxLength": 128, "pattern": "^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9._/-]*$"},
    "status": {"type": "string", "enum": ["live", "tombstoned"]},
    "superseded_by": {"type": ["string", "null"], "pattern": "^mt1_[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$"},
    "first_shipped_version": {"type": "string", "pattern": "^[0-9]{8}T[0-9]{6}Z$"},
    "last_seen_version": {"type": "string", "pattern": "^[0-9]{8}T[0-9]{6}Z$"}
  }
}
```

- [ ] **Step 8: Run the registry tests to verify they pass**

Run: `cd contracts && python -m pytest tests/test_place_id.py tests/test_registry.py -q`
Expected: PASS (all place_id + registry tests green, incl. non-anchor union-of-refs, ambiguity refusal carrying candidates, transitive supersede, cycle rejection, winner-only guard).

- [ ] **Step 9: Commit**

```bash
git add contracts/src/mt_contracts/place_id.py contracts/src/mt_contracts/registry.py \
        contracts/schemas/registry-record.schema.json \
        contracts/fixtures/place_id/frozen_vectors.json \
        contracts/tests/test_place_id.py contracts/tests/test_registry.py
git commit -m "Pin place_id format, registry record shape, and union-of-refs / QID-merge invariants"
```

---

### Task 3: Place JSON schema + validator (finite-float guard) + fixtures

**Files:**
- Create: `contracts/schemas/place.schema.json`, `contracts/src/mt_contracts/validation.py`
- Create: `contracts/fixtures/place/valid/*.json`, `contracts/fixtures/place/invalid/*.json`
- Test: `contracts/tests/test_place_schema.py`

**Interfaces:**
- Consumes: `place.schema.json`, `registry-record.schema.json`.
- Produces: `validation.load_schema(name)`, `validation.validator_for(name)`, `validation.validate_instance(name, instance)` (raises on schema violation OR non-finite float), `validation.is_valid(name, instance)`.

- [ ] **Step 1: Write the failing test**

`contracts/tests/test_place_schema.py`:
```python
import json
import pytest
from mt_contracts.validation import is_valid, validate_instance

def _load_dir(root, sub):
    return sorted((root / "fixtures/place" / sub).glob("*.json"))

def test_valid_place_fixtures_all_pass(contracts_root):
    files = _load_dir(contracts_root, "valid")
    assert files, "expected at least one valid place fixture"
    for f in files:
        validate_instance("place", json.loads(f.read_text()))  # raises on failure

@pytest.mark.parametrize("field", ["oversize_blurb", "http_image_url", "bad_tier",
                                   "lat_out_of_range", "missing_place_id",
                                   "control_char_name", "control_char_blurb",
                                   "bidi_name", "noncanonical_ref", "empty_source_refs"])
def test_invalid_place_fixtures_all_fail(contracts_root, field):
    inst = json.loads((contracts_root / f"fixtures/place/invalid/{field}.json").read_text())
    assert not is_valid("place", inst), f"{field} should have failed validation"

def test_non_finite_floats_are_rejected():
    # json.loads accepts NaN/Infinity and JSON Schema minimum/maximum cannot catch
    # them (every comparison with NaN is false). validate_instance must reject.
    import math
    bad = {"place_id": "mt1_" + "0" * 26, "name": "X", "lat": math.nan, "lon": 0,
           "category": "c", "tier": 1, "score": 0.5, "source_refs": ["wd:Q1"]}
    assert not is_valid("place", bad)
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd contracts && python -m pytest tests/test_place_schema.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_contracts.validation'`.

- [ ] **Step 3: Implement `validation.py`**

`contracts/src/mt_contracts/validation.py`:
```python
"""Schema loading and validation. One resolving registry so tile.schema.json can
$ref place.schema.json across files. Also rejects non-finite floats, which
json.loads accepts and JSON Schema bounds cannot catch (Principle 10)."""
from __future__ import annotations

import functools
import json
import math
import pathlib

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

_SCHEMA_DIR = pathlib.Path(__file__).resolve().parents[2] / "schemas"


@functools.lru_cache
def load_schema(name: str) -> dict:
    return json.loads((_SCHEMA_DIR / f"{name}.schema.json").read_text())


@functools.lru_cache
def _registry() -> Registry:
    reg = Registry()
    for path in _SCHEMA_DIR.glob("*.schema.json"):
        schema = json.loads(path.read_text())
        reg = reg.with_resource(schema["$id"], Resource.from_contents(schema))
    return reg


@functools.lru_cache
def validator_for(name: str) -> Draft202012Validator:
    return Draft202012Validator(load_schema(name), registry=_registry())


def _reject_non_finite(node) -> None:
    if isinstance(node, float) and not math.isfinite(node):
        raise ValueError("non-finite float (NaN/Infinity) is not permitted")
    if isinstance(node, dict):
        for v in node.values():
            _reject_non_finite(v)
    elif isinstance(node, list):
        for v in node:
            _reject_non_finite(v)


def validate_instance(name: str, instance: dict) -> None:
    _reject_non_finite(instance)          # defence JSON Schema can't express
    validator_for(name).validate(instance)


def is_valid(name: str, instance: dict) -> bool:
    try:
        validate_instance(name, instance)
        return True
    except Exception:
        return False
```

- [ ] **Step 4: Write `place.schema.json`**

`contracts/schemas/place.schema.json`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://contracts.making-tracks.app/place/1",
  "title": "Place",
  "description": "Read-only place record delivered inside a tile. Fields per spec §5.4; caps + guards per §5.5.",
  "type": "object",
  "additionalProperties": false,
  "required": ["place_id", "name", "lat", "lon", "category", "tier", "score", "source_refs"],
  "properties": {
    "place_id": {"type": "string", "pattern": "^mt1_[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$"},
    "name": {"type": "string", "minLength": 1, "maxLength": 200, "pattern": "^[^\\u0000-\\u001f\\u007f-\\u009f\\u200b\\u2028\\u2029\\u202a-\\u202e\\u2066-\\u2069\\ufeff]*$"},
    "alt_names": {"type": "array", "maxItems": 8, "items": {"type": "string", "minLength": 1, "maxLength": 200, "pattern": "^[^\\u0000-\\u001f\\u007f-\\u009f\\u200b\\u2028\\u2029\\u202a-\\u202e\\u2066-\\u2069\\ufeff]*$"}},
    "lat": {"type": "number", "minimum": -90, "maximum": 90},
    "lon": {"type": "number", "minimum": -180, "maximum": 180},
    "category": {"type": "string", "minLength": 1, "maxLength": 64, "pattern": "^[^\\u0000-\\u001f\\u007f-\\u009f\\u200b\\u2028\\u2029\\u202a-\\u202e\\u2066-\\u2069\\ufeff]*$"},
    "tier": {"type": "integer", "minimum": 1, "maximum": 4},
    "score": {"type": "number", "minimum": 0, "maximum": 1},
    "blurb": {"type": ["string", "null"], "maxLength": 600, "pattern": "^[^\\u0000-\\u001f\\u007f-\\u009f\\u200b\\u2028\\u2029\\u202a-\\u202e\\u2066-\\u2069\\ufeff]*$"},
    "image_url": {"type": ["string", "null"], "maxLength": 2048, "pattern": "^https://[^\\u0000-\\u001f\\u007f-\\u009f\\s]+$"},
    "wikipedia_title": {"type": ["string", "null"], "maxLength": 300, "pattern": "^[^\\u0000-\\u001f\\u007f-\\u009f\\u200b\\u2028\\u2029\\u202a-\\u202e\\u2066-\\u2069\\ufeff]*$"},
    "source_refs": {
      "type": "array", "minItems": 1, "maxItems": 64, "uniqueItems": true,
      "items": {"type": "string", "maxLength": 128, "pattern": "^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9._/-]*$"}
    }
  }
}
```

Note: a `pattern` on a nullable string (`["string","null"]`) applies only when the value is a string — `null` is unaffected, so nullable + guarded is correct. `category` is a free string (the taxonomy is a WP-A3 deliverable, deliberately not enum-pinned). `image_url` is https-only + control/whitespace-free at the schema level; the expected-host allowlist is app config. `source_refs` uses the open canonical-ref grammar (Principle 17: a new source is additive).

- [ ] **Step 5: Write the fixtures**

`contracts/fixtures/place/valid/minimal.json`:
```json
{"place_id": "mt1_00000000000000000000000000", "name": "St. Pancras Clock Tower",
 "lat": 51.5308, "lon": -0.1257, "category": "architecture", "tier": 1,
 "score": 0.82, "source_refs": ["wd:Q42"]}
```
`contracts/fixtures/place/valid/full.json`:
```json
{"place_id": "mt1_00000000000000000000000001", "name": "A Ghost Sign",
 "alt_names": ["Faded Advert"], "lat": 51.51, "lon": -0.09, "category": "oddity",
 "tier": 4, "score": 0.31, "blurb": "A hand-painted advert surviving on brick.",
 "image_url": "https://upload.wikimedia.org/x.jpg", "wikipedia_title": "Ghost sign",
 "source_refs": ["wd:Q123", "osm:node/5", "hehle:1000"]}
```
The invalid fixtures — several carry control/bidi bytes that cannot be hand-typed safely, so **generate them all deterministically** with the script below (it round-trips through `json.dumps`, so control chars survive as proper `\uXXXX` escapes):
```bash
cd contracts && python - <<'PY'
import json, pathlib
full = json.loads(pathlib.Path("fixtures/place/valid/full.json").read_text())
mini = json.loads(pathlib.Path("fixtures/place/valid/minimal.json").read_text())
inv = pathlib.Path("fixtures/place/invalid"); inv.mkdir(parents=True, exist_ok=True)
def w(name, obj): (inv / f"{name}.json").write_text(json.dumps(obj) + "\n")
w("oversize_blurb", {**full, "blurb": "x" * 601})
w("http_image_url", {**full, "image_url": "http://insecure/x.jpg"})
w("bad_tier", {**mini, "tier": 5})
w("lat_out_of_range", {**mini, "lat": 91})
w("control_char_name", {**mini, "name": "Bad\u0007Name"})   # BEL (C0)
w("control_char_blurb", {**full, "blurb": "line1\u001bline2"})  # ESC (ANSI)
w("bidi_name", {**mini, "name": "Museum\u202eevil\u202c"})   # bidi override
w("noncanonical_ref", {**mini, "source_refs": ["wd:Q42 "]})     # trailing space
w("empty_source_refs", {**mini, "source_refs": []})
m = dict(mini); del m["place_id"]; w("missing_place_id", m)
print("wrote", len(list(inv.glob("*.json"))), "invalid fixtures")
PY
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd contracts && python -m pytest tests/test_place_schema.py -q`
Expected: PASS (3 tests, 10 parametrised invalid cases → 12 passed).

- [ ] **Step 7: Commit**

```bash
git add contracts/schemas/place.schema.json contracts/src/mt_contracts/validation.py \
        contracts/fixtures/place contracts/tests/test_place_schema.py contracts/pyproject.toml
git commit -m "Pin place JSON schema with §5.5 caps, SAFE_TEXT + canonical-ref guards, and finite-float check"
```

---

### Task 4: Named caps + deterministic tile codec + place-tile envelope schema

**Files:**
- Create: `contracts/src/mt_contracts/caps.py`, `contracts/src/mt_contracts/tilecodec.py`
- Create: `contracts/schemas/tile.schema.json`
- Create: `contracts/fixtures/tile/valid/*.json`, `contracts/fixtures/tile/invalid/*.json`
- Test: `contracts/tests/test_caps.py`, `contracts/tests/test_tile_schema.py`

**Interfaces:**
- Consumes: `validation`, `place.schema.json` (via `$ref`).
- Produces:
  - `caps.py` — every size cap as a named constant (single source of truth; schema literals asserted equal by test): `NAME_MAX=200`, `ALT_NAMES_MAX=8`, `CATEGORY_MAX=64`, `BLURB_MAX=600`, `IMAGE_URL_MAX=2048`, `WIKIPEDIA_TITLE_MAX=300`, `SOURCE_REFS_MAX=64`, `TILE_ZOOM=10`, `MAX_PLACES_PER_TILE=4000`, `MAX_TILE_UNCOMPRESSED_BYTES=8*1024*1024`, `MAX_TILE_COMPRESSED_BYTES=1*1024*1024`, `PACK_BUDGET_CEILING_BYTES=3_221_225_472`, `CAPS_VERSION=1`; plus `CAPS_SCHEMA_MAP` for the parity meta-test.
  - `caps.select_tile_places(places, max_per_tile=..., byte_budget=...) -> (kept, dropped)` — deterministic overflow bounding BOTH count and serialized bytes.
  - `tilecodec.gzip_tile(obj) -> bytes` (deterministic, `mtime=0`) and `tilecodec.safe_gunzip(data, max_bytes=...) -> bytes` (bomb-safe streaming).
  - `tile.schema.json` — the on-R2 tile envelope. Winner ids only (ratification 3b).

#### Part A — caps + deterministic codec

- [ ] **Step 1: Write the failing caps + codec tests**

`contracts/tests/test_caps.py`:
```python
import gzip
import json
import pytest
from mt_contracts import caps, tilecodec
from mt_contracts.validation import load_schema

def test_schema_literals_match_caps_via_map():
    # Parity is driven from CAPS_SCHEMA_MAP, and every *_MAX constant must appear
    # in it, so a new cap without a matching schema literal trips this test.
    for (schema, path, keyword), const_name in caps.CAPS_SCHEMA_MAP.items():
        node = load_schema(schema)
        for key in path:
            node = node[key]
        assert node[keyword] == getattr(caps, const_name), (schema, path, keyword)
    mapped = set(caps.CAPS_SCHEMA_MAP.values())
    for name in dir(caps):
        if name.endswith("_MAX"):
            assert name in mapped, f"{name} has no parity assertion"

def test_overflow_is_deterministic_and_keeps_best():
    places = [
        {"place_id": "mt1_" + "a" * 26, "tier": 4, "score": 0.1},
        {"place_id": "mt1_" + "b" * 26, "tier": 1, "score": 0.9},
        {"place_id": "mt1_" + "c" * 26, "tier": 2, "score": 0.5},
    ]
    kept, dropped = caps.select_tile_places(places, max_per_tile=2)
    assert [p["place_id"] for p in kept] == ["mt1_" + "b" * 26, "mt1_" + "c" * 26]
    assert [p["place_id"] for p in dropped] == ["mt1_" + "a" * 26]
    assert caps.select_tile_places(places, max_per_tile=2) == (kept, dropped)  # stable

def test_overflow_stable_tie_break_by_place_id():
    a = {"place_id": "mt1_" + "1" * 26, "tier": 1, "score": 0.5}
    b = {"place_id": "mt1_" + "2" * 26, "tier": 1, "score": 0.5}
    kept, _ = caps.select_tile_places([b, a], max_per_tile=1)
    assert [p["place_id"] for p in kept] == ["mt1_" + "1" * 26]  # lower id wins

def test_overflow_also_bounds_bytes():
    # A count under the limit but serialized bytes over budget still sheds.
    big = [{"place_id": "mt1_" + f"{i:026d}"[:26], "tier": 1, "score": 0.5,
            "blob": "x" * 1000} for i in range(50)]
    kept, dropped = caps.select_tile_places(big, max_per_tile=999, byte_budget=5000)
    assert dropped, "byte budget should force some drops"
    assert len(json.dumps(kept).encode()) <= 5000

def test_gzip_is_deterministic():
    obj = {"schema_version": 1, "z": 10, "x": 1, "y": 2, "places": []}
    assert tilecodec.gzip_tile(obj) == tilecodec.gzip_tile(obj)   # no wall-clock mtime

def test_safe_gunzip_roundtrip():
    obj = {"a": 1}
    assert json.loads(tilecodec.safe_gunzip(tilecodec.gzip_tile(obj))) == obj

def test_safe_gunzip_aborts_on_bomb():
    bomb = gzip.compress(b"\0" * (2 * 1024 * 1024))
    with pytest.raises(ValueError):
        tilecodec.safe_gunzip(bomb, max_bytes=1024)   # never fully expands
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd contracts && python -m pytest tests/test_caps.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_contracts.caps'`.

- [ ] **Step 3: Implement `caps.py` and `tilecodec.py`**

`contracts/src/mt_contracts/caps.py`:
```python
"""Named, versioned size caps (single source of truth) + the deterministic
tile-overflow rule. Schema literals are asserted equal to these by test_caps.py,
so a cap can never drift; changing one requires a schema_version bump."""
from __future__ import annotations

import json

CAPS_VERSION = 1

NAME_MAX = 200
ALT_NAMES_MAX = 8
CATEGORY_MAX = 64
BLURB_MAX = 600
IMAGE_URL_MAX = 2048
WIKIPEDIA_TITLE_MAX = 300
SOURCE_REFS_MAX = 64

TILE_ZOOM = 10
MAX_PLACES_PER_TILE = 4000
# Reader hard-reject bound. Chosen with headroom over a realistic dense tile
# (~4000 places at a few hundred bytes each ≈ 1-2 MB). The producer additionally
# enforces this exact bound (select_tile_places byte_budget), so the schema's
# per-field caps × MAX_PLACES_PER_TILE worst case can never actually ship.
MAX_TILE_UNCOMPRESSED_BYTES = 8 * 1024 * 1024
MAX_TILE_COMPRESSED_BYTES = 1 * 1024 * 1024   # pre-decompression bound for a reader

PACK_BUDGET_CEILING_BYTES = 3_221_225_472     # 3 GiB per offline pack (§5.1)

# Drives the schema-literal parity meta-test (test_caps.py). Every *_MAX constant
# must appear as a value here.
CAPS_SCHEMA_MAP = {
    ("place", ("properties", "name"), "maxLength"): "NAME_MAX",
    ("place", ("properties", "alt_names"), "maxItems"): "ALT_NAMES_MAX",
    ("place", ("properties", "category"), "maxLength"): "CATEGORY_MAX",
    ("place", ("properties", "blurb"), "maxLength"): "BLURB_MAX",
    ("place", ("properties", "image_url"), "maxLength"): "IMAGE_URL_MAX",
    ("place", ("properties", "wikipedia_title"), "maxLength"): "WIKIPEDIA_TITLE_MAX",
    ("place", ("properties", "source_refs"), "maxItems"): "SOURCE_REFS_MAX",
    ("tile", ("properties", "places"), "maxItems"): "MAX_PLACES_PER_TILE",
}


def select_tile_places(places, max_per_tile: int = MAX_PLACES_PER_TILE,
                       byte_budget: int = MAX_TILE_UNCOMPRESSED_BYTES):
    """Deterministically choose which places survive a tile's caps.

    Keep the most prominent: sort by (tier ascending — T1 most prominent, then
    score descending, then place_id ascending as a stable tie-break); keep the
    first `max_per_tile` that also fit within `byte_budget` serialized. Returns
    (kept, dropped); the caller (A7) MUST log `dropped` — silent truncation is
    forbidden. Bounds BOTH count and bytes so a schema-valid-but-huge tile can
    never exceed the reader's decode cap.
    """
    ordered = sorted(places, key=lambda p: (p["tier"], -p["score"], p["place_id"]))
    kept, running = [], len(b"[]")
    for p in ordered[:max_per_tile]:
        running += len(json.dumps(p).encode("utf-8")) + 1  # +1 for the comma
        if running > byte_budget:
            break
        kept.append(p)
    dropped = [p for p in ordered if p not in kept]
    return kept, dropped
```

`contracts/src/mt_contracts/tilecodec.py`:
```python
"""Deterministic tile gzip (mtime=0 → stable bytes → stable sha256, Principle 12)
and a bomb-safe streaming gunzip bounded by an uncompressed cap (Principle 10:
even our own tiles are untrusted). Never use gzip.decompress on tile bytes."""
from __future__ import annotations

import gzip
import json
import zlib

from .caps import MAX_TILE_UNCOMPRESSED_BYTES


def gzip_tile(obj) -> bytes:
    raw = json.dumps(obj, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return gzip.compress(raw, mtime=0)   # mtime=0 → identical content, identical bytes


def safe_gunzip(data: bytes, max_bytes: int = MAX_TILE_UNCOMPRESSED_BYTES) -> bytes:
    """Incrementally inflate, raising the moment output would exceed max_bytes.

    Never materialises more than max_bytes, so a small gzip bomb cannot exhaust
    memory. (gzip's ISIZE trailer is attacker-controlled and stored mod 2**32, so
    it cannot be trusted as a size oracle.)
    """
    dec = zlib.decompressobj(wbits=16 + zlib.MAX_WBITS)  # 16 => gzip framing
    out = bytearray()
    for i in range(0, len(data), 65536):
        out += dec.decompress(data[i:i + 65536], max_bytes - len(out) + 1)
        if len(out) > max_bytes:
            raise ValueError("gunzip exceeded max_bytes (possible bomb)")
    if not dec.eof:
        raise ValueError("truncated or trailing-garbage gzip stream")
    return bytes(out)
```

- [ ] **Step 4: Run the caps + codec tests to verify they pass**

Run: `cd contracts && python -m pytest tests/test_caps.py -q`
Expected: PASS (7 passed) — note `test_schema_literals_match_caps_via_map` reads the `tile` schema, so it stays green only after Part B creates it; if you run Step 4 before Part B, filter with `-k "not literals"` and re-run the full file at Step 9.

#### Part B — tile envelope schema

- [ ] **Step 5: Write the failing tile test**

`contracts/tests/test_tile_schema.py`:
```python
import json
from mt_contracts import caps
from mt_contracts.validation import is_valid, validate_instance, load_schema

def test_tile_schema_literals_match_caps():
    schema = load_schema("tile")
    assert schema["properties"]["z"]["const"] == caps.TILE_ZOOM
    assert schema["properties"]["places"]["maxItems"] == caps.MAX_PLACES_PER_TILE

def test_valid_tile_fixture_passes(contracts_root):
    validate_instance("tile", json.loads((contracts_root / "fixtures/tile/valid/one_place.json").read_text()))

def test_tile_with_bad_place_fails(contracts_root):
    assert not is_valid("tile", json.loads((contracts_root / "fixtures/tile/invalid/bad_place.json").read_text()))

def test_tile_wrong_zoom_fails(contracts_root):
    assert not is_valid("tile", json.loads((contracts_root / "fixtures/tile/invalid/wrong_zoom.json").read_text()))

def test_tile_xy_out_of_range_fails(contracts_root):
    assert not is_valid("tile", json.loads((contracts_root / "fixtures/tile/invalid/xy_out_of_range.json").read_text()))
```

- [ ] **Step 6: Run to verify it fails**

Run: `cd contracts && python -m pytest tests/test_tile_schema.py -q`
Expected: FAIL — fixtures / schema do not exist yet.

- [ ] **Step 7: Write `tile.schema.json`**

`contracts/schemas/tile.schema.json`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://contracts.making-tracks.app/tile/1",
  "title": "PlaceTile",
  "description": "A z10 geographic cell of places. Served gzip-compressed (mtime=0) at {publish_version}/tiles/10/{x}/{y}.json.gz. Carries winner place_ids only.",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "z", "x", "y", "places"],
  "properties": {
    "schema_version": {"type": "integer", "const": 1},
    "z": {"type": "integer", "const": 10},
    "x": {"type": "integer", "minimum": 0, "maximum": 1023},
    "y": {"type": "integer", "minimum": 0, "maximum": 1023},
    "places": {
      "type": "array", "maxItems": 4000,
      "items": {"$ref": "https://contracts.making-tracks.app/place/1"}
    }
  }
}
```

- [ ] **Step 8: Write the fixtures**

`contracts/fixtures/tile/valid/one_place.json`:
```json
{"schema_version": 1, "z": 10, "x": 511, "y": 340,
 "places": [{"place_id": "mt1_00000000000000000000000000", "name": "St. Pancras Clock Tower",
             "lat": 51.5308, "lon": -0.1257, "category": "architecture", "tier": 1,
             "score": 0.82, "source_refs": ["wd:Q42"]}]}
```
`contracts/fixtures/tile/invalid/bad_place.json` — same, but the inner place has `"tier": 9`.
`contracts/fixtures/tile/invalid/wrong_zoom.json` — same as valid but `"z": 11`.
`contracts/fixtures/tile/invalid/xy_out_of_range.json` — same as valid but `"x": 1024`.

- [ ] **Step 9: Run the full Task-4 suite to verify it passes**

Run: `cd contracts && python -m pytest tests/test_caps.py tests/test_tile_schema.py -q`
Expected: PASS (12 passed).

- [ ] **Step 10: Commit**

```bash
git add contracts/src/mt_contracts/caps.py contracts/src/mt_contracts/tilecodec.py \
        contracts/tests/test_caps.py contracts/schemas/tile.schema.json \
        contracts/fixtures/tile contracts/tests/test_tile_schema.py
git commit -m "Pin caps, deterministic gzip + bomb-safe gunzip, byte-bounded overflow, and tile envelope"
```

---

### Task 5: Manifest schema + checksum reference helper + fixtures

**Files:**
- Create: `contracts/schemas/manifest.schema.json`, `contracts/src/mt_contracts/checksums.py`
- Create: `contracts/fixtures/manifest/valid/*.json`, `contracts/fixtures/manifest/invalid/*.json`
- Test: `contracts/tests/test_manifest_schema.py`

**Interfaces:**
- Consumes: `validation`.
- Produces: `manifest.schema.json` (self-contained; the app can verify every tile + the basemap it references); `checksums.sha256_hex(data: bytes) -> str` (lowercase hex) that A7 fills and B3/B7 verify.

- [ ] **Step 1: Write the failing test**

`contracts/tests/test_manifest_schema.py`:
```python
import hashlib
import json
from mt_contracts.validation import is_valid, validate_instance
from mt_contracts.checksums import sha256_hex

def test_valid_manifest_passes(contracts_root):
    validate_instance("manifest", json.loads((contracts_root / "fixtures/manifest/valid/uk.json").read_text()))

def test_manifest_missing_provenance_fails(contracts_root):
    assert not is_valid("manifest", json.loads((contracts_root / "fixtures/manifest/invalid/no_provenance.json").read_text()))

def test_manifest_empty_provenance_fails(contracts_root):
    assert not is_valid("manifest", json.loads((contracts_root / "fixtures/manifest/invalid/empty_provenance.json").read_text()))

def test_manifest_bad_checksum_length_fails(contracts_root):
    assert not is_valid("manifest", json.loads((contracts_root / "fixtures/manifest/invalid/bad_checksum.json").read_text()))

def test_manifest_traversal_filename_fails(contracts_root):
    assert not is_valid("manifest", json.loads((contracts_root / "fixtures/manifest/invalid/traversal_filename.json").read_text()))

def test_sha256_hex_matches_hashlib():
    data = b"making tracks"
    assert sha256_hex(data) == hashlib.sha256(data).hexdigest()
    assert len(sha256_hex(data)) == 64
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd contracts && python -m pytest tests/test_manifest_schema.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_contracts.checksums'`.

- [ ] **Step 3: Implement `checksums.py`**

`contracts/src/mt_contracts/checksums.py`:
```python
"""Reference checksum for every `sha256` field in the manifest contract.
A7 fills these; B3/B7 verify against them (resumable + checksum-verified, §5.3)."""
from __future__ import annotations

import hashlib


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()
```

- [ ] **Step 4: Write `manifest.schema.json`**

`contracts/schemas/manifest.schema.json`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://contracts.making-tracks.app/manifest/1",
  "title": "RegionManifest",
  "description": "Per-region, per-publish manifest. Written last, atomically (§5.2). Self-contained: the app can verify every tile and the basemap it references. Untrusted input (defence in depth): every string is bounded, filenames cannot traverse.",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "min_reader_version", "region", "publish_version",
               "tile_z", "tiles", "counts", "basemap", "provenance"],
  "properties": {
    "schema_version": {"type": "integer", "const": 1},
    "min_reader_version": {"type": "integer", "minimum": 1},
    "region": {"type": "string", "minLength": 1, "maxLength": 64, "pattern": "^[a-z][a-z0-9_]*$"},
    "publish_version": {"type": "string", "pattern": "^[0-9]{8}T[0-9]{6}Z$"},
    "generated_at": {"type": "string", "maxLength": 32, "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$"},
    "tile_z": {"type": "integer", "const": 10},
    "tiles": {
      "type": "array", "maxItems": 1048576,
      "items": {
        "type": "object", "additionalProperties": false,
        "required": ["x", "y", "sha256", "bytes"],
        "properties": {
          "x": {"type": "integer", "minimum": 0, "maximum": 1023},
          "y": {"type": "integer", "minimum": 0, "maximum": 1023},
          "sha256": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
          "bytes": {"type": "integer", "minimum": 1, "maximum": 1048576}
        }
      }
    },
    "counts": {
      "type": "object", "additionalProperties": false, "required": ["total", "by_tier"],
      "properties": {
        "total": {"type": "integer", "minimum": 0},
        "by_tier": {"type": "array", "minItems": 4, "maxItems": 4, "items": {"type": "integer", "minimum": 0}}
      }
    },
    "basemap": {
      "type": "object", "additionalProperties": false,
      "required": ["filename", "maxzoom", "sha256", "bytes", "bbox"],
      "properties": {
        "filename": {"type": "string", "maxLength": 128, "pattern": "^[a-z0-9][a-z0-9._-]{0,123}\\.pmtiles$"},
        "maxzoom": {"type": "integer", "minimum": 0, "maximum": 15},
        "sha256": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
        "bytes": {"type": "integer", "minimum": 1, "maximum": 3221225472},
        "bbox": {"type": "array", "minItems": 4, "maxItems": 4, "items": {"type": "number", "minimum": -180, "maximum": 180}}
      }
    },
    "provenance": {
      "type": "array", "minItems": 1, "maxItems": 32,
      "description": "Prompt-version set that produced this tiering (§5.2 + task_id fix).",
      "items": {
        "type": "object", "additionalProperties": false,
        "required": ["task_id", "model", "prompt_version"],
        "properties": {
          "task_id": {"type": "string", "enum": ["curiosity", "blurb", "category", "reconcile"]},
          "model": {"type": "string", "minLength": 1, "maxLength": 128},
          "prompt_version": {"type": "string", "minLength": 1, "maxLength": 64}
        }
      }
    }
  }
}
```

Note: `basemap.filename` is anchored, char-classed and length-capped so a hostile manifest cannot path-traverse the basemap cache directory (`../`, leading `/`, control chars, and an unbounded length are all rejected). `tiles`/`provenance` are bounded (parse-time DoS). `min_reader_version` lets the data declare a reader floor (a reader also refuses when its own max < this — see CONTRACTS.md §8).

- [ ] **Step 5: Write the fixtures**

`contracts/fixtures/manifest/valid/uk.json`:
```json
{"schema_version": 1, "min_reader_version": 1, "region": "uk",
 "publish_version": "20260714T120000Z", "generated_at": "2026-07-14T12:00:00Z",
 "tile_z": 10,
 "tiles": [{"x": 511, "y": 340, "sha256": "0000000000000000000000000000000000000000000000000000000000000000", "bytes": 812}],
 "counts": {"total": 1, "by_tier": [1, 0, 0, 0]},
 "basemap": {"filename": "uk.pmtiles", "maxzoom": 14,
             "sha256": "1111111111111111111111111111111111111111111111111111111111111111",
             "bytes": 1463177229, "bbox": [-8.65, 49.84, 1.77, 60.86]},
 "provenance": [{"task_id": "curiosity", "model": "open-weight-x", "prompt_version": "curiosity-v3"}]}
```
Generate the invalid fixtures deterministically:
```bash
cd contracts && python - <<'PY'
import json, pathlib
v = json.loads(pathlib.Path("fixtures/manifest/valid/uk.json").read_text())
inv = pathlib.Path("fixtures/manifest/invalid"); inv.mkdir(parents=True, exist_ok=True)
def w(name, obj): (inv / f"{name}.json").write_text(json.dumps(obj) + "\n")
np = dict(v); del np["provenance"]; w("no_provenance", np)
w("empty_provenance", {**v, "provenance": []})
bad = json.loads(json.dumps(v)); bad["tiles"][0]["sha256"] = "abc"; w("bad_checksum", bad)
trav = json.loads(json.dumps(v)); trav["basemap"]["filename"] = "../../../etc/evil.pmtiles"; w("traversal_filename", trav)
print("wrote invalid manifest fixtures")
PY
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd contracts && python -m pytest tests/test_manifest_schema.py -q`
Expected: PASS (6 passed).

- [ ] **Step 7: Commit**

```bash
git add contracts/schemas/manifest.schema.json contracts/src/mt_contracts/checksums.py \
        contracts/fixtures/manifest contracts/tests/test_manifest_schema.py
git commit -m "Pin manifest schema (traversal-safe basemap, bounded arrays, provenance) + checksum helper"
```

---

### Task 6: Region-config schema + real UK/Malaysia configs + measured basemap budget

**Measured basemap sizes** — `pmtiles extract` against the live Protomaps planet build `20260714.pmtiles` (136 GB), min-zoom 0, `overfetch 0.05`. The two **v1 pack rows (z14) are exact on-disk bytes from real extracts**; other zooms are the tool's own rounded dry-run archive-size report (approximate); Malaysia z13 is also exact (a real extract cross-check, 112,289,127 bytes):

| Region | z11 | z12 | z13 | z14 (real) | z15 |
|---|---|---|---|---|---|
| UK (`-8.65,49.84,1.77,60.86`) | ~147 MB | ~341 MB | ~730 MB | **1,463,177,229 B (1.46 GB)** | ~3.0 GB |
| Malaysia (`99.64,0.85,119.27,7.36`) | ~21 MB | ~52 MB | 112,289,127 B | **223,155,574 B (223 MB)** | ~447 MB |

**Decision (§5.1 budget = "low single-digit GB on WiFi"): max basemap zoom = 14.** At z14, UK = 1.46 GB and Malaysia = 223 MB (real, validated MVT archives) — both comfortably single-digit GB, so **country-granularity whole-file packs are viable for both v1 regions; no sub-region tiling required.** z15 stays a per-region knob (schema supports it) but is the ceiling — UK z15 ≈ 3.0 GB sits at the top of budget and would be the first candidate for sub-region cutting if street detail proves insufficient. Pack ceiling `PACK_BUDGET_CEILING_BYTES = 3_221_225_472` (3 GiB), in `caps.py`. Place tiles add negligibly (basemap dominates).

**Files:**
- Create: `contracts/schemas/region-config.schema.json`, `contracts/basemap-budget.json`
- Create: `contracts/regions/uk.json`, `contracts/regions/malaysia.json`
- Test: `contracts/tests/test_region_config_schema.py`, `contracts/tests/test_basemap_budget.py`

**Interfaces:**
- Consumes: `validation`, `caps.PACK_BUDGET_CEILING_BYTES`.
- Produces: `region-config.schema.json` (A1 region param, A7 extract bbox+maxzoom, B7 pack budget); `regions/{uk,malaysia}.json`; `basemap-budget.json`.

- [ ] **Step 1: Write the failing tests**

`contracts/tests/test_region_config_schema.py`:
```python
import json
from mt_contracts.validation import validate_instance, is_valid

def test_uk_config_valid(contracts_root):
    validate_instance("region-config", json.loads((contracts_root / "regions/uk.json").read_text()))

def test_malaysia_config_valid(contracts_root):
    validate_instance("region-config", json.loads((contracts_root / "regions/malaysia.json").read_text()))

def test_region_id_pattern_rejects_uppercase(contracts_root):
    cfg = json.loads((contracts_root / "regions/uk.json").read_text())
    cfg["region_id"] = "UK"
    assert not is_valid("region-config", cfg)  # Principle 17: lowercase additive ids
```

`contracts/tests/test_basemap_budget.py`:
```python
import json
from mt_contracts import caps

def test_budget_ceiling_matches_caps_constant(contracts_root):
    budget = json.loads((contracts_root / "basemap-budget.json").read_text())
    assert budget["ceiling_bytes"] == caps.PACK_BUDGET_CEILING_BYTES  # single-sourced

def test_every_region_config_stays_under_ceiling(contracts_root):
    budget = json.loads((contracts_root / "basemap-budget.json").read_text())
    for region in ("uk", "malaysia"):
        cfg = json.loads((contracts_root / f"regions/{region}.json").read_text())
        assert cfg["basemap"]["size_budget_bytes"] <= caps.PACK_BUDGET_CEILING_BYTES
        mz = cfg["basemap"]["maxzoom"]
        row = next(m for m in budget["measurements"] if m["region"] == region and m["maxzoom"] == mz)
        # the config's declared measured size must match the budget table (exact for z14)
        assert cfg["basemap"]["measured_archive_bytes"] == row["archive_bytes"]
        assert row["exact"] is True   # the shipped maxzoom must rest on a real measurement
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd contracts && python -m pytest tests/test_region_config_schema.py tests/test_basemap_budget.py -q`
Expected: FAIL — schema/config/budget files absent.

- [ ] **Step 3: Write `region-config.schema.json`**

`contracts/schemas/region-config.schema.json`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://contracts.making-tracks.app/region-config/1",
  "title": "RegionConfig",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "region_id", "display_name", "bbox", "languages", "sources", "basemap"],
  "properties": {
    "schema_version": {"type": "integer", "const": 1},
    "region_id": {"type": "string", "pattern": "^[a-z][a-z0-9_]*$", "maxLength": 64},
    "display_name": {"type": "string", "minLength": 1, "maxLength": 80, "pattern": "^[^\\u0000-\\u001f\\u007f-\\u009f\\u200b\\u2028\\u2029\\u202a-\\u202e\\u2066-\\u2069\\ufeff]*$"},
    "bbox": {"type": "array", "minItems": 4, "maxItems": 4, "items": {"type": "number", "minimum": -180, "maximum": 180}},
    "languages": {"type": "array", "minItems": 1, "maxItems": 16, "items": {"type": "string", "pattern": "^[a-z]{2,3}$"}},
    "sources": {
      "type": "object", "additionalProperties": false,
      "required": ["wikidata", "wikipedia", "osm", "historic_england", "open_plaques", "national_register"],
      "properties": {
        "wikidata": {"type": "boolean"},
        "wikipedia": {"type": "boolean"},
        "osm": {"type": "boolean"},
        "historic_england": {"type": "boolean"},
        "open_plaques": {"type": "boolean"},
        "national_register": {
          "description": "Optional per-region register (Principle 17). null = none / feasibility pending (Malaysia, WP-A1d).",
          "type": ["object", "null"], "additionalProperties": false,
          "required": ["id", "enabled"],
          "properties": {"id": {"type": "string", "maxLength": 64, "pattern": "^[a-z][a-z0-9_]*$"}, "enabled": {"type": "boolean"}}
        }
      }
    },
    "basemap": {
      "type": "object", "additionalProperties": false,
      "required": ["source_pmtiles", "maxzoom", "pack_granularity", "size_budget_bytes", "measured_archive_bytes"],
      "properties": {
        "source_pmtiles": {"type": "string", "maxLength": 2048, "pattern": "^https://[^\\u0000-\\u001f\\u007f-\\u009f\\s]+$"},
        "maxzoom": {"type": "integer", "minimum": 0, "maximum": 15},
        "pack_granularity": {"type": "string", "enum": ["country", "subregion"]},
        "subregions": {
          "type": "array", "maxItems": 256,
          "items": {"type": "object", "additionalProperties": false, "required": ["id", "bbox"],
                    "properties": {"id": {"type": "string", "pattern": "^[a-z][a-z0-9_]*$", "maxLength": 64},
                                   "bbox": {"type": "array", "minItems": 4, "maxItems": 4, "items": {"type": "number", "minimum": -180, "maximum": 180}}}}
        },
        "size_budget_bytes": {"type": "integer", "minimum": 1, "maximum": 3221225472},
        "measured_archive_bytes": {"type": "integer", "minimum": 1, "maximum": 3221225472}
      }
    }
  }
}
```

- [ ] **Step 4: Write `basemap-budget.json` and the two region configs**

`contracts/basemap-budget.json`:
```json
{
  "ceiling_bytes": 3221225472,
  "budget_note": "§5.1 'low single-digit GB on WiFi'; 3 GiB per-pack ceiling. maxzoom 14 chosen for v1.",
  "source_build": "https://build.protomaps.com/20260714.pmtiles",
  "method": "pmtiles extract --minzoom=0 --maxzoom=Z --bbox=... . exact=true rows are real on-disk extract byte counts; exact=false are the tool's rounded dry-run archive-size report.",
  "measurements": [
    {"region": "uk", "maxzoom": 11, "archive_bytes": 147000000, "exact": false},
    {"region": "uk", "maxzoom": 12, "archive_bytes": 341000000, "exact": false},
    {"region": "uk", "maxzoom": 13, "archive_bytes": 730000000, "exact": false},
    {"region": "uk", "maxzoom": 14, "archive_bytes": 1463177229, "exact": true},
    {"region": "uk", "maxzoom": 15, "archive_bytes": 3000000000, "exact": false},
    {"region": "malaysia", "maxzoom": 11, "archive_bytes": 21000000, "exact": false},
    {"region": "malaysia", "maxzoom": 12, "archive_bytes": 52000000, "exact": false},
    {"region": "malaysia", "maxzoom": 13, "archive_bytes": 112289127, "exact": true},
    {"region": "malaysia", "maxzoom": 14, "archive_bytes": 223155574, "exact": true},
    {"region": "malaysia", "maxzoom": 15, "archive_bytes": 447000000, "exact": false}
  ]
}
```

`contracts/regions/uk.json`:
```json
{"schema_version": 1, "region_id": "uk", "display_name": "United Kingdom",
 "bbox": [-8.65, 49.84, 1.77, 60.86], "languages": ["en"],
 "sources": {"wikidata": true, "wikipedia": true, "osm": true,
             "historic_england": true, "open_plaques": true, "national_register": null},
 "basemap": {"source_pmtiles": "https://build.protomaps.com/20260714.pmtiles",
             "maxzoom": 14, "pack_granularity": "country",
             "size_budget_bytes": 2000000000, "measured_archive_bytes": 1463177229}}
```

`contracts/regions/malaysia.json`:
```json
{"schema_version": 1, "region_id": "malaysia", "display_name": "Malaysia",
 "bbox": [99.64, 0.85, 119.27, 7.36], "languages": ["en"],
 "sources": {"wikidata": true, "wikipedia": true, "osm": true,
             "historic_england": false, "open_plaques": true,
             "national_register": {"id": "malaysia_heritage", "enabled": false}},
 "basemap": {"source_pmtiles": "https://build.protomaps.com/20260714.pmtiles",
             "maxzoom": 14, "pack_granularity": "country",
             "size_budget_bytes": 500000000, "measured_archive_bytes": 223155574}}
```

(Malaysia's `national_register.enabled: false` encodes the §4 / WP-A1d feasibility-pending state; `historic_england: false` because it is UK-only — Principle 17: no source is load-bearing.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd contracts && python -m pytest tests/test_region_config_schema.py tests/test_basemap_budget.py -q`
Expected: PASS (5 passed).

- [ ] **Step 6: Commit**

```bash
git add contracts/schemas/region-config.schema.json contracts/basemap-budget.json \
        contracts/regions contracts/tests/test_region_config_schema.py contracts/tests/test_basemap_budget.py
git commit -m "Pin region-config schema, measured (exact z14) basemap budget, and real UK/Malaysia configs"
```

---

### Task 7: Full-suite green + CONTRACTS.md authoritative doc + consumer map + self-review

**Files:**
- Create: `contracts/CONTRACTS.md`, `contracts/README.md`
- Test: entire `contracts/tests` suite green.

- [ ] **Step 1: Run the whole suite**

Run: `cd contracts && python -m pytest -q`
Expected: PASS (all tests from Tasks 1–6 green).

- [ ] **Step 2: Write `CONTRACTS.md`**

Author `contracts/CONTRACTS.md` (prose pointing at the machine artifacts as source of truth):

1. **Status & immutability rules** — schemas are versioned (`versions.json`); the `place_id` scheme and the frozen vectors are immutable once shipped (Principle 7, validation included); changing any shipped shape is a `schema_version` bump, never an in-place edit; all caps live in `caps.py`.
2. **`place_id`** — the `mt1_<26 Crockford base32>` grammar; the **exact frozen mint-key canonicalization** (lowercase source prefix, ASCII, no whitespace: `wd:Q123` / `osm:{node|way|relation}/456` / `hehle:1234567` / `plaque:openplaques/9876`; hehle = Historic England List Entry) with per-source **conformance vectors** any reimplementation must reproduce; the **APPEND-ONLY additive source path** — a new source is a new alternative in `_SOURCE_IDENT_GRAMMAR` plus a priority entry plus new conformance vectors, and nothing else; it never alters the canonical form or minted id of any existing source, and the frozen vectors remain untouched forever; derivation-then-registry-ownership; anchor priority (QID > OSM node>way>rel > Historic England > Open Plaques) — **mint-time determinism only, no meaning after mint**; QID-merge survival via union-of-refs; **validation covers all `KNOWN_ID_SCHEMES`** so shipped ids validate forever; **ambiguous multi-place ref matches RAISE** (`AmbiguousRefsError`, carrying candidate ids) rather than silently merging (Principle 9); `superseded_by` soft de-dup resolved **transitively** to a terminal winner with a **no-cycle** write invariant; **published tiles carry the winner id only** (`tile_winner_violations` guard) — loser ids live forever in the registry + user `place_snapshots` and resolve for rendering with **no app-side special case**; tombstones.
3. **Place JSON** — field table (§5.4); the §5.5 caps (named in `caps.py`, single-sourced, schema literals asserted equal + a `*_MAX` coverage meta-test); the `SAFE_TEXT` guard on every string incl. nullable `blurb`/`wikipedia_title` (and why LRM/RLM are allowed but bidi overrides are not); `image_url` https-only + control/whitespace-free (host allowlist is app config); non-finite floats rejected at the Python layer; `source_refs` open canonical-ref grammar.
4. **Place tile** — z10 XYZ envelope; on-R2 path `{publish_version}/tiles/10/{x}/{y}.json.gz`; **gzip with `mtime=0`** (deterministic bytes / stable sha256); reader uses **`tilecodec.safe_gunzip`** bounded by `MAX_TILE_UNCOMPRESSED_BYTES` (never `gzip.decompress`); `MAX_PLACES_PER_TILE=4000`; **deterministic, byte-bounded overflow** `caps.select_tile_places` (keep by tier asc, score desc, place_id asc; drop the tail; A7 **logs** every dropped place; bounds BOTH count and serialized bytes so the reader cap can never be legitimately exceeded).
5. **Manifest** — tile index + per-tile sha256 + basemap descriptor + prompt-version provenance (with `task_id`, `minItems:1`); **traversal-safe `basemap.filename`**; bounded `tiles`/`provenance`; written last, atomically; versioned publish paths; rollback = repoint the manifest.
6. **Region config** — fields; region **and source** modularity (no enums); per-region sources optional; https-only `source_pmtiles`.
7. **Basemap pack budget** — the measured table (exact z14: UK 1,463,177,229 B; MY 223,155,574 B) and the maxzoom-14 decision; `caps.PACK_BUDGET_CEILING_BYTES` (single-sourced with `basemap-budget.json`).
8. **Versioning & compatibility** — `check_version` semantics (TOO_NEW → keep cache / prompt update; TOO_OLD → refuse; fresh install on too-old app → "update required"); `MIN_SUPPORTED_VERSIONS` is the documented window floor (today [1,1]); a reader also refuses when its own max understood version < a manifest's `min_reader_version` (the data-declared floor), which composes with the schema_version check.
9. **Consumer map:**

   | Consumer WP | Consumes from A0 |
   |---|---|
   | A1 | `regions/*.json`, `region-config.schema.json` |
   | A2 | `place_id.py`, `registry.py`, `registry-record.schema.json` (mint + union-of-refs + ambiguity + tombstone/supersede invariants) |
   | A7 | `tile.schema.json`, `manifest.schema.json`, `checksums.sha256_hex`, `tilecodec.gzip_tile`, `caps.select_tile_places`, `registry.tile_winner_violations`, region `basemap` block (bbox + maxzoom 14) |
   | B1 | `place.schema.json` (fields seeding `place_snapshots`) |
   | B3 | `manifest.schema.json`, `tile.schema.json`, `versions.check_version`, `tilecodec.safe_gunzip` (fetch, bomb-safe decode, invalidation) |
   | B7 | `basemap-budget.json`, `caps.PACK_BUDGET_CEILING_BYTES`, region `basemap` block (pack size, maxzoom, granularity, refresh vs `publish_version`) |

`contracts/README.md`: one paragraph — "Authoritative cross-track contracts for Making Tracks. See CONTRACTS.md. Machine source of truth: `schemas/`, `versions.json`, `regions/`, `basemap-budget.json`, `src/mt_contracts/`. `pip install -e '.[dev]' && pytest` validates the whole contract."

- [ ] **Step 3: Self-review against the spec (checklist — run yourself)**

- **Spec coverage:** §5.1 budget → T6 (exact z14). §5.2 tile/manifest/place_id/registry → T2,4,5. §5.4 fields → T3. §5.5 caps+guards → T3,4,5. §5.6 versioning → T1 + every schema. §8 WP-A0 row → all present. §7 QID-merge + tombstone regression → T2.
- **Placeholder scan:** no "TBD"/"add validation" — every step carries literal content.
- **Type consistency:** `PLACE_ID`/`SHA256_HEX`/`SAFE_TEXT`/`CANONICAL_REF`/`HTTPS_URL`/`PUBLISH_VERSION` strings identical everywhere; `z==10` const everywhere; `versions.json` == `SCHEMA_VERSIONS`; caps == schema literals (meta-test).

- [ ] **Step 4: Commit**

```bash
git add contracts/CONTRACTS.md contracts/README.md
git commit -m "Add authoritative CONTRACTS.md, consumer map, and README"
```

---

## Review Record

**Author self-review** — every WP-A0 deliverable in §8's row maps to a task: tile format (T4), manifest (T5), place JSON (T3), `place_id` (T2), region config (T6), measured UK/Malaysia basemap sizes (T6, exact z14 from real extracts). §5.6 versioning (T1). §5.5 caps+guards (T3/T4/T5). §7 QID-merge stability + tombstone-not-remint have regression tests that fail an anchor-only implementation (T2). No placeholders; shared regex/const strings are identical wherever they appear.

**Ratifications (fable, thread `wp/a0`)** — opaque hash of a frozen anchor; anchor priority QID>OSM(node>way>rel)>HE>Open Plaques; soft-supersede (keep-both, transitive, winner-only); exact mint-key canonicalization + per-source conformance vectors; caps as named versioned constants + deterministic logged overflow; validation accepts all `KNOWN_ID_SCHEMES` forever; `resolve_by_refs` raises on ambiguity (carrying candidate ids); append-only source grammar (never alters existing sources or frozen vectors).

**Adversarial review (5 subagent critics + cross-examination, per AGENTS.md gate)** — raised 30 findings across spec-fidelity, coherence, feasibility, security, and test-quality; after cross-examination the material fixes below were folded in (all others were confirmed already-correct or duplicates):
- *Blockers:* `control_char` fixture carried a raw byte that broke JSON parsing (now escaped + script-generated); `cd /contracts` was an absolute path (now `cd contracts`); `basemap.filename` was path-traversable (now anchored/char-classed/capped).
- *Correctness/security:* `blurb`/`wikipedia_title` lacked control-char guards; `image_url` body unconstrained; `source_refs`/registry refs allowed whitespace → false-merge risk; manifest `tiles`/`provenance` unbounded (DoS) + `provenance` now `minItems:1`; gzip decode had no bomb guard and no `mtime=0` determinism; non-finite floats slipped numeric bounds; source set was hard-enumerated (blocked Malaysia register, Principle 17) → made append-only additive; the `SAFE_TEXT` guard extended to C1/bidi/line-sep/zero-width while preserving RTL marks.
- *Test quality:* the scheme-bump validation test was tautological (now tests `_build_place_id_re` directly); the QID-merge test passed an anchor-only impl (now rides a non-anchor ref); "winner-only in tiles" had no executable test (now `tile_winner_violations` + test); added an independent hand-computed frozen-vector cross-check; caps parity is now map-driven with a `*_MAX` coverage meta-test.
- *Empirical:* the "measured" sizes were the tool's rounded report; the two v1 pack rows (UK z14, MY z14) are now **exact on-disk bytes from real extracts** (1,463,177,229 and 223,155,574), with per-row `exact` flags and a guard test that the shipped maxzoom rests on a real measurement.
