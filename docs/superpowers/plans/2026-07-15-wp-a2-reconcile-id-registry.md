# WP-A2 (Reconcile + ID Registry) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The `reconcile` stage — cluster `source_records` into places, mint a **stable `place_id`** per cluster, and maintain a persistent **ID registry** keyed on the union of every ref ever clustered, so upstream churn (Wikidata QID merges, OSM `wikidata=*` tag changes) **never re-mints or reassigns an id**. Conservative fuzzy fallback; ambiguous cases deferred to a review file (never auto-merged); tombstones, never deletes. Deterministic and re-runnable.

**Architecture:** A new `mt_pipeline.reconcile` package under `pipeline/`. It consumes `source_records` (from A1's store) and a Wikidata redirect-map snapshot, produces a local JSONL **registry file** (records conforming to A0's `registry-record.schema.json`), a **places table** for downstream stages, and a **review file** (the A6/human adjudication seam). It uses A0's frozen `mt_contracts` id/registry API — `mint_place_id`, `select_mint_anchor`, `resolve_by_refs`, `resolve_superseded`, `AmbiguousRefsError` — and never re-implements minting or lookup.

**Tech Stack:** Python 3.11+ (`mt_pipeline` + `mt-contracts`), stdlib (`json`/`math`/`difflib`/`unicodedata`), `jsonschema` (already an A0 dep), `pytest`. No new heavy deps.

## Global Constraints

