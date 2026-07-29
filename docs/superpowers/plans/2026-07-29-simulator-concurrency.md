# Simulator Concurrency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every builder seat its own simulator while serialising same-simulator work, limiting simultaneous gates to two, and permanently closing #497's lock-inode split.

**Architecture:** `sim-lock.sh` parses the simulator UDID from the required `MT_RELEASE_GATE_DESTINATION`, opens a stable per-UDID lock file once, and holds `flock` on that open descriptor for the whole child command. After the simulator lock is held, it acquires one of `MT_GATE_MAX_CONCURRENT` stable global slot files; the default is two, and the slot descriptor remains open until the child exits. `release-gate.sh` rejects missing destinations before doing work and keys its default run/DerivedData directory from the destination UDID.

**Tech Stack:** macOS Bash 3.2+, Homebrew `flock`, ShellCheck, `scripts/sim-lock-tests.sh`, pytest

## Global Constraints

- Branch from current `origin/ios`; target `ios`.
- The literal branch is `wp-infra-sim-concurrency`.
- Lock files live under `/private/tmp`, are opened with `O_CREAT`, are locked by open file descriptor, and are never deleted or replaced.
- Same-simulator work serialises; different simulators may overlap; no more than `MT_GATE_MAX_CONCURRENT` locked commands overlap globally (default `2`).
- `MT_RELEASE_GATE_DESTINATION` is mandatory and must contain exactly one comma-delimited
  `id=<simulator-udid>` field.
- `MT_GATE_MAX_CONCURRENT` defaults to the host ceiling of `2` and may lower it to `1`; a caller cannot
  enlarge the host-wide ceiling.
- The test harness must exercise real process, lock, and timing effects; it must not inspect source text. Process-detection cases run with host process-list access because the sandbox denies `pgrep`.
- The per-seat simulator table is recorded in the iOS gate's operational ledger because `docs/INFRA.md` is develop-owned and deliberately absent from the `ios` tree.

---

### Task 1: Establish the host baseline and pin the new contracts red

**Files:**
- Modify: `scripts/sim-lock-tests.sh`
- Modify: `docs/superpowers/phases/pre-phase/tasks.md`

**Interfaces:**
- Consumes: `MT_SIM_LOCK_TEST_MODE=1`, `MT_SIM_LOCK_TEST_ROOT`, `MT_RELEASE_GATE_DESTINATION`, and the real `scripts/sim-lock.sh`
- Produces: a clean 11-test baseline plus timing assertions for lock and semaphore behavior

- [x] **Step 1: Run the unchanged harness with host process-list access**

Run: `./scripts/sim-lock-tests.sh`

Expected: `11 passed, 0 failed`. A sandboxed run is not a valid baseline because `pgrep` cannot enumerate host processes there; #544 records and closes that false-positive path.

- [x] **Step 2: Add four independent behavior tests**

Add tests that prove:

1. two commands targeting the same UDID never overlap;
2. commands targeting different UDIDs do overlap;
3. with `MT_GATE_MAX_CONCURRENT=2`, a third different-UDID command stays queued until either holder exits;
4. while one process holds the per-UDID lock, another invocation observes the same inode and cannot acquire it even if a retired path exists.

Each test records start/end markers in a temp directory and derives its expected ordering from literal marker relationships, not from implementation helpers.

- [x] **Step 3: Add release-gate boundary tests**

Run `scripts/release-gate.sh` in a controlled temp git worktree with its external commands stubbed below the script boundary. Assert that an unset destination fails before fetch/build work, malformed destinations fail clearly, and two distinct UDIDs yield distinct default run/DerivedData paths.

- [x] **Step 4: Run the expanded harness and verify RED**

Run: `./scripts/sim-lock-tests.sh`

Expected: the same-simulator, cap, stable-inode, and destination/DerivedData tests fail because the current scripts use one replaceable global path and a fallback UDID.

### Task 2: Hold stable per-UDID and semaphore locks on descriptors

**Files:**
- Modify: `scripts/sim-lock.sh`
- Test: `scripts/sim-lock-tests.sh`

**Interfaces:**
- Consumes: `MT_RELEASE_GATE_DESTINATION`, optional positive integer `MT_GATE_MAX_CONCURRENT`, optional `MT_SIM_LOCK_WAIT`
- Produces: `MT_SIM_LOCK=1` for the child, a stable `/private/tmp/making-tracks-sim-<UDID>.lock`, and stable `/private/tmp/making-tracks-gate-slot-<N>.lock` files

- [x] **Step 1: Parse and validate the destination**

