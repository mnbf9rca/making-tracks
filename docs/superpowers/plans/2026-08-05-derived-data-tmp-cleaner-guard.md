# DerivedData tmp-cleaner Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Relocate every host gate's reusable DerivedData to a persistent per-seat user cache and fail closed before Xcode whenever a selected DerivedData path resolves below `/tmp` or `/private/tmp`.

**Architecture:** A shared Bash library owns canonicalization and the #612 temporary-root predicate. `sim-lock.sh` injects the logical seat and safe default and validates caller/direct-Xcode paths; `release-gate.sh` independently validates its effective path before any DerivedData mutation.

**Tech Stack:** macOS Bash 3.2, `realpath`, the existing shell host harness, ShellCheck, GitHub Actions' explicit release-gate environment.

## Global Constraints

- Host defaults are exactly `$HOME/Library/Caches/making-tracks-gates/<seat>`.
- The frozen codex2 crime-scene DD under `/private/tmp` is read-only evidence and is never migrated.
- Result bundles and lock files may stay under `/private/tmp`; only active/reusable DerivedData is prohibited.
- Both boundaries fail before Xcode and cite #612.
- CI retains its explicit non-temporary DerivedData override.
- The production gate ceiling remains 2 outside planner-announced #600 windows.

---

## File structure

- Create `scripts/derived-data-path.sh`: shared canonical-path resolver and temporary-root refusal predicate.
- Modify `scripts/sim-lock.sh`: export seat/default DD and validate inherited/direct-Xcode paths.
- Modify `scripts/release-gate.sh`: use the per-seat cache default and independently validate before prune/create.
- Modify `scripts/sim-lock-tests.sh`: real-boundary RED/GREEN coverage and seat isolation.
- Modify `AGENTS.md` and `docs/ios-gate-ledger.md`: iOS-specific disk-hygiene law and operator reference.
- Modify active regeneration scripts/docs that still prescribe `/private/tmp` DDs; historical plan transcripts remain unchanged.
- Modify `docs/superpowers/phases/pre-phase/tasks.md`: durable #612 branch/test/review status.

### Task 1: Prove and implement both fail-closed boundaries

**Files:**
- Create: `scripts/derived-data-path.sh`
- Modify: `scripts/sim-lock.sh`
- Modify: `scripts/release-gate.sh`
- Test: `scripts/sim-lock-tests.sh`

**Interfaces:**
- Produces: `mt_canonical_derived_data_path <path>` prints one canonical absolute path or returns nonzero with diagnostics.
- Produces: `mt_refuse_tmp_derived_data <path> <prefix>` prints the canonical safe path, or returns nonzero with a `#612` refusal through the supplied command prefix.
- Produces: `MT_SIM_LOCK_SEAT=<codex1..codex4>` and `MT_RELEASE_GATE_DERIVED_DATA=$HOME/Library/Caches/making-tracks-gates/<seat>` for wrapped commands when the caller supplied no override.
- Consumes: `HOME`, selected `SEAT`, optional `MT_RELEASE_GATE_DERIVED_DATA`, and direct `xcodebuild -derivedDataPath`/`-derivedDataPath=<path>` arguments.

- [ ] **Step 1: Add release-gate RED cases to the existing fake-Xcode boundary**

Add cases that set an explicit `/private/tmp/...`, `/tmp/...`, and a symlinked safe-looking parent targeting `/private/tmp`; each must expect nonzero, `#612`, and an absent fake-Xcode log. Add a safe explicit cache path that must reach fake Xcode unchanged.

```bash
unsafe_gate_out="$(
  PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$HERE/.." \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$RELEASE_UDID_A" \
    MT_SIM_LOCK_SEAT=codex1 \
    MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$RELEASE_UDID_A" \
    MT_RELEASE_GATE_DERIVED_DATA="/private/tmp/mt-612-unsafe" \
    MT_RELEASE_GATE_MODE=build \
    "$RELEASE_GATE" 2>&1
)"
```

- [ ] **Step 2: Add sim-lock RED cases**

Use the test seams to prove an inherited temporary override and direct
`xcodebuild -derivedDataPath /tmp/...` both refuse before a marker command or
fake Xcode can run. Add one wrapped helper that records
`MT_SIM_LOCK_SEAT|MT_RELEASE_GATE_DERIVED_DATA` and assert distinct codex1 and
codex2 cache paths under a fixture `HOME`.

- [ ] **Step 3: Run RED and verify the failure has teeth**

