# Release Gate Committed Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every iOS release-gate Xcode phase consume the committed `ios/Package.resolved` graph and fail closed on dirty input or resolution drift.

**Architecture:** `scripts/release-gate.sh` owns one preflight snapshot and one post-Xcode invariant around its existing `run_xcodebuild` boundary. The host controller harness drives the real gate against a disposable repository fixture, so deliberate corruption never touches the builder worktree.

**Tech Stack:** Bash 3.2, Git, `xcodebuild`, `shasum`, ShellCheck, and `scripts/sim-lock-tests.sh`.

## Global Constraints

- Scope is gate verification for #523; #614 retains resolver unification, intentional lockfile updates, and dependency-transition DerivedData invalidation.
- `ios/Package.resolved` must be a regular non-symlink tracked file, with neither staged nor unstaged differences from `HEAD`.
- Every Xcode phase receives exactly one `-onlyUsePackageVersionsFromResolvedFile`.
- The SHA-256 captured before artifact creation and simulator boot must still match after every Xcode invocation, even when Xcode fails.
- Resolution drift wins as the diagnostic; otherwise preserve Xcode's original status.
- Never restore or rewrite `ios/Package.resolved` in the gate.
- Final simulator verification uses seat `codex1` with `MT_GATE_MAX_CONCURRENT=3`.
- Do not change dependency declarations, CI topology, app behavior, or user-facing surfaces.

---

### Task 1: Fail Closed Around the Committed Lockfile

**Files:**
- Modify: `scripts/sim-lock-tests.sh`
- Modify: `scripts/release-gate.sh`

**Interfaces:**
- Consumes: `refuse(message)`, `phase(label, command...)`, `run_xcodebuild(label, args...)`, and the existing fake Git/Xcode seam.
- Produces: `capture_committed_package_resolution()`, `verify_committed_package_resolution()`, and immutable `PACKAGE_RESOLVED_DIGEST`.

- [ ] **Step 1: Add a disposable release-gate repository fixture**

Before the release-gate host tests, create and reset:

```bash
RELEASE_FIXTURE_REPO="$TMP/release-fixture-repo"
RELEASE_FIXTURE_RESOLVED="$RELEASE_FIXTURE_REPO/ios/Package.resolved"
RELEASE_FIXTURE_PBXPROJ="$RELEASE_FIXTURE_REPO/ios/App/MakingTracks.xcodeproj/project.pbxproj"

reset_release_fixture_repo() {
  rm -rf "$RELEASE_FIXTURE_REPO"
  mkdir -p "$(dirname "$RELEASE_FIXTURE_RESOLVED")" "$(dirname "$RELEASE_FIXTURE_PBXPROJ")"
  cp "$HERE/../ios/Package.resolved" "$RELEASE_FIXTURE_RESOLVED"
  cp "$HERE/../ios/App/MakingTracks.xcodeproj/project.pbxproj" "$RELEASE_FIXTURE_PBXPROJ"
}
```

Extend fake Git with independently controlled outcomes:

```bash
"ls-files --error-unmatch") [ "${MT_TEST_GIT_TRACKED:-1}" = "1" ] ;;
"diff --quiet") [ "${MT_TEST_GIT_UNSTAGED_DIRTY:-0}" = "0" ] ;;
"diff --cached") [ "${MT_TEST_GIT_STAGED_DIRTY:-0}" = "0" ] ;;
```

Extend fake Xcode to append `mutated` to `$MT_TEST_PACKAGE_RESOLVED` when
`MT_TEST_XCODEBUILD_MUTATE_RESOLVED=1` and to return
`MT_TEST_XCODEBUILD_BUILD_STATUS` for the Release-build shape. Route artifact
fixtures through `RELEASE_FIXTURE_REPO`. Add `XCRUN_LOG="$TMP/xcrun.log"`,
make fake `xcrun` append its arguments when `MT_TEST_XCRUN_LOG` is set, and
export that path from the fixture runner.

- [ ] **Step 2: Write seven failing preflight/post-phase cases**

Add these exact cases:

```text
release gate refuses an absent Package.resolved before Xcode
release gate refuses a symlinked Package.resolved before Xcode
release gate refuses an untracked Package.resolved before Xcode
release gate refuses an unstaged Package.resolved before Xcode
release gate refuses a staged Package.resolved before Xcode
release gate rejects a successful Xcode phase that changes Package.resolved
release gate preserves an unchanged failing Xcode phase status
```

