# Simulator Concurrency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every builder seat its own simulator while serialising same-simulator work, limiting simultaneous gates to two, and permanently closing #497's lock-inode split.

**Architecture:** `sim-lock.sh` parses the simulator UDID from the required `MT_RELEASE_GATE_DESTINATION`, opens a stable per-UDID lock file once, and holds `flock` on that open descriptor for the whole child command. After the simulator lock is held, it acquires one of `MT_GATE_MAX_CONCURRENT` stable global slot files; the default is two, and the slot descriptor remains open until the child exits. `release-gate.sh` rejects missing destinations before doing work and keys its default run/DerivedData directory from the destination UDID.

**Tech Stack:** Bash 5, Homebrew `flock`, ShellCheck, `scripts/sim-lock-tests.sh`

## Global Constraints

- Branch from current `origin/ios`; target `ios`.
- The literal branch is `wp-infra-sim-concurrency`.
- Lock files live under `/private/tmp`, are opened with `O_CREAT`, are locked by open file descriptor, and are never deleted or replaced.
- Same-simulator work serialises; different simulators may overlap; no more than `MT_GATE_MAX_CONCURRENT` locked commands overlap globally (default `2`).
- `MT_RELEASE_GATE_DESTINATION` is mandatory and must contain `id=<simulator-udid>`.
- The test harness must exercise real process, lock, and timing effects; it must not inspect source text.
- The per-seat simulator table is recorded in the iOS gate's operational ledger because `docs/INFRA.md` is develop-owned and deliberately absent from the `ios` tree.

---

### Task 1: Repair the baseline process fixture and pin the new contracts red

**Files:**
- Modify: `scripts/sim-lock-tests.sh`
- Modify: `docs/superpowers/phases/pre-phase/tasks.md`

**Interfaces:**
- Consumes: `MT_SIM_LOCK_TEST_MODE=1`, `MT_SIM_LOCK_TEST_ROOT`, `MT_RELEASE_GATE_DESTINATION`, and the real `scripts/sim-lock.sh`
- Produces: observable long-running fake gate processes plus timing assertions for lock and semaphore behavior

- [ ] **Step 1: Replace the `exec -a ... sleep` fixture with a temporary executable whose real path or arguments contain the fake UDID**

Create the fixture inside the test temp directory and invoke it with the destination string as a real argument. Confirm independently with `pgrep -f -- "$FAKE_UDID"` before using it in an assertion.

- [ ] **Step 2: Run the existing harness and verify the #544 baseline turns green**

Run: `./scripts/sim-lock-tests.sh`

Expected: `11 passed, 0 failed` before adding the new contract tests.

- [ ] **Step 3: Add four independent behavior tests**

Add tests that prove:

1. two commands targeting the same UDID never overlap;
2. commands targeting different UDIDs do overlap;
3. with `MT_GATE_MAX_CONCURRENT=2`, a third different-UDID command stays queued until either holder exits;
4. while one process holds the per-UDID lock, another invocation observes the same inode and cannot acquire it even if a retired path exists.

Each test records start/end markers in a temp directory and derives its expected ordering from literal marker relationships, not from implementation helpers.

- [ ] **Step 4: Add release-gate boundary tests**

Run `scripts/release-gate.sh` in a controlled temp git worktree with its external commands stubbed below the script boundary. Assert that an unset destination fails before fetch/build work, malformed destinations fail clearly, and two distinct UDIDs yield distinct default run/DerivedData paths.

- [ ] **Step 5: Run the expanded harness and verify RED**

Run: `./scripts/sim-lock-tests.sh`

Expected: the same-simulator, cap, stable-inode, and destination/DerivedData tests fail because the current scripts use one replaceable global path and a fallback UDID.

### Task 2: Hold stable per-UDID and semaphore locks on descriptors

**Files:**
- Modify: `scripts/sim-lock.sh`
- Test: `scripts/sim-lock-tests.sh`

**Interfaces:**
- Consumes: `MT_RELEASE_GATE_DESTINATION`, optional positive integer `MT_GATE_MAX_CONCURRENT`, optional `MT_SIM_LOCK_WAIT`
- Produces: `MT_SIM_LOCK=1` for the child, a stable `/private/tmp/making-tracks-sim-<UDID>.lock`, and stable `/private/tmp/making-tracks-gate-slot-<N>.lock` files

