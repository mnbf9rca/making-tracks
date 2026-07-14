# WP-A1 (Skeleton) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold the Python data pipeline — a region-parameterised CLI whose five stages (extract → reconcile → score → categorize → publish) are dispatchable no-ops that enforce §5.2 stage order, the normalized **source-record model** every extractor will implement, and the SQLite working store between stages — consuming WP-A0's contracts, so A1b/A1c/A1d extractors and A2 reconcile have a stable foundation.

**Architecture:** A `making-tracks-pipeline` package under `pipeline/`, a **uv workspace** member depending on `mt-contracts` (WP-A0). The CLI (stdlib `argparse`) resolves `--region` to a schema-validated A0 region config, and dispatches stage subcommands that refuse to run until their predecessor stage has recorded completion in the working store. The source-record model is a dataclass + defensive parser whose `source_ref` validity is **delegated to `mt_contracts`' exported canonical-ref grammar** (never re-declared here). All between-stage state lives in a deterministic SQLite working store.

**Tech Stack:** Python 3.11+, uv workspace, `mt-contracts` (WP-A0), stdlib `sqlite3` + `argparse`, `pytest`.

## Global Constraints

- **Python 3.11+; uv workspace.** Root `pyproject.toml` declares `[tool.uv.workspace] members = ['contracts', 'pipeline']`; `pipeline` depends on `mt-contracts` via `[tool.uv.sources] mt-contracts = { workspace = true }`. **No-uv fallback** (documented, must work): `pip install -e ./contracts -e ./pipeline` (that order). GHA later uses the same workspace resolution.
- **Consume A0, never re-declare it.** `source_ref` validity, the canonical-ref grammar, region-config schema, and region JSON are all owned by `mt_contracts`. The pipeline imports them; it never re-implements a grammar or re-parses a schema. When a source is added (append-only, per A0), there is exactly one place it happens — in `mt_contracts`.
- **Determinism (Principle 12).** No wall-clock or randomness in any *output* value. `extracted_at` and `run_id` are run **metadata only** — they never feed an id, a hash, an ordering, or any value that reaches a published artifact. A regression test asserts this.
- **All source data is untrusted (Principle 10 / §5.5).** The source-record parser defends every field: string length caps, control-character stripping, coordinate bounds-check, `https://`-only URLs; nothing from a source is interpolated into SQL (parameterised queries only) or a shell. Extractors (A1b/c/d) reuse this one parser.
- **Region modularity (Principle 17).** The active region is resolved from an A0 region config; no region id, bbox, or source list is hardcoded in pipeline logic. Adding a region is adding a config file in A0.
- **Stage order (§5.2).** `extract → reconcile → score → categorize → publish`. A stage refuses to run (fails loudly, naming the stage to run first) unless its immediate predecessor has recorded completion for that region. `extract` has no predecessor.
- **A1 is scaffolding only.** Stages are no-op-but-dispatchable: they validate inputs, enforce order, and record completion — they do **not** implement extract/reconcile/score/categorize/publish logic (those are A1b–d, A2, A4, A3, A7). No reconcile stub (that would prejudice A2's design).
- **Test-first.** Every module lands with a failing test first.

**Required WP-A0 exports (precondition — flagged to fable; A0 is on PR #26, additive).** A1 consumes two helpers that A0's `mt_contracts` package must export. Both are small and additive; the plan is written against them:
1. `mt_contracts.is_canonical_ref(s: str) -> bool` and `mt_contracts.CANONICAL_REF_RE` — the single source of the canonical-ref grammar `^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9._/-]*$` currently living only inside the JSON schemas.
2. `mt_contracts.load_region_config(region_id: str) -> dict` (reads the packaged, schema-validated region JSON) and `mt_contracts.available_regions() -> list[str]`. (This also requires A0 to ship `schemas/`, `regions/`, and `versions.json` as package data so a built wheel — not only an editable install — can read them.)

---

## File Structure

```
pyproject.toml                       # repo root: [tool.uv.workspace] members = ['contracts','pipeline'] (Task 1)
pipeline/
  pyproject.toml                     # name=making-tracks-pipeline; depends on mt-contracts (workspace) (Task 1)
  README.md                          # run instructions + no-uv fallback (Task 6)
  src/mt_pipeline/
    __init__.py
    store.py                         # SQLite working store: schema, connect, stage-completion ledger (Task 2)
    config.py                        # resolve --region to a validated A0 RegionConfig (Task 3)
    source_record.py                 # SourceRecord model + defensive parser + persistence (Task 4)
    stages.py                        # the five no-op-but-dispatchable stage fns + ORDER (Task 5)
    cli.py                           # argparse CLI: --region + stage subcommands, order enforcement (Task 5)
  tests/
    conftest.py                      # tmp working-store + a sample region monkeypatch
    test_store.py                    # Task 2
    test_config.py                   # Task 3
    test_source_record.py            # Task 4
    test_stages.py                   # Task 5
    test_cli.py                      # Task 5
```

Each module has one responsibility. `store.py` is the only module that touches SQLite; `source_record.py` is the one defensive-parse boundary every extractor reuses; `stages.py`/`cli.py` hold dispatch + order, no domain logic.

---

### Task 1: uv workspace + pipeline package scaffold

**Files:**
- Create: `pyproject.toml` (repo root), `pipeline/pyproject.toml`, `pipeline/src/mt_pipeline/__init__.py`
- Test: `pipeline/tests/test_import.py` (temporary smoke test, folded here)

**Interfaces:**
- Consumes: `mt-contracts` (WP-A0), resolved via the uv workspace.
- Produces: an installable `mt_pipeline` package that can `import mt_contracts`.

- [ ] **Step 1: Write the failing smoke test**

`pipeline/tests/test_import.py`:
```python
def test_pipeline_and_contracts_import():
    import mt_pipeline            # this package
    import mt_contracts          # the A0 dependency, resolved via the workspace
    assert mt_pipeline is not None
    assert hasattr(mt_contracts, "SCHEMA_VERSIONS") or hasattr(mt_contracts, "versions")
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && python -m pytest tests/test_import.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_pipeline'`.

- [ ] **Step 3: Create the root uv workspace**

Root `pyproject.toml` (create at repo root; if one already exists, merge these tables):
```toml
[tool.uv.workspace]
members = ["contracts", "pipeline"]
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

Run (uv): `uv sync` (from repo root) — resolves the workspace so `mt-contracts` is importable from `pipeline`.
No-uv fallback (documented for CI/dev without uv): `pip install -e ./contracts -e ./pipeline`.
Then: `cd pipeline && python -m pytest tests/test_import.py -q`
Expected: PASS (1 passed).

- [ ] **Step 6: Commit**

```bash
git add pyproject.toml pipeline/pyproject.toml pipeline/src/mt_pipeline/__init__.py pipeline/tests/test_import.py
git commit -m "Scaffold pipeline package as a uv-workspace member depending on mt-contracts"
```

---

### Task 2: SQLite working store + stage-completion ledger

**Files:**
- Create: `pipeline/src/mt_pipeline/store.py`
- Create: `pipeline/tests/conftest.py`
- Test: `pipeline/tests/test_store.py`

**Interfaces:**
- Consumes: stdlib `sqlite3`.
- Produces:
  - `store.connect(db_path) -> sqlite3.Connection` (foreign keys on; row factory set).
  - `store.init_schema(conn) -> None` (idempotent, deterministic DDL).
  - `store.mark_stage_complete(conn, region: str, stage: str, run_id: str, completed_at: str) -> None`.
  - `store.stage_completed(conn, region: str, stage: str) -> bool`.
  - `store.STAGE_RUNS_TABLE`, `store.SOURCE_RECORDS_TABLE` (table names).

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

def test_schema_is_idempotent(conn):
    store.init_schema(conn)  # second call must not raise
    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert {store.SOURCE_RECORDS_TABLE, store.STAGE_RUNS_TABLE} <= tables

def test_stage_completion_ledger(conn):
    assert store.stage_completed(conn, "uk", "extract") is False
    store.mark_stage_complete(conn, "uk", "extract", run_id="r1", completed_at="2026-07-14T00:00:00Z")
    assert store.stage_completed(conn, "uk", "extract") is True
    # per (region, stage): malaysia is unaffected
    assert store.stage_completed(conn, "malaysia", "extract") is False

def test_mark_stage_complete_is_upsert(conn):
    store.mark_stage_complete(conn, "uk", "extract", "r1", "2026-07-14T00:00:00Z")
    store.mark_stage_complete(conn, "uk", "extract", "r2", "2026-07-14T01:00:00Z")  # re-run
    rows = list(conn.execute(
        f"SELECT run_id FROM {store.STAGE_RUNS_TABLE} WHERE region=? AND stage=?", ("uk", "extract")))
    assert len(rows) == 1 and rows[0][0] == "r2"  # one row per (region, stage), latest wins

def test_source_records_uses_parameterised_insert(conn):
    # a hostile source_ref with SQL metacharacters must be stored verbatim, not executed
    hostile = "wd:Q1'); DROP TABLE source_records;--"
    conn.execute(
        f"INSERT INTO {store.SOURCE_RECORDS_TABLE} (region, source, source_ref, name, lat, lon, props_json, run_id) "
        f"VALUES (?,?,?,?,?,?,?,?)",
        ("uk", "wd", hostile, "x", 51.5, -0.1, "{}", "r1"))
    got = conn.execute(f"SELECT source_ref FROM {store.SOURCE_RECORDS_TABLE}").fetchone()[0]
    assert got == hostile  # table still exists; value stored literally
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && python -m pytest tests/test_store.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_pipeline.store'`.

- [ ] **Step 3: Implement `store.py`**

`pipeline/src/mt_pipeline/store.py`:
```python
"""SQLite working store: the deterministic between-stages state.

Holds normalized source records and a stage-completion ledger used to enforce
§5.2 stage order. All writes are parameterised (never string-interpolated —
Principle 10). completed_at / run_id here are run METADATA and never feed a
published value (Principle 12)."""
from __future__ import annotations

import pathlib
import sqlite3

SOURCE_RECORDS_TABLE = "source_records"
STAGE_RUNS_TABLE = "stage_runs"

_SCHEMA = f"""
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

Run: `cd pipeline && python -m pytest tests/test_store.py -q`
Expected: PASS (4 passed).

- [ ] **Step 5: Commit**

```bash
git add pipeline/src/mt_pipeline/store.py pipeline/tests/conftest.py pipeline/tests/test_store.py
git commit -m "Add SQLite working store with stage-completion ledger and parameterised writes"
```

---

### Task 3: Region config loader (consumes A0)

**Files:**
- Create: `pipeline/src/mt_pipeline/config.py`
- Test: `pipeline/tests/test_config.py`

**Interfaces:**
- Consumes: `mt_contracts.load_region_config`, `mt_contracts.available_regions` (WP-A0 exports).
- Produces:
  - `config.RegionConfig` (frozen dataclass: `region_id`, `display_name`, `bbox`, `languages`, `sources`, `basemap` — the validated fields).
  - `config.load(region_id: str) -> RegionConfig` (raises `config.UnknownRegionError` for an unknown region).
  - `config.UnknownRegionError`.

- [ ] **Step 1: Write the failing test**

`pipeline/tests/test_config.py`:
```python
import pytest
from mt_pipeline import config

def test_load_known_region_returns_validated_config():
    cfg = config.load("uk")
    assert cfg.region_id == "uk"
    assert len(cfg.bbox) == 4
    assert "en" in cfg.languages
    assert cfg.basemap["maxzoom"] == 14

def test_unknown_region_raises_naming_available():
    with pytest.raises(config.UnknownRegionError) as exc:
        config.load("atlantis")
    assert "uk" in str(exc.value)  # error lists available regions

def test_load_delegates_validation_to_contracts(monkeypatch):
    # config.load must run the record through mt_contracts validation, not its own.
    import mt_contracts
    called = {}
    real = mt_contracts.load_region_config
    def spy(region_id):
        called["region"] = region_id
        return real(region_id)
    monkeypatch.setattr(mt_contracts, "load_region_config", spy)
    config.load("malaysia")
    assert called["region"] == "malaysia"
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && python -m pytest tests/test_config.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_pipeline.config'`.

- [ ] **Step 3: Implement `config.py`**

`pipeline/src/mt_pipeline/config.py`:
```python
"""Resolve --region to a schema-validated A0 region config.

Validation and the region JSON are owned by mt_contracts; this module only
loads the requested region and exposes a typed view. It never re-declares the
schema or hardcodes a region (Principle 17)."""
from __future__ import annotations

from dataclasses import dataclass

import mt_contracts


class UnknownRegionError(ValueError):
    pass


@dataclass(frozen=True)
class RegionConfig:
    region_id: str
    display_name: str
    bbox: tuple[float, float, float, float]
    languages: tuple[str, ...]
    sources: dict
    basemap: dict

    @classmethod
    def from_dict(cls, d: dict) -> "RegionConfig":
        return cls(
            region_id=d["region_id"],
            display_name=d["display_name"],
            bbox=tuple(d["bbox"]),
            languages=tuple(d["languages"]),
            sources=d["sources"],
            basemap=d["basemap"],
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

Run: `cd pipeline && python -m pytest tests/test_config.py -q`
Expected: PASS (3 passed).

- [ ] **Step 5: Commit**

```bash
git add pipeline/src/mt_pipeline/config.py pipeline/tests/test_config.py
git commit -m "Add region config loader consuming A0 mt_contracts (validation delegated)"
```

---

### Task 4: Source-record model + defensive parser (the extractor interface)

**Files:**
- Create: `pipeline/src/mt_pipeline/source_record.py`
- Test: `pipeline/tests/test_source_record.py`

**Interfaces:**
- Consumes: `mt_contracts.is_canonical_ref` (WP-A0 export), `store` (persistence).
- Produces:
  - `source_record.SourceRecord` (frozen dataclass: `region`, `source`, `source_ref`, `name`, `lat`, `lon`, `props`).
  - `source_record.parse(region, source, source_ref, name, lat, lon, props, *, run_id) -> SourceRecord` — the one defensive-parse boundary every extractor (A1b/c/d) calls. Raises `SourceRecordError` on invalid input.
  - `source_record.SourceRecordError`.
  - `source_record.NAME_MAX` (defensive cap), `source_record.persist(conn, record, *, run_id) -> None`.

- [ ] **Step 1: Write the failing test**

`pipeline/tests/test_source_record.py`:
```python
import pytest
from mt_pipeline import source_record as sr
from mt_pipeline import store

def _ok(**over):
    kw = dict(region="uk", source="wd", source_ref="wd:Q42", name="Big Ben",
              lat=51.5, lon=-0.12, props={"k": "v"}, run_id="r1")
    kw.update(over)
    return sr.parse(**kw)

def test_parse_accepts_valid_record():
    r = _ok()
    assert r.source_ref == "wd:Q42" and r.name == "Big Ben"

def test_parse_rejects_noncanonical_source_ref_via_contracts():
    # grammar is owned by mt_contracts; pipeline delegates, never re-declares it.
    with pytest.raises(sr.SourceRecordError):
        _ok(source_ref="wd:Q42 ")   # trailing space is non-canonical
    with pytest.raises(sr.SourceRecordError):
        _ok(source_ref="WD:Q42")

def test_parse_bounds_coordinates():
    with pytest.raises(sr.SourceRecordError):
        _ok(lat=91.0)
    with pytest.raises(sr.SourceRecordError):
        _ok(lon=-181.0)

def test_parse_strips_control_chars_and_caps_length():
    r = _ok(name="Big" + chr(0x07) + "Ben" + "x" * 500)
    assert chr(0x07) not in r.name           # control char stripped
    assert len(r.name) <= sr.NAME_MAX        # length capped

def test_parse_rejects_empty_name_after_stripping():
    with pytest.raises(sr.SourceRecordError):
        _ok(name=chr(0x07) + chr(0x00))      # nothing left after stripping

def test_run_id_is_metadata_not_in_the_record():
    # Principle 12: run_id is metadata for persistence only; it is NOT a field of
    # the value object and never influences its identity/ordering.
    r = _ok(run_id="r1")
    assert not hasattr(r, "run_id")

def test_persist_roundtrips(tmp_path):
    conn = store.connect(tmp_path / "w.db"); store.init_schema(conn)
    sr.persist(conn, _ok(), run_id="r1")
    row = conn.execute(f"SELECT source_ref, run_id FROM {store.SOURCE_RECORDS_TABLE}").fetchone()
    assert row[0] == "wd:Q42" and row[1] == "r1"
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && python -m pytest tests/test_source_record.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_pipeline.source_record'`.

- [ ] **Step 3: Implement `source_record.py`**

`pipeline/src/mt_pipeline/source_record.py`:
```python
"""The normalized source-record model: the single interface every extractor
(A1b/c/d) emits and reconcile (A2) consumes. `parse` is the one defensive-parse
boundary (Principle 10). source_ref validity is delegated to mt_contracts'
canonical-ref grammar — never re-declared here. run_id is metadata (Principle 12)."""
from __future__ import annotations

import json
import unicodedata
from dataclasses import dataclass

import mt_contracts
from . import store

NAME_MAX = 300  # defensive cap; the published name cap (200) is enforced later in A7


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


def _clean_text(value: str) -> str:
    # strip C0/C1/DEL and format controls; collapse to a bounded plain string
    out = "".join(ch for ch in value if unicodedata.category(ch) not in ("Cc", "Cf"))
    return out.strip()[:NAME_MAX]


def parse(region: str, source: str, source_ref: str, name: str,
          lat: float, lon: float, props: dict, *, run_id: str) -> SourceRecord:
    if not mt_contracts.is_canonical_ref(source_ref):
        raise SourceRecordError(f"non-canonical source_ref: {source_ref!r}")
    if source_ref.split(":", 1)[0] != source:
        raise SourceRecordError(f"source {source!r} does not match source_ref {source_ref!r}")
    try:
        lat, lon = float(lat), float(lon)
    except (TypeError, ValueError):
        raise SourceRecordError("lat/lon not numeric")
    if not (-90.0 <= lat <= 90.0) or not (-180.0 <= lon <= 180.0):
        raise SourceRecordError(f"coordinates out of range: {lat},{lon}")
    clean = _clean_text(name)
    if not clean:
        raise SourceRecordError("name empty after stripping control characters")
    if not isinstance(props, dict):
        raise SourceRecordError("props must be a dict")
    return SourceRecord(region=region, source=source, source_ref=source_ref,
                        name=clean, lat=lat, lon=lon, props=props)


def persist(conn, record: SourceRecord, *, run_id: str) -> None:
    conn.execute(
        f"INSERT INTO {store.SOURCE_RECORDS_TABLE} "
        f"(region, source, source_ref, name, lat, lon, props_json, run_id) VALUES (?,?,?,?,?,?,?,?)",
        (record.region, record.source, record.source_ref, record.name,
         record.lat, record.lon, json.dumps(record.props, sort_keys=True), run_id))
    conn.commit()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd pipeline && python -m pytest tests/test_source_record.py -q`
Expected: PASS (7 passed).

- [ ] **Step 5: Commit**

```bash
git add pipeline/src/mt_pipeline/source_record.py pipeline/tests/test_source_record.py
git commit -m "Add source-record model + defensive parser (ref-grammar delegated to mt_contracts)"
```

---

### Task 5: CLI + stage dispatch with §5.2 order enforcement

**Files:**
- Create: `pipeline/src/mt_pipeline/stages.py`, `pipeline/src/mt_pipeline/cli.py`
- Test: `pipeline/tests/test_stages.py`, `pipeline/tests/test_cli.py`

**Interfaces:**
- Consumes: `config.load`, `store`, `stages`.
- Produces:
  - `stages.STAGE_ORDER: tuple[str, ...]` == `("extract", "reconcile", "score", "categorize", "publish")`.
  - `stages.predecessor(stage) -> str | None`.
  - `stages.run_stage(conn, region, stage, *, run_id) -> None` — enforces order (raises `stages.StageOrderError` if the predecessor is not complete), then records completion. No domain logic (A1 no-op).
  - `stages.StageOrderError`.
  - `cli.main(argv=None) -> int` — argparse CLI: `mt-pipeline --region <id> <stage> [--db <path>]`.

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

def test_later_stage_fails_loudly_when_predecessor_missing(conn):
    with pytest.raises(stages.StageOrderError) as exc:
        stages.run_stage(conn, "uk", "score", run_id="r1")  # reconcile not done
    assert "reconcile" in str(exc.value)  # names the stage to run first
    assert not store.stage_completed(conn, "uk", "score")   # did NOT record completion

def test_stage_runs_once_predecessor_complete(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    stages.run_stage(conn, "uk", "reconcile", run_id="r1")
    assert store.stage_completed(conn, "uk", "reconcile")

def test_order_is_per_region(conn):
    stages.run_stage(conn, "uk", "extract", run_id="r1")
    with pytest.raises(stages.StageOrderError):
        stages.run_stage(conn, "malaysia", "reconcile", run_id="r1")  # malaysia extract missing
```

`pipeline/tests/test_cli.py`:
```python
import pytest
from mt_pipeline import cli, store

def test_cli_runs_a_stage(tmp_path, capsys):
    db = tmp_path / "w.db"
    rc = cli.main(["--region", "uk", "extract", "--db", str(db)])
    assert rc == 0
    conn = store.connect(db)
    assert store.stage_completed(conn, "uk", "extract")

def test_cli_rejects_unknown_region(tmp_path):
    rc = cli.main(["--region", "atlantis", "extract", "--db", str(tmp_path / "w.db")])
    assert rc != 0  # non-zero exit, no traceback

def test_cli_enforces_stage_order(tmp_path, capsys):
    db = tmp_path / "w.db"
    rc = cli.main(["--region", "uk", "publish", "--db", str(db)])
    assert rc != 0
    assert "categorize" in capsys.readouterr().err  # names the missing predecessor
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd pipeline && python -m pytest tests/test_stages.py tests/test_cli.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_pipeline.stages'`.

- [ ] **Step 3: Implement `stages.py`**

`pipeline/src/mt_pipeline/stages.py`:
```python
"""The five pipeline stages, wired as no-op-but-dispatchable in A1. Each enforces
§5.2 order — a stage refuses to run until its predecessor has recorded completion
for that region — then records its own completion. Domain logic lands in later
WPs (extract=A1b/c/d, reconcile=A2, score=A4, categorize=A3, publish=A7)."""
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
    store.mark_stage_complete(conn, region, stage, run_id=run_id,
                              completed_at=_completed_at())


def _completed_at() -> str:
    # run METADATA only (Principle 12): never feeds an id/hash/ordering/published
    # value. Isolated here so its non-determinism cannot leak into stage logic.
    import datetime
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
```

- [ ] **Step 4: Implement `cli.py`**

`pipeline/src/mt_pipeline/cli.py`:
```python
"""Region-parameterised CLI: `mt-pipeline --region <id> <stage> [--db <path>]`.
Resolves the region against A0 config, then dispatches one ordered stage. Errors
exit non-zero with a plain message on stderr — never a traceback for user error."""
from __future__ import annotations

import argparse
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
        cfg = config.load(args.region)  # raises UnknownRegionError
    except config.UnknownRegionError as e:
        print(str(e), file=sys.stderr)
        return 2
    conn = store.connect(args.db)
    store.init_schema(conn)
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

Run: `cd pipeline && python -m pytest tests/test_stages.py tests/test_cli.py -q`
Expected: PASS (9 passed).

- [ ] **Step 6: Commit**

```bash
git add pipeline/src/mt_pipeline/stages.py pipeline/src/mt_pipeline/cli.py \
        pipeline/tests/test_stages.py pipeline/tests/test_cli.py
git commit -m "Add region CLI + stage dispatch enforcing §5.2 order (fail-loud on missing predecessor)"
```

---

### Task 6: Full-suite green + README + determinism guard + self-review

**Files:**
- Create: `pipeline/README.md`
- Test: `pipeline/tests/test_determinism.py`; run the whole suite.

- [ ] **Step 1: Write the determinism guard test**

`pipeline/tests/test_determinism.py`:
```python
import ast
import pathlib
from mt_pipeline import source_record, stages

def test_run_id_and_completed_at_are_not_record_fields():
    # Principle 12: metadata never becomes part of a value object.
    fields = {f.name for f in source_record.SourceRecord.__dataclass_fields__.values()}
    assert "run_id" not in fields and "completed_at" not in fields

def test_wallclock_is_isolated_to_completed_at():
    # datetime.now must appear ONLY in stages._completed_at, nowhere else in the
    # package — so non-determinism cannot leak into a stage body or output.
    src_dir = pathlib.Path(stages.__file__).parent
    offenders = []
    for py in src_dir.glob("*.py"):
        tree = ast.parse(py.read_text())
        for node in ast.walk(tree):
            if isinstance(node, ast.Attribute) and node.attr == "now":
                # allowed only inside _completed_at
                func = _enclosing_func(tree, node)
                if not (py.name == "stages.py" and func == "_completed_at"):
                    offenders.append(f"{py.name}:{func}")
    assert offenders == [], f"wall-clock used outside stages._completed_at: {offenders}"

def _enclosing_func(tree, target):
    for fn in [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]:
        if any(n is target for n in ast.walk(fn)):
            return fn.name
    return None
```

- [ ] **Step 2: Run the whole suite**

Run: `cd pipeline && python -m pytest -q`
Expected: PASS (all Task 1–6 tests green).

- [ ] **Step 3: Write `pipeline/README.md`**

Content: what the pipeline is (extract→reconcile→score→categorize→publish, region-parameterised, laptop-first); how to set up (`uv sync` from repo root; **no-uv fallback** `pip install -e ./contracts -e ./pipeline`); how to run (`mt-pipeline --region uk extract`); the stage-order rule; that A1 stages are dispatchable no-ops (domain logic in A1b–d/A2/A3/A4/A7); the source-record model as the extractor interface; determinism + untrusted-input posture.

- [ ] **Step 4: Self-review against the spec (run yourself)**

- **Scope coverage:** CLI scaffold + region param (Task 1,3,5); source-record model = extractor interface (Task 4); SQLite working store (Task 2); stage-order enforcement (Task 5); consumes A0, never re-declares (Task 3,4). No extractor/reconcile logic (deferred). 
- **Principle checks:** determinism guard (Task 6, run_id/completed_at metadata-only, wall-clock isolated); untrusted-input parse boundary (Task 4); parameterised SQL (Task 2); region modularity (Task 3, no hardcoded region); append-only single-source grammar (delegated to mt_contracts).
- **Placeholder scan / type consistency:** `STAGE_ORDER`, `source_ref`, `run_id`, `RegionConfig` fields, `stage_completed` signature identical across tasks.

- [ ] **Step 5: Commit**

```bash
git add pipeline/README.md pipeline/tests/test_determinism.py
git commit -m "Add pipeline README, determinism guard test, and A1 self-review"
```

---

## Self-Review (plan author)

**Scope coverage** — every WP-A1 deliverable maps to a task: CLI scaffold (T1/T5), region config consumption (T3), source-record model / extractor interface (T4), SQLite working store (T2), §5.2 stage-order enforcement (T5, fable's scope addition). Stages are no-op-but-dispatchable; no reconcile stub (A2's job).

**Consumes A0, never re-declares** — `source_ref` grammar via `mt_contracts.is_canonical_ref` (T4); region schema+JSON via `mt_contracts.load_region_config`/`available_regions` (T3); the pipeline holds no copy of either.

**Determinism (Principle 12)** — `run_id`/`completed_at` are metadata, asserted not to be record fields; wall-clock is isolated to `stages._completed_at` and a guard test fails if it appears anywhere else.

**Untrusted input (Principle 10)** — one defensive-parse boundary (`source_record.parse`: ref-grammar delegation, coord bounds, control-char strip, length cap); all SQL parameterised (a hostile `source_ref` test proves no injection).

**Cross-package dependency surfaced (per AGENTS.md, not unilaterally changed)** — A1 requires two small **additive** WP-A0 exports from `mt_contracts`: (1) `is_canonical_ref` / `CANONICAL_REF_RE`; (2) `load_region_config` / `available_regions` (+ shipping `schemas/`+`regions/`+`versions.json` as package data). Flagged to fable on thread `wp/a1`; A0 is still on PR #26 so the additions are cheap. The plan is written against these interfaces.