Every preflight case requires a nonzero status, the exact lockfile path, the
recovery text `commit the intentional update, or restore it from HEAD`, and an
empty Xcode log and empty simulator-command log. The successful-mutator case
runs `full` mode and requires only one logged Xcode call, a drift diagnostic,
and no success marker. The unchanged failure case makes the fake Release build
return `73` and requires both gate exit `73` and
`release build status=73`.

- [ ] **Step 3: Run RED**

Run `bash scripts/sim-lock-tests.sh`.

Expected: the existing 126 cases remain green and all seven new cases fail.
If sandboxing blocks cache or process-inspection paths, rerun the identical
command with host approval.

- [ ] **Step 4: Implement the snapshot and invariant**

Add:

```bash
PACKAGE_RESOLVED="ios/Package.resolved"
PACKAGE_RESOLVED_DIGEST=""

package_resolution_digest() {
  shasum -a 256 "$PACKAGE_RESOLVED" | awk '{print $1}'
}

package_resolution_matches_head() {
  [ -f "$PACKAGE_RESOLVED" ] &&
    [ ! -L "$PACKAGE_RESOLVED" ] &&
    git ls-files --error-unmatch -- "$PACKAGE_RESOLVED" >/dev/null 2>&1 &&
    git diff --quiet -- "$PACKAGE_RESOLVED" &&
    git diff --cached --quiet HEAD -- "$PACKAGE_RESOLVED"
}

capture_committed_package_resolution() {
  package_resolution_matches_head ||
    refuse "$PACKAGE_RESOLVED must be a regular tracked file matching HEAD; commit the intentional update, or restore it from HEAD"
  PACKAGE_RESOLVED_DIGEST="$(package_resolution_digest)" ||
    refuse "could not hash committed package resolution: $PACKAGE_RESOLVED"
  [ -n "$PACKAGE_RESOLVED_DIGEST" ] ||
    refuse "could not hash committed package resolution: $PACKAGE_RESOLVED"
  echo "release-gate: package resolution: $PACKAGE_RESOLVED sha256=$PACKAGE_RESOLVED_DIGEST" >&2
}

verify_committed_package_resolution() {
  local current_digest
  if ! package_resolution_matches_head; then
    echo "release-gate: dependency resolution drift: Xcode changed $PACKAGE_RESOLVED; refusing gate result" >&2
    return 1
  fi
  current_digest="$(package_resolution_digest)" || {
    echo "release-gate: dependency resolution drift: could not hash $PACKAGE_RESOLVED after Xcode" >&2
    return 1
  }
  if [ "$current_digest" != "$PACKAGE_RESOLVED_DIGEST" ]; then
    echo "release-gate: dependency resolution drift: $PACKAGE_RESOLVED sha256=$current_digest expected=$PACKAGE_RESOLVED_DIGEST" >&2
    return 1
  fi
}
```

Call `capture_committed_package_resolution` after ancestry/lock validation and
before `prepare_artifact_paths`.

Refactor `run_xcodebuild` so local Xcode or the CI pipeline stores its status in
`xcode_status`, then executes:

```bash
verify_committed_package_resolution || return 1
return "$xcode_status"
```

The surrounding `phase` already disables `errexit` and `pipefail` preserves the
CI pipeline status.

- [ ] **Step 5: Run GREEN and prove post-phase teeth**

Run `bash scripts/sim-lock-tests.sh`.

Expected: `133 passed, 0 failed` and no lockfile change in `git status --short`.

Use `apply_patch` to temporarily replace the post-phase verification call with
`:`. Rerun the harness; exactly the successful-mutator case must fail. Restore
the call with `apply_patch` and rerun to `133 passed, 0 failed`.

- [ ] **Step 6: Commit and publish Task 1**

```bash
git add scripts/release-gate.sh scripts/sim-lock-tests.sh
git commit -S -m "Fail release gate on resolution drift"
git push origin HEAD
```

Run each mutation as a separate command and verify the signed remote head.

---

### Task 2: Pin Every Xcode Invocation

**Files:**
- Modify: `scripts/sim-lock-tests.sh`
- Modify: `scripts/release-gate.sh`

**Interfaces:**
- Consumes: Task 1's `run_xcodebuild` boundary and fake-Xcode argument log.
- Produces: `PACKAGE_RESOLUTION_ARGS`, the single policy source for all four Xcode invocation shapes.

- [ ] **Step 1: Write two failing argument invariants**

Add:

```bash
all_xcode_calls_use_committed_resolution() {
  local expected_calls="$1"
  local flag="-onlyUsePackageVersionsFromResolvedFile"
  [ "$(wc -l <"$XCODEBUILD_LOG" | tr -d '[:space:]')" = "$expected_calls" ] || return 1
  awk -v flag="$flag" '{
    count = 0
    for (i = 1; i <= NF; i++) if ($i == flag) count++
    if (count != 1) exit 1
  }' "$XCODEBUILD_LOG"
}
```

