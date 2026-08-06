# Release-gate Package.resolved Fixture Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the release-gate Python harness to a clean baseline by making each disposable repository satisfy the production package-resolution invariant without inheriting host signing state.

**Architecture:** Keep `scripts/release-gate.sh` unchanged. The existing `_init_repo` test fixture owns both prerequisites: it disables commit signing in the disposable repository only and writes a structurally valid SwiftPM v3 `ios/Package.resolved` into every committed branch shape. Existing end-to-end harness cases remain the regression oracle because they invoke the production gate and assert its observable behavior.

**Tech Stack:** Python 3.11+, pytest, temporary Git repositories, JSON, the production Bash release gate

## Global Constraints

- Work only in `/Users/rob/git/making-tracks/.worktrees/fix-632-release-gate-package-fixture` on `fix-632-release-gate-package-fixture`, based on fresh `origin/ios` `7a3fa31`.
- Preserve `scripts/release-gate.sh` and its refusal of an absent, non-regular, untracked, or dirty `ios/Package.resolved`.
- Set `commit.gpgsign=false` only in repositories created beneath pytest's `tmp_path`; do not alter user, worktree, or repository Git signing configuration.
- Write a valid SwiftPM v3 document with `version: 3`, `pins: []`, and a fixed 64-character lowercase hexadecimal `originHash`.
- Ensure both the normal `ios` base and deliberately unrelated orphan branch commit the resolution so each test reaches its intended gate invariant.
- Existing behavioral tests are the oracle. Do not assert on production source text or add a test-mode bypass.
- Require the focused file to pass without caller Git overrides and the full pipeline result to be 695 passed plus the existing live-provider skip.
- Publish gate-pending unless historical evidence identifies a standalone test-only release-gate harness change that consumed a simulator gate.

---

### Task 1: Make disposable release-gate repositories hermetic

**Files:**

- Modify: `pipeline/tests/test_release_gate_script.py:27-78`
- Test: `pipeline/tests/test_release_gate_script.py`

**Interfaces:**

- Consumes: `_git(repo: Path, *args: str)`, `_write_project(repo: Path, tests_target: bool)`, and `_init_repo(tmp_path: Path, tests_target: bool, ios_derived: bool) -> Path`.
- Produces: `_write_package_resolution(repo: Path) -> None`; `_init_repo` guarantees unsigned disposable commits and a regular tracked `ios/Package.resolved` matching each temporary branch's `HEAD`.

- [ ] **Step 1: Preserve the first RED caused by inherited signing**

Create the ignored worktree-local `.venv`, install the repository's editable Python packages and pytest, then run one successful-path test with no `GIT_CONFIG_*` environment override:

```bash
.venv/bin/python -m pytest pipeline/tests/test_release_gate_script.py::test_release_gate_runs_release_build_for_testing_and_tests_without_rebuilding -v
```

Expected RED: `_git(repo, "commit", "-q", "-m", "base")` fails because the temporary repository inherits `commit.gpgsign` and cannot reach the 1Password signing agent. This names the first production test-fixture break: removing local signing isolation makes every disposable commit environment-dependent.

- [ ] **Step 2: Add only disposable-repository signing isolation**

Immediately after the fixture configures `user.name`, add:

```python
_git(repo, "config", "commit.gpgsign", "false")
```

Do not set an environment variable and do not change global or worktree config.

- [ ] **Step 3: Re-run and observe the second, deeper RED**

Run the same single test again with no caller overrides.

Expected RED: the base/work commits now succeed, and the production gate refuses with
`ios/Package.resolved must be a regular tracked file matching HEAD`. This names the second fixture break: removing the committed package-resolution input prevents successful-path tests from reaching Xcode behavior.

- [ ] **Step 4: Add the minimal valid resolution writer**

Add this helper beside `_write_project`:

```python
def _write_package_resolution(repo: Path) -> None:
    package_resolution = repo / "ios/Package.resolved"
    package_resolution.parent.mkdir(parents=True, exist_ok=True)
    package_resolution.write_text(
        "{\n"
        '  "originHash" : "0000000000000000000000000000000000000000000000000000000000000000",\n'
        '  "pins" : [\n'
        "  ],\n"
        '  "version" : 3\n'
        "}\n",
        encoding="utf-8",
    )
```

Call `_write_package_resolution(repo)` after `_write_project(repo, tests_target=tests_target)` in the base setup and again after `_write_project(repo, tests_target=tests_target)` in the orphan branch. The existing `git add .` and commits must own the files; do not add a special staging path or gate bypass.

- [ ] **Step 5: Verify focused GREEN without external overrides**

Run:

```bash
.venv/bin/python -m pytest pipeline/tests/test_release_gate_script.py -v
```

Expected: all 26 release-gate Python tests pass. Confirm the environment has no `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_0`, or `GIT_CONFIG_VALUE_0` requirement.

- [ ] **Step 6: Verify full GREEN and static checks**

Run each command separately:

```bash
.venv/bin/python -m pytest pipeline/tests -q
python3 scripts/lint_agent_law.py
git diff --check
```

Expected: 695 passed, 1 skipped; agent-law lint and diff check pass.

- [ ] **Step 7: Commit the single fixture repair**

```bash
git add pipeline/tests/test_release_gate_script.py
git diff --cached --check
git commit -S -m "test: repair release gate package fixture"
```

Verify the signature, branch status, and `origin/ios...HEAD` diff separately.

---

### Task 2: Review and publish the gate-pending repair

**Files:**

- Modify: `docs/superpowers/phases/pre-phase/tasks.md`
- Modify: only `pipeline/tests/test_release_gate_script.py` if an independent review finding survives validation

**Interfaces:**

- Consumes: the signed test-only repair and exact RED/GREEN outputs from Task 1.
- Produces: a scoped independent-review verdict, historical gate-precedent decision, issue update, signed remote head, and draft PR targeting `ios`.

- [ ] **Step 1: Ground simulator-gate precedent**

Inspect history for standalone changes to `pipeline/tests/test_release_gate_script.py` and the PRs named by the planner:

```bash
git log --oneline --decorate -- pipeline/tests/test_release_gate_script.py
git show --stat 6a2a63b
git show --stat 79a8a19
```

If no standalone test-only harness precedent used a simulator gate, record that #632 is published gate-pending per planner ruling `2026-08-06T21-49-50.034Z_pid95527_f8391adb`. Do not allocate or boot a simulator.

- [ ] **Step 2: Run scoped independent review**

Review exact `origin/ios...HEAD` for: preservation of the production guard, correctness of SwiftPM v3 fixture shape, hermetic signing scope, orphan-branch coverage, and test quality. Reject any suggestion to weaken the gate or rely on caller environment. Resolve surviving findings test-first and rerun the focused/full suites.

- [ ] **Step 3: Record the tests-green checkpoint**

Append a ledger transition containing the signed code head, 26/26 focused result, 695 passed plus 1 skipped full result, static checks, review verdict, and gate-pending ruling. Commit the ledger separately and verify its signature.

- [ ] **Step 4: Push and update issue #632**

Push `fix-632-release-gate-package-fixture`, verify the exact remote SHA, and update the issue body with root cause, two-stage RED, focused/full GREEN, review result, scope, and gate-pending disposition.

- [ ] **Step 5: Open and inspect the draft PR**

Open a draft PR from `fix-632-release-gate-package-fixture` to `ios`, link `Fixes #632`, and apply `sourcery-review`, `track-b-ios`, and `wp`. Inspect the rendered body, required labels, target/base, exact head, and Actions state. Report the PR and gate-pending status to the planner; do not merge it.
