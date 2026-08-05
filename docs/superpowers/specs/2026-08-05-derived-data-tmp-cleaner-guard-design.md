# DerivedData tmp-cleaner Guard Design

## Status and authority

This design delivers issue #612's durable fix. The planner accepted the proven
root cause and assigned the target root and enforcement requirements in AMQ
`2026-08-05T16-44-24.783Z_pid65822_34b0d9c2`. Rob's repeated AMQ-doorbell
instruction authorizes acting on that directive.

## Proven failure

The local release gate kept reusable DerivedData below `/private/tmp`. macOS
launches `/usr/libexec/tmp_cleaner` at local midnight; that script traverses
`/tmp` (which resolves to `/private/tmp`) and deletes each file whose access,
modification, and change times are all older than three days. A warm codex2
DerivedData directory crossed midnight during #600. The cleaner deleted cached
MapLibre metadata while preserving recently accessed files such as the binary,
so later UI tests loaded an incomplete standalone framework and aborted.

The recurrence fixes both the previously proven immediate #612 mechanism and
its formerly unknown trigger. Touching the DerivedData root or a sentinel cannot
prevent the failure because the cleaner evaluates files individually.

## Requirements

1. Every host seat uses one persistent default DerivedData directory at
   `$HOME/Library/Caches/making-tracks-gates/<seat>`. On this host that is
   `/Users/rob/Library/Caches/making-tracks-gates/<seat>`.
2. `sim-lock.sh` exports the selected logical seat and the seat-scoped default
   DerivedData path to its wrapped command.
3. `sim-lock.sh` rejects an inherited `MT_RELEASE_GATE_DERIVED_DATA` or a direct
   `xcodebuild -derivedDataPath` that canonically resolves to `/tmp`,
   `/private/tmp`, `/var/tmp`, or macOS's per-user `/private/var/folders/*/T/`
   temporary tree.
4. `release-gate.sh` independently canonicalizes and rejects its selected
   DerivedData path below either temporary root before pruning, creating, or
   invoking Xcode.
5. Every refusal fails closed, occurs before Xcode runs, and cites #612.
6. Result bundles may remain under `/private/tmp`. Stable coordination files
   live under `$HOME/Library/Application Support/making-tracks-gates/locks`,
   outside automatic temporary and cache cleanup jurisdictions.
7. GitHub Actions keeps its explicit ephemeral DerivedData override. Its path is
   validated by the same release-gate boundary.
8. The frozen codex2 crime-scene DerivedData is not migrated or modified.

## Considered approaches

### Selected: shared validator with two boundary checks

A small sourced shell library owns canonicalization and the temporary-root
predicate. `sim-lock.sh` establishes the per-seat default and checks inherited
or direct-Xcode paths. `release-gate.sh` checks again after resolving its own
override/default. This is the smallest design that covers both ordinary gate
entry and direct release-gate invocation without allowing the two checks to
drift.

### Rejected: release-gate-only validation

This protects the full release gate but permits direct `xcodebuild` and helper
commands under `sim-lock.sh` to keep using vulnerable paths. It does not satisfy
the assigned wrapper boundary.

### Rejected: refresh timestamps inside `/private/tmp`

Recursively touching a large DerivedData tree before every run is slow, races
the midnight cleaner, mutates cached products, and treats the symptom. A root
touch or sentinel is ineffective because deletion eligibility is per-file.

## Components and data flow

`sim-lock.sh` already owns the authoritative `--seat` selection. Immediately
before executing a wrapped command it derives
`$HOME/Library/Caches/making-tracks-gates/$SEAT`, creates only the user-owned
cache parent, validates any caller override and direct Xcode argument, then
exports `MT_SIM_LOCK_SEAT` and `MT_RELEASE_GATE_DERIVED_DATA` with the safe
seat default when no override was supplied.

`release-gate.sh` requires `MT_SIM_LOCK_SEAT` for local default selection. CI
may omit the seat only when it supplies the existing explicit DerivedData
override through the Actions-only lock bypass. Before any DerivedData prune or
creation, it canonicalizes the selected path and refuses a temporary-root
result.

The shared validator resolves existing paths with `realpath`. For a new path it
requires an existing parent, resolves that parent, rejects terminal `.` or `..`
components, and appends the final component. Both callers create only their
known-safe cache parent before validation; arbitrary override parents are never
created to make validation succeed.

## Error handling

Malformed, relative, unresolved-parent, or temporary-root DerivedData paths are
configuration errors. The command exits nonzero before Xcode with a message of
the form `refused: DerivedData path resolves under system-managed temporary storage; use
$HOME/Library/Caches/making-tracks-gates/<seat> (#612)`. Validation failure never
falls back to the vulnerable legacy run-directory default.

## Test design

The host shell harness proves these behaviors before implementation:

- each seat receives a distinct cache-root default even when `AM_ME` is absent;
- `release-gate.sh` rejects explicit `/tmp`, `/private/tmp`, `/var/tmp`, the
  per-user `.../T/` tree, and a safe symlink whose canonical target is
  `/private/tmp`, before fake Xcode runs;
- `sim-lock.sh` rejects the same inherited override and a direct Xcode
  `-derivedDataPath` argument before the wrapped marker command runs;
- safe explicit paths and the seat default reach fake Xcode unchanged;
- CI's explicit non-temporary override remains accepted;
- test neutering is demonstrated by temporarily bypassing the predicate and
  observing the focused refusal tests turn red before restoring the source.

The complete `scripts/sim-lock-tests.sh` suite, Bash syntax, ShellCheck, and
agent-law lint must remain green. The app workload is unchanged, but the normal
host release gate runs once from the new codex3 cache root before the PR.

## Documentation and active callers

The iOS `AGENTS.md` disk-hygiene delta and `docs/ios-gate-ledger.md` name the
cache-root law once, retain `/private/tmp` only for result bundles, and place
stable coordination files in Application Support.
Active regeneration scripts that consume `MT_RELEASE_GATE_DERIVED_DATA` use the
injected seat default or the matching cache path; historical plan transcripts
remain historical evidence and are not rewritten.

## Evidence preservation

Before implementation, the at-risk raw #612 evidence was copied to
`$HOME/Library/Caches/making-tracks-gates/evidence/issue-612`. The 27 recurrence
IPS files, 27 interruption-experiment files, and 2 crash-evidence files match
their sources by file count and aggregate SHA-256 manifest. The original
codex2 DerivedData remains frozen at its recorded `/private/tmp` crime-scene
path until #612 closes.
