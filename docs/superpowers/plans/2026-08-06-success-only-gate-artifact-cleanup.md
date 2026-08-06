# Success-only Gate Artifact Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve every failed local release-gate artifact while bounding disk use by allowing a later successful default full gate to remove only gate-owned successful runs strictly older than 24 hours.

**Architecture:** Local artifact-producing invocations create unique owned run directories beneath the validated simulator UUID root and record exact owner/success markers. Success finalization is explicit and unreachable after a failed phase. Pruning is a post-success operation restricted to canonical direct siblings that satisfy the exact name, directory, marker, identity, and age predicates. Caller-named paths and CI keep separate ownership lifecycles and are never enrolled in local cleanup.

**Tech Stack:** Bash 3.2-compatible shell, macOS filesystem tools, the existing fake-Git/fake-simulator/fake-Xcode host harness in `scripts/sim-lock-tests.sh`, Bash syntax validation, ShellCheck

## Global Constraints

- Work only in `/Users/rob/git/making-tracks/.worktrees/fix-546-success-only-gate-artifact-cleanup`; never switch or mutate the root `ios` checkout.
- Preserve the approved design in `docs/superpowers/specs/2026-08-06-success-only-gate-artifact-cleanup-design.md` and the planner rulings: `86400` seconds, strict `age > threshold`, pruning only after a successful fully-default local `full` gate, and no automatic deletion of failed/unmarked or caller-owned artifacts.
- Use `$HOME/Library/Application Support/making-tracks-gates/evidence/<issue>` for durable evidence. The convention comes from AMQ ruling `2026-08-06T07-18-11.151Z_pid12763_bf6584ff`; cache roots are purgeable and may hold only bounded transient evidence with a named cleanup trigger.
- Keep CI behavior unchanged. Do not change `.github/workflows/ios-gate.yml`, simulator destinations, locks, semaphore policy, DerivedData policy, application code, or Xcode project files.
- All tests exercise the production `scripts/release-gate.sh`; doubles replace only Git, simulator, and Xcode boundaries. Assertions target exit status and filesystem state, not source text.
- Follow strict RED → GREEN → REFACTOR. Record the intended production break before every new test group and observe the new assertion fail for the intended reason before implementation.
- Use only exact resolved paths as deletion operands. Never pass a wildcard, a parent directory, an unresolved environment variable, or a symlink to `rm -rf`.
- Every repository mutation is a bare single command and is verified in the next command. Commits are signed and single-purpose.
- Do not launch the host gate until the planner explicitly opens codex3's slot after the #600 cap-3 guard gate.

---

## Task 1: Extend the fake-Xcode boundary and prove owned-success behavior RED

**Files:**

- Modify: `scripts/sim-lock-tests.sh:2088-2469`
- Test: `scripts/sim-lock-tests.sh`

- [x] **Step 1: Add artifact-aware fake-Xcode behavior**

Extend the existing fake `xcodebuild` program so it still logs the complete argument vector, then recognizes real Xcode output flags without replacing production logic:

```bash
args=" $* "
case "$args" in
  *" -resultBundlePath "*)
    result_path="${args#* -resultBundlePath }"
    result_path="${result_path%% *}"
    mkdir -p "$result_path"
    printf '%s\n' fake-result >"$result_path/Info.plist"
    ;;
esac
case "$args" in
  *" -test-enumeration-output-path "*)
    enumeration_path="${args#* -test-enumeration-output-path }"
    enumeration_path="${enumeration_path%% *}"
    mkdir -p "$(dirname "$enumeration_path")"
    printf '%s\n' '{"tests":[]}' >"$enumeration_path"
    ;;
esac
case "$args" in
  *" test-without-building "*) exit "${MT_TEST_XCODEBUILD_TEST_STATUS:-0}" ;;
esac
```

The fake earns no assertions of its own. Its output exists only so the real gate can create, mark, preserve, and prune artifact directories.

- [x] **Step 2: Add a local artifact fixture runner**

Add a helper that invokes the real script in `test` or `full` mode with the existing valid UUID, lock identity, safe persistent DerivedData, test mode, and optional deterministic clock:

