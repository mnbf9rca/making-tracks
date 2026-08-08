# Pipeline Acquisition Heartbeats — Design

**Issue:** #388

**Target branch:** `develop`

**Status:** Approved and implemented on this branch; pending review.

## 1. Context and tracker drift

Issue #388 began as the observability follow-up to the UK blank-extract refresh. PR #431 already delivered more of the issue than its still-open title suggests:

- the shared `mt_pipeline.progress.PhaseProgress` helper;
- the shared publish `UploadProgress` helper;
- blank-extract batch, fallback, and persistence heartbeats;
- baseline Wikipedia geosearch, page-fetch, and persistence heartbeats; and
- the review-blocking pipeline observability law.

The live issue checklist and the current `develop` tree agree on the remaining delta. Six acquisition surfaces still have no ETA-computable heartbeat coverage:

1. Wikidata class/bbox acquisition;
2. QID-sitelink entity lookup and Wikipedia page fetch;
3. Wikidata redirect-map acquisition;
4. the OSM whole-file download;
5. Historic England and Open Plaques register downloads; and
6. pageviews title acquisition.

The `docs/process/coordination.md` and current-phase task ledgers named by `AGENTS.md` are absent from the current `develop` tree. This design therefore treats the live #388 body, PR #431, and the current code as the recoverable scope record. It does not infer any additional work package from the missing ledgers.

## 2. Goals

The target behavior is that a human tailing an acquisition log can identify the current phase and, whenever the upstream server exposes a total, compute progress, rate, and ETA without inspecting the process.

The implementation will:

- close all six remaining checklist entries in one coherent change;
- reuse `PhaseProgress` for every phase rather than introduce a second logging shape;
- emit START before work, periodic HEARTBEAT lines during both record loops and blocked requests, and DONE only after the phase's successful publication or write boundary;
- preserve existing snapshot payloads, metadata, cache formats, retry behavior, validation, and default public call behavior; and
- keep telemetry deterministic and directly testable through injected clocks and streams.

## 3. Non-goals

This work does not change acquisition concurrency, retry policy, source selection, snapshot schemas, cache keys, output ordering, endpoint security checks, response-size caps, or pipeline data products. It does not add an ETA field: done/total, elapsed time, and rate remain the machine- and human-computable primitive values.

## 4. Architecture

### 4.1 Request-loop phases

The existing `_retry_json_with_phase_heartbeats` adapter will be reused for serial HTTP request loops. Each acquisition function creates one `PhaseProgress`, computes its deterministic total before START, and passes the current processed count into the adapter. The adapter continues emitting a no-progress heartbeat when a request remains in flight for a heartbeat interval. After a response is validated and incorporated, the caller advances the count by the number of represented work items and calls `tick`.

The caller owns START and DONE. DONE occurs only after the result crosses the phase's durable boundary where one exists. A request loop that finishes but then fails its atomic snapshot write emits no DONE.

### 4.2 Byte progress for file downloads

`fetch.get_to_file` and `fetch.conditional_get_to_file` will gain an optional byte-progress callback. Existing callers that omit it retain their current behavior and return types. The callback receives cumulative bytes written and the response's total byte count when a valid `Content-Length` is present.

The fetch layer will invoke the callback once after response headers are accepted and after each written chunk. A missing `Content-Length` produces an explicit unknown total. A malformed, negative, or over-limit `Content-Length` is not treated as an honest unknown: fetch validation rejects it before body transfer. Content encoding remains forbidden, so reported wire bytes and written bytes cannot silently diverge through decompression. A conditional `304` has no body to estimate and completes without a byte heartbeat after the retained file is verified.

`PhaseProgress` will expose a small method for adopting a total discovered after START. The acquisition-layer callback updates that total and ticks the shared phase with cumulative bytes. The fetch layer remains unaware of phase names, regions, or logging formats.

`acquire_osm` constructs and owns its region-scoped phase. `acquire_registers` constructs a source-specific phase with `region_config.region_id` and passes it into `_snapshot.download_snapshot`, which owns START/DONE around fetch, validation, and sidecar publication. They emit DONE only after the downloaded file has passed existing validation and the provenance sidecar or conditional-fetch metadata has been written successfully. A validation, checksum, atomic replacement, or sidecar failure leaves the phase without DONE and preserves the existing cleanup behavior.

### 4.3 Pageviews loop observation

The resumable `pageviews.acquire` loop will gain an optional progress observer. It will materialize its already-deduplicated title list once, making the total deterministic, and notify the observer after every title, including cache hits. Notifications carry processed, total, fetched, and cached counts.

`acquire_all` owns the `PhaseProgress` instance and maps observer notifications to heartbeat ticks. START precedes the pageviews call; DONE follows only a successful loop and manifest/cache writes. Existing return semantics remain the count of newly fetched titles.