One successful `full` fixture requires exactly three pinned calls. One
successful `enumerate` fixture requires exactly one pinned call.

- [ ] **Step 2: Run RED**

Run `bash scripts/sim-lock-tests.sh`.

Expected: Task 1 remains green and exactly the two argument cases fail.

- [ ] **Step 3: Centralize the Xcode argument**

Add:

```bash
PACKAGE_RESOLUTION_ARGS=(-onlyUsePackageVersionsFromResolvedFile)
```

Both local and CI branches inside `run_xcodebuild` invoke:

```bash
xcodebuild "${PACKAGE_RESOLUTION_ARGS[@]}" "$@"
```

The CI branch retains its existing `tee`/`xcbeautify` pipeline. Do not duplicate
the flag at the Release, build-for-testing, test, or enumerate call sites.

- [ ] **Step 4: Run GREEN and prove argument teeth**

Run `bash scripts/sim-lock-tests.sh`. Expected: `135 passed, 0 failed`.

Use `apply_patch` to temporarily change `PACKAGE_RESOLUTION_ARGS` to an empty
array. Rerun the harness; exactly both argument invariants must fail. Restore
the flag and rerun to `135 passed, 0 failed`.

- [ ] **Step 5: Run static verification**

```bash
bash -n scripts/release-gate.sh scripts/sim-lock-tests.sh
shellcheck scripts/release-gate.sh scripts/sim-lock-tests.sh
python3 scripts/lint_agent_law.py
git diff --check
git status --short
```

Expected: all succeed, only intended #523 files are modified, and
`ios/Package.resolved` is absent from status.

- [ ] **Step 6: Commit and publish Task 2**

```bash
git add scripts/release-gate.sh scripts/sim-lock-tests.sh
git commit -S -m "Pin release gate to committed packages"
git push origin HEAD
```

Run each mutation separately and verify the signed remote head.

---

### Task 3: Review, Gate, and Publish the Exact Head

**Files:**
- Modify: `docs/superpowers/phases/pre-phase/tasks.md`
- Modify: this plan only to check completed steps

**Interfaces:**
- Consumes: Task 2's exact signed code head and project review/gate protocols.
- Produces: exact-head review evidence, one ceiling-3 host gate, a draft PR to `ios`, and planner handoff.

- [ ] **Step 1: Re-ground**

Run `git fetch origin ios`, `git merge-base --is-ancestor origin/ios HEAD`,
`git diff --stat origin/ios..HEAD`, and `git diff --check` as separate calls.
If `ios` advanced, merge it non-interactively and rerun the controller harness
plus both mutation proofs.

- [ ] **Step 2: Run adversarial review**

Obtain independent critics for spec fidelity, Bash 3.2/status correctness, test
quality/teeth, #614 scope separation, and security/untrusted-input posture.
Cross-examine findings, fix survivors test-first, and receive final
Critical/Important/Minor counts for the exact signed head.

- [ ] **Step 3: Run exactly one fresh ceiling-3 host gate**

Require `./scripts/sim-lock.sh --seat codex1 --status` to report `FREE`, then
run exactly once:

```bash
MT_GATE_MAX_CONCURRENT=3 ./scripts/sim-lock.sh --seat codex1 ./scripts/release-gate.sh
```

Do not retry without planner direction. Record the emitted lockfile SHA-256,
Release/build-for-testing outcomes, exact app/unit and UI counts, timings,
owned result path and markers, clean Git status, and final authoritative
`codex1` status.

- [ ] **Step 4: Record and commit evidence**

Append one chronological ledger line with the exact head, controller count,
both mutation results, review counts, one host-gate result, lockfile digest and
cleanliness, artifact lifecycle, and seat status. Run law lint and diff checks,
then sign, push, and verify the docs-only evidence commit.

- [ ] **Step 5: Open and verify the draft PR**

Target `ios` and serve #523. Include exact tests/review/gate evidence, both
installed-Xcode probes, and explicit #614 separation. Include:

```markdown
## Taste guesses

None.
```

Apply and verify `sourcery-review`, `track-b-ios`, and `wp`. Disposition every
automated review comment. Leave the PR unmerged.

- [ ] **Step 6: Hand off**

Send the planner the PR URL, exact signed head, ancestry/two-dot scope,
controller/mutation results, review verdict, host-gate counts, lock digest and
clean status, artifact markers, final seat status, and Sourcery disposition.
Wait for a drained receipt; planner owns merge and #523 closure.
