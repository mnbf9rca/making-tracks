# Pipeline Acquisition Heartbeats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish #388 by adding ETA-computable START / HEARTBEAT / DONE telemetry to every remaining long-running acquisition surface.

**Architecture:** Existing JSON request loops reuse `PhaseProgress` and `_retry_json_with_phase_heartbeats`. File fetchers expose an optional cumulative byte callback while remaining ignorant of phase names, and pageviews exposes an optional loop observer; acquisition callers own phase names, counters, and durable DONE boundaries.

**Tech Stack:** Python 3.11, `urllib`, `pytest`, existing `mt_pipeline.progress`, atomic JSON/file writes.

## Global Constraints

- Preserve snapshot payloads, metadata, cache formats, cache keys, output ordering, retry behavior, source selection, and return values.
- Telemetry never enters snapshots, manifests, hashes, caches, or other deterministic pipeline outputs.
- Missing `Content-Length` is the only unknown byte-total case; malformed, negative, duplicate/comma-joined, or over-limit values fail closed.
- Existing HTTPS/redirect allowlists, response-size caps, deadlines, and forbidden content-encoding checks remain enforced.
- START precedes work; HEARTBEAT is flushed; DONE follows the phase's successful durable write boundary and is absent on failure.
- New callback/observer parameters default to `None`; the fetch layer never learns phase names or regions.
- Write each behavior test first and run it red before implementation.
- Run commands from `.worktrees/fix-388-pipeline-heartbeats` with `PYTHONPATH=$PWD/contracts/src:$PWD/pipeline/src` and `/Users/rob/git/making-tracks/.venv/bin/python`.

---

### Task 1: Late totals and fetch-layer byte callbacks

**Files:**
- Modify: `pipeline/src/mt_pipeline/progress.py:15-101`
- Modify: `pipeline/src/mt_pipeline/fetch.py:158-218,367-423,536-655`
- Test: `pipeline/tests/test_progress.py`
- Test: `pipeline/tests/test_register_snapshot.py`
- Test: `pipeline/tests/test_fetch.py`

**Interfaces:**
- Produces: `PhaseProgress.set_total(total: int | None) -> None`.
- Produces: `fetch.get_to_file(..., on_progress: Callable[[int, int | None], None] | None = None) -> int`.
- Produces: `fetch.conditional_get_to_file(..., on_progress: Callable[[int, int | None], None] | None = None) -> ConditionalFetchResult`.
- Callback contract: emit `(0, total)` after accepted response headers, then cumulative `(written, total)` after each written chunk; omit callback on conditional `304`.

- [ ] **Step 1: Add failing `PhaseProgress` late-total tests**

Add `import pytest` to `test_progress.py`, then add:

```python
def test_phase_progress_can_adopt_a_known_total_after_start():
    clock = _StepClock()
    stream = _FlushingStream()
    phase = progress.PhaseProgress(
        "acquire.osm.download",
        region="united-kingdom",
        total=None,
        total_label="bytes",
        heartbeat_every_records=1,
        heartbeat_every_seconds=999,
        clock=clock,
        stream=stream,
    )
    phase.start()
    phase.set_total(9)
    clock.now = 3.0
    phase.tick(9)
    phase.done(9)
    assert "bytes=unknown" in stream.getvalue()
    assert "processed=9/9 rate=3.0/s" in stream.getvalue()


@pytest.mark.parametrize("bad_total", [-1, True, 1.5, "9"])
def test_phase_progress_rejects_invalid_late_totals(bad_total):
    phase = progress.PhaseProgress(
        "acquire.osm.download", region="uk", total=None, total_label="bytes"
    )
    with pytest.raises(ValueError, match="total"):
        phase.set_total(bad_total)
```

- [ ] **Step 2: Run the late-total tests and verify RED**

Run:
```bash
env PYTHONPATH="$PWD/contracts/src:$PWD/pipeline/src" /Users/rob/git/making-tracks/.venv/bin/python -m pytest pipeline/tests/test_progress.py -q
```