Run:

```bash
./scripts/sim-lock-tests.sh
```

Expected: the new temporary-root/default-path assertions fail because the
current scripts still accept `/private/tmp` and derive DD below the run dir;
all pre-existing assertions remain green.

- [ ] **Step 4: Implement the shared validator**

Create `scripts/derived-data-path.sh` with no top-level mutation. For an
existing target, resolve it directly. For a new target, reject terminal `.` or
`..`, require an existing parent, resolve the parent, and append the basename.
Reject canonical results equal to or below `/private/tmp` (which also covers
`/tmp` after resolution) with the assigned cache-root guidance and `#612`.

```bash
mt_refuse_tmp_derived_data() {
  local canonical
  local path="$1"
  local prefix="$2"

  canonical="$(mt_canonical_derived_data_path "$path")" || {
    echo "$prefix refused: cannot resolve DerivedData path: $path (#612)" >&2
    return 1
  }
  case "$canonical/" in
    /private/tmp/|/private/tmp/*)
      echo "$prefix refused: DerivedData path resolves under /tmp or /private/tmp; use \$HOME/Library/Caches/making-tracks-gates/<seat> (#612)" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$canonical"
}
```

- [ ] **Step 5: Wire `release-gate.sh`**

For local runs without an explicit override, require the wrapper-provided
`MT_SIM_LOCK_SEAT`, validate it as `codex1..codex4`, create the known-safe cache
parent, and select `$HOME/Library/Caches/making-tracks-gates/$MT_SIM_LOCK_SEAT`.
CI may omit the seat only when `MT_RELEASE_GATE_DERIVED_DATA` is explicit.
Canonicalize/refuse before `prune_derived_data_if_stale` and `mkdir -p
"$DERIVED_DATA"`.

- [ ] **Step 6: Wire `sim-lock.sh`**

Before executing a wrapped command, create the known-safe cache parent,
validate an inherited DD override if present, scan direct Xcode arguments for
both derived-data flag forms, then export `MT_SIM_LOCK_SEAT` and either the
validated override or the per-seat default. Do not apply this to `--status` or
other non-command inspection paths.

- [ ] **Step 7: Run GREEN and full shell checks**

Run:

```bash
./scripts/sim-lock-tests.sh
bash -n scripts/derived-data-path.sh scripts/sim-lock.sh scripts/release-gate.sh scripts/sim-lock-tests.sh
shellcheck scripts/derived-data-path.sh scripts/sim-lock.sh scripts/release-gate.sh scripts/sim-lock-tests.sh
```

Expected: every host assertion passes, including all new #612 cases; syntax and
ShellCheck emit no diagnostics.

- [ ] **Step 8: Prove mutation teeth**

Temporarily change only the shared temporary-root predicate to return the
canonical path. Run the focused host harness and confirm the new refusal cases
turn red because fake Xcode/markers run. Restore the source exactly and rerun
the harness green.

- [ ] **Step 9: Commit the boundary fix**

```bash
git add scripts/derived-data-path.sh scripts/sim-lock.sh scripts/release-gate.sh scripts/sim-lock-tests.sh
git commit -m "Keep gate DerivedData outside temporary storage"
```

### Task 2: Align law, operator docs, and active regeneration callers

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/ios-gate-ledger.md`
- Modify: `docs/design/design-system/regenerate-place-card-press-inset.sh`
- Modify: `docs/design/design-system/regenerate-snow-theme-lock.sh`
- Modify: `docs/design/design-system/README.md`
- Modify: `docs/design/design-system/place-card-press-inset-evidence.md`
- Modify: `docs/superpowers/phases/pre-phase/tasks.md`

**Interfaces:**
- Consumes: the cache-root contract implemented in Task 1.
- Produces: runnable active commands that agree with the enforced path policy and one iOS-specific law home for the develop-law override.

- [ ] **Step 1: Add the iOS-specific disk-hygiene delta**

Amend `AGENTS.md`'s existing disk-hygiene delta rather than copying develop's
rule. State that reusable seat DDs live at
`$HOME/Library/Caches/making-tracks-gates/<seat>` and temporary-root DDs are
refused because of #612. Keep result-bundle cleanup and lock-file rules intact.

- [ ] **Step 2: Update the gate ledger**

Add the per-seat cache-root mapping beside the Host Gate Seats table and explain
that `/private/tmp` remains valid for stable locks/result bundles but never DD.

- [ ] **Step 3: Migrate active regeneration defaults and commands**

Replace executable/default `/private/tmp/dd-codexN` references in active
design-system regeneration scripts and their current README/evidence commands
with `$HOME/Library/Caches/making-tracks-gates/codexN`. Preserve historical
plans as records.

- [ ] **Step 4: Add the durable pre-phase status row**

Record the proven tmp-cleaner root cause, #612 branch, preserved evidence root,
and host-test result without claiming merge or closure.

- [ ] **Step 5: Verify documentation and active caller coherence**

Run:

```bash
rg -n '/private/tmp/dd-|MT_RELEASE_GATE_DERIVED_DATA=/private/tmp' \
  AGENTS.md docs/ios-gate-ledger.md docs/design/design-system scripts
