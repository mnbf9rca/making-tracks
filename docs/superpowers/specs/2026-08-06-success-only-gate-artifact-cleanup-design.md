# Success-only gate artifact cleanup design

## Status and scope

Issue #546 adds bounded cleanup for **local artifacts owned by `scripts/release-gate.sh`**. It does not clean DerivedData, stable lock files, CI artifacts, caller-named output paths, or evidence copied to durable storage.

The policy is deliberately asymmetric:

- a completed local run becomes cleanup-eligible only after every requested gate phase succeeds;
- a failed or interrupted run remains unmarked and is never automatically deleted;
- a later successful, fully default `full` gate may prune marked successful runs strictly older than 24 hours (`86400` seconds);
- local caller-named paths are preserved by construction, and CI keeps its existing ownership and upload behavior.

The 24-hour threshold is the planner ruling for #546. Recent full-gate result bundles are about 168–178 MiB, so a day of successful bundles stays well below the old 35 GB exhaustion class while retaining a short audit/recovery window. Longer retention buys no diagnostic value after counts are extracted; failed bundles carry that value and are exempt from automatic deletion.

## Context

The current local default is one fixed directory per simulator:

```text
/private/tmp/release-gate-<validated simulator UUID>/MakingTracksTests.xcresult
```

`release-gate.sh` removes that result path before Xcode starts. A simple exit trap was previously attempted in the simulator-concurrency work and rejected because it deleted caller-named bundles and failure evidence. The replacement must therefore distinguish ownership and outcome structurally, not infer them from a broad pathname scan.

The project record names two old-machine ENOSPC incidents. The durable incident entry quantifies one as roughly 35 GB of DerivedData and result-bundle litter filling the shared host; both incidents required manual sweeps. #612 separately moved reusable DerivedData and stable locks out of automatic temporary cleanup roots. #546 is only the remaining result-artifact policy.

## Approaches considered

### A. Per-run owned directories with explicit success markers — approved

Each local invocation whose artifact paths are not overridden receives a unique direct child below its validated simulator root. The gate writes an ownership marker before Xcode and a success marker only after all requested phases return zero. A later default full gate inspects only direct siblings that satisfy every ownership, name, marker, age, and canonical-path check.

This makes failure preservation the absence of an action: failed runs never receive a success marker and therefore cannot become cleanup candidates.

### B. Rotate the fixed result path before the next run — rejected

Rotation could preserve the previous failure, but every new invocation would have to rename an artifact before knowing its provenance or outcome. Collision handling and recovery after interrupted renames would be more complex than the cleanup policy itself.

### C. Scan `/private/tmp/release-gate-*` globally — rejected

A global `find` is short but has cross-seat blast radius, can encounter an active sibling gate, and cannot prove caller ownership from a name. It repeats the unsafe category of mistake that allowed temporary cleanup to unlink stable lock paths.

## Artifact layout and ownership

The validated simulator UUID remains the seat-isolation boundary:

```text
/private/tmp/release-gate-<UUID>/
└── runs/
    └── run-<UTC basic timestamp>-<PID>/
        ├── .release-gate-owned
        ├── .release-gate-preserve       # only when a caller override targets this run
        ├── MakingTracksTests.xcresult
        ├── enumerated-tests.json        # enumerate mode only
        └── .release-gate-success        # created only after success
```

The run name format is exact: `run-YYYYMMDDTHHMMSSZ-<decimal PID>`. A pre-existing run name is an error; the gate never replaces it.

`.release-gate-owned` is a regular, non-symlink file created by this invocation before any external build command. Its content records a small schema identifier and the validated UUID. `.release-gate-success` is a regular, non-symlink file created only by the successful finalizer and carries the same identity. Cleanup requires both markers with exact content.

The unique owned layout is used for local `full`, `test`, and `enumerate` modes when both `MT_RELEASE_GATE_RUN_DIR` and `MT_RELEASE_GATE_RESULT_BUNDLE` are unset. `build` mode produces no result artifact and retains its existing run-directory behavior.

Any explicit local `MT_RELEASE_GATE_RUN_DIR` or `MT_RELEASE_GATE_RESULT_BUNDLE` makes the path caller-owned. The gate never removes it. If Xcode requires a nonexistent result path and the caller-owned target already exists, the gate refuses with a recovery instruction instead of deleting it. CI retains the existing preflight replacement and later upload lifecycle because CI, not the local cleanup policy, owns those explicit artifacts.

If a caller-named result or enumeration path resolves anywhere inside an otherwise valid owned run, the gate writes an exact `.release-gate-preserve` identity marker before Xcode. That marker permanently disqualifies the containing run from automatic pruning, so a later default gate cannot delete the caller-owned descendant indirectly.

## Successful finalization and pruning

The finalizer is an explicit call at the bottom of `release-gate.sh`, after every requested phase. `set -e` prevents it from running after a failed or interrupted build/test command.

Finalization does the following:

