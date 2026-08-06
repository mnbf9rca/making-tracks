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


def _guard_job_conditions() -> list[str]:
    lines = WORKFLOW_PATH.read_text(encoding="utf-8").splitlines()
    job_index = next(
        index for index, line in enumerate(lines) if line.strip() == "source-branch-check:"
    )
    job_indent = len(lines[job_index]) - len(lines[job_index].lstrip())
    condition_indents = {job_indent + 2, job_indent + 6}
    conditions: list[str] = []
    for line in lines[job_index + 1 :]:
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        if indent <= job_indent:
            break
        if indent in condition_indents and line.strip().startswith("if:"):
            conditions.append(line.strip())
    return conditions


def test_guard_binds_repository_contexts_through_environment() -> None:
    env, _ = _guard_step()

    assert env["HEAD_REPOSITORY"] == "${{ github.event.pull_request.head.repo.full_name }}"
    assert env["BASE_REPOSITORY"] == "${{ github.repository }}"


def test_guard_job_and_step_cannot_skip_enforcement() -> None:
    assert _guard_job_conditions() == []


@pytest.mark.parametrize(
    (
        "head_ref",
        "head_repository",
        "expected_status",
        "expected_output",
        "rejected_outputs",
    ),
    [
        ("develop", "mnbf9rca/making-tracks", 0, "OK: promotion from develop", ()),
        ("ios", "mnbf9rca/making-tracks", 0, "OK: promotion from ios", ()),
        (
            "develop",
            "attacker/making-tracks",
            1,
            "BLOCKED: promotion source repository",
            ("OK: promotion from", "main only accepts promotions from develop or ios"),
        ),
        (
            "ios",
            "attacker/making-tracks",
            1,
            "BLOCKED: promotion source repository",
            ("OK: promotion from", "main only accepts promotions from develop or ios"),
        ),
        (
            "feature",
            "mnbf9rca/making-tracks",
            1,
            "main only accepts promotions from develop or ios",
            (),
        ),
    ],
)
def test_guard_enforces_repository_before_branch(
    head_ref: str,
    head_repository: str,
    expected_status: int,
    expected_output: str,
    rejected_outputs: tuple[str, ...],
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
    for rejected_output in rejected_outputs:
        assert rejected_output not in result.stdout
