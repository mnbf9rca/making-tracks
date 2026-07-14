# WP-A0 (Contracts) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce the authoritative, executable cross-track contracts — `place_id` format, place JSON, place-tile, manifest, region-config schemas, the versioning policy, and the measured basemap pack budget — that every other work package builds against, before any of them starts.

**Architecture:** Contracts are made *executable*, not just prose. A standalone, dependency-free Python package `mt-contracts` under `/contracts/` ships (a) language-neutral JSON Schema 2020-12 files, (b) golden fixtures (valid + invalid) that both the Python pipeline and the Swift app validate their encoders/decoders against, (c) a reference `place_id` mint/validate implementation with a *frozen golden-vector tripwire* enforcing Principle 7, and (d) a version registry encoding the §5.6 compatibility policy. A human-readable `CONTRACTS.md` ties them together and records what each downstream WP consumes. The basemap pack budget is fixed from **real measurements** taken against the live Protomaps planet build.

**Tech Stack:** Python 3.11+, `jsonschema>=4.21` (2020-12 support), `pytest`, `pmtiles` CLI (measurement only, already run). JSON Schema draft 2020-12. Crockford base32 for `place_id`.

## Global Constraints

Every task's requirements implicitly include these. Values are copied verbatim from the spec / PRINCIPLES.md.

- **Python 3.11+.** Package is `src`-layout, name `mt-contracts`, import root `mt_contracts`.
- **`place_id` is forever (Principle 7).** Once shipped, never reassigned or reformatted. The frozen golden-vector test (Task 2) is the tripwire; if it breaks, the change is wrong.
- **Everything that crosses a boundary is versioned (Principle 11 / §5.6).** Manifest, tile, place, region-config, and the ID registry each carry a `schema_version`; readers declare a max understood version and degrade — never silently misread newer/older data.
- **Determinism (Principle 12).** No wall-clock or randomness in any *output* value. Timestamps that appear in artifacts (`manifest.generated_at`) are metadata only and never feed an id, a hash, or an ordering. `place_id` derivation is a pure function of a frozen mint key.
- **All source data is untrusted (Principle 10 / §5.5).** Schemas enforce, on **every** source- or LLM-derived string (incl. nullable ones like `blurb`/`wikipedia_title`): length caps; the shared **`SAFE_TEXT`** guard (rejects C0, DEL, C1, line/paragraph separators U+2028/2029, bidi overrides+isolates U+202A–202E/2066–2069, zero-width U+200B/FEFF — but **not** LRM/RLM U+200E/200F, so legitimate RTL names such as Jawi survive); coordinate bounds; `https://`-only URLs with no control/whitespace in the body; bounded array sizes; and the shared **canonical-ref** grammar (`^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9._/-]*$`) on every ref field. Numeric fields additionally reject non-finite floats (`NaN`/`Infinity`) at the Python validation layer, which JSON Schema `minimum`/`maximum` cannot catch. The app treats even our own tiles as untrusted (defence in depth): tiles are decompressed by a **bomb-safe streaming decoder** bounded by `MAX_TILE_UNCOMPRESSED_BYTES` (never `gzip.decompress`, which expands fully before any check).
- **Deterministic tile bytes (Principle 12).** Producers gzip tiles with `mtime=0` so identical content yields identical bytes and a stable per-tile `sha256` across builds; a wall-clock gzip header would flip checksums and break cache invalidation. Enforced by a determinism test.
- **Path convention.** In this plan `/contracts/…` denotes the repo-relative top-level `contracts/` directory. All shell commands run from the repo root and use `cd contracts` (never the absolute `/contracts`).
- **Caps are named, versioned constants (fable ratification, addition 4).** Every size cap lives in `mt_contracts.caps` as a named constant, single-sourced; the JSON Schemas' literal numbers are asserted equal to the constants by test (no drift). Changing a cap requires a `schema_version` bump — never a silent edit. No cap truncates silently: where a cap can be exceeded (places-per-tile), a deterministic overflow rule drops the excess and the drop is logged.
- **Region modularity (Principle 17).** No schema may hard-enum the region set; region ids match `^[a-z][a-z0-9_]*$`. Adding a region is additive.
- **Test-first.** Every schema lands with a failing fixture test before the schema exists; the ID-stability invariants have regression tests (§7).
- **Regions in scope:** `uk`, `malaysia`. **Recall language:** English-only for now (`languages` is per-region config so Malay etc. enable later without structural change).

**Ratified by the design lead.** The `place_id` scheme (Task 2), anchor priority, and soft-supersede model were confirmed by fable on AMQ thread `wp/a0`, with five additions folded in (see the closing Self-Review). Rob retains override until the plan is approved.

---

## File Structure

Language-neutral contract artifacts and the reference implementation live together under a new top-level `/contracts` directory (neutral home consumed by both `/pipeline` and `/ios`; A1 later depends on this package rather than redefining it).

```
/contracts/
  pyproject.toml                      # standalone installable package `mt-contracts`
  README.md                           # one-paragraph pointer to CONTRACTS.md
  CONTRACTS.md                        # AUTHORITATIVE human-readable doc (Task 8)
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
    region-config/{valid,invalid}/*.json  # Task 6
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
    test_versions.py                  # Task 1
    test_place_id.py                  # Task 2
    test_registry.py                  # Task 2
    test_place_schema.py              # Task 3
    test_caps.py                      # Task 4
    test_tile_schema.py               # Task 4
    test_manifest_schema.py           # Task 5
    test_region_config_schema.py      # Task 6
    test_basemap_budget.py            # Task 6
    conftest.py                       # contracts_root fixture path helper
```

Each `*.schema.json` has one responsibility (one artifact shape). Fixtures live beside the schema they exercise. The reference `.py` modules are small and single-purpose so a reviewer can reject one artifact without touching its neighbours.

---

### Task 1: Contracts package scaffold + version registry + §5.6 compatibility policy

**Files:**
- Create: `/contracts/pyproject.toml`
- Create: `/contracts/src/mt_contracts/__init__.py`
- Create: `/contracts/versions.json`
- Create: `/contracts/src/mt_contracts/versions.py`
- Create: `/contracts/tests/conftest.py`
- Test: `/contracts/tests/test_versions.py`

**Interfaces:**
- Consumes: nothing (WP-A0 has no dependencies).
- Produces:
  - `mt_contracts.versions.SCHEMA_VERSIONS: dict[str,int]` — keys `place`, `tile`, `manifest`, `region_config`, `registry_record`, `id_scheme`.
  - `mt_contracts.versions.Compat` — `Enum{OK, TOO_NEW, TOO_OLD}`.
  - `mt_contracts.versions.check_version(reader_max: int, data_version: int, min_supported: int) -> Compat`.
  - `conftest.py` fixture `contracts_root: pathlib.Path`.

- [ ] **Step 1: Write `conftest.py` (shared path helper) and the failing test**

`/contracts/tests/conftest.py`:
```python
import pathlib
import pytest

@pytest.fixture(scope="session")
def contracts_root() -> pathlib.Path:
    # the contracts/ dir: parents[0]=tests/, parents[1]=contracts/
    return pathlib.Path(__file__).resolve().parents[1]
```