- **The mint anchor is used ONCE and NEVER re-selected (adversarial-review §1 — THE invariant).** Stated exactly (fable): **we never recompute `select_mint_anchor` for a known place.** `mint_place_id(select_mint_anchor(refs))` runs **only for a brand-new cluster** (no existing place matches its refs). An existing place is found by `registry.resolve_by_refs(records, refs)` (union-of-refs overlap) and its `place_id` is **reused unchanged** — the anchor is **never recomputed**. A cluster gaining a higher-priority ref (a QID merge, an OSM feature gaining `wikidata=*`) therefore keeps its id. **Re-anchoring an existing place is the §1 critical bug; this plan must never do it.** (Anchor priority `wd<osm(node<way<rel)<hehle<plaque<wp` is mint-time determinism only, meaningless after mint.)
- **QID-merge stability via redirect-bridging (§5.2 / §7 regression).** Wikidata merges a duplicate QID into a winner (loser → redirect). Every run loads a **redirect-map snapshot** and canonicalizes QIDs (transitively, cycle-safe) on **both** the incoming record refs **and** the registry's stored refs **before** `resolve_by_refs`, so a place shipped on `wd:Q123` still matches when the source now reports the winner `wd:Q456`. On match, the canonical winner ref is **added** to the place's union (keeping the historical ref too — the union of *every* ref ever clustered). This is what makes "QID A merged into B keeps `place_id` stable" (§7) hold.
- **Redirect-map provenance + freshness gate (fable).** The redirect map is an **acquisition artifact** with the same discipline as every snapshot: dated, self-describing (a `_meta` block with `snapshot_date`, `wikidata_snapshot_date`, `complete: true`), segments-complete-or-abort. **Reconcile REFUSES to run when the redirect map is missing, incomplete, or *older* than the Wikidata `source_records` snapshot it is reconciling** — a stale-inversion (reconciling fresh Wikidata against an old redirect map) would miss merges and mint duplicate ids / mis-merge. The *acquisition* (WDQS query for redirects among the KNOWN QID set = registry union ∪ incoming refs, segmented — bounded and cheap vs a full dump) is **codex's `wp/acquire-and-run` scope** (flagged to fable); A2 designs the **consumption + the refusal gate** only.
- **`superseded_by` is adjudication-only — A2 NEVER auto-merges two shipped ids (Principle 9).** `resolve_by_refs` raising `AmbiguousRefsError(place_ids)` means a cluster's refs bridge **two distinct existing places**. The conservative default (a false merge corrupts user data; a false split is merely ugly) is to **keep them split** and **emit the case to the review file** for A6/human adjudication. A2 ships the `superseded_by` *writer* (soft-supersede: keep-both, transitive winner, winner-only in tiles — via A0's `resolve_superseded`/`tile_winner_violations`) but applies it **only from an adjudication decision**, never automatically.
- **Conservative fuzzy fallback — DEFER-ONLY, never auto-merge (Principle 9; tightened from the ratified band after the gate found empirical false-merges — flagged to fable).** Fuzzy runs **only between clusters with no shared ref** (QID/OSM-join clustering wins first) — i.e. exactly where the evidence is *weakest* (no corroborating id). The gate proved that even `sim ≥ 0.92 ∧ ≤ 50 m` **auto-merge false-merges real Malaysia data**: two distinct KL temples with different Chinese/Tamil/Jawi names ~30 m apart, and two distinct generic-named places (*Surau*, *Tandas*, *Warung*) ~13 m apart. So A2 **never fuzzy-auto-merges** — a fuzzy candidate is only ever **deferred to the review file** (the §5.2 "ambiguous middle cases can be LLM-adjudicated" home) or **split**. A pair is **deferred** when both names have a non-trivial normalized form (≥ `MIN_ALNUM` alnum chars) **and** `sim ≥ FUZZY_SIM_DEFER` (0.85) **and** `dist ≤ FUZZY_DIST_DEFER_M` (150 m); otherwise **split**. **A cluster that fuzzy-matches more than one other is deferred, never assigned.** Thresholds live in `pipeline/config/reconcile.json` (a `FuzzyConfig` **threaded into `reconcile.reconcile`**, not read from disk by the pure core); WP-A5's eval tunes them. Result: a genuine no-QID duplicate ships as two places (a false split — "merely ugly", Principle 9) until A6/human adjudication merges them via the review file — never a silent immutable false merge.
- **Name normalization is Unicode-aware and cannot collapse a real name to nothing (§5.5).** `normalize_name`: NFKD → drop combining marks (diacritics: `café→cafe`) → casefold → replace every **non-alphanumeric** run (Unicode `str.isalnum`, so **CJK / Tamil / Arabic letters are KEPT**, not stripped) with one space → collapse → `strip()`, with a **256-char cap** applied first (DoS bound). `观音亭` → `观音亭` (not `""`); `天后宫` → `天后宫`; their similarity ≈ 0, so they **split** — never the sim-1.0 empty-string false-merge the gate found. A normalized form shorter than `MIN_ALNUM` is **never a fuzzy candidate** (belt-and-suspenders for all-punctuation/emoji names).
- **Deterministic + re-runnable (Principle 12).** Same `source_records` + same registry + same redirect map + same `--version` → **identical** clusters, ids, registry, places, and review file. QID/OSM clustering is union-find (order-independent connected components); fuzzy candidate pairs are enumerated and processed in a **fixed sorted order**; output files sort by `place_id`. **No wall-clock/randomness** — `first_shipped_version`/`last_seen_version` are the passed-in `--version` (a `^[0-9]{8}T[0-9]{6}Z$` run parameter, like `--run-id`), never `datetime.now()`.
- **Registry lifecycle: LOCAL file first (laptop-first); R2 is a thin deferred adapter.** The registry is a local JSONL file (one schema-validated `RegistryRecord` per line, sorted by `place_id`). Load at stage start, write atomically at stage end. R2 persistence (§5.2 "in R2", single-writer under GHA `concurrency`, "updated only on successful publish") is a **thin adapter** deferred to `WP-A2-publish`/A7 — the load/save interface is `RegistryStore`, with a `LocalRegistryStore` now and an `R2RegistryStore` later; no reconcile logic changes.
- **Tombstones, never delete — with a source-success condition (Principle 7, fable).** A live place with **no** member `source_record` this run is **never deleted**; whether its absence advances *staleness* depends on WHY it is absent, and the three cases must be distinguished so **one bad Historic England run cannot start tombstoning every English listed building**:
  - **vanished-from-a-successful-extract** — every source that historically contributed to the place was **enabled AND its extract succeeded** this run, yet the place has no member → the absence is real → **tick staleness** (eligible for tombstone after `TOMBSTONE_AFTER_VERSIONS`, default conservative).
  - **source-failed** — a contributing source was enabled but its extract **failed** this run → **do NOT tick** (a gap, not a disappearance); hold `last_seen`.
  - **source-disabled** — a contributing source is **not enabled** for this region/run (e.g. Malaysia's disabled HE/plaques) → **do NOT tick** (absence-by-config is not disappearance).
  **Encoding (no `RegistryRecord` schema change):** `last_seen_version` is the last version at which the place's presence/absence was *trustworthy*. Present → `last_seen = version`. Absent-but-verified (all contributing sources ∈ `succeeded_sources`) → `last_seen` **held** (it ages → eventual tombstone by the deferred `TOMBSTONE_AFTER_VERSIONS` policy). Absent-but-unverifiable (any contributing source failed or is disabled) → `last_seen` **advanced** to `version` (we could not confirm the vanish, so we do not age it). Reconcile receives `succeeded_sources` (enabled sources whose extract **succeeded** this run, from `stage_runs` ∩ region config). A tombstoned place's id and refs remain valid forever and still `resolve_by_refs`/`resolve_superseded`.
- **Ref budget — the schema caps `refs` at `maxItems: 256` (fixes the registry-brick DoS the gate found).** The union grows monotonically (QID-bridging keeps historical refs), and a hostile actor can tag hundreds of OSM nodes `wikidata=Q<famous>` so they all accrete onto one place — a 257-ref record fails `registry-record.schema.json` validation on save and, because the save is atomic, **bricks the whole region's registry permanently**. So reconcile enforces `MAX_REFS_PER_PLACE = 256` **before** save: it keeps `mint_anchor` + **all** `wd:` refs (the join keys that must never be dropped, for QID-merge stability) + the highest-priority refs, and **evicts the lowest-priority overflow** (surplus `osm:node`/`wp` refs), and **emits a review item** when a place nears the cap (a merge-magnet likely needing adjudication). Dropping a `wd:` ref is forbidden (it would break `resolve_by_refs` QID stability); the eviction only ever sheds low-priority, non-anchor refs.
- **§5.5 untrusted data.** Clustering runs over adversarially-controllable names/coords/tags. Coordinates are already A1-bounds-checked; names are re-normalized before fuzzy comparison; nothing is interpolated into SQL unescaped (parameterized) or into any prompt (LLM adjudication is A6, and delimits source text there). A vandalized record can shift a cluster but **cannot** force a false auto-merge (fuzzy is conservative + ambiguity defers).
- **Uses A0's contracts, never re-implements them — exact import paths (verified against develop).** `from mt_contracts.place_id import mint_place_id, select_mint_anchor` and `from mt_contracts.registry import RegistryRecord, resolve_by_refs, resolve_superseded, assert_no_supersede_cycles, tile_winner_violations, AmbiguousRefsError`. **These are NOT re-exported at the top level** — only `is_canonical_ref`, `strip_unsafe_text`, `load_region_config`, `available_regions` are (`import mt_contracts; mt_contracts.is_canonical_ref(...)`). The record shape + supersede/tombstone semantics are A0's; A2 orchestrates them.
- **LLM adjudication (A6) is OUT.** A2 produces the review file (the seam); A6 (or a human) adjudicates. A2 depends on A1b/A1c/A1d (all merged) for real `source_records`.

**Ratified (fable, thread `wp/a2`)** — the never-re-anchor invariant; redirect-bridging for QID-merge stability; supersede is adjudication-only (AmbiguousRefsError → keep-split + review); local JSONL registry (R2 = thin deferred adapter); conservative fuzzy (sim≥0.92 ∧ ≤50 m auto, middle band defers, >1-match defers); versions are a run parameter; real-malaysia end-to-end as the final task.

---

## File Structure

```
pipeline/src/mt_pipeline/reconcile/
  __init__.py
  redirects.py          # Wikidata redirect-map: load snapshot + canonicalize_ref (transitive, cycle-safe)
  refs.py               # refs_of(record, redirect_map) -> canonical ref set (own ref + wd QID join)
  cluster.py            # union-find over shared refs + conservative name+distance fuzzy fallback + ambiguity
  registry_file.py      # RegistryStore protocol; LocalRegistryStore (JSONL, schema-validated, sorted)
  review.py             # the ambiguity review-file writer (AmbiguousRefsError + borderline fuzzy) — A6 seam
  reconcile.py          # the stage: orchestrate load→bridge→resolve→mint/reuse→tombstone→persist
pipeline/config/
  reconcile.json        # fuzzy thresholds + file paths (config, not code)
pipeline/src/mt_pipeline/
  stages.py             # MODIFY: reconcile branch calls reconcile.run
  store.py              # MODIFY: add the places table (place_id, name, lat, lon, refs, members, status)
  cli.py                # MODIFY: accept --version (publish_version) for the reconcile stage
pipeline/tests/
  test_reconcile_redirects.py
  test_reconcile_refs.py
  test_reconcile_cluster.py
  test_reconcile_registry_file.py
  test_reconcile_core.py            # mint/reuse/redirect-bridge/ambiguity/tombstone + the §7 churn regressions
  test_reconcile_review.py
  test_reconcile_stage.py           # wiring + determinism guard
  fixtures/reconcile/...            # tiny source-record + redirect + registry fixtures
```

---

### Task 1: Wikidata redirect map — load + canonicalize (transitive, cycle-safe)

**Files:**
- Create: `pipeline/src/mt_pipeline/reconcile/redirects.py`
- Test: `pipeline/tests/test_reconcile_redirects.py`

**Interfaces:**
- Produces:
  - `redirects.RedirectSnapshot` — `dataclass(map: dict[str,str], snapshot_date: str, wikidata_snapshot_date: str, complete: bool)`.
  - `redirects.load_redirect_snapshot(path | None) -> RedirectSnapshot` — reads a JSON `{ "_meta": {"snapshot_date","wikidata_snapshot_date","complete"}, "redirects": {"Q123":"Q456",...} }`; a missing/None path → an **empty-but-complete** snapshot only if the caller opts in (dev); otherwise the reconcile stage's freshness gate refuses. Bounds size; rejects non-`Q[0-9]+` entries and a `complete != true` map (segments-complete-or-abort).
  - `redirects.assert_fresh(snap, wikidata_snapshot_date) -> None` — raises `RedirectMapError` when the redirect snapshot is **older than** the Wikidata `source_records` snapshot being reconciled (staleness inversion → missed merges). Reconcile calls this before clustering.
  - `redirects.canonical_qid(qid, m) -> str` — follows the chain transitively (`Q1→Q2→Q3` ⇒ `Q3`), **cycle-safe** (returns the entry point on a cycle, logs once — never loops).
  - `redirects.canonicalize_ref(ref, m) -> str` — `wd:Q123` → `wd:<canonical_qid>`; any non-`wd:` ref returned unchanged.

- [ ] **Step 1: Write the failing tests**

`test_reconcile_redirects.py`:
```python
import json
import pytest
from mt_pipeline.reconcile import redirects

def test_canonical_qid_follows_chain_transitively():
    m = {"Q1": "Q2", "Q2": "Q3"}
    assert redirects.canonical_qid("Q1", m) == "Q3"
    assert redirects.canonical_qid("Q3", m) == "Q3"        # terminal winner
    assert redirects.canonical_qid("Q99", m) == "Q99"      # not redirected

def test_canonicalize_ref_only_touches_wd():
    m = {"Q1": "Q2"}
    assert redirects.canonicalize_ref("wd:Q1", m) == "wd:Q2"
    assert redirects.canonicalize_ref("osm:node/5", m) == "osm:node/5"   # untouched

def test_cycle_is_safe_not_infinite():
    m = {"Q1": "Q2", "Q2": "Q1"}                           # hostile cycle
    assert redirects.canonical_qid("Q1", m) in {"Q1", "Q2"}   # terminates, does not hang

def test_load_rejects_hostile_or_incomplete_snapshot(tmp_path):
    p = tmp_path / "r.json"
    p.write_text(json.dumps({"_meta": {"complete": True, "snapshot_date": "20260715T000000Z",
                                       "wikidata_snapshot_date": "20260715T000000Z"},
                             "redirects": {"not-a-qid": "Q1"}}))
    with pytest.raises(redirects.RedirectMapError):
        redirects.load_redirect_snapshot(p)                      # non-QID entry
    p.write_text(json.dumps({"_meta": {"complete": False}, "redirects": {}}))
    with pytest.raises(redirects.RedirectMapError):
        redirects.load_redirect_snapshot(p)                      # not complete → abort

def test_freshness_gate_refuses_stale_redirect_map(tmp_path):
    snap = redirects.RedirectSnapshot(map={}, snapshot_date="20260714T000000Z",
                                      wikidata_snapshot_date="20260714T000000Z", complete=True)
    redirects.assert_fresh(snap, "20260714T000000Z")             # equal → OK
    with pytest.raises(redirects.RedirectMapError):
        redirects.assert_fresh(snap, "20260715T000000Z")         # wikidata NEWER than redirects → refuse
```

- [ ] **Step 2–4: Run-fail, implement, run-pass**

Run: `cd pipeline && uv run python -m pytest tests/test_reconcile_redirects.py -q` (FAIL → implement → PASS).

`pipeline/src/mt_pipeline/reconcile/redirects.py`:
```python
"""Wikidata redirect map: a merged (loser) QID resolves to its winner. Consumed as a dated
snapshot (acquisition deferred — see Cross-package needs). Untrusted: bounded + shape-checked."""
from __future__ import annotations

import json
import logging
import pathlib
import re
from dataclasses import dataclass

MAX_REDIRECT_ENTRIES = 20_000_000
_QID = re.compile(r"Q[0-9]+")
_DATE = re.compile(r"[0-9]{8}T[0-9]{6}Z")
_log = logging.getLogger(__name__)


class RedirectMapError(Exception):
    pass


@dataclass
class RedirectSnapshot:
    map: dict
    snapshot_date: str
    wikidata_snapshot_date: str
    complete: bool


def load_redirect_snapshot(path) -> RedirectSnapshot:
    if path is None:                                   # dev/no-redirects; the stage's freshness gate decides
        return RedirectSnapshot({}, "", "", complete=True)
    p = pathlib.Path(path)
    try:
        data = json.loads(p.read_text())
    except (ValueError, OSError) as e:
        raise RedirectMapError(f"unreadable redirect map {p}: {e}") from e
    meta = data.get("_meta") if isinstance(data, dict) else None
    reds = data.get("redirects") if isinstance(data, dict) else None
    if not isinstance(meta, dict) or not isinstance(reds, dict) or len(reds) > MAX_REDIRECT_ENTRIES:
        raise RedirectMapError("redirect snapshot must be {_meta, redirects} and bounded")
    if meta.get("complete") is not True:               # segments-complete-or-abort
        raise RedirectMapError("redirect snapshot is not marked complete")
    for k, v in reds.items():
        if not (_QID.fullmatch(k) and _QID.fullmatch(v)):
            raise RedirectMapError(f"non-QID redirect entry: {k!r}->{v!r}")
    return RedirectSnapshot(map=reds, snapshot_date=str(meta.get("snapshot_date", "")),
                            wikidata_snapshot_date=str(meta.get("wikidata_snapshot_date", "")),
                            complete=True)


def assert_fresh(snap: RedirectSnapshot, wikidata_snapshot_date: str) -> None:
    # Refuse a stale-inversion: reconciling fresh Wikidata against an older redirect map misses merges.
    if snap.snapshot_date and wikidata_snapshot_date and snap.snapshot_date < wikidata_snapshot_date:
        raise RedirectMapError(
            f"redirect map ({snap.snapshot_date}) is older than the wikidata snapshot "
            f"({wikidata_snapshot_date}) — refusing to reconcile (staleness inversion)")


def canonical_qid(qid: str, m: dict) -> str:
    seen: list[str] = []
    cur = qid
    while cur in m and cur not in seen:
        seen.append(cur)
        cur = m[cur]
    if cur in seen:
        # a hostile/real redirect cycle: pick a DETERMINISTIC representative (min of the cycle) so
        # every entry point agrees — else Q1 and Q2 in a 2-cycle bridge to different reps → duplicate id.
        cycle = seen[seen.index(cur):]
        rep = min(cycle)
        _log.warning("redirect cycle %s -> representative %s (surface to review)", cycle, rep)
        return rep
    return cur


def canonicalize_ref(ref: str, m: dict) -> str:
    if ref.startswith("wd:") and m:
        return "wd:" + canonical_qid(ref[3:], m)
    return ref
```

- [ ] **Step 5: Commit** — `git commit -m "Add Wikidata redirect map (transitive, cycle-safe, bounded)"`

---

### Task 2: Ref extraction per source_record (own ref + QID join)

**Files:**
- Create: `pipeline/src/mt_pipeline/reconcile/refs.py`
- Test: `pipeline/tests/test_reconcile_refs.py`

**Interfaces:**
- Consumes: a `source_record` row (`source`, `source_ref`, `props`), `redirects.RedirectMap`.
- Produces: `refs.refs_of(source, source_ref, props, redirect_map) -> set[str]` — the record's **canonical ref set**: its own `source_ref` (redirect-canonicalized) **plus** `wd:<props["wikidata"]>` when present and QID-shaped (the free join for `osm`/`wp` records, §5.2), also canonicalized. Invalid QID join values are dropped (never a garbage ref). Every returned ref satisfies `mt_contracts.is_canonical_ref`.

- [ ] **Step 1: Failing test**

`test_reconcile_refs.py`:
```python
from mt_pipeline.reconcile import refs

def test_own_ref_plus_qid_join_canonicalized():
    m = {"Q1": "Q2"}
    # an OSM record carrying wikidata=Q1 → its own ref + the redirect-resolved QID join
    out = refs.refs_of("osm", "osm:node/5", {"wikidata": "Q1"}, m)
    assert out == {"osm:node/5", "wd:Q2"}

def test_wd_record_own_ref_is_canonicalized():
    out = refs.refs_of("wd", "wd:Q1", {}, {"Q1": "Q2"})
    assert out == {"wd:Q2"}

def test_garbage_qid_join_is_dropped():
    out = refs.refs_of("wp", "wp:12345", {"wikidata": "not-a-qid"}, {})
    assert out == {"wp:12345"}                        # bad join dropped, own ref kept
```

- [ ] **Steps 2–4:** implement:
```python
"""Canonical ref set for a source_record: its own ref + the wikidata=* free join (§5.2)."""
from __future__ import annotations

import re

import mt_contracts

from .redirects import canonicalize_ref

_QID = re.compile(r"Q[0-9]+")


def refs_of(source: str, source_ref: str, props: dict, redirect_map: dict) -> set[str]:
    out: set[str] = set()
    own = canonicalize_ref(source_ref, redirect_map)
    if mt_contracts.is_canonical_ref(own):
        out.add(own)
    wd = props.get("wikidata")
    if isinstance(wd, str) and _QID.fullmatch(wd):
        join = canonicalize_ref(f"wd:{wd}", redirect_map)
        if mt_contracts.is_canonical_ref(join):
            out.add(join)
    return out
```
- [ ] **Step 5: Commit** — `"Add ref extraction (own ref + redirect-canonicalized wikidata join)"`

---

### Task 3: QID-anchored union-find clustering (deterministic)

**Files:**
- Create: `pipeline/src/mt_pipeline/reconcile/cluster.py` (union-find portion)
- Test: `pipeline/tests/test_reconcile_cluster.py`

**Interfaces:**
- Produces:
  - `cluster.Member` — `dataclass(source: str, source_ref: str, name: str, lat: float, lon: float, refs: frozenset[str])`.
  - `cluster.cluster_by_refs(members) -> list[cluster.Cluster]` — connected components over **shared refs** (a place = a set of members transitively linked by any common ref). `Cluster` has `members: list[Member]` (sorted) and `refs: set[str]` (union). Result sorted by `select_mint_anchor(cluster.refs)`. Order-independent (same members in any order → same clusters).

- [ ] **Step 1: Failing test** (`test_reconcile_cluster.py`):
```python
from mt_pipeline.reconcile import cluster as C

def _m(sref, refs, name="X", lat=1.0, lon=1.0):
    return C.Member(source=sref.split(":")[0], source_ref=sref, name=name, lat=lat, lon=lon, refs=frozenset(refs))

def test_qid_join_clusters_osm_wp_wd_into_one_place():
    members = [
        _m("wd:Q42", {"wd:Q42"}),
        _m("osm:node/5", {"osm:node/5", "wd:Q42"}),   # osm wikidata=Q42 join
        _m("wp:99", {"wp:99", "wd:Q42"}),             # wikipedia wikidata=Q42 join
        _m("osm:node/6", {"osm:node/6"}),             # unrelated → its own cluster
    ]
    clusters = C.cluster_by_refs(members)
    assert len(clusters) == 2
    big = max(clusters, key=lambda c: len(c.members))
    assert big.refs == {"wd:Q42", "osm:node/5", "wp:99"}
    assert len(big.members) == 3

def test_clustering_is_order_independent():
    # determinism is asserted by INPUT REVERSAL (not by seeding randomness).
    a = [_m("wd:Q1", {"wd:Q1"}), _m("osm:node/1", {"osm:node/1", "wd:Q1"})]
    c1 = C.cluster_by_refs(a)
    c2 = C.cluster_by_refs(list(reversed(a)))
    assert [sorted(c.refs) for c in c1] == [sorted(c.refs) for c in c2]
```

- [ ] **Steps 2–4:** implement union-find:
```python
"""Cluster source-record members into candidate places by shared canonical refs (QID-anchored)."""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Member:
    source: str
    source_ref: str
    name: str
    lat: float
    lon: float
    refs: frozenset


@dataclass
class Cluster:
    members: list
    refs: set = field(default_factory=set)


class _UF:
    def __init__(self): self.parent = {}
    def find(self, x):
        self.parent.setdefault(x, x)
        root = x
        while self.parent[root] != root:
            root = self.parent[root]
        while self.parent[x] != root:
            self.parent[x], x = root, self.parent[x]
        return root
    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            lo, hi = sorted((ra, rb))            # deterministic: the lexically SMALLER id is the root
            self.parent[hi] = lo


def cluster_by_refs(members) -> list:
    uf = _UF()
    ref_owner: dict = {}
    for i, m in enumerate(members):
        key = f"m{i}"
        uf.find(key)
        for r in m.refs:
            if r in ref_owner:
                uf.union(key, ref_owner[r])
            else:
                ref_owner[r] = key
                uf.union(key, r)                 # link the member to its ref node
    groups: dict = {}
    for i, m in enumerate(members):
        groups.setdefault(uf.find(f"m{i}"), []).append(m)
    clusters = []
    for ms in groups.values():
        refs: set = set()
        for m in ms:
            refs |= set(m.refs)
        if not refs:                              # every member's refs were dropped (all non-canonical)
            continue                              # a ref-less cluster can't be anchored/minted — skip it
        clusters.append(Cluster(members=sorted(ms, key=lambda x: x.source_ref), refs=refs))
    # deterministic TOTAL order by the lexically-smallest ref — never calls select_mint_anchor here
    # (that would ValueError on a canonical-but-not-mint-key ref like `foo:bar`; minting guards it, Task 6).
    clusters.sort(key=lambda c: min(c.refs))
    return clusters
```
- [ ] **Step 5: Commit** — `"Add QID-anchored union-find clustering (deterministic, order-independent)"`

---

### Task 4: Conservative name+distance fuzzy fallback + ambiguity

**Files:**
- Modify: `pipeline/src/mt_pipeline/reconcile/cluster.py`
- Create: `pipeline/config/reconcile.json`
- Test: `pipeline/tests/test_reconcile_cluster.py` (append)

**Interfaces:**
- Produces:
  - `cluster.MAX_NAME_LEN = 256`, `cluster.normalize_name(s) -> str` — pinned, in order: truncate to `MAX_NAME_LEN` (DoS bound); NFKD; drop combining marks (diacritics, `café→cafe`); casefold; replace every **non-alphanumeric run** (`ch.isalnum()` — Unicode, so **CJK/Tamil/Arabic letters are kept**) with one space; collapse; `strip()`. `观音亭→观音亭` (NOT `""`), `"St. Mary's Church"→"st marys church"`.
  - `cluster.name_similarity(a, b) -> float` — `difflib.SequenceMatcher(None, a, b).ratio()` on normalized names.
  - `cluster.haversine_m(a_lat, a_lon, b_lat, b_lon) -> float` — **the true-haversine formula (pinned, antimeridian-safe via `sin(Δλ/2)`; NOT an equirectangular `Δlon·cos(lat)` approximation)**: `R=6371000; dφ,dλ=radians; a=sin(dφ/2)²+cos(φ1)cos(φ2)sin(dλ/2)²; return 2R·asin(min(1,√a))`.
  - `cluster.FuzzyConfig(sim_defer=0.85, dist_defer_m=150.0, min_alnum=4)` — **threaded into `reconcile.reconcile`** (config in `reconcile.json`; the pure core does not read disk). **No `sim_min`/`dist_max` — there is no auto-merge band.**
  - `cluster.FuzzyDefer` — `dataclass(anchor_a, anchor_b, sim, dist_m)`.
  - `cluster.fuzzy_defer(clusters, cfg) -> list[FuzzyDefer]` — **DEFER-ONLY: never merges, returns the input clusters unchanged.** For pairs of **no-shared-ref** clusters within `dist_defer_m` (a cheap spatial pre-filter so it is not all-pairs), emits a `FuzzyDefer` when **both** normalized names are ≥ `min_alnum` chars **and** `sim ≥ sim_defer` **and** `dist ≤ dist_defer_m`. A pair where either name normalizes shorter than `min_alnum` (empty/near-empty — the non-Latin/emoji case) is **not** a candidate → split. Deterministic: pairs enumerated in sorted `(anchor_a, anchor_b)` order; normalized names cached per member. The reconcile stage sends every `FuzzyDefer` to the review file; A6/human adjudicates. **A2 never auto-merges a fuzzy pair.**

- [ ] **Step 1: Failing tests** (append) — all assert that clustering is **unchanged** by fuzzy (defer-only) and that the dangerous cases neither merge nor even defer:
```python
CFG = C.FuzzyConfig(sim_defer=0.85, dist_defer_m=150.0, min_alnum=4)

def test_close_similar_pair_defers_never_merges(tmp_path=None):
    a = C.Cluster(members=[_m("osm:node/1", {"osm:node/1"}, name="St Mary's Church", lat=51.5000, lon=-0.1200)], refs={"osm:node/1"})
    b = C.Cluster(members=[_m("hehle:9", {"hehle:9"}, name="St Marys Church", lat=51.50003, lon=-0.12001)], refs={"hehle:9"})
    deferred = C.fuzzy_defer([a, b], CFG)
    assert len(deferred) == 1                          # near-identical + close → DEFER (A6 decides), never merge

def test_distinct_non_latin_names_do_NOT_defer_or_merge():
    # THE Malaysia guard: two DIFFERENT Chinese temple names ~30m apart must NOT be a fuzzy candidate.
    a = C.Cluster(members=[_m("osm:node/1", {"osm:node/1"}, name="观音亭", lat=3.1500, lon=101.7000)], refs={"osm:node/1"})
    b = C.Cluster(members=[_m("osm:node/2", {"osm:node/2"}, name="天后宫", lat=3.15003, lon=101.70001)], refs={"osm:node/2"})
    deferred = C.fuzzy_defer([a, b], CFG)
    assert deferred == []                              # kept as CJK letters, sim≈0 → SPLIT (no empty-string sim=1.0 merge)

def test_generic_name_close_pair_defers_never_merges():
    # even an EXACT generic name a few metres apart never auto-merges (vandal/Surau/Tandas guard).
    a = C.Cluster(members=[_m("osm:node/1", {"osm:node/1"}, name="Surau Al-Hidayah", lat=3.15, lon=101.70)], refs={"osm:node/1"})
    b = C.Cluster(members=[_m("osm:node/2", {"osm:node/2"}, name="Surau Al-Hidayah", lat=3.15012, lon=101.70)], refs={"osm:node/2"})  # ~13m
    deferred = C.fuzzy_defer([a, b], CFG)
    assert len(deferred) == 1                          # DEFERRED, not merged — a human/A6 confirms

def test_far_apart_same_name_splits():
    a = C.Cluster(members=[_m("osm:node/1", {"osm:node/1"}, name="St Mary's Church", lat=51.5, lon=-0.12)], refs={"osm:node/1"})
    b = C.Cluster(members=[_m("osm:node/2", {"osm:node/2"}, name="St Mary's Church", lat=52.0, lon=-1.0)], refs={"osm:node/2"})
    assert C.fuzzy_defer([a, b], CFG) == []            # ~100km apart → not even a candidate (SPLIT)

def test_empty_normalized_name_is_not_a_candidate():
    a = C.Cluster(members=[_m("osm:node/1", {"osm:node/1"}, name="★☆♥", lat=3.15, lon=101.70)], refs={"osm:node/1"})
    b = C.Cluster(members=[_m("osm:node/2", {"osm:node/2"}, name="♦♣", lat=3.15001, lon=101.70)], refs={"osm:node/2"})
    assert C.fuzzy_defer([a, b], CFG) == []            # both normalize to "" → never compared
```

- [ ] **Steps 2–4:** `reconcile.json` (`{"fuzzy": {"sim_defer":0.85,"dist_defer_m":150,"min_alnum":4}, "registry_path":"registry/<region>.jsonl", "review_path":"reconcile-review/<region>.jsonl"}`) + implement `normalize_name` (Unicode-alnum + 256-cap)/`name_similarity`/`haversine_m` (pinned formula)/`fuzzy_defer` (defer-only, spatial pre-filter). **Teeth:** the non-Latin test reds if `normalize_name` strips to `[a-z0-9]` (the false-merge bug); the generic-name test reds if any auto-merge is introduced; the empty-name test reds without the `min_alnum` guard.
- [ ] **Step 5: Commit** — `"Add DEFER-ONLY fuzzy fallback (Unicode-safe normalize, no auto-merge, spatial pre-filter)"`

---

### Task 5: Registry file lifecycle (local JSONL, schema-validated)

**Files:**
- Create: `pipeline/src/mt_pipeline/reconcile/registry_file.py`
- Test: `pipeline/tests/test_reconcile_registry_file.py`

**Interfaces:**
- Produces:
  - `registry_file.RegistryStore` (Protocol): `load() -> list[RegistryRecord]`, `save(records) -> None`.
  - `registry_file.LocalRegistryStore(path)` — JSONL, one `RegistryRecord` per line, **sorted by `place_id`**, each validated against `registry-record.schema.json` on save; a missing file loads as `[]`; writes **atomically** (temp + rename). `refs` serialized as a **sorted list** (deterministic), reloaded as a `set`. **Schema location (gate finding):** the schema lives at `contracts/schemas/`, *not* inside the installed `mt_contracts` package — so it must be located via `importlib.resources` (preferably after bundling it as `mt_contracts` package data / exposing an `mt_contracts` validator) or an explicit config path; do NOT assume `schemas/` is importable from the wheel. Flag the packaging addition to A0/codex.
  - (Deferred, noted-not-built: `R2RegistryStore` — the same Protocol over R2, single-writer, written only on successful publish. Reconcile depends only on `RegistryStore`.)

- [ ] **Step 1: Failing test** (`test_reconcile_registry_file.py`): round-trips a `RegistryRecord`, asserts sorted-by-place_id output, set↔sorted-list `refs`, atomic overwrite, schema rejection of a malformed record, and empty-file → `[]`. (Full test in the plan; asserts determinism: two saves of the same records byte-identical.)
- [ ] **Steps 2–4:** implement (`json.dumps(sort_keys=True)` per line; `jsonschema.validate` against the packaged schema; `os.replace` for atomicity).
- [ ] **Step 5: Commit** — `"Add local JSONL registry store (schema-validated, sorted, atomic)"`

---

### Task 6: Reconcile core — mint / reuse / redirect-bridge / ambiguity (the §7 churn regressions)

**Files:**
- Create: `pipeline/src/mt_pipeline/reconcile/reconcile.py`
- Test: `pipeline/tests/test_reconcile_core.py`

**Interfaces:**
- Produces:
  - `reconcile.reconcile(members, existing, redirect_map, *, version, succeeded_sources, cfg) -> ReconcileResult` — the pure core. `existing: list[RegistryRecord]` (**treated as read-only — reconcile deep-COPIES before mutating; it never mutates the caller's list/records**, or the twice-called staleness test aliases and a live run corrupts the caller's registry); `succeeded_sources: set[str]` (ref-prefixes whose extract succeeded — drives staleness); `cfg: FuzzyConfig` (thresholds, threaded in — the core does not read disk, so A5 can tune). Returns `ReconcileResult(records, places, review)`. Steps: (1) cluster (Task 3) then `fuzzy_defer` (Task 4) → every `FuzzyDefer` becomes a review item (defer-only, no merge); (2) **redirect-bridge** the existing registry's refs (canonicalize QIDs) so a merged QID matches; (3) per cluster: `anchor_refs = [r for r in cluster.refs if it is a valid mint-key]` — if empty ⇒ emit an `unmintable` review item and skip (never `select_mint_anchor([])`/`mint_place_id(non-mint-key)` → no ValueError crash); then `resolve_by_refs(bridged_existing, cluster.refs)` → **None** ⇒ mint new (`select_mint_anchor(anchor_refs)` → `mint_place_id`, `status="live"`, `first_shipped=last_seen=version`); **id** ⇒ **reuse unchanged**, union new refs (enforcing `MAX_REFS_PER_PLACE`), advance `last_seen=version` (**never re-anchor**); **`AmbiguousRefsError(ids)`** ⇒ keep split, emit a review item carrying the bridging cluster's members (so they can be re-surfaced), attach nothing to either place; (4) staleness: an unseen live place holds `last_seen` (ages) **only if all its member-sources ∈ `succeeded_sources`** (verified vanish); otherwise `last_seen` advances to `version` (unverifiable absence — never wrongly ages), never deleted. Deterministic.

- [ ] **Step 1: Failing tests — the load-bearing §7 regressions** (`test_reconcile_core.py`):
```python
from mt_contracts.place_id import mint_place_id       # NOT top-level (mt_contracts.place_id submodule)
from mt_pipeline.reconcile import reconcile as R, cluster as C

V1, V2 = "20260714T000000Z", "20260715T000000Z"
SS = {"wd", "osm", "wp", "hehle", "plaque"}   # all sources succeeded (staleness-eligible)
CFG = C.FuzzyConfig(sim_defer=0.85, dist_defer_m=150.0, min_alnum=4)
def _m(sref, refs, name="X", lat=1.0, lon=1.0):
    return C.Member(source=sref.split(":")[0], source_ref=sref, name=name, lat=lat, lon=lon, refs=frozenset(refs))

def test_new_cluster_mints_stable_id():
    res = R.reconcile([_m("wd:Q42", {"wd:Q42"})], [], {}, version=V1, succeeded_sources=SS, cfg=CFG)
    assert len(res.records) == 1
    assert res.records[0].place_id == mint_place_id("wd:Q42")   # anchor = the QID

def test_rerun_same_input_same_id():
    r1 = R.reconcile([_m("wd:Q42", {"wd:Q42"})], [], {}, version=V1, succeeded_sources=SS, cfg=CFG)
    r2 = R.reconcile([_m("wd:Q42", {"wd:Q42"})], r1.records, {}, version=V2, succeeded_sources=SS, cfg=CFG)
    assert r2.records[0].place_id == r1.records[0].place_id                  # id stable

def test_qid_merge_keeps_place_id_stable():
    # v1: place shipped anchored on wd:Q123 (a plaque with only a QID — union-of-refs can't rescue it)
    r1 = R.reconcile([_m("wd:Q123", {"wd:Q123"})], [], {}, version=V1, succeeded_sources=SS, cfg=CFG)
    pid = r1.records[0].place_id
    # v2: Wikidata merged Q123 -> Q456; the source now reports Q456. Redirect map bridges it.
    r2 = R.reconcile([_m("wd:Q456", {"wd:Q456"})], r1.records, {"Q123": "Q456"}, version=V2, succeeded_sources=SS, cfg=CFG)
    assert len(r2.records) == 1
    assert r2.records[0].place_id == pid                                     # SAME id — no re-mint (§1/§7)
    assert {"wd:Q123", "wd:Q456"} <= r2.records[0].refs                      # union keeps both

def test_osm_gains_wikidata_tag_keeps_id():
    # v1: an OSM-only place (osm:node/5). v2: it gains wikidata=Q42 (a higher-priority ref).
    r1 = R.reconcile([_m("osm:node/5", {"osm:node/5"})], [], {}, version=V1, succeeded_sources=SS, cfg=CFG)
    pid = r1.records[0].place_id
    r2 = R.reconcile([_m("osm:node/5", {"osm:node/5", "wd:Q42"})], r1.records, {}, version=V2, succeeded_sources=SS, cfg=CFG)
    assert r2.records[0].place_id == pid            # id UNCHANGED despite the new higher-priority ref
    assert r2.records[0].mint_anchor == "osm:node/5"   # anchor NEVER re-selected

def test_ambiguous_bridge_defers_never_merges():
    # two shipped places; a new cluster's refs bridge both → keep split + review, never auto-merge.
    a = R.reconcile([_m("wd:Q1", {"wd:Q1"})], [], {}, version=V1, succeeded_sources=SS, cfg=CFG).records
    b = R.reconcile([_m("wd:Q2", {"wd:Q2"})], a, {}, version=V1, succeeded_sources=SS, cfg=CFG).records
    bridging = _m("osm:node/9", {"osm:node/9", "wd:Q1", "wd:Q2"})   # links both places
    res = R.reconcile([bridging], b, {}, version=V2, succeeded_sources=SS, cfg=CFG)
    assert res.review                               # emitted for adjudication
    assert {r.place_id for r in res.records} == {r.place_id for r in b}   # neither place mutated/merged

def test_absence_ages_a_place_ONLY_when_the_vanish_is_verified():
    # Encoding (no schema change): last_seen is the last version at which the place's presence/absence
    # was TRUSTWORTHY. Absence ages a place (holds last_seen stale → eventual tombstone) ONLY when every
    # contributing source succeeded (verified vanish). If a contributing source FAILED/was DISABLED we
    # could not verify, so we DON'T age it — last_seen advances to `version`. This is exactly what stops
    # "one bad HE run tombstones every English listed building".
    r1 = R.reconcile([_m("hehle:7", {"hehle:7"})], [], {}, version=V1, succeeded_sources={"hehle"}, cfg=CFG)
    assert r1.records[0].last_seen_version == V1                            # present → seen at V1
    # (a) hehle FAILED at V2 (absent, unverifiable) → last_seen ADVANCES to V2 (not aged; never deleted)
    fail_run = R.reconcile([], r1.records, {}, version=V2, succeeded_sources={"wd", "osm"}, cfg=CFG)
    assert fail_run.records[0].last_seen_version == V2 and fail_run.records[0].status == "live"
    # (b) hehle SUCCEEDED at V2 but the place is gone → VERIFIED vanish → last_seen HELD at V1 (ages)
    ok_run = R.reconcile([], r1.records, {}, version=V2, succeeded_sources={"hehle"}, cfg=CFG)
    assert ok_run.records[0].last_seen_version == V1 and ok_run.records[0].status == "live"  # never deleted
    # Teeth: neuter the source-success guard (always hold last_seen on absence) → case (a) reds (expects V2).
```

- [ ] **Steps 2–4:** implement `reconcile.reconcile` per the interface. **Critical:** an existing-place match **reuses the stored `place_id` and `mint_anchor`** and only unions refs + advances `last_seen`; `mint_place_id` is called **only** on the `None` branch. Redirect-bridge builds a `bridged` view of existing refs (`canonicalize_ref` each) for the `resolve_by_refs` call, then writes the winner ref into the real record's union. `AmbiguousRefsError` → `review.append(...)`, no mutation. **Teeth:** `test_qid_merge_keeps_place_id_stable` and `test_osm_gains_wikidata_tag_keeps_id` go RED under a naive "recompute the anchor each run" implementation (the §1 bug) — that is the whole point.
- [ ] **Step 5: Commit** — `"Add reconcile core: mint-once, reuse-by-union-of-refs, redirect-bridge, ambiguity-defers (§7 churn regressions)"`

---

### Task 7: Review file — the ambiguity/adjudication seam (A6)

**Files:**
- Create: `pipeline/src/mt_pipeline/reconcile/review.py`
- Test: `pipeline/tests/test_reconcile_review.py`

**Interfaces:**
- Produces:
  - `review.ReviewItem` — `dataclass(kind: str, reason: str, cluster_refs: list[str], candidate_place_ids: list[str], members: list[str])` where `kind ∈ {"ambiguous_refs", "fuzzy_defer", "unmintable"}`. **`candidate_place_ids` and every list field are built with `sorted(...)`** — `AmbiguousRefsError.place_ids` is a `set`, so `list(...)` would be non-deterministic and churn the review file across re-runs (breaking Principle 12). `members` carries the bridging cluster's member `source_ref`s so ambiguously-withheld places can be re-surfaced.
  - `review.write_review(path, items) -> None` — deterministic JSONL (sorted, sorted keys). The A6/human adjudication input; A2 keeps everything **split** until an adjudication decision comes back.
  - `review.supersede(records, loser, winner) -> list[RegistryRecord]` — **the adjudication writer** (used by A6/a human tool, NOT auto by reconcile): sets `loser.superseded_by = winner`, keeps both live-valid, then `assert_no_supersede_cycles`. This is the ONLY place `superseded_by` is written.

- [ ] **Steps 1–4:** tests + impl. Assert: `write_review` is deterministic and sorted; `supersede` sets the chain and `resolve_superseded(records, loser) == winner`; a supersede that would create a cycle raises (via `assert_no_supersede_cycles`); reconcile itself never calls `supersede` (grep-level assertion in the stage test).
- [ ] **Step 5: Commit** — `"Add ambiguity review file + adjudication-only supersede writer (A6 seam)"`

---

### Task 8: Places table + wire into the reconcile stage + CLI `--version`

**Files:**
- Modify: `pipeline/src/mt_pipeline/store.py` (add `places` table), `stages.py` (reconcile branch), `cli.py` (`--version`)
- Test: `pipeline/tests/test_reconcile_stage.py`

**Interfaces:**
- `places` table: `(place_id TEXT PRIMARY KEY, region, name, lat, lon, refs_json, member_refs_json, status)`. Representative `name`/`lat`/`lon` chosen by a **TOTAL** order (no equal-key ambiguity, fable): among members, the one whose single own `source_ref` sorts first under the anchor order (`select_mint_anchor` over `{member.source_ref}`), then by `source_ref` lexical as the final tie-break. Downstream (score/categorize/publish) read this.
- `stages.run_stage(conn, region, "reconcile", *, run_id, version)` → calls `reconcile.run(conn, region, run_id=run_id, version=version)`:
  - reads `source_records` for the region; loads the region registry + **redirect snapshot** (`load_redirect_snapshot`, path from `reconcile.json`).
  - **REDIRECT GATE — FAIL-CLOSED (fixes the fail-open gap the gate found).** A run that stamps shippable ids **refuses** unless it has a redirect map that is **present, complete, and at least as fresh as the wikidata snapshot**: if `snap.snapshot_date` is blank (no real map) *or* `redirects.assert_fresh(snap, wikidata_snapshot_date)` raises → **abort**. The only bypass is an explicit dev flag `--allow-no-redirects` (logs a loud "QID-merge protection OFF" warning) — and it is **barred from the malaysia/report path (Task 9)**. So the flagship run cannot silently reconcile with redirect-bridging inert.
  - the **wikidata snapshot date** comes from the extract provenance (see Cross-package needs — until the extract records it, the gate treats the date as unknown and, on a non-dev run, **refuses** rather than proceeding blind).
  - computes `succeeded_sources` = the region's **enabled** sources (from `RegionConfig.sources`, mapped source-key→ref-prefix — see below) whose extract **succeeded** this run (from `stage_runs`); runs `reconcile.reconcile(..., succeeded_sources=..., cfg=FuzzyConfig(...))`; writes the `places` table, saves the registry, writes the review file, marks the stage complete. The **immediate-predecessor gate** (extract-first) is already enforced by `run_stage`.
- **`SOURCE_KEY_TO_PREFIX` (fixes the dead namespace the gate found):** region-config source keys are `wikidata/wikipedia/osm/historic_england/open_plaques`; a place's member-sources are ref-prefixes `wd/wp/osm/hehle/plaque`. The stage maps the region's succeeded **keys** to **prefixes** — `{"wikidata":"wd","wikipedia":"wp","osm":"osm","historic_england":"hehle","open_plaques":"plaque"}` — and passes `succeeded_sources` **as ref-prefixes** to the core (the namespace the core and its tests use). A stage-level test builds `succeeded_sources` from real `RegionConfig.sources` names so the mapping is under test.
- `cli`: `mt reconcile <region> --run-id <id> --version <YYYYMMDDThhmmssZ>`; `--version` is required for `reconcile` (it stamps `first_shipped`/`last_seen`), validated against `^[0-9]{8}T[0-9]{6}Z$`.

- [ ] **Steps 1–4:** tests + impl. `test_reconcile_stage.py` runs a tiny extract→reconcile end-to-end against a real store, asserts the `places` table + registry file + review file, and that a **second reconcile run with the same inputs is byte-identical** (determinism guard). Also assert the stage refuses to run before `extract` (predecessor gate).
- [ ] **Step 5: Commit** — `"Wire reconcile stage: places table, registry+review persistence, --version"`

---

### Task 9: Determinism guard + REAL malaysia end-to-end (Rob's demonstrability bar)

**Files:**
- Create: `pipeline/tests/test_reconcile_determinism.py`; a small `scripts/reconcile_report.py`
- Test/Run: the real malaysia extract

**Interfaces:** consumes Tasks 1–8. No new production code — this task **proves** the WP on real data.

- [ ] **Step 1: Determinism guard** — a test that runs `reconcile.reconcile` twice on a shuffled copy of a multi-cluster fixture (QID joins + a fuzzy pair + an ambiguity) and asserts identical `records`/`places`/`review` (ids, order, refs). Reds if any ordering leaks (unsorted iteration, dict-order dependence).

- [ ] **Step 2: Real malaysia run (Rob's bar).** Against the real malaysia `source_records` codex produced (or produce them: `mt extract malaysia --run-id r1` then `mt reconcile malaysia --run-id r1 --version <v>`):
```bash
cd pipeline && uv run mt extract malaysia --run-id real1
uv run mt reconcile malaysia --run-id real1 --version 20260715T000000Z
uv run python scripts/reconcile_report.py malaysia   # prints the report below
```
`scripts/reconcile_report.py` prints: **cluster count**, **place_ids minted** (count + a sample), **QID-anchored vs fuzzy-merged vs singleton breakdown**, **review-file size** (ambiguities deferred), and the **re-run-is-identical** confirmation (run reconcile twice, diff the registry — must be empty). Commit the report output as `docs/superpowers/reports/2026-07-15-a2-malaysia-reconcile.md` (a committed artifact, like A3's audit).

- [ ] **Step 3: Commit** — `"Add reconcile determinism guard + real malaysia end-to-end report"`

---

## Review Record

**Author self-review** — deliverables map to tasks: redirect map (T1), ref extraction (T2), QID-anchored union-find (T3), conservative fuzzy fallback (T4), local JSONL registry (T5), the reconcile core with the §7 churn regressions (T6), the review-file + adjudication-only supersede (T7), stage wiring + places + `--version` (T8), determinism guard + real-malaysia report (T9). Uses A0's `mint_place_id`/`resolve_by_refs`/`resolve_superseded`/`AmbiguousRefsError`, never re-implements them. **The anchor is minted once and never re-selected** (the §1 invariant); QID-merge stability is redirect-bridged; `superseded_by` is adjudication-only (A2 never auto-merges two shipped ids, Principle 9); deterministic (union-find + sorted fuzzy + version-as-param, no wall-clock); registry is a local JSONL file (R2 = a thin deferred adapter); tombstone never deletes.

**Ratifications (fable, thread `wp/a2`)** — never-re-anchor; redirect-bridging; supersede adjudication-only; local JSONL registry; versions as a run parameter; real-malaysia final task; **PLUS the two fable additions** (redirect-map freshness gate; tombstone source-success 3-case). **Fuzzy tightened from the ratified 0.92/50 m auto-merge band to DEFER-ONLY** after the gate found empirical false-merges on real Malaysia data — flagged to fable for veto (see below).

**Cross-package needs surfaced:**
- **Redirect-map acquisition** (`codex wp/acquire-and-run`, fable-briefed): a segmented WDQS redirect query over the KNOWN QID set, emitting `{_meta:{snapshot_date, wikidata_snapshot_date, complete}, redirects:{Qloser:Qwinner}}`. Reconcile consumes it + the **fail-closed** freshness gate (refuses a missing/blank/stale map on a shippable run; only `--allow-no-redirects` dev bypasses, barred from the malaysia/report path).
- **Extract must record per-source outcome + snapshot date** — `succeeded_sources` and the freshness gate need: (a) which enabled sources **succeeded** this run (per-source — today `stage_runs` records only stage-level completion), (b) the **wikidata snapshot date**. Flag to codex/A1; **until then the reconcile stage FAILS CLOSED** (refuses rather than reconciling blind), not a silent warning.
- **`registry-record.schema.json` is at `contracts/schemas/`, not inside the installed package** — `LocalRegistryStore` must locate it via `importlib.resources` (bundle the schema into `mt_contracts` package data) or a config path, and mt_contracts should expose a validator; flag to A0/codex.
- **Ambiguously-bridged cluster members get no `places` row** until adjudicated (availability, not corruption — the two existing places are correctly untouched). The review item carries those members so A6/human can re-surface them; A3/A4 must tolerate `source_records` that have no `places` row (documented).
- **R2 registry persistence** — `R2RegistryStore` (single-writer, on successful publish, §5.2/§6) is A7/`WP-A2-publish`. **A6** calls `review.supersede` (the only `superseded_by` writer). **A7** runs `registry.tile_winner_violations` at publish. **A3/A4** read the `places` table.

**Adversarial review (per AGENTS.md gate) — COMPLETED. 3 independent critics, all running against the real `mt_contracts` venv (contract-fidelity+invariant; determinism+hostile-data; coherence+venv-build). The invariant held; the critics found real data-corruption and DoS holes, all fixed and re-verified.**
- **Fixed — CRITICAL:** `normalize_name` stripped to `[a-z0-9]`, collapsing every non-Latin name to `""` (`SequenceMatcher("","")==1.0`) → **two distinct KL temples ~30 m apart auto-merged on the flagship Malaysia run** → **fixed** with Unicode-aware `str.isalnum` (CJK/Tamil/Arabic kept; verified `观音亭` vs `天后宫` → sim 0.000), and fuzzy made **DEFER-ONLY** (no auto-merge at all — the generic-name/vandal false-merge the gate also found is gone). Flagged the defer-only tightening to fable.
- **Fixed — HIGH:** `refs` union DoS (schema `maxItems:256` → atomic save bricks the registry) → `MAX_REFS_PER_PLACE` eviction (keep anchor + all `wd:` + high-priority, shed low-priority overflow, review-flag). `succeeded_sources` namespace was dead (region-config keys vs ref-prefixes — only `osm` coincided; tombstoning silently dead for 4/5 sources, **and the unit tests passed because they hand-fed ref-prefixes the stage never produced** — my own executed-path lesson) → explicit `SOURCE_KEY_TO_PREFIX` map + a stage-level test. Redirect gate **failed open** (empty map passed, no refusal) → **fail-closed**. **My own false teeth claim:** the "recompute-anchor" neuter does NOT red the QID-merge test (the union still min-selects Q123 → same id) — the real tooth is breaking **redirect-bridging** → checklist corrected; re-anchor's tooth is `test_osm_gains_wikidata_tag_keeps_id` alone. `import random_stub` landmine removed; `test_middle_band` fixture fixed (0.615 sim → split, not defer). Input-immutability unstated (twice-called test aliased) → reconcile deep-copies `existing`.
- **Fixed — MEDIUM/LOW:** mint-key/empty-ref anchor crash (`foo:bar`/all-dropped → `select_mint_anchor([])` ValueError) → mint-key guard + empty-cluster skip; redirect **cycle** returned per-entry rep (duplicate id) → deterministic `min()` representative; `_UF` root comment inverted; haversine pinned to the true (antimeridian-safe) formula; `review.candidate_place_ids` sorted (`AmbiguousRefsError.place_ids` is a `set`); schema-location seam.
- **Affirmed by the critics (verified against real mt_contracts, unchanged):** never-re-anchor; redirect-bridging (incl. the pure-Wikidata plaque rescue union-of-refs alone can't do); supersede adjudication-only (reconcile never calls `review.supersede`); union-find determinism (24/120 permutations → identical minted ids); schema enum `["live","tombstoned"]`; import paths; scope boundaries (A6/A7/acquisition not built into A2). **Before PR:** re-run all Task tests + the neuters (break-redirect-bridge reds the QID test; re-anchor reds the osm-gains-tag test; strip-to-ascii reds the non-Latin test; drop the source-success guard reds the tombstone test) against the real venv, and run the real-malaysia end-to-end (Task 9).