## 5. Phase contract

| Phase | Unit and total | Phase-specific counters | DONE boundary |
| --- | --- | --- | --- |
| `acquire.wikidata.bbox` | class-chunk × bbox-tile segments | bindings materialized | complete snapshot atomically written |
| `acquire.qid_sitelink.entity_lookup` | seed QIDs | sitelink titles found | all entity batches validated and incorporated |
| `acquire.qid_sitelink.page_fetch` | distinct sitelink titles | pages materialized, mismatches skipped | all page batches validated and incorporated |
| `acquire.wikidata.redirect_map` | known QIDs | redirects found | complete redirect snapshot atomically written |
| `acquire.osm.download` | response bytes | current source | PBF validated and provenance sidecar written |
| `acquire.register.<source>.download` | response bytes | source and conditional-fetch status when known | snapshot validated and provenance sidecar written |
| `acquire.pageviews.title_fetch` | deduplicated titles | fetched and cached | all required cache files and manifest writes succeed |

The existing log grammar remains:

```text
PHASE START <name> region=<region> <unit>=<total-or-unknown>
PHASE HEARTBEAT <name> region=<region> processed=<done>/<total-or-unknown> rate=<rate>/s elapsed=<seconds>s <counters>
PHASE DONE <name> region=<region> processed=<done>/<total-or-unknown> elapsed=<seconds>s <counters>
```

Language-scoped Wikipedia phases use the language code as their existing `region` value. Region-scoped Wikidata, OSM, register, redirect, and pageviews callers pass the configured region ID. Source-specific register phase names use the stable config keys `historic_england` and `open_plaques`.

`acquire_all` passes its region ID into Wikidata acquisition; the redirect CLI passes the loaded region ID into redirect acquisition. Those internal acquisition entry points accept an optional region value for compatibility with existing direct callers and test doubles, while every production call supplies the real region.

## 6. Error handling and compatibility

- Exceptions retain their current types and cleanup paths.
- No DONE line is emitted from a failed phase.
- A blocked JSON request continues producing time-axis heartbeats without falsely advancing its processed count.
- File downloads continue enforcing HTTPS host allowlists, redirect allowlists, size caps, deadlines, and forbidden content encodings before telemetry can declare success.
- Optional callback and observer parameters default to `None`; injected test doubles and all unrelated callers remain source-compatible.
- Telemetry does not enter snapshots, manifests, caches, hashes, or deterministic pipeline outputs.

## 7. Test design and teeth

Tests will be written red before production changes. They will cover both the exact log contract and the real production entry points.

1. **Shared progress:** injected clock/stream tests pin late total adoption, flush behavior, and unknown-total formatting.
2. **Wikidata bbox:** a multi-segment acquisition proves START/HEARTBEAT/DONE and binding counters. Neuter: remove the loop tick; the heartbeat assertion fails.
3. **QID sitelinks:** entity and page batches prove their distinct totals and counters, including a mismatched Wikibase item. Neuter: remove either phase emit; its phase-specific assertion fails.
4. **Redirect map:** multiple chunks prove progress by represented QIDs and redirect counts. Neuter: remove the chunk tick; the heartbeat assertion fails.
5. **Fetch byte callback:** body-serving responses prove the header callback, cumulative chunk callbacks, missing-total behavior, invalid-length rejection, and unchanged behavior when no callback is supplied. Neuter: remove the per-chunk callback; cumulative progress assertions fail.
6. **OSM and registers:** production acquisition entry points prove byte heartbeats and prove DONE is absent when validation or sidecar publication fails. Neuter: remove callback wiring; the entry-point log assertion fails.
7. **Pageviews:** a mixed cached/fetched run proves done/total and both counters through `acquire_all` wiring. Neuter: skip cached-title observation or remove the loop emit; the final count or heartbeat assertion fails.
8. **Blocked requests:** injected short heartbeat intervals prove a request that advances no items still emits. Neuter: bypass `_retry_json_with_phase_heartbeats`; the time-axis assertion fails.

The final gate runs the entire pipeline suite with the worktree-local `contracts/src` and `pipeline/src` first on `PYTHONPATH`, matching the clean baseline of 909 passed and 1 skipped. The adversarial review gate will use independent spec-fidelity, semantics/error-boundary, hostile-input, and test-teeth lenses.

## 8. Documentation and tracker closeout

The implementation PR will update #388's body as one coherent story: PR #431's delivered set, this six-surface delta, the final checked coverage list, and the actual validation evidence. It will not add running-status comments. No new policy wording is needed because PR #431 already landed the shared-helper and ETA-computability law.

After merge, the merger can close #388 only when all seven phase families above are present on `develop`, the issue checklist is fully checked, and the issue's acceptance tests are green.
