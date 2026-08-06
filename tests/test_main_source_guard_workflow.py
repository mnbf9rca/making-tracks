from __future__ import annotations

import os
from pathlib import Path
import subprocess

import pytest


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_PATH = REPOSITORY_ROOT / ".github/workflows/main-source-guard.yml"


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip())


def _mapping_entry(line: str) -> tuple[str, str] | None:
    token = line.strip()
    if token.startswith("- "):
        token = token[2:].lstrip()
    key, separator, value = token.partition(":")
    if not separator:
        return None
    return key.strip().strip("'\""), value.strip()


def _guard_structure(lines: list[str]) -> tuple[int, int, int, int]:
    job_index = next(
        index for index, line in enumerate(lines) if line.strip() == "source-branch-check:"
    )
    job_indent = _indent(lines[job_index])
    job_end = next(
        (
            index
            for index in range(job_index + 1, len(lines))
            if lines[index].strip() and _indent(lines[index]) <= job_indent
        ),
        len(lines),
    )
    name_index = next(
        index
        for index in range(job_index + 1, job_end)
        if _mapping_entry(lines[index]) == ("name", "Verify head source")
    )
    step_indent = job_indent + 4
    step_index = next(
        index
        for index in range(name_index, job_index, -1)
        if _indent(lines[index]) == step_indent and lines[index].lstrip().startswith("- ")
    )
    step_end = next(
        (
            index
            for index in range(step_index + 1, job_end)
            if lines[index].strip()
            and _indent(lines[index]) == step_indent
            and lines[index].lstrip().startswith("- ")
        ),
        job_end,
    )
    return job_index, job_end, step_index, step_end


def _guard_step() -> tuple[dict[str, str], str]:
    lines = WORKFLOW_PATH.read_text(encoding="utf-8").splitlines()
    _, _, step_index, step_end = _guard_structure(lines)
    run_index = next(
        index
        for index in range(step_index, step_end)
        if _mapping_entry(lines[index]) == ("run", "|")
    )
    run_indent = _indent(lines[run_index])

    env_index = next(
        index
        for index in range(run_index - 1, step_index - 1, -1)
        if _mapping_entry(lines[index]) == ("env", "")
        and _indent(lines[index]) == run_indent
    )
    env: dict[str, str] = {}
    for line in lines[env_index + 1 : run_index]:
        if not line.strip():
            continue
        indent = _indent(line)
        if indent <= run_indent:
            break
        key, value = line.strip().split(":", 1)
        env[key] = value.strip()

    script_lines: list[str] = []
    content_indent: int | None = None
    for line in lines[run_index + 1 :]:
        if line.strip():
            indent = _indent(line)
            if indent <= run_indent:
                break
            if content_indent is None:
                content_indent = indent
        script_lines.append("" if content_indent is None else line[content_indent:])

    return env, "\n".join(script_lines) + "\n"


def _guard_job_conditions() -> list[str]:
    lines = WORKFLOW_PATH.read_text(encoding="utf-8").splitlines()
    job_index, job_end, step_index, step_end = _guard_structure(lines)
    job_indent = _indent(lines[job_index])
    step_indent = _indent(lines[step_index])
    conditions: list[str] = []
    for index in range(job_index + 1, job_end):
        entry = _mapping_entry(lines[index])
        if _indent(lines[index]) == job_indent + 2 and entry is not None and entry[0] == "if":
            conditions.append(lines[index].strip())
    for index in range(step_index, step_end):
        entry = _mapping_entry(lines[index])
        if (
            (index == step_index or _indent(lines[index]) == step_indent + 2)
            and entry is not None
            and entry[0] == "if"
        ):
            conditions.append(lines[index].strip())
    return conditions


def test_guard_binds_repository_contexts_through_environment() -> None:
    env, script = _guard_step()

    assert env["HEAD_REF"] == "${{ github.head_ref }}"
    assert env["HEAD_REPOSITORY"] == "${{ github.event.pull_request.head.repo.full_name }}"
    assert env["BASE_REPOSITORY"] == "${{ github.repository }}"
    assert "${{" not in script


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