Expected: FAIL because `PhaseProgress` has no `set_total` method.

- [ ] **Step 3: Implement validated late-total adoption**

```python
def set_total(self, total: int | None) -> None:
    if total is not None and (isinstance(total, bool) or not isinstance(total, int) or total < 0):
        raise ValueError("progress total must be a non-negative integer or None")
    self.total = total
```

- [ ] **Step 4: Add failing fetch byte-callback tests through public entry points**

Add this response helper beside `_FakeOpener`, then use it with `Content-Length: 6`:

```python
class _HeaderOpener:
    def __init__(self, body: bytes, header_values: dict[str, str]):
        self.body = body
        self.header_values = header_values

    def open(self, url, timeout=None):
        headers = email.message.Message()
        for key, value in self.header_values.items():
            headers[key] = value
        return urllib.response.addinfourl(io.BytesIO(self.body), headers, url, 200)


def test_get_to_file_reports_header_and_cumulative_byte_progress(tmp_path, monkeypatch):
    monkeypatch.setattr(fetch, "_opener", lambda _hosts: _HeaderOpener(b"abcdef", {"Content-Length": "6"}))
    events = []
    assert fetch.get_to_file(
        "https://example.com/data", tmp_path / "data",
        expected_hosts={"example.com"}, max_bytes=10, on_progress=lambda done, total: events.append((done, total)),
    ) == 6
    assert events[0] == (0, 6)
    assert events[-1] == (6, 6)


def test_get_to_file_reports_unknown_only_when_length_is_absent(tmp_path, monkeypatch):
    monkeypatch.setattr(fetch, "_opener", lambda _hosts: _HeaderOpener(b"abc", {}))
    events = []
    fetch.get_to_file(
        "https://example.com/data", tmp_path / "data",
        expected_hosts={"example.com"}, max_bytes=10, on_progress=lambda done, total: events.append((done, total)),
    )
    assert events == [(0, None), (3, None)]


@pytest.mark.parametrize("value", ["-1", "+1", "1, 1", "nope", "11"])
def test_get_to_file_rejects_invalid_or_over_limit_content_length(tmp_path, monkeypatch, value):
    monkeypatch.setattr(fetch, "_opener", lambda _hosts: _HeaderOpener(b"abc", {"Content-Length": value}))
    with pytest.raises(fetch.FetchError, match="Content-Length"):
        fetch.get_to_file(
            "https://example.com/data", tmp_path / "data",
            expected_hosts={"example.com"}, max_bytes=10,
        )


def test_get_to_file_rejects_duplicate_content_length_headers(tmp_path, monkeypatch):
    class DuplicateLengthOpener:
        def open(self, url, timeout=None):
            headers = email.message.Message()
            headers["Content-Length"] = "3"
            headers["Content-Length"] = "3"
            return urllib.response.addinfourl(io.BytesIO(b"abc"), headers, url, 200)

    monkeypatch.setattr(fetch, "_opener", lambda _hosts: DuplicateLengthOpener())
    with pytest.raises(fetch.FetchError, match="Content-Length"):
        fetch.get_to_file(
            "https://example.com/data", tmp_path / "data",
            expected_hosts={"example.com"}, max_bytes=10,
        )
```

Add the equivalent cumulative callback assertion to an existing `conditional_get_to_file` `200` test and assert that the existing `304` test produces no callback events.

- [ ] **Step 5: Run the fetch tests and verify RED**

Run:
```bash
env PYTHONPATH="$PWD/contracts/src:$PWD/pipeline/src" /Users/rob/git/making-tracks/.venv/bin/python -m pytest pipeline/tests/test_register_snapshot.py pipeline/tests/test_fetch.py -q
```

Expected: FAIL because both public fetch functions reject `on_progress` and do not validate `Content-Length` for telemetry.

- [ ] **Step 6: Implement the callback without phase knowledge**

Add:

