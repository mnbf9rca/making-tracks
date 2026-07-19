#!/usr/bin/env python3
"""Tripwire against dated narrative in rule text.

`AGENTS.md` states rules timelessly. Incident rationale lives in
`docs/process/incidents.md`, which is exempt because history is safe to date.

Rules that carry their own anecdote rot: the fact stops being true, and the
stale fact reads as permission to skip the rule. Two gates were disabled that
way. See docs/process/incidents.md -> "Stale law disabled two gates".

WHAT THIS IS NOT
----------------
This does not prove rule text is timeless. "Narrative versus rule" is a
semantic distinction and no regex decides it. An undated, time-word-free
anecdote ("three worktrees popped an editor window, so never run interactive
git") passes clean.

This catches the known regression forms: dates, the common narrative openers,
and line-number cross-references. The structural work is done by
docs/process/incidents.md existing as the place narrative belongs, and by
AGENTS.md's "Amending this file" section stating the constraint where an
editor sees it first. Treat a green run as "no known bad shape", not "correct".

Run: python3 scripts/lint_agent_law.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Rule text that must stay timeless. AGENTS.md must exist; the rest are linted
# only where present, so the check survives on branches carrying a subset of
# docs (the `ios` branch has AGENTS.md but not docs/).
REQUIRED = ("AGENTS.md",)
OPTIONAL = ("docs/INFRA.md", "docs/process/gate-lessons.md")

# NOT linted, deliberately:
#   docs/PRINCIPLES.md   - its dates are amendment provenance, which is the
#                          traceability that doc exists to carry. Only Rob
#                          amends it.
#   docs/SECRETS.md      - dates research provenance against upstream docs.
#   docs/threat-model.md - same.
#   docs/process/incidents.md - dated by design.

FENCE = re.compile(r"^\s*(```|~~~)")

# Inline code, markdown link targets and bare URLs carry dated filenames
# legitimately.
STRIP_COMMON = re.compile(r"`[^`]*`|\]\([^)]*\)|https?://\S+")
# Bare paths (docs/superpowers/specs/2026-07-14-x.md) are dated by filename,
# not by narrative. Stripped for the date check only - line-number citations
# like `foo.md:42` must still be caught.
STRIP_PATHS = re.compile(r"\b[\w./-]+\.(?:md|swift|py|ya?ml|json|txt|log|tpl)\b")

MONTHS = (
    r"jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|"
    r"jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"
)

DATE_PATTERNS = (
    re.compile(r"\b20\d{2}-\d{2}-\d{2}\b"),                    # 2026-07-18
    re.compile(r"\b20\d{2}/\d{1,2}/\d{1,2}\b"),                # 2026/07/18
    re.compile(r"\b\d{1,2}/\d{1,2}/(?:20)?\d{2}\b"),           # 18/07/2026, 07/18/26
    re.compile(rf"\b\d{{1,2}}\s+(?:{MONTHS})\b", re.I),        # 18 July
    re.compile(rf"\b(?:{MONTHS})\s+\d{{1,2}}\b", re.I),        # July 18
    re.compile(rf"\b(?:{MONTHS})\s+20\d{{2}}\b", re.I),        # July 2026
    re.compile(r"\b20\d{2}-\d{2}\b"),                          # 2026-07
    re.compile(r"\b20\d{6}\b"),                                # 20260718
)

# Narrative openers. Deliberately excludes "today", "currently" and "still":
# they appear in legitimate rule text ("mark what exists today against the
# tree"), and false positives here would train authors to route around the
# check.
TIME_WORDS = re.compile(
    r"\b(?:as[- ]of|this (?:morning|afternoon|evening)|last night|tonight|"
    r"yesterday|earlier today|last week|the other day|at the time of writing|"
    r"until recently|recently|just now|right now|at present|these days|"
    r"for now|temporarily)\b",
    re.IGNORECASE,
)

LINE_REFS = (
    re.compile(r"\bline[- ]\d+\b", re.IGNORECASE),
    re.compile(r"\blines\s+\d+\s*[-–]\s*\d+\b", re.IGNORECASE),
    re.compile(r"\bL\d+\b"),
    re.compile(r"\b[\w./-]+\.(?:md|swift|py|ya?ml|json):\d+"),
)

GUIDANCE = (
    "Move the incident to docs/process/incidents.md and cite it by name. "
    "State the rule timelessly. Cite sections, never line numbers."
)


def lint(path: Path) -> list[str]:
    failures: list[str] = []
    in_fence = False
    rel = path.relative_to(REPO_ROOT)

    lines = path.read_text(encoding="utf-8").splitlines()
    for lineno, raw in enumerate(lines, 1):
        if FENCE.match(raw):
            in_fence = not in_fence
            continue
        if in_fence:
            continue

        common = STRIP_COMMON.sub("", raw)
        for_dates = STRIP_PATHS.sub("", common)

        for pattern in DATE_PATTERNS:
            if m := pattern.search(for_dates):
                failures.append(f"{rel}:{lineno}: a date in rule text -- {m.group(0)!r}")
                break

        if m := TIME_WORDS.search(for_dates):
            failures.append(
                f"{rel}:{lineno}: dated narrative in rule text -- {m.group(0)!r}"
            )

        for pattern in LINE_REFS:
            if m := pattern.search(common):
                failures.append(
                    f"{rel}:{lineno}: a line-number cross-reference "
                    f"(cite the section name instead) -- {m.group(0)!r}"
                )
                break

    # An unclosed fence would silently disable every check below it.
    if in_fence:
        failures.append(f"{rel}: unbalanced code fence -- checks below it were skipped")

    return failures


def main() -> int:
    failures: list[str] = []
    checked = 0

    for name in REQUIRED:
        path = REPO_ROOT / name
        if not path.exists():
            print(f"lint-agent-law: missing required file {name}", file=sys.stderr)
            return 1
        failures.extend(lint(path))
        checked += 1

    for name in OPTIONAL:
        path = REPO_ROOT / name
        if path.exists():
            failures.extend(lint(path))
            checked += 1

    if failures:
        print("lint-agent-law: rule text must be timeless\n", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        print(f"\n{GUIDANCE}", file=sys.stderr)
        return 1

    print(f"lint-agent-law: OK ({checked} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