```bash
run_artifact_gate() {
  local mode="$1"
  shift
  env "$@" \
    PATH="$FAKE_BIN:$PATH" \
    MT_TEST_REPO_ROOT="$HERE/.." \
    MT_TEST_XCODEBUILD_LOG="$XCODEBUILD_LOG" \
    MT_SIM_LOCK_TEST_MODE=1 \
    MT_SIM_LOCK=1 \
    MT_SIM_LOCK_UDID="$RELEASE_UDID_A" \
    MT_SIM_LOCK_SEAT=codex1 \
    MT_SIM_LOCK_DESTINATION="platform=iOS Simulator,id=$RELEASE_UDID_A" \
    MT_RELEASE_GATE_DERIVED_DATA="$SAFE_DERIVED_DATA" \
    MT_RELEASE_GATE_MODE="$mode" \
    "$RELEASE_GATE"
}
```

Locate the created run through the literal test root `/private/tmp/release-gate-$RELEASE_UDID_A/runs` and assert one exact direct child; do not recreate the production run-name matcher in a test helper.

- [x] **Step 3: Write the first behavioral tests**

Name the breaks before the bodies:

1. Removing owned per-run layout must fail because a successful default `test` invocation does not leave a unique direct child containing `MakingTracksTests.xcresult`, `.release-gate-owned`, and `.release-gate-success`.
2. Moving finalization before Xcode must fail because a controlled test failure would incorrectly leave `.release-gate-success`.
3. Running pruning before success must fail because a controlled failing default `full` invocation would remove an eligible older successful sibling.

Build the literal marker expectation from the independently controlled UUID fixture, not from a production helper:

```bash
expected_marker="$(printf 'release-gate-artifact-v1\nudid=%s' "$RELEASE_UDID_A")"
```

Assert the failed run retains its result bundle and owner marker, has no success marker, and leaves the seeded eligible sibling intact.

- [x] **Step 4: Run the new tests and observe RED**

Run:

```bash
./scripts/sim-lock-tests.sh
```

Expected: the new owned-layout assertion fails because the current script still writes the fixed result bundle and has no markers. Existing assertions remain green. If the failure is instead sandbox denial under the intentional `~/Library/Caches` fixture, rerun the same command with the required sandbox approval; do not change production paths to accommodate the sandbox.

---

## Task 2: Implement owned run creation and success-only finalization

**Files:**

- Modify: `scripts/release-gate.sh:52-70`
- Modify: `scripts/release-gate.sh:195-288`
- Test: `scripts/sim-lock-tests.sh`

- [x] **Step 1: Introduce explicit ownership state**

Add named constants and state near the existing path variables:

```bash
# #546 planner ruling: retain successful local gate artifacts for a strict 24-hour window.
SUCCESSFUL_ARTIFACT_MAX_AGE_SECONDS=86400
ARTIFACT_MARKER_SCHEMA="release-gate-artifact-v1"
DEFAULT_GATE_ROOT="/private/tmp/release-gate-$GATE_UDID"
LOCAL_GATE=true
[ "${GITHUB_ACTIONS:-}" = "true" ] && LOCAL_GATE=false
OWNS_ARTIFACT_RUN=false
PRUNE_AFTER_SUCCESS=false
OWNERSHIP_MARKER=""
SUCCESS_MARKER=""
```

Treat a local `full`, `test`, or `enumerate` invocation as gate-owned only when both `MT_RELEASE_GATE_RUN_DIR` and `MT_RELEASE_GATE_RESULT_BUNDLE` are empty. `build` keeps the existing fixed run-directory behavior and creates no ownership markers. A fully-default local `full` owned invocation sets `PRUNE_AFTER_SUCCESS=true`.

- [x] **Step 2: Validate and create the owned directory chain before Xcode**

Implement small Bash functions with one responsibility each:

```bash
refuse_symlink_or_non_directory() { ...; }
canonical_directory() { (cd "$1" 2>/dev/null && pwd -P); }
write_identity_marker() {
  printf '%s\nudid=%s\n' "$ARTIFACT_MARKER_SCHEMA" "$GATE_UDID" >"$1"
}
```

For owned invocations:

1. validate/create `DEFAULT_GATE_ROOT` and `DEFAULT_GATE_ROOT/runs` as real, non-symlink directories;
2. require their canonical values to equal the literal validated UUID paths;
3. derive `run-$(date -u +%Y%m%dT%H%M%SZ)-$$` and reject any existing file, directory, or symlink with that name;
4. create the run directory without `mkdir -p` at the leaf;
5. write `.release-gate-owned` before simulator/Xcode work;
6. point the default result and enumeration paths inside that run.

Print the exact owned run path to stderr so a failed gate tells the operator what was preserved.

- [x] **Step 3: Replace unsafe local preflight deletion**