`/contracts/tests/test_versions.py`:
```python
import json
from mt_contracts.versions import SCHEMA_VERSIONS, Compat, check_version

REQUIRED_KEYS = {"place", "tile", "manifest", "region_config", "registry_record", "id_scheme"}

def test_versions_json_matches_module(contracts_root):
    on_disk = json.loads((contracts_root / "versions.json").read_text())
    assert on_disk == SCHEMA_VERSIONS

def test_all_version_keys_present():
    assert REQUIRED_KEYS <= set(SCHEMA_VERSIONS)
    assert all(isinstance(v, int) and v >= 1 for v in SCHEMA_VERSIONS.values())

def test_check_version_equal_is_ok():
    assert check_version(reader_max=1, data_version=1, min_supported=1) is Compat.OK

def test_check_version_newer_data_is_too_new():
    assert check_version(reader_max=1, data_version=2, min_supported=1) is Compat.TOO_NEW

def test_check_version_older_within_window_is_ok():
    assert check_version(reader_max=3, data_version=2, min_supported=2) is Compat.OK

def test_check_version_older_below_window_is_too_old():
    assert check_version(reader_max=3, data_version=1, min_supported=2) is Compat.TOO_OLD
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd contracts && python -m pytest tests/test_versions.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_contracts'`.

- [ ] **Step 3: Create the package scaffold**

`/contracts/pyproject.toml`:
```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "mt-contracts"
version = "0.1.0"
description = "Making Tracks cross-track contracts (schemas, place_id, versioning)."
requires-python = ">=3.11"
dependencies = ["jsonschema>=4.21"]

[project.optional-dependencies]
dev = ["pytest>=8"]

[tool.hatch.build.targets.wheel]
packages = ["src/mt_contracts"]

[tool.pytest.ini_options]
pythonpath = ["src"]
testpaths = ["tests"]
```

`/contracts/src/mt_contracts/__init__.py`:
```python
"""Making Tracks cross-track contracts. See /contracts/CONTRACTS.md."""
```

- [ ] **Step 4: Write `versions.json` and `versions.py`**

`/contracts/versions.json`:
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

`/contracts/src/mt_contracts/versions.py`:
```python
"""Schema version registry and the §5.6 reader-compatibility policy.

A reader declares the maximum artifact version it understands (`reader_max`)
and the oldest it still accepts (`min_supported`, the documented back-compat
window floor). check_version() classifies a piece of data accordingly so a
reader can refuse or degrade — never silently misread. (Principle 11.)
"""
from __future__ import annotations

import enum
import json
import pathlib

_VERSIONS_PATH = pathlib.Path(__file__).resolve().parents[2] / "versions.json"

# Loaded once at import; the file is the single source of truth so schemas and
# code can never drift (test_versions_json_matches_module enforces equality).
SCHEMA_VERSIONS: dict[str, int] = json.loads(_VERSIONS_PATH.read_text())


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
Expected: PASS (6 passed).

- [ ] **Step 6: Commit**

```bash
git add contracts/pyproject.toml contracts/src/mt_contracts/__init__.py \
        contracts/versions.json contracts/src/mt_contracts/versions.py \
        contracts/tests/conftest.py contracts/tests/test_versions.py
git commit -m "Add contracts package scaffold, version registry, and §5.6 compatibility policy"
```

---

### Task 2: `place_id` format + reference implementation + registry record shape

This is the highest-stakes artifact in the project. The design resolves the spec's tension (§5.2 "derived from anchor ref" vs "never re-mint when the anchor changes"): **derivation seeds the *first* mint only; the ID registry is authoritative forever after.** `mint_place_id()` is called *only* for a genuinely new cluster; every later run looks a place up by its union-of-refs and reuses the frozen id.

**Files:**
- Create: `/contracts/src/mt_contracts/place_id.py`
- Create: `/contracts/src/mt_contracts/registry.py`
- Create: `/contracts/schemas/registry-record.schema.json`
- Create: `/contracts/fixtures/place_id/frozen_vectors.json`
- Test: `/contracts/tests/test_place_id.py`
- Test: `/contracts/tests/test_registry.py`

**Interfaces:**
- Consumes: `mt_contracts.versions.SCHEMA_VERSIONS`.
- Produces:
  - `place_id.PLACE_ID_RE: re.Pattern` (accepts every `KNOWN_ID_SCHEMES` prefix), `place_id.PLACE_ID_PREFIX: str` (current mint scheme, == `"mt1_"`), `place_id.KNOWN_ID_SCHEMES: frozenset[int]` (monotonic; validation covers all of these forever).
  - `place_id.canonical_ref(source: str, ident: str) -> str` → `"{source}:{ident}"`.
  - `place_id.select_mint_anchor(refs: Iterable[str]) -> str` — deterministic anchor pick.
  - `place_id.mint_place_id(mint_key: str) -> str` — pure, deterministic; raises `ValueError` on a non-canonical `mint_key`.
  - `place_id.MINT_KEY_RE` / `place_id.assert_canonical_mint_key(mint_key) -> None` — the frozen canonicalization grammar.
  - `place_id.is_valid_place_id(value: str) -> bool`.
  - `registry.RegistryRecord` (dataclass), `registry.resolve_by_refs(records, incoming_refs) -> str | None`, `registry.resolve_superseded(records, place_id) -> str` (transitive winner), `registry.assert_no_supersede_cycles(records) -> None`.

- [ ] **Step 1: Write the failing `place_id` tests (format, determinism, anchor priority, frozen vectors)**

`/contracts/tests/test_place_id.py`:
```python
import json
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

def test_shipped_ids_validate_after_a_future_mint_scheme_bump(monkeypatch):
    # Principle 7 applies to VALIDATION, not just minting: once an mt1_ id ships
    # it must validate forever, even after the mint scheme advances. PLACE_ID_RE
    # is built from KNOWN_ID_SCHEMES (which only grows), so simulating the mint
    # scheme moving to 2 must not invalidate an existing mt1_ id.
    from mt_contracts import place_id as pid
    shipped = pid.mint_place_id("wd:Q42")            # an mt1_ id
    monkeypatch.setattr(pid, "_ID_SCHEME_VERSION", 2)
    monkeypatch.setattr(pid, "PLACE_ID_PREFIX", "mt2_")
    assert pid.is_valid_place_id(shipped)            # still valid — validation covers KNOWN schemes

def test_current_mint_scheme_is_a_known_scheme():
    from mt_contracts.place_id import KNOWN_ID_SCHEMES, _ID_SCHEME_VERSION
    assert _ID_SCHEME_VERSION in KNOWN_ID_SCHEMES

def test_canonical_ref():
    assert canonical_ref("wd", "Q42") == "wd:Q42"

def test_mint_rejects_noncanonical_key():
    # Canonicalization is part of the frozen scheme: an unpinned key format is a
    # silent second version of the scheme (fable ratification, addition 1).
    import pytest
    for bad in ["WD:Q42", "wd: Q42", "wd:Q42 ", "osm:Way/456", "wd:Qé", "foo:1"]:
        with pytest.raises(ValueError):
            mint_place_id(bad)

def test_conformance_vectors_cover_every_source_type(contracts_root):
    # At least one (mint_key -> place_id) vector per source type so any
    # reimplementation can prove byte-level conformance.
    import json
    vectors = json.loads((contracts_root / "fixtures/place_id/frozen_vectors.json").read_text())
    prefixes = {row["mint_key"].split(":", 1)[0] for row in vectors}
    assert {"wd", "osm", "hehle", "plaque"} <= prefixes

def test_anchor_priority_prefers_wikidata():
    refs = ["osm:way/10", "wd:Q7", "plaque:openplaques/3"]
    assert select_mint_anchor(refs) == "wd:Q7"

def test_anchor_priority_osm_type_and_numeric_order():
    # node < way < relation; numeric (not lexical) within type
    refs = ["osm:way/2", "osm:node/100", "osm:node/9"]
    assert select_mint_anchor(refs) == "osm:node/9"

def test_anchor_is_order_independent():
    a = select_mint_anchor(["wd:Q9", "osm:node/1", "hehle:5"])
    b = select_mint_anchor(["hehle:5", "osm:node/1", "wd:Q9"])
    assert a == b == "wd:Q9"

