# Main Source Guard Repository Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reject pull requests to `main` whose allowed branch name comes from a different repository.

**Architecture:** Keep enforcement in the existing inline GitHub Actions step. Pass repository identities through environment variables, fail explicitly on repository mismatch before evaluating the branch allowlist, and test the real workflow script by extracting and executing its `run` block.

**Tech Stack:** GitHub Actions YAML, Bash, Python 3.11, pytest.

## Global Constraints

- Enforce `github.event.pull_request.head.repo.full_name == github.repository` exactly.
- Treat repository identity as the outer trust boundary and evaluate it before the branch allowlist.
- A repository mismatch must fail the step; it must never skip the job.
- GitHub context values enter shell execution only through `env` bindings.
- Keep the shell inline in the workflow; do not introduce a reusable script or a new dependency.
- The regression executes the production `run` block and covers same-repository, fork, and branch cases.
- This workflow-only change does not use the iOS simulator.

---

### Task 1: Enforce and prove repository identity

**Files:**
- Create: `tests/test_main_source_guard_workflow.py`
- Modify: `.github/workflows/main-source-guard.yml:9-17`

**Interfaces:**
- Consumes: GitHub Actions values `github.head_ref`, `github.event.pull_request.head.repo.full_name`, and `github.repository`.
- Produces: an inline Bash step that exits `0` only for same-repository `develop` or `ios` promotions; all other inputs exit non-zero.

- [ ] **Step 1: Write the failing production-workflow regression**

Create `tests/test_main_source_guard_workflow.py` with the following content. The production change that makes the test fail is removing or bypassing the repository comparison: fork cases named `develop` or `ios` then exit `0`.

```python
from __future__ import annotations

import os
from pathlib import Path
import subprocess

import pytest


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_PATH = REPOSITORY_ROOT / ".github/workflows/main-source-guard.yml"


def _guard_step() -> tuple[dict[str, str], str]:
    lines = WORKFLOW_PATH.read_text(encoding="utf-8").splitlines()
    run_index = next(index for index, line in enumerate(lines) if line.strip() == "run: |")
    run_indent = len(lines[run_index]) - len(lines[run_index].lstrip())

    env_index = next(
        index
        for index in range(run_index - 1, -1, -1)
        if lines[index].strip() == "env:"
        and len(lines[index]) - len(lines[index].lstrip()) == run_indent
    )
    env: dict[str, str] = {}
    for line in lines[env_index + 1 : run_index]:
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        if indent <= run_indent:
            break
        key, value = line.strip().split(":", 1)
        env[key] = value.strip()

    script_lines: list[str] = []
    content_indent: int | None = None
    for line in lines[run_index + 1 :]:
        if line.strip():
            indent = len(line) - len(line.lstrip())
            if indent <= run_indent:
                break
            if content_indent is None:
                content_indent = indent
        script_lines.append("" if content_indent is None else line[content_indent:])

    return env, "\n".join(script_lines) + "\n"


def test_guard_binds_repository_contexts_through_environment() -> None:
    env, _ = _guard_step()

    assert env["HEAD_REPOSITORY"] == "${{ github.event.pull_request.head.repo.full_name }}"
    assert env["BASE_REPOSITORY"] == "${{ github.repository }}"


@pytest.mark.parametrize(
    ("head_ref", "head_repository", "expected_status", "expected_output", "rejected_output"),
    [
        ("develop", "mnbf9rca/making-tracks", 0, "OK: promotion from develop", None),
        ("ios", "mnbf9rca/making-tracks", 0, "OK: promotion from ios", None),
        (
            "develop",
            "attacker/making-tracks",
            1,
            "BLOCKED: promotion source repository",
            "main only accepts promotions from develop or ios",
        ),
        (
            "ios",
            "attacker/making-tracks",
            1,
            "BLOCKED: promotion source repository",
            "main only accepts promotions from develop or ios",
        ),
        (
            "feature",
            "mnbf9rca/making-tracks",
            1,
            "main only accepts promotions from develop or ios",
            None,
        ),
    ],
)
def test_guard_enforces_repository_before_branch(
    head_ref: str,
    head_repository: str,
    expected_status: int,
    expected_output: str,
    rejected_output: str | None,
) -> None:
    _, script = _guard_step()
    env = os.environ.copy()
    env.update(
        HEAD_REF=head_ref,
        HEAD_REPOSITORY=head_repository,
        BASE_REPOSITORY="mnbf9rca/making-tracks",
    )

    result = subprocess.run(
        ["bash"],
        input=script,
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )

    assert result.returncode == expected_status
    assert expected_output in result.stdout
    if rejected_output is not None:
        assert rejected_output not in result.stdout
```

- [ ] **Step 2: Run the regression and verify RED**

Run:

```bash
/Users/rob/git/making-tracks/.venv/bin/pytest tests/test_main_source_guard_workflow.py -v
```

Expected: FAIL. The binding test raises `KeyError: 'HEAD_REPOSITORY'`, and both fork cases return `0` because the current production script ignores repository identity. Same-repository allowed branches and the disallowed `feature` branch retain their current outcomes.

- [ ] **Step 3: Add the minimal repository guard**

Change the existing workflow step to:

```yaml
      - name: Verify head source
        env:
          HEAD_REF: ${{ github.head_ref }}
          HEAD_REPOSITORY: ${{ github.event.pull_request.head.repo.full_name }}
          BASE_REPOSITORY: ${{ github.repository }}
        run: |
          if [ "$HEAD_REPOSITORY" != "$BASE_REPOSITORY" ]; then
            echo "BLOCKED: promotion source repository must match $BASE_REPOSITORY (got: $HEAD_REPOSITORY)"
            exit 1
          fi
          case "$HEAD_REF" in
            develop|ios) echo "OK: promotion from $HEAD_REF" ;;
            *) echo "BLOCKED: main only accepts promotions from develop or ios (got: $HEAD_REF)"; exit 1 ;;
          esac
```

- [ ] **Step 4: Run the focused regression and verify GREEN**

Run:

```bash
/Users/rob/git/making-tracks/.venv/bin/pytest tests/test_main_source_guard_workflow.py -v
```

Expected: `8 passed`; the two allowed same-repository cases pass, all three fork cases fail for repository identity before branch evaluation, the disallowed same-repository branch fails the branch allowlist, and the context-binding and non-skippable-enforcement tests pass.

- [ ] **Step 5: Prove teeth by neutering only the repository comparison**

Temporarily change `if [ "$HEAD_REPOSITORY" != "$BASE_REPOSITORY" ]; then` to `if false; then`, rerun the focused regression, and verify `3 failed, 5 passed`: the two allowed-name fork scripts unexpectedly exit successfully with status `0`, while the disallowed fork exits `1` for the wrong branch-first reason and never emits the required repository diagnostic. Restore the exact guarded workflow and rerun the focused regression to `8 passed`.

- [ ] **Step 6: Run host verification**

Run:

```bash
/Users/rob/git/making-tracks/.venv/bin/pytest contracts/tests -q --ignore=contracts/tests/test_validation.py
git diff --check
git status --short
```

Expected: the complete contract suite remains `173 passed` when `hatchling` is supplied through an isolated test target; the focused workflow suite remains `8 passed`; `git diff --check` is silent. Do not modify the shared runner environment to supply the missing build backend.

- [ ] **Step 7: Commit the implementation**

```bash
git add tests/test_main_source_guard_workflow.py .github/workflows/main-source-guard.yml
git commit -S -m "Guard main promotions by repository"
```

Verify the signed commit and clean worktree with:

```bash
git log -1 --show-signature --format=fuller --stat
git status --short --branch
```