Keep `rm -rf "$RESULT_BUNDLE"` only in the existing GitHub Actions ownership path. For local `full` and `test`, if a caller-owned result target already exists or is a symlink, refuse before simulator/Xcode work and name the exact path plus the durable evidence recovery root. Never delete an explicit local `MT_RELEASE_GATE_RUN_DIR`, `MT_RELEASE_GATE_RESULT_BUNDLE`, or enumeration output.

- [x] **Step 4: Add the explicit success finalizer**

At the bottom of the script, after `touch "$DERIVED_DATA"`, call `finalize_owned_artifacts`. It must:

1. revalidate the owned run as a direct real child of the canonical `runs` root;
2. require the current owner marker to be a regular non-symlink file with exact content;
3. refuse if a success marker already exists or is a symlink;
4. write `.release-gate-success` with exact identity content;
5. invoke pruning only when `PRUNE_AFTER_SUCCESS=true`.

Because the script uses `set -e`, no failed external phase can reach this call. A marker write or current-run validation failure keeps the process nonzero and the run unmarked.

- [x] **Step 5: Run GREEN and refactor without broadening behavior**

Run:

```bash
./scripts/sim-lock-tests.sh
bash -n scripts/release-gate.sh scripts/sim-lock-tests.sh
shellcheck scripts/release-gate.sh scripts/sim-lock-tests.sh
```

Expected: all assertions pass; syntax and ShellCheck are clean. Refactor only duplicated fixture setup or validation expressions, rerunning the suite after each change.

- [x] **Step 6: Commit the owned lifecycle**

```bash
git add scripts/release-gate.sh scripts/sim-lock-tests.sh
git diff --cached --check
git commit -S -m "Preserve failed release gate artifacts"
git status --short
git log -1 --show-signature --format=fuller
```

---

## Task 3: Prove and implement the exact pruning predicate

**Files:**

- Modify: `scripts/sim-lock-tests.sh`
- Modify: `scripts/release-gate.sh`

- [x] **Step 1: Add deterministic test-only time**

Add production time selection that accepts `MT_RELEASE_GATE_TEST_NOW` only when `MT_SIM_LOCK_TEST_MODE=1`; otherwise it must use `date +%s` even if the test variable leaks into the environment:

```bash
gate_now_seconds() {
  if [ "${MT_SIM_LOCK_TEST_MODE:-}" = "1" ] && [ -n "${MT_RELEASE_GATE_TEST_NOW:-}" ]; then
    printf '%s\n' "$MT_RELEASE_GATE_TEST_NOW"
  else
    date +%s
  fi
}
```

Reject a non-decimal injected value before any deletion.

- [x] **Step 2: Write the pruning safety matrix and observe RED**

Seed literal direct-child fixtures under the same `runs` root and execute the real successful default `full` gate with `MT_RELEASE_GATE_TEST_NOW=200000`. Use UTC timestamps so one exact marker has epoch `113600` (age `86400`) and another has epoch `113599` (age `86401`). Add distinct sentinels and prove:

- the `86401`-second valid owned success is removed;
- equality at `86400` is retained;
- the current run is retained;
- unmarked failure, owner-only, wrong owner content, wrong success content, wrong UUID, invalid basename, nested valid-looking directory, symlink run, symlink owner marker, and symlink success marker are untouched;
- a sibling beneath another UUID root is untouched;
- a failing default `full` gate deletes none of them.

Run `./scripts/sim-lock-tests.sh` and observe failure because pruning is not yet implemented or lacks at least one predicate.

- [x] **Step 3: Implement candidate validation before exact deletion**

Iterate only shell-expanded direct children of the canonical `runs` directory, converting each expansion into one candidate before evaluation. For every candidate require:

```text
basename regex: ^run-[0-9]{8}T[0-9]{6}Z-[0-9]+$
candidate: directory and not symlink
canonical parent: exactly current canonical runs root
owner marker: regular, not symlink, byte-identical to current owner marker
success marker: regular, not symlink, byte-identical to current owner marker
age: now - success_mtime > 86400
```

Skip the current run explicitly. Negative ages are retained. Only after every check succeeds call `rm -rf -- "$candidate"`. If deletion fails, emit `release-gate: cleanup warning:` with the exact candidate and continue successfully so the marker remains retryable.

- [x] **Step 4: Run GREEN plus mutation checks**

Run:

```bash
./scripts/sim-lock-tests.sh
```

Then make and restore these one-at-a-time local mutations, proving the named test turns red each time:

1. change `-gt` to `-ge` (the equality fixture must fail);
2. remove the success-marker check (the failed/unmarked fixture must fail);
3. remove the canonical-parent check (the boundary fixture must fail);
4. run pruning before the test phase (the failing-full fixture must fail).