```python
from collections.abc import Callable


ProgressCallback = Callable[[int, int | None], None]


def _response_content_length(response_headers, *, max_bytes: int) -> int | None:
    if response_headers is None:
        return None
    values = response_headers.get_all("Content-Length")
    if not values:
        return None
    if len(values) != 1:
        raise FetchError(f"invalid Content-Length values: {values!r}")
    raw = values[0]
    if not isinstance(raw, str) or not raw.isascii() or not raw.isdigit():
        raise FetchError(f"invalid Content-Length: {raw!r}")
    total = int(raw)
    if total > max_bytes:
        raise FetchError(f"Content-Length exceeded {max_bytes} bytes")
    return total
```

Extend `_stream_response_to_file` with `on_progress=None`, call it at `(0, total)` and after every chunk, and make `get_to_file` use that shared stream helper. Thread the same keyword through `conditional_get_to_file`. Keep `304` on the retained-file verification path with no callback.

- [ ] **Step 7: Run focused tests GREEN and verify callback teeth**

Run the Task 1 tests. Then temporarily remove the per-chunk callback invocation and rerun `test_get_to_file_reports_header_and_cumulative_byte_progress`; expected FAIL because the final cumulative event is absent. Restore the invocation and rerun GREEN.

- [ ] **Step 8: Commit Task 1**

```bash
git add pipeline/src/mt_pipeline/progress.py pipeline/src/mt_pipeline/fetch.py pipeline/tests/test_progress.py pipeline/tests/test_register_snapshot.py pipeline/tests/test_fetch.py
git commit -m "Add observable byte progress to fetches"
```

### Task 2: Wikidata class/bbox phase

**Files:**
- Modify: `pipeline/src/mt_pipeline/acquire.py:25-38,312-391,1656-1672`
- Test: `pipeline/tests/test_acquire_wiki.py:50-325`

**Interfaces:**
- Consumes: `PhaseProgress` and `_retry_json_with_phase_heartbeats`.
- Produces: `acquire_wikidata(..., region: str = "unknown")` with `acquire.wikidata.bbox` telemetry.
- Unit: class-chunk × bbox-tile segments; counters: `bindings`.

- [ ] **Step 1: Write a failing multi-segment entry-point test**

```python
def test_wikidata_acquisition_emits_bbox_progress_after_durable_write(tmp_path, capsys, monkeypatch):
    monkeypatch.setattr(acquire, "_ACQUIRE_HEARTBEAT_EVERY_RECORDS", 1, raising=False)
    responses = iter([
        {"results": {"bindings": [_binding("Q1", "Q5")]}},
        {"results": {"bindings": [_binding("Q2", "Q5")]}},
    ])
    out = acquire.acquire_wikidata(
        tmp_path, bbox=(0.0, 0.0, 2.0, 1.0), class_qids=["Q5"],
        config={"endpoint": "https://query.wikidata.org/sparql", "allowed_hosts": ["query.wikidata.org"]},
        fetch_json=lambda *_args, **_kwargs: next(responses), tile_degrees=1.0,
        sleep=lambda _seconds: None, retrieved_at="2026-07-15T00:00:00Z", region="united-kingdom",
    )
    assert out.exists()
    err = capsys.readouterr().err
    assert "PHASE START acquire.wikidata.bbox region=united-kingdom segments=2" in err
    assert "PHASE HEARTBEAT acquire.wikidata.bbox region=united-kingdom processed=1/2" in err
    assert "bindings=1" in err
    assert "PHASE DONE acquire.wikidata.bbox region=united-kingdom processed=2/2" in err
```

Also add a write-failure test that monkeypatches `_atomic_write_json` to raise and asserts no `PHASE DONE acquire.wikidata.bbox` line.

- [ ] **Step 2: Run the two tests and verify RED**

Expected: FAIL because the phase lines are absent.

- [ ] **Step 3: Implement the phase with blocked-request heartbeats**

Materialize sorted class chunks and tiles once, construct `PhaseProgress(total=len(chunks) * len(tiles), total_label="segments")`, call `start`, and replace `_retry_json` with:

