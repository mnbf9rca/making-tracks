#!/usr/bin/env python3
"""Keep dated narrative out of rule text.

`AGENTS.md` states rules timelessly. Incident rationale lives in
`docs/process/incidents.md`, which is exempt because history is safe to date.

Rules that carry their own anecdote rot: the fact stops being true, and the
stale fact reads as permission to skip the rule. Two gates were disabled that
way. See docs/process/incidents.md -> "Stale law disabled two gates".

Run: python scripts/lint_agent_law.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Files whose rule text must stay timeless.
#
# docs/PRINCIPLES.md is deliberately NOT linted: its dates are amendment
# provenance ("v2 amendment, <date> — see ..."), which is exactly the
# traceability that doc is supposed to carry. Only Rob amends it.
LINTED = ("AGENTS.md", "docs/INFRA.md")

FENCE = re.compile(r"^\s*```")
# Inline code, link targets, and bare URLs carry dated filenames legitimately.
STRIP = re.compile(r"`[^`]*`|\]\([^)]*\)|https?://\S+")

BANNED = (
    (re.compile(r"\b20\d{2}-\d{2}-\d{2}\b"), "a date in rule text"),
    (
        re.compile(
            r"\b(this morning|this afternoon|last night|tonight|yesterday|"
            r"earlier today|as of\b)",
            re.IGNORECASE,
        ),
        "dated narrative in rule text",
    ),
    (
        re.compile(r"\bline[- ]\d+\b", re.IGNORECASE),
        "a line-number cross-reference (cite the section name instead)",
    ),
)

GUIDANCE = (
    "Move the incident to docs/process/incidents.md and cite it by name. "
    "State the rule timelessly."
)


def lint(path: Path) -> list[str]:
    failures: list[str] = []
    in_fence = False

    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if FENCE.match(raw):
            in_fence = not in_fence
            continue
        if in_fence:
            continue

        line = STRIP.sub("", raw)
        for pattern, why in BANNED:
            match = pattern.search(line)
            if match:
                rel = path.relative_to(REPO_ROOT)
                failures.append(f"{rel}:{lineno}: {why} -- {match.group(0)!r}")

    return failures


def main() -> int:
    failures: list[str] = []
    for name in LINTED:
        path = REPO_ROOT / name
        if not path.exists():
            print(f"lint-agent-law: missing linted file {name}", file=sys.stderr)
            return 1
        failures.extend(lint(path))

    if failures:
        print("lint-agent-law: rule text must be timeless\n", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        print(f"\n{GUIDANCE}", file=sys.stderr)
        return 1

    print(f"lint-agent-law: OK ({len(LINTED)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