After restoration, rerun `bash -n`, ShellCheck, and the entire host suite.

- [x] **Step 5: Commit pruning safety**

```bash
git add scripts/release-gate.sh scripts/sim-lock-tests.sh
git diff --cached --check
git commit -S -m "Prune only old successful gate runs"
git status --short
git log -1 --show-signature --format=fuller
```

---

## Task 4: Lock down caller ownership and CI compatibility

**Files:**

- Modify: `scripts/sim-lock-tests.sh`
- Modify only if RED requires it: `scripts/release-gate.sh`

- [x] **Step 1: Add caller-owned path regressions**

Through the production script prove that local explicit paths are never removed:

1. an existing explicit `MT_RELEASE_GATE_RESULT_BUNDLE` containing a sentinel makes the gate fail before Xcode and retains the sentinel;
2. an explicit `MT_RELEASE_GATE_RUN_DIR` with its default nested result already present is likewise refused and preserved;
3. a fresh explicit result path is accepted, is populated by fake Xcode, and receives no ownership/success marker;
4. an explicit enumeration output path is populated and is never a cleanup candidate.

Observe RED before any necessary production adjustment.

- [x] **Step 2: Add CI lifecycle regression**

Create a fake `xcbeautify` that passes stdin through. Run the real script with `GITHUB_ACTIONS=true`, `MT_RELEASE_GATE_SKIP_LOCK=1`, a valid `MT_RELEASE_GATE_CI_DESTINATION`, and explicit run/result paths. Seed an old sentinel in the result path. Assert CI still replaces that result, completes successfully, and creates no local ownership/success markers.

This test protects the approved non-change: CI owns its explicit upload artifact and retains preflight replacement.

- [x] **Step 3: Reach GREEN and rerun the complete harness**

Run:

```bash
./scripts/sim-lock-tests.sh
bash -n scripts/release-gate.sh scripts/sim-lock-tests.sh
shellcheck scripts/release-gate.sh scripts/sim-lock-tests.sh
```

Expected: all ownership, CI, #612 DerivedData, destination, locking, and concurrency tests pass.

- [x] **Step 4: Commit compatibility coverage**

```bash
git add scripts/release-gate.sh scripts/sim-lock-tests.sh
git diff --cached --check
git commit -S -m "Protect release gate artifact ownership boundaries"
git status --short
git log -1 --show-signature --format=fuller
```

---

## Task 5: Document operations and close the task record

**Files:**

- Modify: `docs/ios-gate-ledger.md:34-40`
- Modify: `docs/superpowers/phases/pre-phase/tasks.md`
- Reference: `docs/superpowers/specs/2026-08-06-success-only-gate-artifact-cleanup-design.md`

- [x] **Step 1: Replace the inherited one-line result claim**

Document the exact local lifecycle:

- successful default artifact-producing runs use unique directories under `/private/tmp/release-gate-<UUID>/runs/`;
- only later successful fully-default `full` gates prune owned successes with marker age strictly greater than `86400` seconds;
- failed and interrupted runs have no success marker and are never gate-deleted;
- local caller-named paths and CI artifacts are outside this cleanup policy;
- operators copy durable evidence to `$HOME/Library/Application Support/making-tracks-gates/evidence/<issue>`;
- macOS `com.apple.tmp_cleaner` may remove `/private/tmp` evidence after access, modification, and change times all exceed roughly three days, so extraction within that window is an operator SLA, not gate behavior;
- the 24-hour success window bounds repeated 168–178 MiB bundles and addresses the incident class in which about 35 GB of DerivedData/result litter exhausted the old host, while acknowledging the second incident without inventing a measurement.

- [x] **Step 2: Update the #546 task line with evidence placeholders only after evidence exists**

Record the signed implementation heads, host-test counts, ShellCheck status, review disposition, Sourcery result, exact host-gate head/counts/duration, PR URL, labels, and merge ownership. Do not write aspirational completion claims.

- [x] **Step 3: Review prose and commit**

```bash
rg -n 'making-tracks-gates/evidence|86400|tmp_cleaner' docs/ios-gate-ledger.md docs/superpowers/specs/2026-08-06-success-only-gate-artifact-cleanup-design.md docs/superpowers/plans/2026-08-06-success-only-gate-artifact-cleanup.md
git diff --check
git diff -- docs/ios-gate-ledger.md docs/superpowers/phases/pre-phase/tasks.md
git add docs/ios-gate-ledger.md docs/superpowers/phases/pre-phase/tasks.md
git commit -S -m "Document release gate artifact retention"
git status --short
git log -1 --show-signature --format=fuller
```