```python
data = _retry_json_with_phase_heartbeats(
    url,
    phase=phase,
    processed=processed,
    extra=lambda: f" bindings={len(bindings)}",
    expected_hosts=expected_hosts,
    max_bytes=max_bytes,
    fetch_json=fetch_json,
    retries=retries,
    sleep=sleep,
)
```

After incorporating each segment, increment `processed`, call `phase.tick(processed, extra=f" bindings={len(bindings)}")`, atomically write the complete snapshot, then call `phase.done`. Pass `region_config.region_id` from `acquire_all`.

- [ ] **Step 4: Run focused tests GREEN and verify teeth**

Remove the loop `tick`, rerun the multi-segment test, and confirm RED on the required heartbeat; restore and rerun GREEN.

- [ ] **Step 5: Commit Task 2**

```bash
git add pipeline/src/mt_pipeline/acquire.py pipeline/tests/test_acquire_wiki.py
git commit -m "Report Wikidata bbox acquisition progress"
```

### Task 3: QID-sitelink entity and page phases

**Files:**
- Modify: `pipeline/src/mt_pipeline/acquire.py:912-1083`
- Test: `pipeline/tests/test_acquire_wiki.py:760-1365`

**Interfaces:**
- Consumes: `_retry_json_with_phase_heartbeats`.
- Produces: `acquire.qid_sitelink.entity_lookup` over seed QIDs.
- Produces: `acquire.qid_sitelink.page_fetch` over distinct titles.
- Counters: `titles`, then `pages` and `skipped_mismatch`.

- [ ] **Step 1: Write failing phase-contract tests on `acquire_qid_sitelink_wikipedia`**

Extend the existing two-QID test so `qid_batch_size=1`, `title_batch_size=1`, and one Wikipedia page has a mismatched `wikibase_item`. Set `_ACQUIRE_HEARTBEAT_EVERY_RECORDS=1` and assert:

```python
assert "PHASE START acquire.qid_sitelink.entity_lookup region=en qids=2" in err
assert "PHASE HEARTBEAT acquire.qid_sitelink.entity_lookup region=en processed=1/2" in err
assert "titles=1" in err
assert "PHASE DONE acquire.qid_sitelink.entity_lookup region=en processed=2/2" in err
assert "PHASE START acquire.qid_sitelink.page_fetch region=en titles=2" in err
assert "PHASE HEARTBEAT acquire.qid_sitelink.page_fetch region=en processed=1/2" in err
assert "pages=1 skipped_mismatch=0" in err
assert "PHASE DONE acquire.qid_sitelink.page_fetch region=en processed=2/2" in err
assert "skipped_mismatch=1" in err
```

Add a short heartbeat interval and a blocking entity fetch to prove `processed=0/2` appears while the request is in flight.

- [ ] **Step 2: Run the QID-sitelink tests and verify RED**

Expected: FAIL because only the already-shipped blank-extract phases appear.

- [ ] **Step 3: Implement entity lookup telemetry**

Construct the phase in `_wikidata_sitelink_titles`, process QID counts rather than batch counts, use `_retry_json_with_phase_heartbeats`, tick after validated entities, and DONE after the in-memory title map is complete.

```python
processed += len(batch)
phase.tick(processed, extra=f" titles={len(out)}")
```

- [ ] **Step 4: Implement page-fetch telemetry**

Construct the page phase after `qid_by_title` is stable. Track `processed += len(title_batch)`, increment `skipped_mismatch` when a returned page's Wikibase item differs from the expected QID, and tick only after the response is parsed.

```python
page_phase.tick(
    processed,
    extra=f" pages={len(qid_pages)} skipped_mismatch={skipped_mismatch}",
)
```

Call page DONE before the already-existing blank refresh begins; snapshot durability remains covered by `blank_extract.persist`.

- [ ] **Step 5: Run focused tests GREEN and verify both teeth independently**

