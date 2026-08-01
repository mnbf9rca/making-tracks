# Evidence Pipeline Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Discharge issue #584 by making all four Phase 2 evidence scripts boot a locked seat on demand and by declaring the evidence class of every committed Phase 2 implementation packet.

**Architecture:** Keep each regeneration script standalone. After it validates the lock-owned destination, it blocks on `xcrun simctl bootstatus <locked-UDID> -b` before any status-bar override, build, or test; a behavioral shell harness substitutes external tools and asserts that first simulator touch for all four consumers. The design-system README classifies assets using the three names ratified in the fleet evidence law.

**Tech Stack:** Bash, the existing `scripts/sim-lock-tests.sh` behavioral harness, Markdown evidence records, ShellCheck.

## Global Constraints

- The four scripts remain callable only through `scripts/sim-lock.sh --seat <seat>` and never accept a caller-supplied public destination.
- `scripts/sim-lock.sh` remains the sole lock owner; descendant boot waits use only the lock-validated `MT_SIM_LOCK_UDID`.
- Evidence classes are exactly **Deterministic fixture**, **Head-anchored**, and **Nondeterministic content**.
- No app source, project file, render, digest, or measurement record changes.

---

### Task 1: Pin cold-seat boot ordering

**Files:**
- Modify: `scripts/sim-lock-tests.sh`
- Modify: `docs/design/design-system/capture-t2.8-implementation.sh`
- Modify: `docs/design/design-system/regenerate-t2.3-door-glyph.sh`
- Modify: `docs/design/design-system/regenerate-t2.9-settings.sh`
- Modify: `docs/design/design-system/regenerate-t2.10-about.sh`

**Interfaces:**
- Consumes: lock-owned `MT_SIM_LOCK_DESTINATION`, `MT_SIM_LOCK_UDID`, and `MT_SIM_LOCK=1`.
- Produces: a blocking boot-on-demand guarantee before each script's first simulator-dependent action.

- [ ] **Step 1: Add a behavioral regression to `scripts/sim-lock-tests.sh`**

Create fake `xcrun` and `xcodebuild` executables. Run each evidence script with a lock-owned fake destination and assert its first logged `simctl` call is the literal `bootstatus <fake-UDID> -b`; the fake must terminate before any real simulator or build operation.

- [ ] **Step 2: Run the harness and verify RED**

Run: `./scripts/sim-lock-tests.sh`

Expected: four new failures. T2.3/T2.9/T2.10 first log `status_bar`; T2.8 reaches its fake build without any simulator boot.

- [ ] **Step 3: Add the minimal boot wait to all four scripts**

Immediately after lock/destination validation (and the existing Xcode-version guard where present), add:

```bash
xcrun simctl bootstatus "$simulator_udid" -b
```

- [ ] **Step 4: Run the harness and verify GREEN**

Run: `./scripts/sim-lock-tests.sh`

Expected: all tests pass, including four cold-seat ordering checks.

### Task 2: Declare packet evidence classes

**Files:**
- Modify: `docs/design/design-system/README.md`

**Interfaces:**
- Consumes: the evidence-class law in `docs/process/coordination.md` and #584's four-script regeneration scoreboard.
- Produces: explicit per-packet or per-frame oracle semantics for future readers.

- [ ] **Step 1: Label every Phase 2 implementation packet row**

State:

- T2.3: **Deterministic fixture**; SHA-256 is the byte-reproduction oracle.
- T2.8: **Nondeterministic content**; paired measurement records are the reproduction oracle and SHA-256 pins reviewed-session bytes.
- T2.9: **Deterministic fixture**; SHA-256 is the byte-reproduction oracle.
- T2.10: `t2.10-about.png` is **Head-anchored** at its named source head; the other five frames are **Deterministic fixture**.

- [ ] **Step 2: Verify the docs and scripts**

Run:

```bash
shellcheck scripts/*.sh docs/design/design-system/*.sh
python3 scripts/lint_agent_law.py
./scripts/sim-lock-tests.sh
```

Expected: zero ShellCheck/law-lint findings and the complete simulator-lock harness green.

### Task 3: Publish and close the tracked finding

**Files:**
- Modify: issue #584 body through GitHub after the PR is merge-ready and again after merge.

**Interfaces:**
- Consumes: exact verification counts, adversarial review accounting, and merged SHA.
- Produces: a PR into `ios`, then a body-first issue closeout naming both delivered obligations and their merge.

- [ ] **Step 1: Run adversarial review and fix every surviving actionable finding**

Review lenses: spec/law fidelity, shell correctness and cold-seat ordering, test teeth, evidence-class accuracy, and hostile-input/security scope.

- [ ] **Step 2: Commit, push, and open the PR**

Target `ios`; apply `sourcery-review`, `track-b-ios`, and `wp`; name #584 and include exact test output plus adversarial accounting.

- [ ] **Step 3: After planner merges, update issue #584 body before closing it**

Rewrite the issue body into one coherent record containing the original findings, delivered fix, verification evidence, PR number, and merge SHA. Then close the issue and verify its state.