Expected before commit: every durable-evidence reference resolves beneath `Library/Application Support`; operational wording distinguishes gate behavior from OS cleanup.

---

## Task 6: Run complete local verification and independent reviews

**Files:**

- Review: all branch changes against `origin/ios`
- Modify only for verified findings: files already in scope

- [x] **Step 1: Verify the exact branch and diff**

```bash
git fetch origin ios
git merge-base --is-ancestor origin/ios HEAD
git status --short
git diff --check origin/ios...HEAD
git diff --stat origin/ios...HEAD
git log --show-signature --oneline origin/ios..HEAD
```

- [x] **Step 2: Run repeatable host validation**

```bash
./scripts/sim-lock-tests.sh
./scripts/sim-lock-tests.sh
./scripts/sim-lock-tests.sh
bash -n scripts/release-gate.sh scripts/sim-lock-tests.sh
shellcheck scripts/release-gate.sh scripts/sim-lock-tests.sh
```

Record each exact passed/failed count. A sandbox denial of the intentional home-cache fixture is environmental only after the same command succeeds with approved access.

- [x] **Step 3: Request independent adversarial reviews**

Use the project-required independent agents on the complete diff with non-overlapping prompts:

1. deletion-boundary/security review: try to find any path, symlink, marker, race, or age condition that can delete failure/caller/cross-seat data;
2. contract/test review: compare every issue/design requirement with implementation and identify missing observable coverage;
3. provenance/operations review: verify #546/#612 incident claims, CI non-change, durable evidence convention, and task/ledger reporting.

Classify findings as Critical/Important/Minor. Fix all Critical and Important findings with RED tests when behavioral; justify any declined Minor finding concretely. Rerun all host checks after fixes and obtain re-review of changed findings.

- [x] **Step 4: Run Sourcery and address actionable findings**

Run the repository's required Sourcery review on the complete branch diff. Save its output in durable evidence storage if needed, address actionable findings, and rerun host verification. If the service is unavailable, record the exact command/error and planner-approved disposition; do not silently omit the gate.

---

## Task 7: Run the planner-authorized host gate and publish the draft PR

**Files:**

- Modify after evidence: `docs/superpowers/phases/pre-phase/tasks.md`
- External: GitHub issue #546 and the draft PR into `ios`

- [x] **Step 1: Request and wait for the codex3 gate window**

Send the planner the exact signed head, host-test/ShellCheck evidence, review disposition, and command requested:

```bash
./scripts/sim-lock.sh --seat codex3 --status
./scripts/sim-lock.sh --seat codex3 ./scripts/release-gate.sh
```

Do not infer availability from lock files and do not launch until the planner explicitly confirms the #600 cap-3 guard gate has released the shared slot.

- [x] **Step 2: Run the authoritative gate at the exact reviewed head**

After authorization:

```bash
./scripts/sim-lock.sh --seat codex3 --status
./scripts/sim-lock.sh --seat codex3 ./scripts/release-gate.sh
./scripts/sim-lock.sh --seat codex3 --status
```

Record exact Release/app/UI counts, warnings, duration, owned result path, and final two-way `FREE` status. Any failure remains unmarked and is copied to `$HOME/Library/Application Support/making-tracks-gates/evidence/546` within the roughly three-day OS window before manual disposition.

- [ ] **Step 3: Commit truthful closeout evidence**

Update only facts now observed in the #546 task entry, then:

```bash
git add docs/superpowers/phases/pre-phase/tasks.md
git diff --cached --check
git commit -S -m "Record issue 546 gate evidence"
git status --short
git log -1 --show-signature --format=fuller
```

If this evidence-only commit follows the gated implementation head, do not claim the host gate covered the evidence commit's prose; state the exact gated head.

- [ ] **Step 4: Push and open a draft PR into `ios`**

```bash
git push -u origin HEAD
```

Open a draft PR with base `ios`. Its body must use `Closes #546`, summarize success-only ownership and strict 24-hour pruning, list exact host and full-gate evidence, disclose the `/private/tmp` OS-janitor window, and identify planner/fable as merge owner. Apply all required type/scope/status/semver labels and verify them in a separate read-only call.

- [ ] **Step 5: Hand off without merging or removing the worktree**

Send the planner the PR URL, exact head, signed-commit verification, review/Sourcery disposition, gate evidence, labels, and any residual Minor findings. Leave the branch/worktree intact until the planner confirms merge. After merge, verify the merge SHA and issue closure before removing only this task's worktree and local branch.