Neuter the entity tick and confirm only the entity heartbeat assertion reds. Restore; neuter the page tick and confirm only the page heartbeat assertion reds. Restore and rerun GREEN.

- [ ] **Step 6: Commit Task 3**

```bash
git add pipeline/src/mt_pipeline/acquire.py pipeline/tests/test_acquire_wiki.py
git commit -m "Report QID sitelink acquisition progress"
```

### Task 4: Redirect-map phase

**Files:**
- Modify: `pipeline/src/mt_pipeline/acquire.py:1519-1585`
- Modify: `pipeline/src/mt_pipeline/cli.py:1904-1923`
- Test: `pipeline/tests/test_acquire_wiki.py:1411-1475`

**Interfaces:**
- Produces: `acquire_wikidata_redirect_map(..., region: str = "unknown")`.
- Phase: `acquire.wikidata.redirect_map`; unit: known QIDs; counter: redirects.

- [ ] **Step 1: Write failing chunk and durable-DONE tests**

Set `qid_chunk_size=1`, pass two valid QIDs plus one invalid input, and assert total `2`, first heartbeat `processed=1/2`, redirect count, and DONE after the snapshot exists. Add an `_atomic_write_json` failure test asserting no redirect-map DONE.

- [ ] **Step 2: Run the redirect tests and verify RED**

Expected: FAIL because no redirect-map phase is emitted.

- [ ] **Step 3: Implement the redirect phase**

Create the phase after `known_qids` is filtered, reuse `_retry_json_with_phase_heartbeats`, advance by `len(qid_chunk)`, and call DONE only after `_atomic_write_json` returns. Pass `region.region_id` from the CLI.

- [ ] **Step 4: Run focused tests GREEN and verify teeth**

Remove `phase.tick`, confirm the chunk heartbeat test RED, restore, and rerun GREEN.

- [ ] **Step 5: Commit Task 4**

```bash
git add pipeline/src/mt_pipeline/acquire.py pipeline/src/mt_pipeline/cli.py pipeline/tests/test_acquire_wiki.py
git commit -m "Report redirect map acquisition progress"
```

### Task 5: OSM and register download phases

**Files:**
- Modify: `pipeline/src/mt_pipeline/acquire.py:1429-1500,1724-1733`
- Modify: `pipeline/src/mt_pipeline/extractors/_snapshot.py:68-125`
- Test: `pipeline/tests/test_acquire_osm.py`
- Test: `pipeline/tests/test_register_snapshot.py`

**Interfaces:**
- Consumes: fetch byte callbacks and `PhaseProgress.set_total`.
- Produces: `acquire.osm.download`, `acquire.register.historic_england.download`, and `acquire.register.open_plaques.download`.
- `_snapshot.download_snapshot(..., telemetry: PhaseProgress | None = None)` owns START/DONE when supplied.

- [ ] **Step 1: Add failing OSM production-path progress tests**

Use the real `fetch.get_to_file` with a monkeypatched body opener carrying `Content-Length`, set `_DOWNLOAD_HEARTBEAT_EVERY_BYTES=1`, and call `acquire_osm` without an injected `download_file`. Assert START unknown, a byte heartbeat with known total, and DONE only after the sidecar exists. In the existing MD5 mismatch test, assert no OSM DONE.

- [ ] **Step 2: Add failing register progress tests**

Call `acquire_registers` with a region fixture enabling both sources and monkeypatch `conditional_get_to_file` fakes that invoke `on_progress(0, size)` and `on_progress(size, size)`. Assert both source-specific phases, real region ID, and byte totals. Add a sidecar-write failure assertion proving no DONE for that source.

- [ ] **Step 3: Run OSM/register tests and verify RED**

Expected: FAIL because acquisition does not construct phases or pass byte observers.

- [ ] **Step 4: Implement a shared acquisition-layer byte observer closure**

