# Simulator Seat CLI Implementation Plan

> **For implementation:** Follow the test-driven sequence below. Do not merge or reload agent harnesses;
> those operations remain planner-controlled.

**Goal:** Replace volatile public simulator-destination environment assignments with a stable logical
`--seat codexN` interface that command policy can recognize safely.

**Architecture:** `sim-lock.sh` parses the selected seat from the canonical Host Gate Seats table, derives
its existing per-simulator lock from that destination, injects the destination into xcodebuild, and passes
it privately to the release gate. The public environment fallback is removed. Project rules match only
the bounded seat set and bounded command families. GitHub Actions uses a separate destination variable
that the release gate reads only with its existing Actions-only skip-lock authority.

**Technology:** Bash, Markdown ledger, Codex exec-policy rules, pytest release-gate contract tests.

---

### Task 1: Specify the new wrapper contract in behavioral tests

**Files:**

- Modify: `scripts/sim-lock-tests.sh`

**Step 1: Add a canonical test ledger fixture**

Create a temporary Host Gate Seats table with `codex1` mapped to each test UDID. Point the script at this
fixture only when `MT_SIM_LOCK_TEST_MODE=1`, so production always reads `docs/ios-gate-ledger.md`.

**Step 2: Convert invocation helpers to the public seat interface**

Change status, lock, erase, and release-gate helpers to invoke:

```bash
./scripts/sim-lock.sh --seat codex1 <operation>
```

Remove `MT_RELEASE_GATE_DESTINATION` from those helpers.

**Step 3: Add focused contract cases**

Cover:

- missing `--seat` is rejected;
- an unknown seat is rejected;
- a missing, duplicate, or malformed ledger row fails closed;
- setting only `MT_RELEASE_GATE_DESTINATION` does not enable the legacy invocation;
- xcodebuild receives the selected destination when none was supplied;
- a caller-supplied matching xcodebuild destination is accepted;
- a mismatched xcodebuild destination is rejected.
- a fleet-wide selector is rejected as a seat identity;
- target-taking simctl verbs receive the selected UUID and reject an explicit positional target.

**Step 4: Run the harness and observe failure**

Run:

```bash
./scripts/sim-lock-tests.sh
```

Expected: failures because `sim-lock.sh` does not yet accept `--seat` or read the ledger.

### Task 2: Specify the private release-gate boundary

**Files:**

- Modify: `pipeline/tests/test_release_gate_script.py`

**Step 1: Replace the public destination variable in valid wrapper fixtures**

Use `MT_SIM_LOCK_DESTINATION` together with the existing lock marker and UDID.

**Step 2: Add rejection coverage**

Assert that `MT_RELEASE_GATE_DESTINATION` alone is ignored and that the release gate reports a missing
wrapper-owned destination. Assert that `MT_RELEASE_GATE_CI_DESTINATION` is accepted only when
`GITHUB_ACTIONS=true` and `MT_RELEASE_GATE_SKIP_LOCK=1`.

**Step 3: Run the focused tests and observe failure**

Run:

```bash
pipx run uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_release_gate_script.py -q
```

Expected: failures because `release-gate.sh` still reads the removed public variable.

### Task 3: Implement strict seat resolution in sim-lock

**Files:**

- Modify: `scripts/sim-lock.sh`

**Step 1: Parse the fixed public prefix**

Require `--seat <seat>` before either a wrapped command or a wrapper operation. Accept only `codex1`
through `codex4` in production.

**Step 2: Resolve the canonical ledger row**

Read `docs/ios-gate-ledger.md`, require exactly one row for the seat, extract the destination, and pass it
through the existing destination/UDID validation. In test mode only, permit an explicit fixture ledger
path.

**Step 3: Inject and validate xcodebuild destination**

If no `-destination` argument exists, append the resolved destination. If one exists, retain the exact
match check before acquiring and executing under the lock.

**Step 4: Propagate the private lock context**

Set `MT_SIM_LOCK_DESTINATION` alongside `MT_SIM_LOCK` and `MT_SIM_LOCK_UDID` for descendants. Do not read
`MT_RELEASE_GATE_DESTINATION`.

For bounded target-taking simctl verbs, insert the selected UUID after the verb and reject explicit UUID,
`booted`, or `all` selectors. Leave targetless `simctl list` unchanged.

**Step 5: Update usage and diagnostics**

Show `--seat <codex1|codex2|codex3|codex4>` in every invocation and report actionable errors for ledger
cardinality and destination format failures.

**Step 6: Run the Bash harness**

Run:

```bash
./scripts/sim-lock-tests.sh
```

Expected: all cases pass.

### Task 4: Move release-gate to the private destination

**Files:**

- Modify: `scripts/release-gate.sh`
- Modify: `.github/workflows/ios-gate.yml`
- Modify live simulator consumers added by the current `ios` base if they still read the removed variable.

**Step 1: Read only wrapper-owned destination state**

Replace `MT_RELEASE_GATE_DESTINATION` with `MT_SIM_LOCK_DESTINATION`. Keep the existing destination and
lock-UDID consistency checks.

For the existing Actions-only skip-lock path, read `MT_RELEASE_GATE_CI_DESTINATION` instead. Do not accept
that variable for local execution.

**Step 2: Update error messages**

Direct callers should be told to invoke the gate through `sim-lock.sh --seat <seat>`.

**Step 3: Migrate the workflow atomically**

Replace every GitHub Actions export of `MT_RELEASE_GATE_DESTINATION` with
`MT_RELEASE_GATE_CI_DESTINATION`.

**Step 4: Run focused release-gate tests**

Run:

```bash
pipx run uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_release_gate_script.py -q
```

Expected: all cases pass.

### Task 5: Update project policy and operational documentation

**Files:**

- Modify: `.codex/rules/default.rules`
- Modify: `AGENTS.md`
- Modify: `docs/ios-gate-ledger.md`

**Step 1: Insert the bounded seat token in policy prefixes**

Place the literal `--seat` and a union of `codex1` through `codex4` between `sim-lock.sh` and each bounded
command family.

**Step 2: Update the iOS branch law**

Replace the exported destination instruction and examples with the assigned logical seat interface.

**Step 3: Preserve the ledger as the only registry**

Rename the table's public-contract column to `Destination`. Explain that planner-owned simulator
replacement updates that row and that callers never copy the value into commands.

**Step 4: Check policy behavior**

Run `codex execpolicy check` for representative accepted forms and verify that missing/unknown-seat forms
do not match the allow rules.

### Task 6: Verify and publish for review

**Files:**

- Verify all modified files.

**Step 1: Run syntax and focused test gates**

Run:

```bash
bash -n scripts/sim-lock.sh scripts/sim-lock-tests.sh scripts/release-gate.sh
./scripts/sim-lock-tests.sh
pipx run uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_release_gate_script.py -q
```

**Step 2: Inspect the complete diff and worktree status**

Confirm there are no unrelated changes or generated artifacts.

**Step 3: Commit and push the implementation branch**

Create a signed commit and push `wp-sim-lock-seat-cli`.

**Step 4: Open an `ios`-targeted PR**

Describe the strict cutover, evidence, and planner-controlled rollout boundary. Route the PR to the
designated reviewer immediately.

**Step 5: Notify the planner and stop before rollout**

Send the PR and review status through AMQ. Do not merge, pull into active harnesses, or reload agents until
the planner calls the cleared window.