1. Validate the current owned run directory and ownership marker again.
2. Create the regular success marker. A marker-creation failure makes the gate nonzero and leaves the run in the failure-preserved state.
3. If and only if this invocation is a local, fully default `full` gate, inspect direct siblings under the same canonical `runs` root.
4. Delete an exact sibling directory only when all checks pass:
   - its basename matches the exact run-name grammar;
   - it is a real directory, not a symlink;
   - both markers are real regular files, not symlinks, with exact schema/UUID content;
   - no `.release-gate-preserve` entry exists;
   - its canonical parent is the current canonical `runs` root;
   - the success marker is **strictly older** than `86400` seconds (`age > 86400`; equality is retained).

The threshold is a named constant with a provenance comment pointing to #546. Tests may inject a clock only under the existing simulator-lock test mode; production uses `date +%s`.

Immediately before deletion, cleanup records the validated candidate's device/inode identity, atomically moves the candidate to a unique direct-child quarantine path, and repeats the boundary, identity-marker, preserve-marker, and age checks. A mismatch restores the candidate pathname when possible and otherwise leaves the quarantined directory preserved with an explicit warning. Only the revalidated quarantine path becomes the exact deletion operand.

Prune failures are reported as explicit cleanup warnings and do not rewrite the already successful gate result. The marked directory remains eligible for a later retry. Path/marker validation failures skip that candidate without touching it.

## Safety boundaries

- No cleanup walks above or outside the current validated UUID root.
- No cleanup examines another seat's root.
- No wildcard or global release-gate scan is a deletion target.
- A symlinked gate root, `runs` root, run directory, or marker fails validation; cleanup never follows it.
- Only direct children are candidates; nested descendants and similarly prefixed names are ignored.
- A caller override nested anywhere beneath an owned run creates a preserve marker, and any preserve-marker entry disqualifies that run.
- Legacy fixed-path bundles remain untouched and require operator disposition.
- The gate never automatically deletes failed or unmarked run directories. Because those directories remain under `/private/tmp`, macOS `com.apple.tmp_cleaner` can still remove their files after access, modification, and change times are all older than roughly three days. Operators must extract or copy evidence to the durable convention under `$HOME/Library/Application Support/making-tracks-gates/evidence/` within that OS window; this is an operator SLA, not gate behavior. This durable-root convention follows the planner ruling in AMQ message `2026-08-06T07-18-11.151Z_pid12763_bf6584ff`; `~/Library/Caches` is reserved for bounded transient holdings with a named cleanup trigger.
- DerivedData pruning remains separate. #612's persistent cache roots and temporary-path guards are unchanged.

## Error handling and recovery

An unsafe or ambiguous gate-owned root fails before Xcode. A caller-owned result target that already exists also fails before Xcode and names the exact path; the operator may move it to durable evidence storage or remove it after extraction, then retry.

If a gate fails, the emitted path is preserved for diagnosis. Operators extract counts and failure evidence, copy anything durable beneath `$HOME/Library/Application Support/making-tracks-gates/evidence/<issue>`, and manually delete only the exact released failure directory. Automatic cleanup never makes that judgment.

If successful cleanup reports a warning, operators inspect the named exact candidate. They do not broaden the command to a parent directory or wildcard.

## Test design

`scripts/sim-lock-tests.sh` continues to drive the real `release-gate.sh` boundary with fake Git, simulator, and Xcode commands. The fake Xcode command creates the requested output and can return a controlled test failure.

The regression matrix proves:

1. a successful owned run receives both markers and a later default full success removes an older marked sibling;
2. a failed run remains unmarked and preserved, and failure prevents pruning of an otherwise eligible sibling;
3. explicit local run-directory and result-bundle paths are preserved, including refusal rather than deletion when an output already exists;
4. a success marker exactly `86400` seconds old remains while one at `86401` seconds is removed;
5. invalid names, nested directories, wrong marker content, symlink directories, symlink markers, and candidates outside the canonical direct-child boundary are untouched;
6. CI keeps its current explicit-artifact lifecycle and creates no local ownership/success markers;
7. the existing #612 DerivedData and simulator-lock suites remain green.
8. an unfiltered owned gate succeeds under macOS system Bash 3.2, a nested caller override survives later pruning, and a candidate pathname replacement is detected and restored before deletion.

Each cleanup assertion targets filesystem state produced through the production script, not a copied shell fragment.

## Documentation changes

`docs/ios-gate-ledger.md` will replace the inherited one-line result-bundle claim with the local ownership lifecycle, 24-hour threshold, operator recovery steps, durable-evidence convention, and disk-budget rationale. It will explicitly distinguish the gate's success-only cleanup from macOS `com.apple.tmp_cleaner` and state the operator SLA to extract or copy failure evidence within the roughly three-day OS cleanup window. It will cite the two old-machine ENOSPC incidents without inventing measurements for the unquantified incident.

No production app, workflow, CI upload, simulator destination, semaphore, or lock-root behavior changes.