```python
def _phase_byte_progress(phase: progress.PhaseProgress, *, source: str):
    def observe(done: int, total: int | None) -> None:
        if total is not None:
            phase.set_total(total)
        phase.tick(done, extra=f" source={source} bytes_downloaded={done}")
    return observe
```

Use `_DOWNLOAD_HEARTBEAT_EVERY_BYTES` and the standard heartbeat seconds when constructing byte phases.

- [ ] **Step 5: Wire OSM with a durable DONE boundary**

Change `download_file` default to `None`. The production `None` path calls `fetch.get_to_file(..., on_progress=observer)`; an injected legacy fetch callable is invoked with its existing kwargs and receives a final synthetic `(size, size)` observation. Start before download and call DONE only after MD5 verification, SHA-256 calculation, and sidecar write succeed.

- [ ] **Step 6: Wire register snapshots while preserving injected fetch compatibility**

`acquire_registers` creates each phase with `region_config.region_id` and passes it to `_snapshot.download_snapshot`. The default conditional fetch receives `on_progress`; an injected `fetch_fn` keeps its old kwargs and gets a final synthetic observation. `_snapshot.download_snapshot` calls DONE only after validation and sidecar write, with `status=downloaded`, `status=hash_hit`, or `status=not_modified` when the default conditional client supplied that result.

- [ ] **Step 7: Run focused tests GREEN and verify both wiring teeth**

Remove the OSM observer wiring and confirm the OSM heartbeat test RED. Restore; remove the register observer wiring and confirm the register heartbeat test RED. Restore and rerun GREEN.

- [ ] **Step 8: Commit Task 5**

```bash
git add pipeline/src/mt_pipeline/acquire.py pipeline/src/mt_pipeline/extractors/_snapshot.py pipeline/tests/test_acquire_osm.py pipeline/tests/test_register_snapshot.py
git commit -m "Report source download progress"
```

### Task 6: Pageviews title progress

**Files:**
- Modify: `pipeline/src/mt_pipeline/extractors/pageviews.py:92-124`
- Modify: `pipeline/src/mt_pipeline/acquire.py:1680-1724`
- Test: `pipeline/tests/test_pageviews.py`
- Test: `pipeline/tests/test_acquire_wiki.py:455-585`

**Interfaces:**
- Produces: `pageviews.acquire(..., on_progress: Callable[[int, int, int, int], None] | None = None) -> int`.
- Observer values: processed, total, fetched, cached.
- Produces: `acquire.pageviews.title_fetch` in `acquire_all`.

- [ ] **Step 1: Write failing observer semantics test**

Prepopulate A's valid cache, then acquire A and B:

```python
events = []
count = pageviews.acquire(
    ["A", "B"], window, cache_dir, fetch=fake_fetch, enabled=True,
    on_progress=lambda processed, total, fetched, cached: events.append((processed, total, fetched, cached)),
)
assert count == 1
assert events == [(1, 2, 0, 1), (2, 2, 1, 1)]
```

- [ ] **Step 2: Write failing `acquire_all` phase test**

Extend the enabled-pageviews integration test, set `_ACQUIRE_HEARTBEAT_EVERY_RECORDS=1`, provide one cached and one fetched title, and assert START `titles=2`, HEARTBEAT `processed=1/2 fetched=0 cached=1`, and DONE `processed=2/2 fetched=1 cached=1`.

- [ ] **Step 3: Run pageviews tests and verify RED**

Expected: FAIL because `on_progress` and the phase do not exist.

- [ ] **Step 4: Implement the pageviews observer**

Materialize `deduped_titles = _deduped_titles(titles)`, track cached separately, and invoke the optional observer after every title. Preserve `fetched` as the function's return value and sleep only after new fetches.

- [ ] **Step 5: Wire the phase in `acquire_all`**

Compute titles once, create `PhaseProgress(total=len(titles), total_label="titles", region=region_config.region_id)`, START, pass an observer that ticks with `fetched` and `cached`, and DONE only after `pageviews.acquire` returns successfully.

- [ ] **Step 6: Run focused tests GREEN and verify cached-path teeth**

