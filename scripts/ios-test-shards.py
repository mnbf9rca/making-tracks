#!/usr/bin/env python3
"""Utilities for sharded iOS UI test execution in CI."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable


TEST_FUNCTION_RE = re.compile(r"\bfunc\s+(test[A-Za-z0-9_]+)\s*\(")
# Ruled in #417: widening this five-physical-line horizon requires a new ruling.
AX_WAIT_LOOKAHEAD_PHYSICAL_LINES = 5
AX_ELEMENT_PATTERN = r"buttons|staticTexts|switches"
AX_SELECTOR_PATTERN = r'"(?:[^"\\]|\\.)*"|[A-Za-z_][A-Za-z0-9_]*'
AX_ELEMENT_QUERY_RE = re.compile(
    rf'\.(?P<element>{AX_ELEMENT_PATTERN})\[(?P<selector>{AX_SELECTOR_PATTERN})\]'
)
AX_EXISTENCE_WAIT_RE = re.compile(
    rf'\bXCTAssertTrue\s*\(.*?\.(?P<element>{AX_ELEMENT_PATTERN})'
    rf'\[(?P<selector>{AX_SELECTOR_PATTERN})\]\.waitForExistence\s*\(\s*timeout\s*:',
    re.DOTALL,
)
AX_PROPERTY_ASSERT_RE = re.compile(
    rf'\bXCTAssertEqual\s*\(.*?\.(?P<element>{AX_ELEMENT_PATTERN})'
    rf'\[(?P<selector>{AX_SELECTOR_PATTERN})\]\.(?P<property>label|value)\b',
    re.DOTALL,
)
AX_PROPERTY_ASSERT_START_RE = re.compile(r"\bXCTAssertEqual\s*\(")


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def emit_error(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


def source_test_names(source: Path) -> set[str]:
    return set(TEST_FUNCTION_RE.findall(source.read_text(encoding="utf-8")))


def ui_test_identifier(manifest: dict[str, Any], test_name: str) -> str:
    return f"{manifest['uiTarget']}/{manifest['uiClass']}/{test_name}"


def shard_entries(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    return list(manifest.get("shards", []))


def shard_tests(manifest: dict[str, Any]) -> list[str]:
    tests: list[str] = []
    for shard in shard_entries(manifest):
        tests.extend(shard.get("tests", []))
    return tests


def duplicate_names(values: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    duplicates: set[str] = set()
    for value in values:
        if value in seen:
            duplicates.add(value)
        seen.add(value)
    return sorted(duplicates)


def command_validate_static(args: argparse.Namespace) -> int:
    manifest = load_json(args.manifest)
    expected = source_test_names(args.source)
    assigned_list = shard_tests(manifest)
    assigned = set(assigned_list)

    duplicates = duplicate_names(assigned_list)
    if duplicates:
        return emit_error("duplicate shard manifest tests:\n" + "\n".join(duplicates))

    missing = sorted(expected - assigned)
    extra = sorted(assigned - expected)
    if missing or extra:
        lines: list[str] = []
        if missing:
            lines.append("missing from shard manifest:")
            lines.extend(missing)
        if extra:
            lines.append("not present in source:")
            lines.extend(extra)
        return emit_error("\n".join(lines))

    print(f"static shard manifest covers {len(expected)} UI tests")
    return 0


def strip_swift_line_comment(line: str) -> str:
    in_string = False
    escaped = False
    for char_index, char in enumerate(line):
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "/" and char_index + 1 < len(line) and line[char_index + 1] == "/":
            return line[:char_index]
    return line


def is_blank_or_full_line_comment(line: str) -> bool:
    return not strip_swift_line_comment(line).strip()


def swift_call_statement(lines: list[str], start_index: int) -> tuple[str, int]:
    """Return the balanced call beginning on start_index and its final line index."""
    statement_lines: list[str] = []
    depth = 0
    saw_open = False
    in_string = False
    escaped = False

    for end_index in range(start_index, len(lines)):
        line = strip_swift_line_comment(lines[end_index])
        statement_lines.append(line)
        for char in line:
            if in_string:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    in_string = False
                continue
            if char == '"':
                in_string = True
            elif char == "(":
                saw_open = True
                depth += 1
            elif char == ")" and saw_open:
                depth -= 1
                if depth == 0:
                    return "\n".join(statement_lines), end_index

    return "\n".join(statement_lines), len(lines) - 1


def accessibility_wait_scan(source: Path) -> tuple[int, list[tuple[int, str, str]]]:
    lines = source.read_text(encoding="utf-8").splitlines()
    query_count = sum(
        len(AX_ELEMENT_QUERY_RE.findall(strip_swift_line_comment(line)))
        for line in lines
        if not is_blank_or_full_line_comment(line)
    )
    findings: list[tuple[int, str, str]] = []

    # This wait-anchored lexical check deliberately does not follow local aliases, no-wait
    # property reads, or read-only continuation. Issue #631 owns those wider classes.
    for index, line in enumerate(lines):
        if is_blank_or_full_line_comment(line) or "XCTAssertTrue" not in line:
            continue
        wait_statement, wait_end_index = swift_call_statement(lines, index)
        wait_match = AX_EXISTENCE_WAIT_RE.search(wait_statement)
        if wait_match is None:
            continue

        candidate_indexes = range(
            wait_end_index + 1,
            min(len(lines), wait_end_index + 1 + AX_WAIT_LOOKAHEAD_PHYSICAL_LINES),
        )
        for candidate_index in candidate_indexes:
            candidate = lines[candidate_index]
            if is_blank_or_full_line_comment(candidate):
                continue

            assert_statement = candidate
            if AX_PROPERTY_ASSERT_START_RE.search(candidate):
                assert_statement, _ = swift_call_statement(lines, candidate_index)
            assert_match = AX_PROPERTY_ASSERT_RE.search(assert_statement)
            if (
                assert_match is not None
                and assert_match.group("element") == wait_match.group("element")
                and assert_match.group("selector") == wait_match.group("selector")
            ):
                selector = wait_match.group("selector").strip('"')
                findings.append((index + 1, selector, assert_match.group("property")))
            break

    return query_count, findings


def command_validate_ax_waits(args: argparse.Namespace) -> int:
    query_count, findings = accessibility_wait_scan(args.source)
    if query_count == 0:
        return emit_error("accessibility wait guard matched no supported accessibility queries")
    if findings:
        lines = ["decoy accessibility waits:"]
        lines.extend(
            f"{args.source}:{line_number}: {identifier} .{property_name}"
            for line_number, identifier, property_name in findings
        )
        return emit_error("\n".join(lines))

    print(f"accessibility wait guard found no decoys across {query_count} supported queries")
    return 0


def command_write_only_testing(args: argparse.Namespace) -> int:
    manifest = load_json(args.manifest)
    output_lines: list[str] | None = None

    for shard in shard_entries(manifest):
        if shard.get("id") == args.shard:
            output_lines = [ui_test_identifier(manifest, name) for name in shard.get("tests", [])]
            break

    unit_shard = manifest.get("unitShard", {})
    if output_lines is None and unit_shard.get("id") == args.shard:
        output_lines = list(unit_shard.get("onlyTesting", []))

    if output_lines is None:
        return emit_error(f"unknown shard id: {args.shard}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(output_lines) + "\n", encoding="utf-8")
    print(f"wrote {len(output_lines)} only-testing entries for {args.shard}")
    return 0


def iter_strings(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from iter_strings(item)
    elif isinstance(value, dict):
        for item in value.values():
            yield from iter_strings(item)


def normalize_test_identifier(value: str, target_prefix: str) -> str | None:
    if value.startswith(target_prefix):
        identifier = value
    else:
        target_index = value.find(f"/{target_prefix}")
        if target_index == -1:
            return None
        identifier = value[target_index + 1 :]

    if "/test" not in identifier:
        return None
    if identifier.endswith("()"):
        identifier = identifier[:-2]
    return identifier


def extract_test_identifiers(payload: Any, target_prefix: str) -> set[str]:
    identifiers: set[str] = set()
    for value in iter_strings(payload):
        identifier = normalize_test_identifier(value, target_prefix)
        if identifier is not None:
            identifiers.add(identifier)
    return identifiers


def command_validate_executed(args: argparse.Namespace) -> int:
    expected_payload = load_json(args.expected_json)
    expected = extract_test_identifiers(expected_payload, args.target_prefix)
    if not expected:
        return emit_error(f"no expected tests found with prefix {args.target_prefix}")

    executed_files = sorted(args.executed_json_dir.glob("*.json"))
    if not executed_files:
        return emit_error(f"no executed xcresult JSON files found in {args.executed_json_dir}")

    executed: set[str] = set()
    for path in executed_files:
        executed.update(extract_test_identifiers(load_json(path), args.target_prefix))

    missing = sorted(expected - executed)
    extra = sorted(executed - expected)
    if missing or extra:
        lines: list[str] = []
        if missing:
            lines.append("missing executed tests:")
            lines.extend(missing)
        if extra:
            lines.append("unexpected executed tests:")
            lines.extend(extra)
        return emit_error("\n".join(lines))

    print(f"executed test set matches expected set ({len(expected)} tests)")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)

    validate_static = subcommands.add_parser("validate-static")
    validate_static.add_argument("--source", type=Path, required=True)
    validate_static.add_argument("--manifest", type=Path, required=True)
    validate_static.set_defaults(func=command_validate_static)

    validate_ax_waits = subcommands.add_parser("validate-ax-waits")
    validate_ax_waits.add_argument("--source", type=Path, required=True)
    validate_ax_waits.set_defaults(func=command_validate_ax_waits)

    write_only_testing = subcommands.add_parser("write-only-testing")
    write_only_testing.add_argument("--manifest", type=Path, required=True)
    write_only_testing.add_argument("--shard", required=True)
    write_only_testing.add_argument("--output", type=Path, required=True)
    write_only_testing.set_defaults(func=command_write_only_testing)

    validate_executed = subcommands.add_parser("validate-executed")
    validate_executed.add_argument("--expected-json", type=Path, required=True)
    validate_executed.add_argument("--executed-json-dir", type=Path, required=True)
    validate_executed.add_argument("--target-prefix", required=True)
    validate_executed.set_defaults(func=command_validate_executed)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