def test_frozen_vectors_never_change(contracts_root):
    # Principle 7 tripwire: these (mint_key -> place_id) pairs are shipped
    # contract. If this test fails, the mint algorithm changed and would
    # reassign already-shipped ids. The change is wrong.
    vectors = json.loads(
        (contracts_root / "fixtures/place_id/frozen_vectors.json").read_text()
    )
    for row in vectors:
        assert mint_place_id(row["mint_key"]) == row["place_id"], row["mint_key"]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd contracts && python -m pytest tests/test_place_id.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_contracts.place_id'`.

- [ ] **Step 3: Implement `place_id.py`**

`/contracts/src/mt_contracts/place_id.py`:
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
# ship they must validate forever even after the mint scheme advances to 2
# (Principle 7 applies to validation, not just minting). A scheme bump adds the
# new number here AND to id_scheme in versions.json — it never removes one.
KNOWN_ID_SCHEMES = frozenset({1})
assert _ID_SCHEME_VERSION in KNOWN_ID_SCHEMES, "current mint scheme must be a known scheme"
PLACE_ID_PREFIX = f"mt{_ID_SCHEME_VERSION}_"  # minting emits the current scheme only

# Crockford base32 alphabet: no I, L, O, U (ambiguity-free, case-insensitive).
_CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
_BODY_LEN = 26  # 26 * 5 = 130 bits carrying the lower 128 bits of the digest
# Validation accepts EVERY known scheme prefix, not just the current one, so an
# id-scheme bump can never invalidate an already-shipped id.
_SCHEMES_ALT = "|".join(str(v) for v in sorted(KNOWN_ID_SCHEMES))
PLACE_ID_RE = re.compile(rf"^mt(?:{_SCHEMES_ALT})_[{_CROCKFORD}]{{{_BODY_LEN}}}$")

# Anchor selection: fixed source priority, then a total order within source so
# the same cluster always mints the same id regardless of ingest order. This
# ordering exists SOLELY for mint-time determinism; it carries no meaning after
# mint, so nothing downstream should ever "re-select" an anchor. (Ratification 2.)
_SOURCE_PRIORITY = {"wd": 0, "osm": 1, "hehle": 2, "plaque": 3}
_OSM_TYPE_RANK = {"node": 0, "way": 1, "relation": 2}

# Canonical mint-key grammar is part of the FROZEN scheme (ratification 1):
# lowercase source prefix, exact separator, ASCII only, no whitespace.
#   wd:Q123 | osm:{node|way|relation}/123 | hehle:1234567 | plaque:openplaques/9876
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
Expected: prints 5 rows, each a valid `mt1_…` id; writes `fixtures/place_id/frozen_vectors.json`. **Never regenerate this file after Task 2 ships** — the test depends on it staying constant.

- [ ] **Step 5: Run the `place_id` tests to verify they pass**

Run: `cd contracts && python -m pytest tests/test_place_id.py -q`
Expected: PASS (all place_id tests green, including canonicalization rejection and per-source conformance vectors).

- [ ] **Step 6: Write the failing registry tests (union-of-refs lookup + QID-merge survival + supersede)**

`/contracts/tests/test_registry.py`:
```python
from mt_contracts.registry import RegistryRecord, resolve_by_refs

def _rec(pid, refs, status="live", superseded_by=None):
    return RegistryRecord(
        place_id=pid, refs=set(refs), mint_anchor=sorted(refs)[0],
        status=status, superseded_by=superseded_by,
        first_shipped_version="20260714T000000Z",
        last_seen_version="20260714T000000Z",
    )

def test_resolve_by_any_shared_ref():
    records = [_rec("mt1_" + "0" * 26, ["wd:Q100", "osm:node/5"])]
    # An incoming cluster sharing ONE historical ref resolves to the same id.
    assert resolve_by_refs(records, {"osm:node/5"}) == "mt1_" + "0" * 26

def test_qid_merge_keeps_place_id_stable():
    # Place shipped anchored on Q100; upstream merges Q100 -> Q200 (redirect
    # already resolved by A2 so both are in the incoming union). The place must
    # keep its id, NOT re-mint. (§7 mandated regression test.)
    pid = "mt1_" + "1" * 26
    records = [_rec(pid, ["wd:Q100", "osm:way/9"])]
    assert resolve_by_refs(records, {"wd:Q100", "wd:Q200", "osm:way/9"}) == pid

def test_unknown_refs_resolve_to_none():
    records = [_rec("mt1_" + "0" * 26, ["wd:Q100"])]
    assert resolve_by_refs(records, {"wd:Q999"}) is None

def test_tombstoned_record_still_resolves_and_is_never_reassigned():
    pid = "mt1_" + "2" * 26
    records = [_rec(pid, ["wd:Q7"], status="tombstoned")]
    # A vanished place is tombstoned, not deleted; its refs still resolve to it
    # so the id can never be reassigned to a different place.
    assert resolve_by_refs(records, {"wd:Q7"}) == pid

def test_superseded_by_points_at_a_valid_place_id():
    from mt_contracts.place_id import is_valid_place_id
    keeper = "mt1_" + "3" * 26
    dup = _rec("mt1_" + "4" * 26, ["wd:Q8"], superseded_by=keeper)
    assert is_valid_place_id(dup.superseded_by)

def test_resolve_superseded_is_transitive():
    from mt_contracts.registry import resolve_superseded
    a, b, c = ("mt1_" + ch * 26 for ch in "567")
    records = [_rec(a, ["wd:Q1"], superseded_by=b),
               _rec(b, ["wd:Q2"], superseded_by=c),
               _rec(c, ["wd:Q3"])]  # terminal winner
    # A -> B -> C resolves to C (the id that appears in published tiles).
    assert resolve_superseded(records, a) == c
    assert resolve_superseded(records, c) == c

def test_supersede_cycle_is_rejected_at_write():
    import pytest
    from mt_contracts.registry import assert_no_supersede_cycles
    a, b = ("mt1_" + ch * 26 for ch in "89")
    records = [_rec(a, ["wd:Q1"], superseded_by=b), _rec(b, ["wd:Q2"], superseded_by=a)]
    with pytest.raises(ValueError):
        assert_no_supersede_cycles(records)
```

- [ ] **Step 7: Implement `registry.py` and `registry-record.schema.json`**

`/contracts/src/mt_contracts/registry.py`:
```python
"""ID registry record shape + the union-of-refs lookup contract.

A0 pins the *shape* and the *invariants*; the clustering/redirect algorithm is
WP-A2. The registry is the authoritative owner of place identity: a place is
found by ANY source ref it has ever carried, so upstream churn (QID merges, OSM
tag changes) never mints a new id for an already-shipped place. (Principles 7,8,9.)
"""
from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass, field


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
    """Return the place_id of the record sharing any ref with `incoming_refs`.

    `incoming_refs` must already be redirect-resolved by the caller (A2): e.g.
    a Wikidata redirect Q100->Q200 contributes BOTH to the union. Returns None
    when no existing place matches, signalling A2 to mint a new id.
    """
    for rec in records:
        if rec.refs & incoming_refs:
            return rec.place_id
    return None


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
```

`/contracts/schemas/registry-record.schema.json`:
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
      "items": {"type": "string", "pattern": "^(wd|osm|hehle|plaque):[^\\u0000-\\u001f\\u007f]+$"}
    },
    "mint_anchor": {"type": "string", "pattern": "^(wd|osm|hehle|plaque):"},
    "status": {"type": "string", "enum": ["live", "tombstoned"]},
    "superseded_by": {"type": ["string", "null"], "pattern": "^mt1_[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$"},
    "first_shipped_version": {"type": "string"},
    "last_seen_version": {"type": "string"}
  }
}
```

- [ ] **Step 8: Run the registry tests to verify they pass**

Run: `cd contracts && python -m pytest tests/test_place_id.py tests/test_registry.py -q`
Expected: PASS (all place_id + registry tests green, including transitive supersede resolution and cycle rejection).

- [ ] **Step 9: Commit**

```bash
git add contracts/src/mt_contracts/place_id.py contracts/src/mt_contracts/registry.py \
        contracts/schemas/registry-record.schema.json \
        contracts/fixtures/place_id/frozen_vectors.json \
        contracts/tests/test_place_id.py contracts/tests/test_registry.py