python3 scripts/lint_agent_law.py
bash -n docs/design/design-system/regenerate-place-card-press-inset.sh \
  docs/design/design-system/regenerate-snow-theme-lock.sh
shellcheck docs/design/design-system/regenerate-place-card-press-inset.sh \
  docs/design/design-system/regenerate-snow-theme-lock.sh
```

Expected: the scoped search has no active references; lint, syntax, and
ShellCheck pass.

- [ ] **Step 6: Commit docs and caller alignment**

```bash
git add AGENTS.md docs/ios-gate-ledger.md docs/design/design-system/regenerate-place-card-press-inset.sh docs/design/design-system/regenerate-snow-theme-lock.sh docs/design/design-system/README.md docs/design/design-system/place-card-press-inset-evidence.md docs/superpowers/phases/pre-phase/tasks.md
git commit -m "Document persistent gate DerivedData roots"
```

### Task 3: Verify the host gate, review, and publish the fix

**Files:**
- Modify: `docs/superpowers/phases/pre-phase/tasks.md` only if final evidence changes the recorded counts/head.
- Update externally: issue #612 body and draft PR body.

**Interfaces:**
- Consumes: Tasks 1 and 2 at one exact signed head.
- Produces: verified host evidence, adversarial review accounting, and a draft PR into `ios`; it does not self-merge.

- [ ] **Step 1: Re-ground and run static/host tests**

Run:

```bash
git fetch origin ios
git merge-base --is-ancestor origin/ios HEAD
git diff --check
./scripts/sim-lock-tests.sh
bash -n scripts/derived-data-path.sh scripts/sim-lock.sh scripts/release-gate.sh scripts/sim-lock-tests.sh
shellcheck scripts/derived-data-path.sh scripts/sim-lock.sh scripts/release-gate.sh scripts/sim-lock-tests.sh
python3 scripts/lint_agent_law.py
cd ios && swift test
```

Expected: ancestry succeeds; host harness, syntax, ShellCheck, law lint, and the
full Swift package suite pass with exact counts recorded.

- [ ] **Step 2: Run one full codex3 gate from the new default**

First verify all seats with `sim-lock.sh --status`. Then run exactly once:

```bash
./scripts/sim-lock.sh --seat codex3 ./scripts/release-gate.sh
```

Expected: Release build, Debug build-for-testing, 251 app tests and 120 UI tests
pass without retry; Xcode reports the cache DD below
`/Users/rob/Library/Caches/making-tracks-gates/codex3`. Extract counts and remove
only the successful result bundle; preserve the reusable cache DD.

- [ ] **Step 3: Run adversarial review**

Request independent lenses for spec fidelity, shell correctness/canonical-path
bypasses, test teeth, and security posture. Cross-examine findings, fix every
surviving item with a red test first, and record raised/survived/fixed totals.

- [ ] **Step 4: Update #612 body-first**

Rewrite the issue's outcome/fix section with the landed exact head, tests,
evidence cache path and digests, and the remaining merge ownership. Verify the
live body before changing any issue state; leave #612 open until the PR merges.

- [ ] **Step 5: Push and verify the branch**

```bash
git push origin HEAD
git ls-remote --heads origin fix-612-derived-data-tmp-cleaner
```

Expected: the remote SHA equals local `HEAD` and the signed commit verifies.

- [ ] **Step 6: Open the draft PR and apply gates**

Open a draft PR from `fix-612-derived-data-tmp-cleaner` to `ios`, name #612 in
the body, include exact test output and adversarial accounting, and apply
`sourcery-review`, `track-b-ios`, and `wp`. Verify base/head/labels/body live.
The planner/fable retains merge ownership.