- [ ] **Step 1: Parse and validate the destination**

Reject an unset destination or a value without `id=<simulator-udid>`. Restrict the extracted UDID to letters, digits, and hyphens before using it in a path.

- [ ] **Step 2: Open the simulator lock once and acquire it by descriptor**

Use Bash descriptor allocation with append/create semantics:

```bash
exec {sim_lock_fd}>>"$sim_lock_path"
"$FLOCK_BIN" -w "$LOCK_WAIT_SECONDS" "$sim_lock_fd"
```

Never unlink, rename, symlink, or truncate the lock file.

- [ ] **Step 3: Acquire one global semaphore slot**

Open each stable slot file in numeric order and try `flock -n` on its descriptor. If all slots are occupied, close the unsuccessful descriptors, emit a bounded waiting message, poll until a slot opens or `MT_SIM_LOCK_WAIT` expires, and retain the winning descriptor until the child exits.

- [ ] **Step 4: Preserve re-entrancy and destructive-operation safety**

A nested invocation with `MT_SIM_LOCK=1` executes directly. `--status` still returns HELD if either the selected simulator lock or a non-idle process using that UDID is visible. `--erase`, `--shutdown`, and `--boot` continue to use only the selected UDID.

- [ ] **Step 5: Run the harness and verify GREEN**

Run: `./scripts/sim-lock-tests.sh`

Expected: every process, serialization, concurrency, cap, re-entrancy, status, erase, and inode-stability test passes.

### Task 3: Make release-gate destination and DerivedData seat-specific

**Files:**
- Modify: `scripts/release-gate.sh`
- Test: `scripts/sim-lock-tests.sh`

**Interfaces:**
- Consumes: required `MT_RELEASE_GATE_DESTINATION`
- Produces: default `/private/tmp/release-gate-<UDID>/DerivedData`, unless the existing run-dir or DerivedData overrides are explicitly set

- [ ] **Step 1: Remove the retired hardcoded UDID fallback**

Set `DESTINATION` only from `MT_RELEASE_GATE_DESTINATION` and refuse an empty value with a message that says the per-seat simulator row requires the variable.

- [ ] **Step 2: Derive the default run directory from the validated UDID**

Keep `MT_RELEASE_GATE_RUN_DIR` and `MT_RELEASE_GATE_DERIVED_DATA` as explicit overrides. Otherwise use the parsed UDID so two seats cannot share DerivedData even if `AM_ME` is absent or stale.

- [ ] **Step 3: Run boundary tests and the full harness**

Run: `./scripts/sim-lock-tests.sh`

Expected: all tests pass and the missing-destination case performs no git fetch, simulator, or xcode action.

### Task 4: Record machine facts and execute the gates

**Files:**
- Modify: `docs/ios-gate-ledger.md`
- Modify: `docs/superpowers/phases/pre-phase/tasks.md`
- Test: `scripts/sim-lock-tests.sh`

**Interfaces:**
- Consumes: the four seat assignments from planner
- Produces: one authoritative iOS-branch table of seat, simulator name, and destination plus the default concurrency cap

- [ ] **Step 1: Add the per-seat table to the operational gate ledger**

Record `codex1` through `codex4`, their `mt-gate-*` names, the four literal destinations, the default cap of two, and the rule that the environment exports the matching destination before any simulator command.

- [ ] **Step 2: Run syntax and static analysis**

Run:

```bash
bash -n scripts/sim-lock.sh scripts/sim-lock-tests.sh scripts/release-gate.sh
shellcheck scripts/sim-lock.sh scripts/sim-lock-tests.sh scripts/release-gate.sh
```

Expected: zero errors and zero warnings.

- [ ] **Step 3: Run the complete script harness repeatedly**

Run: `./scripts/sim-lock-tests.sh` at least three consecutive times.

Expected: identical pass counts and zero failures on every run.

- [ ] **Step 4: Prove teeth**

Temporarily neutralise same-simulator locking, lower/raise the semaphore enforcement so a third overlaps, and replace descriptor locking with a replaceable path. In each case, run the one owning test and record its expected failure, then restore production code and rerun green.

- [ ] **Step 5: Update the durable status row**

Append `tests green`, `PR open`, `review clean`, and `ready-to-merge` transitions as each state becomes true; announce the same transitions to planner over AMQ.
