# WP-A1 (Skeleton) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold the Python data pipeline — a region-parameterised CLI whose five stages (extract → reconcile → score → categorize → publish) are dispatchable no-ops that enforce §5.2 stage order, the normalized **source-record model** every extractor will implement (the single defensive-parse boundary), and the SQLite working store between stages — consuming WP-A0's contracts, so A1b/A1c/A1d extractors and A2 reconcile have a stable foundation.

**Architecture:** A `making-tracks-pipeline` package under `pipeline/`, a **uv workspace** member depending on `mt-contracts` (WP-A0). The CLI (stdlib `argparse`) resolves `--region` to a schema-validated A0 region config and dispatches stage subcommands that refuse to run until their predecessor stage has recorded completion. The source-record `parse()` is the one hardened defensive boundary every extractor reuses; it **delegates** ref-grammar and text-safety to `mt_contracts` (never re-declaring them) and bounds/cleans the opaque `props` sub-record. All between-stage state lives in a deterministic SQLite working store.

**Tech Stack:** Python 3.11+, uv workspace, `mt-contracts` (WP-A0), stdlib `sqlite3` + `argparse` + `json`, `pytest`.

## Global Constraints

- **Python 3.11+; uv workspace.** Root `pyproject.toml` declares `[tool.uv.workspace] members = ['contracts', 'pipeline']`; a repo-root `.python-version` pins `3.11` (a virtual root can't set `requires-python`); `pipeline` depends on `mt-contracts` via `[tool.uv.sources] mt-contracts = { workspace = true }`. **Run tests with `uv run`** (uv installs into `.venv`; a bare `python -m pytest` would not see `mt_contracts`). **No-uv fallback** (documented, must work): `pip install -e ./contracts ./pipeline` into an active 3.11 interpreter, then bare `python -m pytest`.
- **Consume A0, never re-declare it — grammar AND character-safety.** `source_ref` grammar, the canonical-ref rule, region-config schema/JSON, **and the text-safety denylist** are all owned by `mt_contracts`. The pipeline imports them; it never re-implements a grammar, a schema, or a codepoint denylist. This is load-bearing: a locally re-declared text rule would diverge from A0 and silently corrupt legitimate RTL/Jawi names (over-strip) or admit chars A0 rejects (under-strip).
- **Determinism (Principle 12).** No wall-clock or randomness in any *output* value. `run_id` and `completed_at` are run **metadata only** — never feeding an id, hash, ordering, or any published value. The determinism guard test scans for wall-clock (`now`/`utcnow`/`time`/`monotonic`/`perf_counter`) and randomness (`random`/`shuffle`/`uuid4`/`urandom`/`randint`/`choice`) and allows only the single sanctioned wall-clock call inside `stages._completed_at`.
- **All source data is untrusted (Principle 10 / §5.5).** `source_record.parse` is *the* boundary every extractor reuses: it delegates the ref grammar to `mt_contracts.is_canonical_ref`, delegates text cleaning to `mt_contracts.strip_unsafe_text`, bounds coordinates (finite + range), and **bounds + cleans the `props` sub-record** (serialized-size / depth / count caps, string keys, string values cleaned, non-finite floats rejected, serialization done at the boundary with `allow_nan=False` so a bad value is a clean error, not a later crash). All SQL is parameterised (never string-interpolated). URL (https-only) validation is **not** an A1-boundary concern — `props` is opaque here; the extractor validates a URL when it maps a known URL field, and A0's `image_url` schema is the final publish gate. (This scoping is deliberate; do not claim the A1 parser validates URLs.)
- **Region modularity (Principle 17).** The active region is resolved from an A0 region config; no region id, bbox, or source list is hardcoded in pipeline logic. Adding a region is adding a config file in A0.
- **Stage order (§5.2).** `extract → reconcile → score → categorize → publish`. A stage refuses to run (fails loudly, naming the **immediate predecessor** to run first) unless that predecessor has recorded completion for that region. `extract` has no predecessor.
- **A1 is scaffolding only.** Stages are no-op-but-dispatchable: they enforce order and record completion — no extract/reconcile/score/categorize/publish domain logic (those are A1b–d, A2, A4, A3, A7). No reconcile stub (would prejudice A2).
- **Working store is ephemeral.** It is single-writer, re-created per run, and NOT one of §5.6's versioned pipeline artefacts — so it is exempt from the cross-boundary versioning rule. A `meta(schema_version)` row is still written so a stale-shaped DB fails loud rather than being silently misread.
- **Test-first.** Every module lands with a failing test first; tests exercise the **production** code path (not stdlib behaviour) and genuinely fail a plausible broken implementation.

**Required WP-A0 exports (precondition — flagged to fable on thread `wp/a1`; A0 is on PR #26, all additive).** A1 is written against these `mt_contracts` exports:
1. `mt_contracts.is_canonical_ref(s: str) -> bool` — the single source of the canonical-ref grammar `^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9._/-]*$`.
2. `mt_contracts.strip_unsafe_text(s: str) -> str` — removes exactly the codepoints A0's `SAFE_TEXT` denylist rejects (C0/DEL/C1, line/para separators, bidi overrides+isolates, zero-width/BOM) while **keeping LRM/RLM** so RTL names survive. Single source of the text-safety rule (mirrors `is_canonical_ref`). *(A0 already has the `SAFE_TEXT` regex in its schemas; this exports a stripper built from the same denylist.)*
3. `mt_contracts.load_region_config(region_id: str) -> dict` (packaged, schema-validated) and `mt_contracts.available_regions() -> list[str]`. Requires A0 to ship `schemas/`, `regions/`, `versions.json` as package data (so a built wheel — not only an editable install — can read them).
4. **Confirmed region-config field names** (A0's schema, from the A0 plan): `region_id`, `display_name`, `bbox`, `languages`, `sources`, `basemap` — and A0 ships regions `uk` and `malaysia`. A1's typed view reads exactly these; if A0's names differ, this must be reconciled before build.

---

## File Structure

```
pyproject.toml                       # repo root: [tool.uv.workspace] members = ['contracts','pipeline'] (Task 1)
.python-version                      # repo root: 3.11 (Task 1)
pipeline/
  pyproject.toml                     # name=making-tracks-pipeline; depends on mt-contracts (workspace) (Task 1)
  README.md                          # run instructions (uv run) + no-uv fallback (Task 6)
  src/mt_pipeline/
    __init__.py
    store.py                         # SQLite working store: schema, connect, meta version, stage ledger (Task 2)
    config.py                        # resolve --region to a validated A0 RegionConfig (Task 3)
    source_record.py                 # SourceRecord model + hardened defensive parser + persistence (Task 4)
    stages.py                        # the five no-op-but-dispatchable stage fns + ORDER (Task 5)
    cli.py                           # argparse CLI: --region + stage subcommands, order + error handling (Task 5)
  tests/
    conftest.py                      # conn fixture (tmp working store)
    test_import.py                   # Task 1 smoke test
    test_store.py                    # Task 2
    test_config.py                   # Task 3
    test_source_record.py            # Task 4
    test_stages.py                   # Task 5
    test_cli.py                      # Task 5
    test_determinism.py              # Task 6
```

Each module has one responsibility. `store.py` is the only SQLite module; `source_record.py` is the one defensive-parse boundary every extractor reuses; `stages.py`/`cli.py` hold dispatch + order + error mapping, no domain logic.

---

### Task 1: uv workspace + pipeline package scaffold

**Files:**
- Create: `pyproject.toml` (repo root), `.python-version` (repo root), `pipeline/pyproject.toml`, `pipeline/src/mt_pipeline/__init__.py`, `pipeline/tests/test_import.py`

**Interfaces:**
- Consumes: `mt-contracts` (WP-A0), resolved via the uv workspace.
- Produces: an installable `mt_pipeline` package that can `import mt_contracts` and reach its exported helpers.

- [ ] **Step 1: Write the failing smoke test**

`pipeline/tests/test_import.py`:
```python
def test_pipeline_and_contracts_import_with_a1_surface():
    import mt_pipeline            # this package
    import mt_contracts          # the A0 dependency, resolved via the workspace
    assert mt_pipeline is not None
    # assert the exact A0 surface A1 is written against (the precondition contract)
    for name in ("is_canonical_ref", "strip_unsafe_text", "load_region_config", "available_regions"):
        assert hasattr(mt_contracts, name), f"A0 must export {name}"
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_import.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_pipeline'` (or, once built, a missing-A0-export `AssertionError` telling you which A0 precondition is unmet).

- [ ] **Step 3: Create the root uv workspace + pinned interpreter**

Root `pyproject.toml` (create at repo root; if one exists, merge these tables):
```toml
[tool.uv.workspace]
members = ["contracts", "pipeline"]
```

Root `.python-version`:
```
3.11
```

- [ ] **Step 4: Create the pipeline package**

`pipeline/pyproject.toml`:
```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "making-tracks-pipeline"
version = "0.1.0"
description = "Making Tracks data pipeline (extract → reconcile → score → categorize → publish)."
requires-python = ">=3.11"
dependencies = ["mt-contracts"]

[project.optional-dependencies]
dev = ["pytest>=8"]

[project.scripts]
mt-pipeline = "mt_pipeline.cli:main"

[tool.uv.sources]
mt-contracts = { workspace = true }

[tool.hatch.build.targets.wheel]
packages = ["src/mt_pipeline"]

[tool.pytest.ini_options]
pythonpath = ["src"]
testpaths = ["tests"]
```

`pipeline/src/mt_pipeline/__init__.py`:
```python
"""Making Tracks data pipeline. Region-parameterised, deterministic, laptop-first."""
```

- [ ] **Step 5: Sync the workspace and run the smoke test**

Run (uv): `uv sync` (from repo root) — resolves the workspace into `.venv`.
Then: `cd pipeline && uv run python -m pytest tests/test_import.py -q`
Expected: PASS (1 passed) — assuming the A0 exports (preconditions) are present. If an export is missing, the assertion names it.
No-uv fallback (CI/dev without uv): `pip install -e ./contracts ./pipeline` into a 3.11 interpreter, then `cd pipeline && python -m pytest tests/test_import.py -q`.

- [ ] **Step 6: Commit**

```bash
git add pyproject.toml .python-version pipeline/pyproject.toml \
        pipeline/src/mt_pipeline/__init__.py pipeline/tests/test_import.py
git commit -m "Scaffold pipeline package as a uv-workspace member depending on mt-contracts"
```

---

### Task 2: SQLite working store + stage-completion ledger

**Files:**
- Create: `pipeline/src/mt_pipeline/store.py`, `pipeline/tests/conftest.py`
- Test: `pipeline/tests/test_store.py`

**Interfaces:**
- Consumes: stdlib `sqlite3`.
- Produces:
  - `store.WORKING_STORE_VERSION: int`.
  - `store.connect(db_path) -> sqlite3.Connection` (foreign keys on).
  - `store.init_schema(conn) -> None` (idempotent, deterministic; writes the meta version row).
  - `store.mark_stage_complete(conn, region, stage, run_id, completed_at) -> None` (upsert per (region, stage)).
  - `store.stage_completed(conn, region, stage) -> bool`.
  - `store.SOURCE_RECORDS_TABLE`, `store.STAGE_RUNS_TABLE`, `store.META_TABLE`.

- [ ] **Step 1: Write `conftest.py` and the failing test**

`pipeline/tests/conftest.py`:
```python
import pathlib
import pytest
from mt_pipeline import store

@pytest.fixture
def conn(tmp_path: pathlib.Path):
    c = store.connect(tmp_path / "work.db")
    store.init_schema(c)
    yield c
    c.close()
```

`pipeline/tests/test_store.py`:
```python
from mt_pipeline import store

def test_schema_is_idempotent_and_versioned(conn):
    store.init_schema(conn)  # second call must not raise
    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert {store.SOURCE_RECORDS_TABLE, store.STAGE_RUNS_TABLE, store.META_TABLE} <= tables
    ver = conn.execute(f"SELECT schema_version FROM {store.META_TABLE}").fetchone()[0]
    assert ver == store.WORKING_STORE_VERSION

def test_stage_completion_ledger(conn):
    assert store.stage_completed(conn, "uk", "extract") is False
    store.mark_stage_complete(conn, "uk", "extract", run_id="r1", completed_at="2026-07-14T00:00:00Z")
    assert store.stage_completed(conn, "uk", "extract") is True
    assert store.stage_completed(conn, "malaysia", "extract") is False  # per (region, stage)

def test_mark_stage_complete_is_upsert(conn):
    store.mark_stage_complete(conn, "uk", "extract", "r1", "2026-07-14T00:00:00Z")
    store.mark_stage_complete(conn, "uk", "extract", "r2", "2026-07-14T01:00:00Z")  # re-run
    rows = list(conn.execute(
        f"SELECT run_id FROM {store.STAGE_RUNS_TABLE} WHERE region=? AND stage=?", ("uk", "extract")))
    assert len(rows) == 1 and rows[0][0] == "r2"  # one row per (region, stage), latest wins
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_store.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_pipeline.store'`.

- [ ] **Step 3: Implement `store.py`**

`pipeline/src/mt_pipeline/store.py`:
```python
"""SQLite working store: the deterministic between-stages state.

Holds normalized source records and a stage-completion ledger used to enforce
§5.2 order. All writes are parameterised (never string-interpolated — Principle
10). completed_at / run_id are run METADATA and never feed a published value
(Principle 12). The store is ephemeral (re-created per run) and thus exempt from
§5.6 artefact versioning, but a meta row lets a stale-shaped DB fail loud."""
from __future__ import annotations

import pathlib
import sqlite3

WORKING_STORE_VERSION = 1
SOURCE_RECORDS_TABLE = "source_records"
STAGE_RUNS_TABLE = "stage_runs"
META_TABLE = "meta"

_SCHEMA = f"""
CREATE TABLE IF NOT EXISTS {META_TABLE} (schema_version INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS {SOURCE_RECORDS_TABLE} (
    id         INTEGER PRIMARY KEY,
    region     TEXT NOT NULL,
    source     TEXT NOT NULL,
    source_ref TEXT NOT NULL,
    name       TEXT NOT NULL,
    lat        REAL NOT NULL,
    lon        REAL NOT NULL,
    props_json TEXT NOT NULL,
    run_id     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_source_records_region ON {SOURCE_RECORDS_TABLE}(region);
CREATE TABLE IF NOT EXISTS {STAGE_RUNS_TABLE} (
    region       TEXT NOT NULL,
    stage        TEXT NOT NULL,
    run_id       TEXT NOT NULL,
    completed_at TEXT NOT NULL,
    PRIMARY KEY (region, stage)
);
"""


def connect(db_path: "str | pathlib.Path") -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(_SCHEMA)  # every statement is IF NOT EXISTS → idempotent
    # meta row: insert exactly once (idempotent — never duplicate on re-init)
    if conn.execute(f"SELECT COUNT(*) FROM {META_TABLE}").fetchone()[0] == 0:
        conn.execute(f"INSERT INTO {META_TABLE} (schema_version) VALUES (?)", (WORKING_STORE_VERSION,))
    conn.commit()


def mark_stage_complete(conn: sqlite3.Connection, region: str, stage: str,
                        run_id: str, completed_at: str) -> None:
    conn.execute(
        f"INSERT INTO {STAGE_RUNS_TABLE} (region, stage, run_id, completed_at) VALUES (?,?,?,?) "
        f"ON CONFLICT(region, stage) DO UPDATE SET run_id=excluded.run_id, completed_at=excluded.completed_at",
        (region, stage, run_id, completed_at))
    conn.commit()


def stage_completed(conn: sqlite3.Connection, region: str, stage: str) -> bool:
    row = conn.execute(
        f"SELECT 1 FROM {STAGE_RUNS_TABLE} WHERE region=? AND stage=?", (region, stage)).fetchone()
    return row is not None
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd pipeline && uv run python -m pytest tests/test_store.py -q`
Expected: PASS (3 passed).

- [ ] **Step 5: Commit**

```bash
git add pipeline/src/mt_pipeline/store.py pipeline/tests/conftest.py pipeline/tests/test_store.py
git commit -m "Add SQLite working store with meta version, stage ledger, and parameterised writes"
```

---

### Task 3: Region config loader (consumes A0)

**Files:**
- Create: `pipeline/src/mt_pipeline/config.py`
- Test: `pipeline/tests/test_config.py`

**Interfaces:**
- Consumes: `mt_contracts.load_region_config`, `mt_contracts.available_regions` (WP-A0 exports; field names per precondition 4).
- Produces:
  - `config.RegionConfig` (frozen dataclass: `region_id`, `display_name`, `bbox`, `languages`, `sources`, `basemap`, plus `raw` = the full validated dict so no A0 field is lost).
  - `config.load(region_id: str) -> RegionConfig` (raises `config.UnknownRegionError` for an unknown region; `config.ConfigError` for a malformed config).
  - `config.UnknownRegionError`, `config.ConfigError`.

- [ ] **Step 1: Write the failing test**

`pipeline/tests/test_config.py`:
```python
import pytest
from mt_pipeline import config

def test_load_known_region_returns_structurally_valid_config():
    cfg = config.load("uk")
    assert cfg.region_id == "uk"
    assert len(cfg.bbox) == 4                      # structural, not A0 magic values
    assert cfg.languages                           # non-empty
    assert isinstance(cfg.basemap.get("maxzoom"), int)
    assert cfg.raw["region_id"] == "uk"            # full dict retained, nothing dropped

def test_region_id_is_carried_through_not_hardcoded():
    # a hardcoded region_id in from_dict would fail this (region modularity, P17)
    assert config.load("malaysia").region_id == "malaysia"

def test_unknown_region_raises_naming_available():
    with pytest.raises(config.UnknownRegionError) as exc:
        config.load("atlantis")
    assert "uk" in str(exc.value)  # error lists available regions

def test_load_delegates_validation_to_contracts(monkeypatch):
    import mt_contracts
    called = {}
    real = mt_contracts.load_region_config
    def spy(region_id):
        called["region"] = region_id
        return real(region_id)
    monkeypatch.setattr(mt_contracts, "load_region_config", spy)
    config.load("malaysia")           # malaysia is a real A0 region (precondition 4)
    assert called["region"] == "malaysia"

def test_malformed_config_raises_config_error(monkeypatch):
    import mt_contracts
    monkeypatch.setattr(mt_contracts, "available_regions", lambda: ["uk"])
    monkeypatch.setattr(mt_contracts, "load_region_config", lambda r: {"region_id": "uk"})  # missing fields
    with pytest.raises(config.ConfigError):
        config.load("uk")
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_config.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_pipeline.config'`.

- [ ] **Step 3: Implement `config.py`**

`pipeline/src/mt_pipeline/config.py`:
```python
"""Resolve --region to a schema-validated A0 region config.

Validation and the region JSON are owned by mt_contracts; this module only loads
the requested region and exposes a typed convenience view (with the full validated
dict retained on `.raw`, so no A0 field is silently dropped). It never re-declares
the schema or hardcodes a region (Principle 17)."""
from __future__ import annotations

from dataclasses import dataclass

import mt_contracts

_FIELDS = ("region_id", "display_name", "bbox", "languages", "sources", "basemap")


class UnknownRegionError(ValueError):
    pass


class ConfigError(ValueError):
    pass


@dataclass(frozen=True)
class RegionConfig:
    region_id: str
    display_name: str
    bbox: tuple
    languages: tuple
    sources: dict
    basemap: dict
    raw: dict

    @classmethod
    def from_dict(cls, d: dict) -> "RegionConfig":
        missing = [f for f in _FIELDS if f not in d]
        if missing:
            raise ConfigError(f"region config missing fields: {missing}")
        return cls(
            region_id=d["region_id"],
            display_name=d["display_name"],
            bbox=tuple(d["bbox"]),
            languages=tuple(d["languages"]),
            sources=d["sources"],
            basemap=d["basemap"],
            raw=d,
        )


def load(region_id: str) -> RegionConfig:
    available = mt_contracts.available_regions()
    if region_id not in available:
        raise UnknownRegionError(
            f"unknown region {region_id!r}; available: {', '.join(sorted(available))}")
    data = mt_contracts.load_region_config(region_id)  # schema-validated by mt_contracts
    return RegionConfig.from_dict(data)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd pipeline && uv run python -m pytest tests/test_config.py -q`
Expected: PASS (5 passed).

- [ ] **Step 5: Commit**

```bash
git add pipeline/src/mt_pipeline/config.py pipeline/tests/test_config.py
git commit -m "Add region config loader consuming A0 mt_contracts (validation delegated, no A0 field dropped)"
```

---

### Task 4: Source-record model + hardened defensive parser (the extractor interface)

**Files:**
- Create: `pipeline/src/mt_pipeline/source_record.py`
- Test: `pipeline/tests/test_source_record.py`

**Interfaces:**
- Consumes: `mt_contracts.is_canonical_ref`, `mt_contracts.strip_unsafe_text` (WP-A0 exports), `store` (persistence).
- Produces:
  - `source_record.SourceRecord` (frozen dataclass: `region`, `source`, `source_ref`, `name`, `lat`, `lon`, `props` — the cleaned, owned copy).
  - `source_record.parse(region, source, source_ref, name, lat, lon, props) -> SourceRecord` — the one defensive-parse boundary every extractor (A1b/c/d) calls. Raises `SourceRecordError` on any invalid input. **No `run_id` parameter** (that is persistence metadata only).
  - `source_record.persist(conn, record, *, run_id) -> None`.
  - `source_record.SourceRecordError`; caps `NAME_MAX`, `RAW_TEXT_MAX`, `SOURCE_REF_MAX`, `PROPS_JSON_MAX`, `PROPS_MAX_DEPTH`, `PROPS_MAX_ITEMS`.

- [ ] **Step 1: Write the failing test**

`pipeline/tests/test_source_record.py`:
```python
import json
import pytest
from mt_pipeline import source_record as sr
from mt_pipeline import store

def _ok(**over):
    kw = dict(region="uk", source="wd", source_ref="wd:Q42", name="Big Ben",
              lat=51.5, lon=-0.12, props={"k": "v"})
    kw.update(over)
    return sr.parse(**kw)

def test_parse_accepts_valid_record():
    r = _ok()
    assert r.source_ref == "wd:Q42" and r.name == "Big Ben"

def test_parse_defers_ref_grammar_to_contracts(monkeypatch):
    # delegation, not re-declaration: flip the delegate and prove parse follows it.
    import mt_contracts
    monkeypatch.setattr(mt_contracts, "is_canonical_ref", lambda s: False)
    with pytest.raises(sr.SourceRecordError):
        _ok(source_ref="wd:Q42")               # normally valid, now rejected

def test_parse_source_prefix_must_match():
    with pytest.raises(sr.SourceRecordError):
        _ok(source="osm", source_ref="wd:Q42")

def test_parse_source_ref_length_capped():
    with pytest.raises(sr.SourceRecordError):
        _ok(source_ref="wd:Q" + "9" * sr.SOURCE_REF_MAX)

@pytest.mark.parametrize("lat,lon", [(91, 0), (-91, 0), (0, 181), (0, -181)])
def test_parse_bounds_coordinates_all_directions(lat, lon):
    with pytest.raises(sr.SourceRecordError):
        _ok(lat=lat, lon=lon)

def test_parse_accepts_boundary_coordinates():
    assert _ok(lat=90, lon=180) and _ok(lat=-90, lon=-180)

def test_parse_rejects_nonfinite_coordinates():
    with pytest.raises(sr.SourceRecordError):
        _ok(lat=float("nan"))

def test_parse_delegates_text_cleaning_to_contracts(monkeypatch):
    import mt_contracts
    monkeypatch.setattr(mt_contracts, "strip_unsafe_text", lambda s: s.replace("Z", ""))
    assert _ok(name="BigZ Ben").name == "Big Ben"   # parse used the (patched) A0 cleaner

def test_parse_caps_name_length():
    assert len(_ok(name="x" * 5000).name) <= sr.NAME_MAX

def test_parse_rejects_oversize_raw_name():
    with pytest.raises(sr.SourceRecordError):
        _ok(name="x" * (sr.RAW_TEXT_MAX + 1))

def test_parse_rejects_empty_or_whitespace_name():
    for bad in ["   ", "\t\n"]:
        with pytest.raises(sr.SourceRecordError):
            _ok(name=bad)

def test_props_must_be_dict():
    with pytest.raises(sr.SourceRecordError):
        _ok(props=["not", "a", "dict"])

def test_props_bounds_depth_and_count():
    deep = cur = {}
    for _ in range(sr.PROPS_MAX_DEPTH + 2):
        cur["x"] = {}; cur = cur["x"]
    with pytest.raises(sr.SourceRecordError):
        _ok(props=deep)
    with pytest.raises(sr.SourceRecordError):
        _ok(props={f"k{i}": 1 for i in range(sr.PROPS_MAX_ITEMS + 1)})

def test_props_rejects_nonstring_keys_and_nonfinite_and_bad_types():
    with pytest.raises(sr.SourceRecordError):
        _ok(props={1: "v"})                      # non-string key
    with pytest.raises(sr.SourceRecordError):
        _ok(props={"x": float("inf")})           # non-finite (A0 bans it too)
    with pytest.raises(sr.SourceRecordError):
        _ok(props={"x": b"bytes"})               # unsupported type

def test_props_string_values_are_cleaned(monkeypatch):
    import mt_contracts
    monkeypatch.setattr(mt_contracts, "strip_unsafe_text", lambda s: s.replace("Z", ""))
    r = _ok(props={"desc": "aZb", "nested": {"t": "cZd"}})
    assert r.props["desc"] == "ab" and r.props["nested"]["t"] == "cd"

def test_record_owns_props_not_caller_alias():
    src = {"k": "v"}
    r = _ok(props=src)
    src["k"] = "MUTATED"
    assert r.props["k"] == "v"                   # owned copy, no TOCTOU

def test_run_id_is_not_a_parse_parameter_and_not_a_field():
    import inspect
    assert "run_id" not in inspect.signature(sr.parse).parameters   # metadata only
    assert "run_id" not in sr.SourceRecord.__dataclass_fields__

def test_injection_hostile_name_through_production_persist(tmp_path):
    # drive a SQL-metacharacter name through the PRODUCTION insert path.
    conn = store.connect(tmp_path / "w.db"); store.init_schema(conn)
    rec = sr.parse(region="uk", source="wd", source_ref="wd:Q42",
                   name="Robert'); DROP TABLE source_records;--", lat=51.5, lon=-0.1, props={})
    sr.persist(conn, rec, run_id="r1")
    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert store.SOURCE_RECORDS_TABLE in tables            # table survived → parameterised
    assert conn.execute(f"SELECT name FROM {store.SOURCE_RECORDS_TABLE}").fetchone()[0].startswith("Robert')")
```

(Note: the delegation tests patch `mt_contracts.strip_unsafe_text`/`is_canonical_ref`; the un-patched real helpers keep `"Big Ben"` unchanged, so the plain tests still hold.)

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_source_record.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_pipeline.source_record'`.

- [ ] **Step 3: Implement `source_record.py`**

`pipeline/src/mt_pipeline/source_record.py`:
```python
"""The normalized source-record model: the single interface every extractor
(A1b/c/d) emits and reconcile (A2) consumes. `parse` is the one defensive-parse
boundary (Principle 10) — it DELEGATES ref-grammar and text-safety to
mt_contracts (never re-declaring them) and bounds/cleans the opaque props
sub-record. run_id is persistence metadata (Principle 12), not a parse input."""
from __future__ import annotations

import json
import math
from dataclasses import dataclass

import mt_contracts
from . import store

NAME_MAX = 300              # cleaned-name cap (published cap of 200 is enforced later in A7)
RAW_TEXT_MAX = 20000        # reject absurd raw strings BEFORE cleaning (pre-strip DoS guard)
SOURCE_REF_MAX = 128        # matches A0 place.source_refs items maxLength
PROPS_JSON_MAX = 65536      # serialized props cap
PROPS_MAX_DEPTH = 6
PROPS_MAX_ITEMS = 500       # per-container key/element count


class SourceRecordError(ValueError):
    pass


@dataclass(frozen=True)
class SourceRecord:
    region: str
    source: str
    source_ref: str
    name: str
    lat: float
    lon: float
    props: dict


def _clean_text(value, *, field: str) -> str:
    if not isinstance(value, str):
        raise SourceRecordError(f"{field} must be a string")
    if len(value) > RAW_TEXT_MAX:
        raise SourceRecordError(f"{field} exceeds raw length cap")
    return mt_contracts.strip_unsafe_text(value).strip()[:NAME_MAX]  # A0-owned denylist, keeps LRM/RLM


def _clean_props(node, depth: int = 0):
    if depth > PROPS_MAX_DEPTH:
        raise SourceRecordError("props nested too deep")
    if isinstance(node, dict):
        if len(node) > PROPS_MAX_ITEMS:
            raise SourceRecordError("props has too many keys")
        out = {}
        for k, v in node.items():
            if not isinstance(k, str):
                raise SourceRecordError("props keys must be strings")
            out[_clean_text(k, field="props key")] = _clean_props(v, depth + 1)
        return out
    if isinstance(node, list):
        if len(node) > PROPS_MAX_ITEMS:
            raise SourceRecordError("props list too long")
        return [_clean_props(v, depth + 1) for v in node]
    if isinstance(node, str):
        return _clean_text(node, field="props value")
    if node is None or isinstance(node, bool):
        return node
    if isinstance(node, int):
        return node
    if isinstance(node, float):
        if not math.isfinite(node):
            raise SourceRecordError("props contains a non-finite float")
        return node
    raise SourceRecordError(f"unsupported props value type: {type(node).__name__}")


def parse(region: str, source: str, source_ref: str, name: str,
          lat: float, lon: float, props: dict) -> SourceRecord:
    if not isinstance(region, str) or not (0 < len(region) <= 64):
        raise SourceRecordError("region invalid")
    if not isinstance(source_ref, str) or len(source_ref) > SOURCE_REF_MAX:
        raise SourceRecordError("source_ref missing or too long")
    if not mt_contracts.is_canonical_ref(source_ref):
        raise SourceRecordError(f"non-canonical source_ref: {source_ref!r}")
    if source_ref.split(":", 1)[0] != source:
        raise SourceRecordError(f"source {source!r} does not match source_ref {source_ref!r}")
    try:
        lat, lon = float(lat), float(lon)
    except (TypeError, ValueError):
        raise SourceRecordError("lat/lon not numeric")
    if not math.isfinite(lat) or not math.isfinite(lon):
        raise SourceRecordError("lat/lon must be finite")
    if not (-90.0 <= lat <= 90.0) or not (-180.0 <= lon <= 180.0):
        raise SourceRecordError(f"coordinates out of range: {lat},{lon}")
    clean_name = _clean_text(name, field="name")
    if not clean_name:
        raise SourceRecordError("name empty after cleaning")
    if not isinstance(props, dict):
        raise SourceRecordError("props must be a dict")
    clean_props = _clean_props(props)  # returns a NEW owned structure (no caller aliasing)
    # serialize at the boundary so a bad value is a clean error here, not a crash at persist
    serialized = json.dumps(clean_props, sort_keys=True, ensure_ascii=False, allow_nan=False)
    if len(serialized.encode("utf-8")) > PROPS_JSON_MAX:
        raise SourceRecordError("props too large after cleaning")
    return SourceRecord(region=region, source=source, source_ref=source_ref,
                        name=clean_name, lat=lat, lon=lon, props=clean_props)


def persist(conn, record: SourceRecord, *, run_id: str) -> None:
    conn.execute(
        f"INSERT INTO {store.SOURCE_RECORDS_TABLE} "
        f"(region, source, source_ref, name, lat, lon, props_json, run_id) VALUES (?,?,?,?,?,?,?,?)",
        (record.region, record.source, record.source_ref, record.name, record.lat, record.lon,
         json.dumps(record.props, sort_keys=True, ensure_ascii=False, allow_nan=False), run_id))
    conn.commit()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd pipeline && uv run python -m pytest tests/test_source_record.py -q`
Expected: PASS (all source-record tests green — delegation, bounds, props hardening, ownership, injection-through-production-persist).

- [ ] **Step 5: Commit**

```bash
git add pipeline/src/mt_pipeline/source_record.py pipeline/tests/test_source_record.py
git commit -m "Add hardened source-record parser (grammar+text-safety delegated, props bounded/cleaned)"
```

---

### Task 5: CLI + stage dispatch with §5.2 order enforcement + error mapping

**Files:**
- Create: `pipeline/src/mt_pipeline/stages.py`, `pipeline/src/mt_pipeline/cli.py`
- Test: `pipeline/tests/test_stages.py`, `pipeline/tests/test_cli.py`

**Interfaces:**
- Consumes: `config.load`, `store`, `stages`.
- Produces:
  - `stages.STAGE_ORDER == ("extract", "reconcile", "score", "categorize", "publish")`; `stages.predecessor(stage) -> str | None`; `stages.run_stage(conn, region, stage, *, run_id) -> None` (raises `stages.StageOrderError`); `stages.StageOrderError`.
  - `cli.main(argv=None) -> int` — `mt-pipeline --region <id> <stage> [--db <path>] [--run-id <id>]`; user errors → plain stderr + non-zero exit (no traceback).

- [ ] **Step 1: Write the failing stage tests**

`pipeline/tests/test_stages.py`:
```python
import pytest
from mt_pipeline import stages, store

def test_stage_order_is_the_spec_order():
    assert stages.STAGE_ORDER == ("extract", "reconcile", "score", "categorize", "publish")

def test_predecessor_mapping():
    assert stages.predecessor("extract") is None
    assert stages.predecessor("reconcile") == "extract"
    assert stages.predecessor("publish") == "categorize"

def test_first_stage_runs_without_predecessor(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    assert store.stage_completed(conn, "uk", "extract")

def test_skipping_immediate_predecessor_is_blocked_even_when_earlier_stage_done(conn):
    # THE headline invariant: an earlier stage being complete must NOT let you skip
    # the immediate predecessor. (Fails an impl that only checks 'extract'.)
    stages.run_stage(conn, "uk", "extract", run_id="r1")          # earlier stage done
    with pytest.raises(stages.StageOrderError) as exc:
        stages.run_stage(conn, "uk", "score", run_id="r1")         # reconcile skipped
    assert "reconcile" in str(exc.value)                           # names the immediate predecessor
    assert not store.stage_completed(conn, "uk", "score")          # did NOT record completion

def test_publish_blocked_names_categorize_after_extract_reconcile(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    stages.run_stage(conn, "uk", "reconcile", run_id="r1")
    with pytest.raises(stages.StageOrderError) as exc:
        stages.run_stage(conn, "uk", "publish", run_id="r1")       # score/categorize missing
    assert "categorize" in str(exc.value)

def test_full_order_runs(conn):
    for st in stages.STAGE_ORDER:
        stages.run_stage(conn, "uk", st, run_id="r1")
    assert store.stage_completed(conn, "uk", "publish")

def test_order_is_per_region(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    with pytest.raises(stages.StageOrderError):
        stages.run_stage(conn, "malaysia", "reconcile", run_id="r1")  # malaysia extract missing
```

`pipeline/tests/test_cli.py`:
```python
from mt_pipeline import cli, store

def test_cli_runs_a_stage(tmp_path):
    db = tmp_path / "w.db"
    assert cli.main(["--region", "uk", "extract", "--db", str(db)]) == 0
    conn = store.connect(db)
    assert store.stage_completed(conn, "uk", "extract")

def test_cli_rejects_unknown_region_without_traceback(tmp_path, capsys):
    rc = cli.main(["--region", "atlantis", "extract", "--db", str(tmp_path / "w.db")])
    assert rc == 2
    assert "atlantis" in capsys.readouterr().err  # plain message, not a traceback

def test_cli_enforces_stage_order(tmp_path, capsys):
    rc = cli.main(["--region", "uk", "publish", "--db", str(tmp_path / "w.db")])
    assert rc == 1
    assert "categorize" in capsys.readouterr().err  # names the missing predecessor

def test_cli_maps_db_open_failure_to_clean_error(tmp_path, capsys):
    bad = tmp_path / "no_such_dir" / "w.db"        # parent dir does not exist
    rc = cli.main(["--region", "uk", "extract", "--db", str(bad)])
    assert rc == 3
    assert "database" in capsys.readouterr().err.lower()  # plain message, no traceback
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd pipeline && uv run python -m pytest tests/test_stages.py tests/test_cli.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_pipeline.stages'`.

- [ ] **Step 3: Implement `stages.py`**

`pipeline/src/mt_pipeline/stages.py`:
```python
"""The five pipeline stages, wired as no-op-but-dispatchable in A1. Each enforces
§5.2 order — a stage refuses to run until its IMMEDIATE predecessor has recorded
completion for that region — then records its own completion. Domain logic lands
in later WPs (extract=A1b/c/d, reconcile=A2, score=A4, categorize=A3, publish=A7)."""
from __future__ import annotations

from . import store

STAGE_ORDER = ("extract", "reconcile", "score", "categorize", "publish")


class StageOrderError(RuntimeError):
    pass


def predecessor(stage: str) -> "str | None":
    if stage not in STAGE_ORDER:
        raise ValueError(f"unknown stage: {stage!r}")
    i = STAGE_ORDER.index(stage)
    return None if i == 0 else STAGE_ORDER[i - 1]


def run_stage(conn, region: str, stage: str, *, run_id: str) -> None:
    prev = predecessor(stage)
    if prev is not None and not store.stage_completed(conn, region, prev):
        raise StageOrderError(
            f"cannot run {stage!r} for region {region!r}: run {prev!r} first")
    # --- A1: no domain logic; later WPs implement the stage body here ---
    store.mark_stage_complete(conn, region, stage, run_id=run_id, completed_at=_completed_at())


def _completed_at() -> str:
    # run METADATA only (Principle 12): never feeds an id/hash/ordering/published
    # value. The ONLY sanctioned wall-clock call in the package (determinism guard).
    import datetime
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
```

- [ ] **Step 4: Implement `cli.py`**

`pipeline/src/mt_pipeline/cli.py`:
```python
"""Region-parameterised CLI: `mt-pipeline --region <id> <stage> [--db <path>]`.
Resolves the region against A0 config, then dispatches one ordered stage. Every
user/environment error becomes a plain stderr message + non-zero exit — never a
traceback. Exit codes: 2 unknown region, 1 stage-order, 3 store/config error."""
from __future__ import annotations

import argparse
import sqlite3
import sys

from . import config, stages, store

_DEFAULT_RUN_ID = "manual"  # metadata only; real runs pass a run id later


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="mt-pipeline", description="Making Tracks data pipeline.")
    p.add_argument("--region", required=True, help="region id (e.g. uk, malaysia)")
    p.add_argument("stage", choices=stages.STAGE_ORDER, help="pipeline stage to run")
    p.add_argument("--db", default="work.db", help="path to the SQLite working store")
    p.add_argument("--run-id", default=_DEFAULT_RUN_ID, help="run metadata tag")
    return p


def main(argv=None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        cfg = config.load(args.region)
    except config.UnknownRegionError as e:
        print(str(e), file=sys.stderr)
        return 2
    except config.ConfigError as e:
        print(f"config error: {e}", file=sys.stderr)
        return 3
    try:
        conn = store.connect(args.db)
        store.init_schema(conn)
    except sqlite3.Error as e:
        print(f"database error opening {args.db!r}: {e}", file=sys.stderr)
        return 3
    try:
        stages.run_stage(conn, cfg.region_id, args.stage, run_id=args.run_id)
    except stages.StageOrderError as e:
        print(str(e), file=sys.stderr)
        return 1
    print(f"{args.stage} complete for {cfg.region_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd pipeline && uv run python -m pytest tests/test_stages.py tests/test_cli.py -q`
Expected: PASS (7 stage tests + 4 cli tests = 11 passed).

- [ ] **Step 6: Commit**

```bash
git add pipeline/src/mt_pipeline/stages.py pipeline/src/mt_pipeline/cli.py \
        pipeline/tests/test_stages.py pipeline/tests/test_cli.py
git commit -m "Add region CLI + stage dispatch enforcing §5.2 order with clean error mapping"
```

---

### Task 6: Full-suite green + README + determinism guard + self-review

**Files:**
- Create: `pipeline/README.md`, `pipeline/tests/test_determinism.py`

- [ ] **Step 1: Write the determinism guard test**

`pipeline/tests/test_determinism.py`:
```python
import ast
import pathlib
from mt_pipeline import source_record, stages

# non-deterministic call attrs; the ONLY permitted one is datetime.now inside _completed_at
_BANNED = {"now", "utcnow", "time", "monotonic", "perf_counter",
           "random", "shuffle", "uuid4", "uuid1", "urandom", "randint", "choice"}

def test_metadata_is_never_a_record_field():
    fields = set(source_record.SourceRecord.__dataclass_fields__)
    assert "run_id" not in fields and "completed_at" not in fields

def test_no_wallclock_or_randomness_outside_completed_at():
    src_dir = pathlib.Path(stages.__file__).parent
    offenders = []
    for py in sorted(src_dir.glob("*.py")):
        tree = ast.parse(py.read_text())
        for node in ast.walk(tree):
            if isinstance(node, ast.Attribute) and node.attr in _BANNED:
                fn = _enclosing_func(tree, node)
                if not (py.name == "stages.py" and fn == "_completed_at" and node.attr == "now"):
                    offenders.append(f"{py.name}:{fn}:{node.attr}")
    assert offenders == [], f"non-determinism outside stages._completed_at: {offenders}"

def _enclosing_func(tree, target):
    for fn in [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]:
        if any(n is target for n in ast.walk(fn)):
            return fn.name
    return None
```

- [ ] **Step 2: Run the whole suite**

Run: `cd pipeline && uv run python -m pytest -q`
Expected: PASS (all Task 1–6 tests green).

- [ ] **Step 3: Write `pipeline/README.md`**

Content: what the pipeline is (extract→reconcile→score→categorize→publish, region-parameterised, laptop-first); setup (`uv sync` from repo root; **run tests/commands with `uv run`**; **no-uv fallback** `pip install -e ./contracts ./pipeline` into a 3.11 interpreter then bare `python -m pytest`); usage (`uv run mt-pipeline --region uk extract`); the stage-order rule (fail-loud on missing immediate predecessor); that A1 stages are dispatchable no-ops (domain logic in A1b–d/A2/A3/A4/A7); the source-record model as the single defensive extractor boundary (delegates grammar + text-safety to `mt_contracts`); determinism + untrusted-input posture; the working store is ephemeral.

- [ ] **Step 4: Self-review against the spec (run yourself)**

- **Scope coverage:** CLI scaffold + region param (T1,3,5); source-record model = extractor interface (T4); SQLite working store (T2); §5.2 immediate-predecessor order enforcement (T5); consumes A0, never re-declares grammar OR text-safety (T3,4). No extractor/reconcile logic.
- **Principle checks:** determinism guard (T6, metadata-only, wall-clock+randomness scanned); one hardened untrusted-input boundary incl. props (T4); parameterised SQL proven via production-path injection test (T4); region modularity (T3, carried-through test); ephemeral working store with meta version (T2).
- **Placeholder scan / type consistency:** `STAGE_ORDER`, `source_ref`, `RegionConfig` fields, `stage_completed`, `parse` (no `run_id`) signatures identical across tasks.

- [ ] **Step 5: Commit**

```bash
git add pipeline/README.md pipeline/tests/test_determinism.py
git commit -m "Add pipeline README, broadened determinism guard, and A1 self-review"
```

---

## Review Record

**Author self-review** — every WP-A1 deliverable maps to a task: CLI scaffold (T1/T5), region config consumption (T3), source-record model / extractor interface (T4), SQLite working store (T2), §5.2 immediate-predecessor order enforcement (T5, fable's scope addition). Stages are no-op-but-dispatchable; no reconcile stub. Consumes A0, never re-declares grammar or text-safety.

**Ratifications (fable, thread `wp/a1`)** — scope boundary (no-op stages, no reconcile stub); uv workspace for the `mt-contracts` dependency (no path deps); source-record model in `/pipeline` with ref validity delegated to `mt_contracts` and `extracted_at`/`run_id` as Principle-12 metadata; stage dispatch enforces §5.2 order (fail loud on a missing predecessor).

**Adversarial review (5 subagent critics + cross-examination, per AGENTS.md gate)** — raised findings across spec-fidelity, coherence, feasibility, security, and test-quality; after cross-examination the material fixes below were folded in:
- *Feasibility (HIGH):* `uv sync` installs into `.venv`, so a bare `python -m pytest` can't see `mt_contracts` — every command now uses `uv run`; added a repo-root `.python-version` (uv otherwise picked 3.14); `from_dict` on a malformed config now raises a typed `ConfigError` the CLI maps cleanly.
- *Security (HIGH):* `props` (the largest attacker surface — raw OSM tags/Wikidata claims) is now bounded (serialized-size/depth/count) and cleaned (string keys, string values cleaned, non-finite rejected, serialized at the boundary with `allow_nan=False`); `_clean_text` no longer re-declares A0's text rule — it **delegates to `mt_contracts.strip_unsafe_text`** (fixing both over-strip of LRM/RLM/ZWNJ that would corrupt Malay-Jawi/Arabic names AND under-strip of U+2028/2029 that A0 rejects); raw name/source_ref length-capped before processing (pre-strip DoS); the record now owns a deep-cleaned `props` copy (no caller-alias TOCTOU); the CLI maps `sqlite3.Error` to a clean non-zero exit; the false "parser validates https URLs" claim is removed (URL validation is an extractor + A0-publish concern, `props` being opaque at the A1 boundary).
- *Test-quality (HIGH):* the injection test now drives a hostile name through the **production** `persist` path (a quote survives cleaning, so it was a real untested surface); a new test proves an earlier-stage-complete state does NOT let you skip the **immediate** predecessor (the headline §5.2 invariant); ref-grammar and text-cleaning delegation are proven by monkeypatching the `mt_contracts` delegate; coordinate bounds are parametrised in all four directions plus boundary acceptance; whitespace-only name, source/prefix mismatch, and props edge cases are covered; the determinism guard now scans wall-clock **and** randomness; region modularity has a carried-through assertion.
- *Spec-fidelity / coherence:* the working store gets an explicit ephemeral-exemption note + a `meta(schema_version)` row (Principle 11); the dead `extracted_at` reference is dropped; `RegionConfig` retains the full validated dict on `.raw` so no A0 field is lost; the smoke test asserts the real A0 precondition surface; `CANONICAL_REF_RE` (unused) dropped from the precondition list; `parse`'s dead `run_id` parameter removed.

**Cross-package need surfaced (per AGENTS.md, not unilaterally changed)** — A1 requires WP-A0 to export, additively: `is_canonical_ref`, `strip_unsafe_text` (new — the text-safety stripper built from A0's existing `SAFE_TEXT` denylist, mirroring `is_canonical_ref`), `load_region_config`, `available_regions`, and to ship `schemas/`+`regions/`+`versions.json` as package data. Confirmed region-config field names: `region_id`, `display_name`, `bbox`, `languages`, `sources`, `basemap`. Flagged to fable on thread `wp/a1`; A0 is still on PR #26 so the additions are cheap.

**Spec note (surfaced, no plan change)** — §4 says the Malaysia heritage-register feasibility check is "part of WP-A1", but §8's A1d row makes it a separate spike; the plan correctly omits it per the confirmed scope. Worth reconciling §4's prose to point at A1d.