git commit -m "Pin place_id format, registry record shape, and union-of-refs / QID-merge invariants"
```

---

### Task 3: Place JSON schema + validator + fixtures

**Files:**
- Create: `/contracts/schemas/place.schema.json`
- Create: `/contracts/src/mt_contracts/validation.py`
- Create: `/contracts/fixtures/place/valid/*.json`, `/contracts/fixtures/place/invalid/*.json`
- Test: `/contracts/tests/test_place_schema.py`

**Interfaces:**
- Consumes: `place.schema.json`, `registry-record.schema.json` (already present).
- Produces:
  - `validation.load_schema(name: str) -> dict` (name without extension, e.g. `"place"`).
  - `validation.validator_for(name: str) -> jsonschema.protocols.Validator` — a resolving validator that can follow `$ref` between contract schemas.
  - `validation.validate_instance(name: str, instance: dict) -> None` (raises `jsonschema.ValidationError`).
  - `validation.is_valid(name: str, instance: dict) -> bool`.

- [ ] **Step 1: Write the failing test (valid fixtures pass, invalid fixtures fail)**

`/contracts/tests/test_place_schema.py`:
```python
import json
import pytest
from mt_contracts.validation import is_valid, validate_instance
import jsonschema

def _load_dir(root, sub):
    d = root / "fixtures/place" / sub
    return sorted(d.glob("*.json"))

def test_valid_place_fixtures_all_pass(contracts_root):
    files = _load_dir(contracts_root, "valid")
    assert files, "expected at least one valid place fixture"
    for f in files:
        validate_instance("place", json.loads(f.read_text()))  # raises on failure

@pytest.mark.parametrize("field", ["oversize_blurb", "http_image_url", "bad_tier",
                                   "lat_out_of_range", "missing_place_id",
                                   "control_char_name", "empty_source_refs"])
def test_invalid_place_fixtures_all_fail(contracts_root, field):
    inst = json.loads((contracts_root / f"fixtures/place/invalid/{field}.json").read_text())
    assert not is_valid("place", inst), f"{field} should have failed validation"
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd contracts && python -m pytest tests/test_place_schema.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_contracts.validation'`.

- [ ] **Step 3: Implement `validation.py`**

`/contracts/src/mt_contracts/validation.py`:
```python
"""Schema loading and validation. One resolving registry so tile.schema.json
can $ref place.schema.json across files."""
from __future__ import annotations

import functools
import json
import pathlib

import jsonschema
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


def validate_instance(name: str, instance: dict) -> None:
    validator_for(name).validate(instance)


def is_valid(name: str, instance: dict) -> bool:
    return validator_for(name).is_valid(instance)
```

Add `referencing>=0.34` to `pyproject.toml` `dependencies` (it ships with `jsonschema>=4.21` but pin it explicitly): edit `/contracts/pyproject.toml` `dependencies = ["jsonschema>=4.21", "referencing>=0.34"]`, then `pip install -e '.[dev]'`.

- [ ] **Step 4: Write `place.schema.json`**

`/contracts/schemas/place.schema.json`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://contracts.making-tracks.app/place/1",
  "title": "Place",
  "description": "Read-only place record delivered inside a tile. Fields per spec §5.4; caps per §5.5.",
  "type": "object",
  "additionalProperties": false,
  "required": ["place_id", "name", "lat", "lon", "category", "tier", "score", "source_refs"],
  "properties": {
    "place_id": {"type": "string", "pattern": "^mt1_[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$"},
    "name": {"type": "string", "minLength": 1, "maxLength": 200, "pattern": "^[^\\u0000-\\u001f\\u007f]*$"},
    "alt_names": {"type": "array", "maxItems": 8, "items": {"type": "string", "minLength": 1, "maxLength": 200, "pattern": "^[^\\u0000-\\u001f\\u007f]*$"}},
    "lat": {"type": "number", "minimum": -90, "maximum": 90},
    "lon": {"type": "number", "minimum": -180, "maximum": 180},
    "category": {"type": "string", "minLength": 1, "maxLength": 64, "pattern": "^[^\\u0000-\\u001f\\u007f]*$"},
    "tier": {"type": "integer", "minimum": 1, "maximum": 4},
    "score": {"type": "number", "minimum": 0, "maximum": 1},
    "blurb": {"type": ["string", "null"], "maxLength": 600},
    "image_url": {"type": ["string", "null"], "maxLength": 2048, "pattern": "^https://"},
    "wikipedia_title": {"type": ["string", "null"], "maxLength": 300},
    "source_refs": {
      "type": "array", "minItems": 1, "maxItems": 64, "uniqueItems": true,
      "items": {"type": "string", "maxLength": 128, "pattern": "^(wd|osm|hehle|plaque):[^\\u0000-\\u001f\\u007f]+$"}
    }
  }
}
```

- [ ] **Step 5: Write the fixtures**

`/contracts/fixtures/place/valid/minimal.json`:
```json
{"place_id": "mt1_00000000000000000000000000", "name": "St. Pancras Clock Tower",
 "lat": 51.5308, "lon": -0.1257, "category": "architecture", "tier": 1,
 "score": 0.82, "source_refs": ["wd:Q42"]}
```
`/contracts/fixtures/place/valid/full.json`:
```json
{"place_id": "mt1_00000000000000000000000001", "name": "A Ghost Sign",
 "alt_names": ["Faded Advert"], "lat": 51.51, "lon": -0.09, "category": "oddity",
 "tier": 4, "score": 0.31, "blurb": "A hand-painted advert surviving on brick.",
 "image_url": "https://upload.wikimedia.org/x.jpg", "wikipedia_title": "Ghost sign",
 "source_refs": ["wd:Q123", "osm:node/5", "hehle:1000"]}
```
`/contracts/fixtures/place/invalid/oversize_blurb.json` — same as `full.json` but `"blurb"` set to a 601-character string (generate: `"x" * 601`).
`/contracts/fixtures/place/invalid/http_image_url.json` — `full.json` with `"image_url": "http://insecure/x.jpg"`.
`/contracts/fixtures/place/invalid/bad_tier.json` — `minimal.json` with `"tier": 5`.
`/contracts/fixtures/place/invalid/lat_out_of_range.json` — `minimal.json` with `"lat": 91`.
`/contracts/fixtures/place/invalid/missing_place_id.json` — `minimal.json` with `place_id` removed.
`/contracts/fixtures/place/invalid/control_char_name.json` — `minimal.json` with `"name": "BadName"`.
`/contracts/fixtures/place/invalid/empty_source_refs.json` — `minimal.json` with `"source_refs": []`.

Generate the oversize-blurb fixture deterministically:
```bash
cd contracts && python - <<'PY'
import json, pathlib
base = json.loads(pathlib.Path("fixtures/place/valid/full.json").read_text())
base["blurb"] = "x" * 601
pathlib.Path("fixtures/place/invalid/oversize_blurb.json").write_text(json.dumps(base) + "\n")
PY
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd contracts && python -m pytest tests/test_place_schema.py -q`
Expected: PASS (2 tests, 7 parametrised invalid cases → 9 passed).

- [ ] **Step 7: Commit**

```bash
git add contracts/schemas/place.schema.json contracts/src/mt_contracts/validation.py \
        contracts/fixtures/place contracts/tests/test_place_schema.py contracts/pyproject.toml
git commit -m "Pin place JSON schema with §5.5 size caps and untrusted-input guards"
```

---

### Task 4: Named caps module + place-tile envelope schema + gzip contract + deterministic overflow rule

**Files:**
- Create: `/contracts/src/mt_contracts/caps.py`
- Create: `/contracts/schemas/tile.schema.json`
- Create: `/contracts/fixtures/tile/valid/*.json`, `/contracts/fixtures/tile/invalid/*.json`
- Test: `/contracts/tests/test_caps.py`
- Test: `/contracts/tests/test_tile_schema.py`

**Interfaces:**
- Consumes: `validation.validate_instance`, `place.schema.json` (via `$ref`), `validation.load_schema`.
- Produces:
  - `caps.py` — every size cap as a named, versioned constant (single source of truth; the JSON Schemas' literals are asserted equal to these by `test_caps.py`): `NAME_MAX=200`, `ALT_NAMES_MAX=8`, `CATEGORY_MAX=64`, `BLURB_MAX=600`, `IMAGE_URL_MAX=2048`, `WIKIPEDIA_TITLE_MAX=300`, `SOURCE_REFS_MAX=64`, `TILE_ZOOM=10`, `MAX_PLACES_PER_TILE=4000`, `MAX_TILE_UNCOMPRESSED_BYTES=4*1024*1024`, `CAPS_VERSION=1`. Changing any cap requires bumping the relevant schema_version.
  - `caps.select_tile_places(places, max_per_tile=MAX_PLACES_PER_TILE) -> tuple[list, list]` — the deterministic overflow rule (returns `(kept, dropped)`); A7 uses it and **must log `dropped`** (no silent truncation).
  - `tile.schema.json` — the on-R2 tile envelope. On-R2 path: `{publish_version}/tiles/{z}/{x}/{y}.json.gz`, gzip-compressed bytes (the app decompresses; do **not** rely on `Content-Encoding`, which R2 static serving does not add). Published tiles carry only the **winner** id of any supersede chain (ratification 3b).

#### Part A — named caps module + overflow rule

- [ ] **Step 1: Write the failing caps tests (schema/const parity + deterministic overflow)**

`/contracts/tests/test_caps.py`:
```python
from mt_contracts import caps
from mt_contracts.validation import load_schema

def test_place_schema_literals_match_caps():
    props = load_schema("place")["properties"]
    assert props["name"]["maxLength"] == caps.NAME_MAX
    assert props["blurb"]["maxLength"] == caps.BLURB_MAX
    assert props["image_url"]["maxLength"] == caps.IMAGE_URL_MAX
    assert props["wikipedia_title"]["maxLength"] == caps.WIKIPEDIA_TITLE_MAX
    assert props["category"]["maxLength"] == caps.CATEGORY_MAX
    assert props["source_refs"]["maxItems"] == caps.SOURCE_REFS_MAX
    assert props["alt_names"]["maxItems"] == caps.ALT_NAMES_MAX

def test_tile_schema_literals_match_caps():
    schema = load_schema("tile")
    assert schema["properties"]["z"]["const"] == caps.TILE_ZOOM
    assert schema["properties"]["places"]["maxItems"] == caps.MAX_PLACES_PER_TILE

def test_overflow_is_deterministic_and_keeps_best():
    # Drop the lowest-quality tail first: keep by (tier asc, score desc, place_id asc).
    places = [
        {"place_id": "mt1_" + "a" * 26, "tier": 4, "score": 0.1},
        {"place_id": "mt1_" + "b" * 26, "tier": 1, "score": 0.9},
        {"place_id": "mt1_" + "c" * 26, "tier": 2, "score": 0.5},
    ]
    kept, dropped = caps.select_tile_places(places, max_per_tile=2)
    assert [p["place_id"] for p in kept] == ["mt1_" + "b" * 26, "mt1_" + "c" * 26]
    assert [p["place_id"] for p in dropped] == ["mt1_" + "a" * 26]
    # stable: same input, same output
    assert caps.select_tile_places(places, max_per_tile=2) == (kept, dropped)

def test_overflow_stable_tie_break_by_place_id():
    a = {"place_id": "mt1_" + "1" * 26, "tier": 1, "score": 0.5}
    b = {"place_id": "mt1_" + "2" * 26, "tier": 1, "score": 0.5}  # identical tier+score
    kept, dropped = caps.select_tile_places([b, a], max_per_tile=1)
    assert [p["place_id"] for p in kept] == ["mt1_" + "1" * 26]  # lower id wins
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd contracts && python -m pytest tests/test_caps.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_contracts.caps'`.

- [ ] **Step 3: Implement `caps.py`**

`/contracts/src/mt_contracts/caps.py`:
```python
"""Named, versioned size caps (single source of truth) + the deterministic
tile-overflow rule. The JSON Schemas' literal numbers are asserted equal to
these by test_caps.py, so a cap can never drift. Changing a cap requires a
schema_version bump (fable ratification, addition 4)."""
from __future__ import annotations

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
MAX_TILE_UNCOMPRESSED_BYTES = 4 * 1024 * 1024


def select_tile_places(places, max_per_tile: int = MAX_PLACES_PER_TILE):
    """Deterministically choose which places survive a tile's cap.

    Keep the most prominent: sort by (tier ascending — T1 is most prominent,
    then score descending, then place_id ascending as a stable tie-break); keep
    the first `max_per_tile`, drop the rest. Returns (kept, dropped); the caller
    (A7) MUST log `dropped` — silent truncation is forbidden.
    """
    ordered = sorted(places, key=lambda p: (p["tier"], -p["score"], p["place_id"]))
    return ordered[:max_per_tile], ordered[max_per_tile:]
```

- [ ] **Step 4: Run the caps tests to verify they pass**

Run: `cd contracts && python -m pytest tests/test_caps.py -q`
Expected: PASS (4 passed).

#### Part B — tile envelope schema

- [ ] **Step 5: Write the failing test (schema + gzip round-trip + decode-cap)**

`/contracts/tests/test_tile_schema.py`:
```python
import gzip
import json
from mt_contracts.validation import is_valid, validate_instance
from mt_contracts.caps import MAX_TILE_UNCOMPRESSED_BYTES

def test_valid_tile_fixture_passes(contracts_root):
    inst = json.loads((contracts_root / "fixtures/tile/valid/one_place.json").read_text())
    validate_instance("tile", inst)

def test_tile_with_bad_place_fails(contracts_root):
    inst = json.loads((contracts_root / "fixtures/tile/invalid/bad_place.json").read_text())
    assert not is_valid("tile", inst)

def test_tile_wrong_zoom_fails(contracts_root):
    inst = json.loads((contracts_root / "fixtures/tile/invalid/wrong_zoom.json").read_text())
    assert not is_valid("tile", inst)

def test_tile_xy_out_of_range_fails(contracts_root):
    inst = json.loads((contracts_root / "fixtures/tile/invalid/xy_out_of_range.json").read_text())
    assert not is_valid("tile", inst)

def test_gzip_roundtrip_and_decode_cap(contracts_root):
    inst = json.loads((contracts_root / "fixtures/tile/valid/one_place.json").read_text())
    raw = json.dumps(inst).encode("utf-8")
    packed = gzip.compress(raw)
    assert len(raw) <= MAX_TILE_UNCOMPRESSED_BYTES  # producer stays under the reader cap
    assert json.loads(gzip.decompress(packed).decode("utf-8")) == inst
```

- [ ] **Step 6: Run to verify it fails**

Run: `cd contracts && python -m pytest tests/test_tile_schema.py -q`
Expected: FAIL — fixtures / schema do not exist yet.

- [ ] **Step 7: Write `tile.schema.json`**

`/contracts/schemas/tile.schema.json`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://contracts.making-tracks.app/tile/1",
  "title": "PlaceTile",
  "description": "A z10 geographic cell of places. Served gzipped at {publish_version}/tiles/10/{x}/{y}.json.gz.",
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

`/contracts/fixtures/tile/valid/one_place.json`:
```json
{"schema_version": 1, "z": 10, "x": 511, "y": 340,
 "places": [{"place_id": "mt1_00000000000000000000000000", "name": "St. Pancras Clock Tower",
             "lat": 51.5308, "lon": -0.1257, "category": "architecture", "tier": 1,
             "score": 0.82, "source_refs": ["wd:Q42"]}]}
```
`/contracts/fixtures/tile/invalid/bad_place.json` — same, but the inner place has `"tier": 9`.
`/contracts/fixtures/tile/invalid/wrong_zoom.json` — same as valid but `"z": 11`.
`/contracts/fixtures/tile/invalid/xy_out_of_range.json` — same as valid but `"x": 1024`.

- [ ] **Step 9: Run the tests to verify they pass**

Run: `cd contracts && python -m pytest tests/test_caps.py tests/test_tile_schema.py -q`
Expected: PASS (9 passed).

- [ ] **Step 10: Commit**

```bash
git add contracts/src/mt_contracts/caps.py contracts/tests/test_caps.py \
        contracts/schemas/tile.schema.json contracts/fixtures/tile contracts/tests/test_tile_schema.py
git commit -m "Pin caps constants, deterministic tile-overflow rule, and place-tile envelope schema"
```

---

### Task 5: Manifest schema + checksum reference helper + fixtures

**Files:**
- Create: `/contracts/schemas/manifest.schema.json`
- Create: `/contracts/src/mt_contracts/checksums.py`
- Create: `/contracts/fixtures/manifest/valid/*.json`, `/contracts/fixtures/manifest/invalid/*.json`
- Test: `/contracts/tests/test_manifest_schema.py`

**Interfaces:**
- Consumes: `validation`, `place_id` pattern.
- Produces:
  - `manifest.schema.json` — the per-region manifest (tile index + checksums + basemap descriptor + prompt-version provenance). "Written last, atomically" (§5.2) is A7 behaviour; the schema makes the manifest self-contained so the app can verify everything it references.
  - `checksums.sha256_hex(data: bytes) -> str` — the reference checksum function (lowercase hex) that A7 uses to fill, and B3/B7 use to verify, every `sha256` field.

- [ ] **Step 1: Write the failing test**

`/contracts/tests/test_manifest_schema.py`:
```python
import hashlib
import json
from mt_contracts.validation import is_valid, validate_instance
from mt_contracts.checksums import sha256_hex

def test_valid_manifest_passes(contracts_root):
    inst = json.loads((contracts_root / "fixtures/manifest/valid/uk.json").read_text())
    validate_instance("manifest", inst)

def test_manifest_missing_provenance_fails(contracts_root):
    inst = json.loads((contracts_root / "fixtures/manifest/invalid/no_provenance.json").read_text())
    assert not is_valid("manifest", inst)

def test_manifest_bad_checksum_length_fails(contracts_root):
    inst = json.loads((contracts_root / "fixtures/manifest/invalid/bad_checksum.json").read_text())
    assert not is_valid("manifest", inst)

def test_sha256_hex_matches_hashlib():
    data = b"making tracks"
    assert sha256_hex(data) == hashlib.sha256(data).hexdigest()
    assert len(sha256_hex(data)) == 64
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd contracts && python -m pytest tests/test_manifest_schema.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_contracts.checksums'`.

- [ ] **Step 3: Implement `checksums.py`**

`/contracts/src/mt_contracts/checksums.py`:
```python
"""Reference checksum for every `sha256` field in the manifest contract.
A7 fills these; B3/B7 verify against them (resumable + checksum-verified, §5.3)."""
from __future__ import annotations

import hashlib


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()
```

- [ ] **Step 4: Write `manifest.schema.json`**

`/contracts/schemas/manifest.schema.json`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://contracts.making-tracks.app/manifest/1",
  "title": "RegionManifest",
  "description": "Per-region, per-publish manifest. Written last, atomically (§5.2). Self-contained: the app can verify every tile and the basemap it references.",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "min_reader_version", "region", "publish_version",
               "tile_z", "tiles", "counts", "basemap", "provenance"],
  "properties": {
    "schema_version": {"type": "integer", "const": 1},
    "min_reader_version": {"type": "integer", "minimum": 1},
    "region": {"type": "string", "pattern": "^[a-z][a-z0-9_]*$"},
    "publish_version": {"type": "string", "pattern": "^[0-9]{8}T[0-9]{6}Z$"},
    "generated_at": {"type": "string", "format": "date-time"},
    "tile_z": {"type": "integer", "const": 10},
    "tiles": {
      "type": "array",
      "items": {
        "type": "object", "additionalProperties": false,
        "required": ["x", "y", "sha256", "bytes"],
        "properties": {
          "x": {"type": "integer", "minimum": 0, "maximum": 1023},
          "y": {"type": "integer", "minimum": 0, "maximum": 1023},
          "sha256": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
          "bytes": {"type": "integer", "minimum": 1}
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
        "filename": {"type": "string", "pattern": "\\.pmtiles$"},
        "maxzoom": {"type": "integer", "minimum": 0, "maximum": 15},
        "sha256": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
        "bytes": {"type": "integer", "minimum": 1},
        "bbox": {"type": "array", "minItems": 4, "maxItems": 4, "items": {"type": "number"}}
      }
    },
    "provenance": {
      "type": "array",
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

- [ ] **Step 5: Write the fixtures**

`/contracts/fixtures/manifest/valid/uk.json`:
```json
{"schema_version": 1, "min_reader_version": 1, "region": "uk",
 "publish_version": "20260714T120000Z", "generated_at": "2026-07-14T12:00:00Z",
 "tile_z": 10,
 "tiles": [{"x": 511, "y": 340, "sha256": "0000000000000000000000000000000000000000000000000000000000000000", "bytes": 812}],
 "counts": {"total": 1, "by_tier": [1, 0, 0, 0]},
 "basemap": {"filename": "uk.pmtiles", "maxzoom": 14,
             "sha256": "1111111111111111111111111111111111111111111111111111111111111111",
             "bytes": 1500000000, "bbox": [-8.65, 49.84, 1.77, 60.86]},
 "provenance": [{"task_id": "curiosity", "model": "open-weight-x", "prompt_version": "curiosity-v3"}]}
```
`/contracts/fixtures/manifest/invalid/no_provenance.json` — the valid manifest with `provenance` removed.
`/contracts/fixtures/manifest/invalid/bad_checksum.json` — the valid manifest with a tile `sha256` of `"abc"` (wrong length).

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd contracts && python -m pytest tests/test_manifest_schema.py -q`
Expected: PASS (4 passed).

- [ ] **Step 7: Commit**

```bash
git add contracts/schemas/manifest.schema.json contracts/src/mt_contracts/checksums.py \
        contracts/fixtures/manifest contracts/tests/test_manifest_schema.py
git commit -m "Pin manifest schema (tile index, checksums, basemap descriptor, prompt-version provenance)"
```

---

### Task 6: Region-config schema + real UK/Malaysia configs + measured basemap budget

The measurements are **already taken** (see the table below and `basemap-budget.json`); this task pins the schema, the machine-readable budget, and the two real region configs, with a guard test that a config's declared basemap can never exceed the pack ceiling.

**Measured basemap sizes** — `pmtiles extract` (dry-run archive size, confirmed against a real Malaysia z13 extract == 112,289,127 bytes on disk) against the live Protomaps planet build `20260714.pmtiles` (136 GB), min-zoom 0, `overfetch 0.05`:

| Region | z11 | z12 | z13 | z14 | z15 |
|---|---|---|---|---|---|
| UK (`-8.65,49.84,1.77,60.86`) | 147 MB | 341 MB | 730 MB | **1.5 GB** | 3.0 GB |
| Malaysia (`99.64,0.85,119.27,7.36`) | 21 MB | 52 MB | 112 MB | **223 MB** | 447 MB |

**Decision (§5.1 budget = "low single-digit GB on WiFi"): max basemap zoom = 14.** At z14, UK = 1.5 GB and Malaysia = 223 MB — both comfortably single-digit GB, so **country-granularity whole-file packs are viable for both v1 regions; no sub-region tiling required.** z15 stays available as a per-region knob (the schema supports it) but is the ceiling — UK z15 = 3.0 GB sits at the top of "low single-digit GB" and would be the first candidate for sub-region cutting if street detail proves insufficient. Pack ceiling constant: `PACK_BUDGET_CEILING_BYTES = 3_221_225_472` (3 GiB). The place tiles add negligibly (v1 place counts are ≤ tens of thousands of small gzipped JSON objects across z10 cells; basemap dominates the pack).

**Files:**
- Create: `/contracts/schemas/region-config.schema.json`
- Create: `/contracts/basemap-budget.json`
- Create: `/contracts/regions/uk.json`, `/contracts/regions/malaysia.json`
- Test: `/contracts/tests/test_region_config_schema.py`, `/contracts/tests/test_basemap_budget.py`

**Interfaces:**
- Consumes: `validation`.
- Produces:
  - `region-config.schema.json` — consumed by A1 (region CLI param), A7 (extract bbox + maxzoom), B7 (pack budget).
  - `regions/{uk,malaysia}.json` — the first real instances.
  - `basemap-budget.json` — `{ceiling_bytes, measurements: [{region, maxzoom, archive_bytes}...]}`.

- [ ] **Step 1: Write the failing tests**

`/contracts/tests/test_region_config_schema.py`:
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

`/contracts/tests/test_basemap_budget.py`:
```python
import json

def test_every_region_config_stays_under_ceiling(contracts_root):
    budget = json.loads((contracts_root / "basemap-budget.json").read_text())
    ceiling = budget["ceiling_bytes"]
    for region in ("uk", "malaysia"):
        cfg = json.loads((contracts_root / f"regions/{region}.json").read_text())
        assert cfg["basemap"]["size_budget_bytes"] <= ceiling
        # the config's declared measured size must match the budget table for its maxzoom
        mz = cfg["basemap"]["maxzoom"]
        row = next(m for m in budget["measurements"] if m["region"] == region and m["maxzoom"] == mz)
        assert cfg["basemap"]["measured_archive_bytes"] == row["archive_bytes"]
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd contracts && python -m pytest tests/test_region_config_schema.py tests/test_basemap_budget.py -q`
Expected: FAIL — schema/config/budget files absent.

- [ ] **Step 3: Write `region-config.schema.json`**

`/contracts/schemas/region-config.schema.json`:
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
    "region_id": {"type": "string", "pattern": "^[a-z][a-z0-9_]*$"},
    "display_name": {"type": "string", "minLength": 1, "maxLength": 80},
    "bbox": {"type": "array", "minItems": 4, "maxItems": 4, "items": {"type": "number"}},
    "languages": {"type": "array", "minItems": 1, "items": {"type": "string", "pattern": "^[a-z]{2,3}$"}},
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
          "properties": {"id": {"type": "string", "maxLength": 64}, "enabled": {"type": "boolean"}}
        }
      }
    },
    "basemap": {
      "type": "object", "additionalProperties": false,
      "required": ["source_pmtiles", "maxzoom", "pack_granularity", "size_budget_bytes", "measured_archive_bytes"],
      "properties": {
        "source_pmtiles": {"type": "string", "pattern": "^https://"},
        "maxzoom": {"type": "integer", "minimum": 0, "maximum": 15},
        "pack_granularity": {"type": "string", "enum": ["country", "subregion"]},
        "subregions": {
          "type": "array",
          "items": {"type": "object", "additionalProperties": false, "required": ["id", "bbox"],
                    "properties": {"id": {"type": "string", "pattern": "^[a-z][a-z0-9_]*$"},
                                   "bbox": {"type": "array", "minItems": 4, "maxItems": 4, "items": {"type": "number"}}}}
        },
        "size_budget_bytes": {"type": "integer", "minimum": 1},
        "measured_archive_bytes": {"type": "integer", "minimum": 1}
      }
    }
  }
}
```

- [ ] **Step 4: Write `basemap-budget.json` and the two region configs**

`/contracts/basemap-budget.json`:
```json
{
  "ceiling_bytes": 3221225472,
  "budget_note": "§5.1 'low single-digit GB on WiFi'; 3 GiB per-pack ceiling. maxzoom 14 chosen for v1.",
  "source_build": "https://build.protomaps.com/20260714.pmtiles",
  "method": "pmtiles extract --minzoom=0 --maxzoom=Z --bbox=... (dry-run archive size; verified against a real z13 Malaysia extract = 112289127 bytes on disk)",
  "measurements": [
    {"region": "uk", "maxzoom": 11, "archive_bytes": 147000000},
    {"region": "uk", "maxzoom": 12, "archive_bytes": 341000000},
    {"region": "uk", "maxzoom": 13, "archive_bytes": 730000000},
    {"region": "uk", "maxzoom": 14, "archive_bytes": 1500000000},
    {"region": "uk", "maxzoom": 15, "archive_bytes": 3000000000},
    {"region": "malaysia", "maxzoom": 11, "archive_bytes": 21000000},
    {"region": "malaysia", "maxzoom": 12, "archive_bytes": 52000000},
    {"region": "malaysia", "maxzoom": 13, "archive_bytes": 112289127},
    {"region": "malaysia", "maxzoom": 14, "archive_bytes": 223000000},
    {"region": "malaysia", "maxzoom": 15, "archive_bytes": 447000000}
  ]
}
```

`/contracts/regions/uk.json`:
```json
{"schema_version": 1, "region_id": "uk", "display_name": "United Kingdom",
 "bbox": [-8.65, 49.84, 1.77, 60.86], "languages": ["en"],
 "sources": {"wikidata": true, "wikipedia": true, "osm": true,
             "historic_england": true, "open_plaques": true, "national_register": null},
 "basemap": {"source_pmtiles": "https://build.protomaps.com/20260714.pmtiles",
             "maxzoom": 14, "pack_granularity": "country",
             "size_budget_bytes": 2000000000, "measured_archive_bytes": 1500000000}}
```

`/contracts/regions/malaysia.json`:
```json
{"schema_version": 1, "region_id": "malaysia", "display_name": "Malaysia",
 "bbox": [99.64, 0.85, 119.27, 7.36], "languages": ["en"],
 "sources": {"wikidata": true, "wikipedia": true, "osm": true,
             "historic_england": false, "open_plaques": true,
             "national_register": {"id": "malaysia_heritage", "enabled": false}},
 "basemap": {"source_pmtiles": "https://build.protomaps.com/20260714.pmtiles",
             "maxzoom": 14, "pack_granularity": "country",
             "size_budget_bytes": 500000000, "measured_archive_bytes": 223000000}}
```

(Malaysia's `national_register.enabled: false` encodes the §4 / WP-A1d feasibility-pending state; `historic_england: false` because it is UK-only — Principle 17: no source is load-bearing.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd contracts && python -m pytest tests/test_region_config_schema.py tests/test_basemap_budget.py -q`
Expected: PASS (5 passed).

- [ ] **Step 6: Commit**

```bash
git add contracts/schemas/region-config.schema.json contracts/basemap-budget.json \
        contracts/regions contracts/tests/test_region_config_schema.py contracts/tests/test_basemap_budget.py
git commit -m "Pin region-config schema, measured basemap budget, and real UK/Malaysia configs"
```

---

### Task 7: Full-suite green + CONTRACTS.md authoritative doc + consumer map + self-review

**Files:**
- Create: `/contracts/CONTRACTS.md`
- Create: `/contracts/README.md`
- Test: run the entire `/contracts/tests` suite green.

**Interfaces:**
- Consumes: every artifact from Tasks 1–6.
- Produces: the single human-readable authoritative document, including the per-WP "what you consume" map so no downstream agent has to reverse-engineer the contract.

- [ ] **Step 1: Run the whole suite**

Run: `cd contracts && python -m pytest -q`
Expected: PASS (all tests from Tasks 1–6 green — versions, place_id + canonicalization + conformance vectors, registry + supersede chain, caps + overflow, place/tile/manifest/region-config schemas, basemap budget).

- [ ] **Step 2: Write `CONTRACTS.md`**

Author `/contracts/CONTRACTS.md` with these sections (prose, pointing at the machine artifacts as the source of truth):

1. **Status & immutability rules** — schemas are versioned (`versions.json`); the `place_id` scheme and the frozen vectors are immutable once shipped (Principle 7); changing any shipped shape is a `schema_version` bump, never an in-place edit.
2. **`place_id`** — the `mt1_<26 Crockford base32>` grammar; the **exact frozen mint-key canonicalization** (lowercase source prefix, ASCII only, no whitespace: `wd:Q123` / `osm:{node|way|relation}/456` / `hehle:1234567` / `plaque:openplaques/9876`) with the per-source **conformance test vectors** (`fixtures/place_id/frozen_vectors.json`) any reimplementation must reproduce; derivation-then-registry-ownership model; anchor priority (QID > OSM node>way>rel > Historic England > Open Plaques) with the explicit note that it exists **only** for mint-time determinism and carries no meaning after mint; QID-merge survival via union-of-refs; `superseded_by` soft de-dup (keep-both, Principle 9) resolved **transitively** to a terminal winner with a **no-cycle** write invariant; **published tiles carry the winner id only** — loser ids live forever in the registry and in user `place_snapshots` and resolve for rendering with **no app-side special case**; tombstones. Point to `src/mt_contracts/place_id.py`, `registry.py`, `schemas/registry-record.schema.json`, `fixtures/place_id/frozen_vectors.json`.
3. **Place JSON** — field table (from §5.4) and the §5.5 caps (named in `src/mt_contracts/caps.py`, single-sourced; schema literals asserted equal by test; a cap change requires a `schema_version` bump); note category is a string (taxonomy is a WP-A3 deliverable, deliberately not enum-pinned here); `image_url` https-only at schema level + expected-host allowlist is app config.
4. **Place tile** — z10 XYZ envelope; on-R2 path `{publish_version}/tiles/10/{x}/{y}.json.gz`; gzip file bytes (app decompresses; not `Content-Encoding`); `MAX_PLACES_PER_TILE=4000`, decode cap 4 MiB; **deterministic overflow rule** `caps.select_tile_places` (keep by tier asc, score desc, place_id asc; drop the tail; A7 **logs** every dropped place — no silent truncation).
5. **Manifest** — tile index + per-tile sha256 + basemap descriptor + prompt-version provenance (with `task_id`); written last, atomically; versioned publish paths; rollback = repoint the manifest (§5.6).
6. **Region config** — fields; region modularity (no region enum); per-region sources optional.
7. **Basemap pack budget** — paste the measured table and the maxzoom-14 decision from Task 6; `PACK_BUDGET_CEILING_BYTES`.
8. **Versioning & compatibility** — the §5.6 policy and `check_version` semantics (TOO_NEW → keep cache / prompt update; TOO_OLD → refuse; fresh install on too-old app → "update required" state).
9. **Consumer map** — a table:

   | Consumer WP | Consumes from A0 |
   |---|---|
   | A1 | `regions/*.json`, `region-config.schema.json` (region CLI param, source-record targets) |
   | A2 | `place_id.py`, `registry.py`, `registry-record.schema.json` (mint + union-of-refs + tombstone/supersede invariants) |
   | A7 | `tile.schema.json`, `manifest.schema.json`, `checksums.sha256_hex`, region `basemap` block (extract bbox + maxzoom 14) |
   | B1 | `place.schema.json` (the read-only fields that seed `place_snapshots`) |
   | B3 | `manifest.schema.json`, `tile.schema.json`, `versions.check_version` (fetch, decode caps, invalidation) |
   | B7 | `basemap-budget.json`, region `basemap` block (pack size, maxzoom, granularity, refresh vs `publish_version`) |

`/contracts/README.md`: one paragraph — "Authoritative cross-track contracts for Making Tracks. See CONTRACTS.md. Machine source of truth: `schemas/`, `versions.json`, `regions/`, `basemap-budget.json`. `pip install -e '.[dev]' && pytest` validates the whole contract."

- [ ] **Step 3: Self-review against the spec (checklist — run yourself, do not dispatch)**

Confirm each item; fix inline if any fails:
- **Spec coverage:** §5.1 basemap budget → Task 6 (measured). §5.2 place tile format / manifest / place_id / registry → Tasks 2,4,5. §5.4 place fields → Task 3. §5.5 caps → Tasks 3,4. §5.6 versioning → Task 1 + every schema. §8 WP-A0 row (tile, manifest, place JSON, place_id, region config, measured sizes) → all present. Adversarial finding #1 (QID-merge stability) → Task 2 `test_qid_merge_keeps_place_id_stable`. Adversarial task_id fix → manifest `provenance`.
- **Placeholder scan:** no "TBD"/"add validation"/"handle edge cases" — every step has literal content.
- **Type consistency:** `place_id` pattern identical across `place`, `tile`(via ref), `manifest.superseded_by`(none — that's registry-record), `registry-record` (`^mt1_[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$`); `sha256` pattern `^[0-9a-f]{64}$` in `manifest` and matches `checksums.sha256_hex` output; `tile_z`/`z` const 10 everywhere; version keys in `versions.json` == `SCHEMA_VERSIONS`.

- [ ] **Step 4: Commit**

```bash
git add contracts/CONTRACTS.md contracts/README.md
git commit -m "Add authoritative CONTRACTS.md, consumer map, and README"
```

---

## Self-Review (plan author)

**Spec coverage** — every WP-A0 deliverable in §8's row maps to a task: tile format (T4), manifest schema (T5), place JSON schema (T3), `place_id` format (T2), region config format (T6), measured UK/Malaysia basemap sizes vs the §5.1 budget (T6, real numbers). §5.6 versioning (T1). §5.5 caps (T3/T4). The two mandated invariants from §7 / adversarial #1 (QID-merge stability, tombstone-not-remint) have explicit regression tests (T2). The manifest `task_id`-in-provenance fix is in T5.

**Placeholder scan** — no deferred content; each code/JSON step carries the literal artifact.

**Type consistency** — the `place_id` regex, `sha256` regex, and `z==10` const are identical everywhere they appear; `SCHEMA_VERSIONS` is asserted equal to `versions.json`; `checksums.sha256_hex` output length matches the manifest `sha256` pattern.

**Ratified** — the `place_id` scheme, anchor priority, and soft-supersede model were confirmed by the design lead (fable) on AMQ `wp/a0`, with five additions now folded in: (1) exact frozen mint-key canonicalization + per-source conformance vectors (Task 2); (2) anchor-priority "mint-time-determinism-only" rationale (Task 2); (3a) transitive `superseded_by` + no-cycle write invariant, (3b) winner-only in published tiles, (3c) snapshot resolution with no app special case (Task 2 + CONTRACTS.md); (4) caps as named versioned constants + deterministic tile-overflow rule with logged drops (Task 4). Rob retains override until the plan is approved.