Remove observer notification from the cache-hit branch; confirm the mixed-cache test RED because processed/cached events differ. Restore and rerun GREEN.

- [ ] **Step 7: Commit Task 6**

```bash
git add pipeline/src/mt_pipeline/extractors/pageviews.py pipeline/src/mt_pipeline/acquire.py pipeline/tests/test_pageviews.py pipeline/tests/test_acquire_wiki.py
git commit -m "Report pageviews acquisition progress"
```

### Task 7: Cross-surface verification and closeout preparation

**Files:**
- Modify if test gaps survive: files from Tasks 1-6 only
- Read/update after implementation evidence exists: GitHub issue #388 body

**Interfaces:**
- Consumes all seven phase families and eight test groups approved in the design.
- Produces a branch ready for the mandatory adversarial review and PR gates.

- [ ] **Step 1: Run all focused heartbeat tests together**

```bash
env PYTHONPATH="$PWD/contracts/src:$PWD/pipeline/src" /Users/rob/git/making-tracks/.venv/bin/python -m pytest \
  pipeline/tests/test_progress.py \
  pipeline/tests/test_fetch.py \
  pipeline/tests/test_register_snapshot.py \
  pipeline/tests/test_acquire_osm.py \
  pipeline/tests/test_acquire_wiki.py \
  pipeline/tests/test_pageviews.py -q
```

Expected: all selected tests pass with zero warnings.

- [ ] **Step 2: Run the full pipeline suite**

```bash
env PYTHONPATH="$PWD/contracts/src:$PWD/pipeline/src" /Users/rob/git/making-tracks/.venv/bin/python -m pytest pipeline/tests
```

Expected: baseline 909 tests plus the new tests pass, with the one existing live-provider skip and zero failures.

- [ ] **Step 3: Run static repository checks**

```bash
python3 scripts/lint_agent_law.py
git diff --check origin/develop..HEAD
git status --short --branch
```

Expected: law lint OK, no whitespace errors, and a clean worktree.

- [ ] **Step 4: Run the mandatory adversarial review gate**

Dispatch independent critics for spec fidelity, internal/error-boundary semantics, hostile-upstream-content handling, and test teeth. Cross-examine every finding, fix survivors test-first, and record raised / survived / fixed counts plus each neuter proof.

- [ ] **Step 5: Re-ground and rerun gates if `origin/develop` moved**

Fetch `origin/develop`, verify it is an ancestor of HEAD, inspect the two-dot diff for only #388 changes, and merge the fresh target if required. Rerun focused/full tests after any merge.

- [ ] **Step 6: Rewrite issue #388 body as the coherent final record**

Preserve the request and incident context, record PR #431's delivered subset and this six-surface delta, check every coverage item, include actual test counts, and keep merge-time closeout criteria. Do not add a running-status comment. Verify the live issue body in the next command.

- [ ] **Step 7: Commit any gate fixes and push**

```bash
git add pipeline/src/mt_pipeline/progress.py pipeline/src/mt_pipeline/fetch.py pipeline/src/mt_pipeline/acquire.py pipeline/src/mt_pipeline/cli.py pipeline/src/mt_pipeline/extractors/_snapshot.py pipeline/src/mt_pipeline/extractors/pageviews.py pipeline/tests/test_progress.py pipeline/tests/test_fetch.py pipeline/tests/test_register_snapshot.py pipeline/tests/test_acquire_osm.py pipeline/tests/test_acquire_wiki.py pipeline/tests/test_pageviews.py
git commit -m "Harden acquisition heartbeat coverage"
git push origin HEAD
```

Skip the commit when no gate fix changed files. Verify the remote branch SHA after the push.

- [ ] **Step 8: Open the develop PR with required labels**

The PR body names #388, includes exact full-suite counts, the phase coverage, drift accounting, DONE/error-boundary proof, and adversarial review accounting. Apply `sourcery-review`, `track-a-pipeline`, and `wp`; do not self-merge.