Reject an unset destination or a value without `id=<simulator-udid>`. Restrict the extracted UDID to letters, digits, and hyphens before using it in a path.

- [x] **Step 2: Open the simulator lock once and acquire it by descriptor**

Use fixed descriptors compatible with the macOS system Bash and append/create semantics:

```bash
exec 8>>"$sim_lock_path"
"$FLOCK_BIN" -w "$LOCK_WAIT_SECONDS" 8
```

Never unlink, rename, symlink, or truncate the lock file.

- [x] **Step 3: Acquire one global semaphore slot**

Open each stable slot file in numeric order and try `flock -n` on its descriptor. If all slots are occupied, close the unsuccessful descriptors, emit a bounded waiting message, poll until a slot opens or `MT_SIM_LOCK_WAIT` expires, and retain the winning descriptor until the child exits.

- [x] **Step 4: Preserve re-entrancy and destructive-operation safety**

A nested invocation executes directly only when `MT_SIM_LOCK=1` and `MT_SIM_LOCK_UDID` exactly matches the
selected destination. `--status` still returns HELD if either the selected simulator lock or a non-idle
process using that UDID is visible, and fails closed when either inspection boundary errors. `--erase`,
`--shutdown`, and `--boot` continue to use only the selected UDID.

- [x] **Step 5: Run the harness and verify GREEN**

Run: `./scripts/sim-lock-tests.sh`

Expected: every process, serialization, concurrency, cap, re-entrancy, status, erase, and inode-stability test passes.

### Task 3: Make release-gate destination and DerivedData seat-specific

**Files:**
- Modify: `scripts/release-gate.sh`
- Test: `scripts/sim-lock-tests.sh`

**Interfaces:**
- Consumes: required `MT_RELEASE_GATE_DESTINATION`
- Produces: default `/private/tmp/release-gate-<UDID>/DerivedData`, unless the existing run-dir or DerivedData overrides are explicitly set

- [x] **Step 1: Remove the retired hardcoded UDID fallback**

Set `DESTINATION` only from `MT_RELEASE_GATE_DESTINATION` and refuse an empty value with a message that says the per-seat simulator row requires the variable.

- [x] **Step 2: Derive the default run directory from the validated UDID**

Keep `MT_RELEASE_GATE_RUN_DIR` and `MT_RELEASE_GATE_DERIVED_DATA` as explicit overrides. Otherwise use the parsed UDID so two seats cannot share DerivedData even if `AM_ME` is absent or stale.

- [x] **Step 3: Run boundary tests and the full harness**

Run: `./scripts/sim-lock-tests.sh`

Expected: all tests pass and the missing-destination case performs no git fetch, simulator, or xcode action.

Run: `python -m pytest pipeline/tests/test_release_gate_script.py -q`

Expected: the established release-gate contract suite passes with explicit matching destination/lock
identities, malformed and duplicate destination rejection, and result-bundle cleanup on success and failure.

### Task 4: Record machine facts and execute the gates

**Files:**
- Modify: `docs/ios-gate-ledger.md`
- Modify: `docs/superpowers/phases/pre-phase/tasks.md`
- Test: `scripts/sim-lock-tests.sh`

**Interfaces:**
- Consumes: the four seat assignments from planner
- Produces: one authoritative iOS-branch table of seat, simulator name, and destination plus the default concurrency cap

- [x] **Step 1: Add the per-seat table to the operational gate ledger**

Record `codex1` through `codex4`, their `mt-gate-*` names, the four literal destinations, the default cap of two, and the rule that the environment exports the matching destination before any simulator command.

- [x] **Step 2: Run syntax and static analysis**

Run:

```bash
bash -n scripts/sim-lock.sh scripts/sim-lock-tests.sh scripts/release-gate.sh
shellcheck scripts/sim-lock.sh scripts/sim-lock-tests.sh scripts/release-gate.sh
```

Expected: zero errors and zero warnings.

- [x] **Step 3: Run the complete script harness repeatedly**

Run: `./scripts/sim-lock-tests.sh` at least three consecutive times.

Expected: identical pass counts and zero failures on every run.

- [x] **Step 4: Prove teeth**

Temporarily neutralise same-simulator locking, lower/raise the semaphore enforcement so a third overlaps, and replace descriptor locking with a replaceable path. In each case, run the one owning test and record its expected failure, then restore production code and rerun green.

- [ ] **Step 5: Update the durable status row**

Append `tests green`, `PR open`, `review clean`, and `ready-to-merge` transitions as each state becomes true; announce the same transitions to planner over AMQ.
