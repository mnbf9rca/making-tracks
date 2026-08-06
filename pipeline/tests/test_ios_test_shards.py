import json
import re
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "ios-test-shards.py"


def _run(*args: str, cwd: Path = REPO_ROOT) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["python3", str(SCRIPT), *args],
        cwd=cwd,
        text=True,
        capture_output=True,
    )


def _write_json(path: Path, payload: object) -> None:
    path.write_text(json.dumps(payload), encoding="utf-8")


def test_static_validation_fails_with_missing_test_name(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """
        final class MakingTracksCoreLoopUITests: XCTestCase {
            func testOne() {}
            func testTwo() {}
        }
        """,
        encoding="utf-8",
    )
    manifest = tmp_path / "manifest.json"
    _write_json(
        manifest,
        {
            "uiTarget": "MakingTracksUITests",
            "uiClass": "MakingTracksCoreLoopUITests",
            "shards": [
                {"id": "ui-1", "tests": ["testOne"]},
            ],
        },
    )

    result = _run("validate-static", "--source", str(source), "--manifest", str(manifest))

    assert result.returncode == 1
    assert "missing from shard manifest:" in result.stderr
    assert "testTwo" in result.stderr


def test_decoy_accessibility_wait_validation_flags_same_identifier_label_read(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """
        final class MakingTracksCoreLoopUITests: XCTestCase {
            func testDecoyWait() {
                XCTAssertTrue(app.buttons["place-card.loved"].waitForExistence(timeout: 5))
                XCTAssertEqual(app.buttons["place-card.loved"].label, "Love")
            }
        }
        """,
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 1
    assert "decoy accessibility waits:" in result.stderr
    assert "place-card.loved" in result.stderr
    assert ".label" in result.stderr


def test_decoy_accessibility_wait_validation_flags_same_identifier_value_read(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """
        final class MakingTracksCoreLoopUITests: XCTestCase {
            func testDecoyWait() {
                XCTAssertTrue(app.buttons["track-filter-picker.loved"].waitForExistence(timeout: 5))
                XCTAssertEqual(app.buttons["track-filter-picker.loved"].value as? String, "Selected")
            }
        }
        """,
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 1
    assert "track-filter-picker.loved" in result.stderr
    assert ".value" in result.stderr


def test_decoy_accessibility_wait_validation_flags_static_text_after_comment_gap(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """
        final class MakingTracksCoreLoopUITests: XCTestCase {
            func testDecoyWait() {
                XCTAssertTrue(app.staticTexts["lists.detail.progress"].waitForExistence(timeout: 5))

                // Content arrives after existence.
                XCTAssertEqual(app.staticTexts["lists.detail.progress"].label, "all seen")
            }
        }
        """,
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 1
    assert "lists.detail.progress" in result.stderr
    assert ".label" in result.stderr


def test_decoy_accessibility_wait_validation_flags_simple_variable_switch_selector(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """
        final class MakingTracksCoreLoopUITests: XCTestCase {
            func testDecoyWait() {
                XCTAssertTrue(app.switches[showSaved].waitForExistence(timeout: 5))
                XCTAssertEqual(app.switches[showSaved].value as? String, "1")
            }
        }
        """,
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 1
    assert "showSaved" in result.stderr
    assert ".value" in result.stderr


def test_decoy_accessibility_wait_validation_flags_multiline_property_assertion(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """XCTAssertTrue(app.switches[showHidden].waitForExistence(timeout: 5))
XCTAssertEqual(
    expectedValue(),
    app.switches[showHidden].value as? String,
    "The switch must begin off.",
    file: #filePath,
    line: #line
)
""",
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 1
    assert "showHidden" in result.stderr
    assert ".value" in result.stderr


def test_decoy_accessibility_wait_validation_flags_xctest_wait_message_overload(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """XCTAssertTrue(
    app.buttons[identifier].waitForExistence(timeout: timeout()),
    "The button must appear.",
    file: #filePath,
    line: #line
)
XCTAssertEqual(expectedLabel(), app.buttons[identifier].label)
""",
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 1
    assert "identifier" in result.stderr
    assert ".label" in result.stderr


def test_decoy_accessibility_wait_validation_detects_fifth_physical_line(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """XCTAssertTrue(app.buttons["x"].waitForExistence(timeout: 5))

// one
// two
// three
XCTAssertEqual(app.buttons["x"].label, "Y")
""",
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 1
    assert 'x' in result.stderr


def test_decoy_accessibility_wait_validation_stops_beyond_fifth_physical_line(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """XCTAssertTrue(app.buttons["x"].waitForExistence(timeout: 5))

// one
// two
// three
// four
XCTAssertEqual(app.buttons["x"].label, "Y")
""",
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 0, result.stderr


def test_decoy_accessibility_wait_validation_stops_at_substantive_line(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """XCTAssertTrue(app.buttons["x"].waitForExistence(timeout: 5))
app.buttons["x"].tap()
XCTAssertEqual(app.buttons["x"].label, "Y")
""",
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 0, result.stderr


def test_decoy_accessibility_wait_validation_requires_same_element_class(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """XCTAssertTrue(app.buttons["x"].waitForExistence(timeout: 5))
XCTAssertEqual(app.staticTexts["x"].label, "Y")
""",
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 0, result.stderr


def test_decoy_accessibility_wait_validation_requires_same_selector_and_stops(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """XCTAssertTrue(app.buttons[expected].waitForExistence(timeout: 5))
XCTAssertEqual(app.buttons[other].label, "Other")
XCTAssertEqual(app.buttons[expected].label, "Expected")
""",
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 0, result.stderr


def test_decoy_accessibility_wait_validation_fails_when_scanner_matches_no_queries(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        'XCTAssertTrue(waitForButtonLabel("Y", identifier: "x", in: app))\n',
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 1
    assert "matched no supported accessibility queries" in result.stderr


def test_decoy_accessibility_wait_validation_ignores_comment_only_queries(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        '// XCTAssertTrue(app.buttons["stale"].waitForExistence(timeout: 5))\n',
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 1
    assert "matched no supported accessibility queries" in result.stderr


def test_decoy_accessibility_wait_validation_ignores_commented_wait_anchor(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """// XCTAssertTrue(app.buttons["active"].waitForExistence(timeout: 5))
XCTAssertEqual(app.buttons["active"].label, "Ready")
""",
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 0, result.stderr


def test_decoy_accessibility_wait_validation_ignores_commented_multiline_wait(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """XCTAssertTrue(
    // app.buttons["active"].waitForExistence(timeout: 5)
    unrelatedCondition
)
XCTAssertEqual(app.buttons["active"].label, "Ready")
""",
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 0, result.stderr


def test_decoy_accessibility_wait_validation_ignores_commented_property_poison(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """XCTAssertTrue(app.buttons[expected].waitForExistence(timeout: 5))
XCTAssertEqual(
    // app.buttons[other].label was the old oracle
    app.buttons[expected].label,
    "Ready"
)
""",
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 1
    assert "expected" in result.stderr


def test_decoy_accessibility_wait_validation_ignores_commented_property_only(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """XCTAssertTrue(app.buttons[expected].waitForExistence(timeout: 5))
XCTAssertEqual(
    // app.buttons[expected].label is intentionally not the oracle
    unrelatedLabel,
    "Ready"
)
""",
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 0, result.stderr


def test_decoy_accessibility_wait_validation_ignores_trailing_comment_queries(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        'let ready = true // app.buttons["stale"]\n',
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 1
    assert "matched no supported accessibility queries" in result.stderr


def test_decoy_accessibility_wait_validation_accepts_property_specific_wait(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """
        final class MakingTracksCoreLoopUITests: XCTestCase {
            func testSpecificWait() {
                XCTAssertTrue(app.buttons["menu"].exists)
                XCTAssertTrue(waitForButtonLabel("Love", identifier: "place-card.loved", in: app))
                XCTAssertTrue(waitForElementValue("Selected", identifier: "track-filter-picker.loved", in: app))
            }
        }
        """,
        encoding="utf-8",
    )

    result = _run("validate-ax-waits", "--source", str(source))

    assert result.returncode == 0, result.stderr
    assert "accessibility wait guard found no decoys" in result.stdout


def test_ios_gate_runs_ax_wait_validation_and_focused_pytest():
    workflow = (REPO_ROOT / ".github" / "workflows" / "ios-gate.yml").read_text(encoding="utf-8")
    job_match = re.search(
        r"^  ios-gate-build:\n(?P<body>.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)",
        workflow,
        flags=re.MULTILINE | re.DOTALL,
    )

    assert job_match is not None
    ios_gate_job = job_match.group("body")
    pytest_step_match = re.search(
        r"^      - name: Test iOS shard tooling\n(?P<body>.*?)(?=^      - |\Z)",
        ios_gate_job,
        flags=re.MULTILINE | re.DOTALL,
    )

    assert pytest_step_match is not None
    pytest_step = pytest_step_match.group("body")
    assert "  pull_request:\n" in workflow
    assert "  workflow_dispatch:\n" in workflow
    assert "\n    if:" not in ios_gate_job
    assert "\n        if:" not in pytest_step
    assert (
        "run: uv run --package making-tracks-pipeline --extra dev pytest "
        "pipeline/tests/test_ios_test_shards.py"
    ) in pytest_step
    assert "python3 scripts/ios-test-shards.py validate-ax-waits" in workflow
    assert '      - "pipeline/tests/test_ios_test_shards.py"' in workflow
    assert """      - uses: astral-sh/setup-uv@v9.0.0

      - name: Test iOS shard tooling
        run: uv run --package making-tracks-pipeline --extra dev pytest pipeline/tests/test_ios_test_shards.py
""" in workflow


def test_write_only_testing_outputs_full_xcode_identifiers(tmp_path):
    manifest = tmp_path / "manifest.json"
    output = tmp_path / "only-testing.txt"
    _write_json(
        manifest,
        {
            "uiTarget": "MakingTracksUITests",
            "uiClass": "MakingTracksCoreLoopUITests",
            "shards": [
                {"id": "ui-1", "tests": ["testOne", "testTwo"]},
            ],
        },
    )

    result = _run(
        "write-only-testing",
        "--manifest",
        str(manifest),
        "--shard",
        "ui-1",
        "--output",
        str(output),
    )

    assert result.returncode == 0, result.stderr
    assert output.read_text(encoding="utf-8").splitlines() == [
        "MakingTracksUITests/MakingTracksCoreLoopUITests/testOne",
        "MakingTracksUITests/MakingTracksCoreLoopUITests/testTwo",
    ]


def test_executed_validation_fails_with_missing_test_name(tmp_path):
    expected = tmp_path / "expected.json"
    executed_dir = tmp_path / "executed"
    executed_dir.mkdir()
    _write_json(
        expected,
        {
            "tests": [
                {"identifier": "MakingTracksUITests/MakingTracksCoreLoopUITests/testOne"},
                {"identifier": "MakingTracksUITests/MakingTracksCoreLoopUITests/testTwo"},
            ]
        },
    )
    _write_json(
        executed_dir / "ui-1.json",
        {
            "tests": [
                {
                    "identifier": "MakingTracksUITests/MakingTracksCoreLoopUITests/testOne",
                    "testStatus": "Success",
                }
            ]
        },
    )

    result = _run(
        "validate-executed",
        "--expected-json",
        str(expected),
        "--executed-json-dir",
        str(executed_dir),
        "--target-prefix",
        "MakingTracksUITests/",
    )

    assert result.returncode == 1
    assert "missing executed tests:" in result.stderr
    assert "MakingTracksUITests/MakingTracksCoreLoopUITests/testTwo" in result.stderr


def test_executed_validation_passes_for_matching_sets(tmp_path):
    expected = tmp_path / "expected.json"
    executed_dir = tmp_path / "executed"
    executed_dir.mkdir()
    _write_json(
        expected,
        {
            "tests": [
                {"identifier": "MakingTracksUITests/MakingTracksCoreLoopUITests/testOne"},
                {"identifier": "MakingTracksUITests/MakingTracksCoreLoopUITests/testTwo"},
            ]
        },
    )
    _write_json(
        executed_dir / "ui-1.json",
        {
            "tests": [
                {
                    "identifier": "MakingTracksUITests/MakingTracksCoreLoopUITests/testTwo",
                    "testStatus": "Failure",
                },
                {
                    "identifier": "MakingTracksUITests/MakingTracksCoreLoopUITests/testOne",
                    "testStatus": "Success",
                },
            ]
        },
    )

    result = _run(
        "validate-executed",
        "--expected-json",
        str(expected),
        "--executed-json-dir",
        str(executed_dir),
        "--target-prefix",
        "MakingTracksUITests/",
    )

    assert result.returncode == 0, result.stderr
    assert "executed test set matches expected set" in result.stdout


def test_executed_validation_accepts_xcresult_node_identifier_urls(tmp_path):
    expected = tmp_path / "expected.json"
    executed_dir = tmp_path / "executed"
    executed_dir.mkdir()
    _write_json(
        expected,
        {
            "tests": [
                {
                    "identifier": "MakingTracksUITests/MakingTracksCoreLoopUITests/testOne()",
                },
            ]
        },
    )
    _write_json(
        executed_dir / "ui-1.json",
        {
            "testNodes": [
                {
                    "nodeType": "Test Case",
                    "nodeIdentifier": "MakingTracksCoreLoopUITests/testOne()",
                    "nodeIdentifierURL": "test://com.apple.xcode/MakingTracks/MakingTracksUITests/MakingTracksCoreLoopUITests/testOne",
                    "result": "Passed",
                },
            ]
        },
    )

    result = _run(
        "validate-executed",
        "--expected-json",
        str(expected),
        "--executed-json-dir",
        str(executed_dir),
        "--target-prefix",
        "MakingTracksUITests/",
    )

    assert result.returncode == 0, result.stderr
    assert "executed test set matches expected set" in result.stdout


def test_executed_validation_fails_with_unexpected_test_name(tmp_path):
    expected = tmp_path / "expected.json"
    executed_dir = tmp_path / "executed"
    executed_dir.mkdir()
    _write_json(
        expected,
        {
            "tests": [
                {"identifier": "MakingTracksUITests/MakingTracksCoreLoopUITests/testOne"},
            ]
        },
    )
    _write_json(
        executed_dir / "ui-1.json",
        {
            "tests": [
                {
                    "identifier": "MakingTracksUITests/MakingTracksCoreLoopUITests/testOne",
                    "testStatus": "Success",
                },
                {
                    "identifier": "MakingTracksUITests/MakingTracksCoreLoopUITests/testUnexpected",
                    "testStatus": "Success",
                },
            ]
        },
    )

    result = _run(
        "validate-executed",
        "--expected-json",
        str(expected),
        "--executed-json-dir",
        str(executed_dir),
        "--target-prefix",
        "MakingTracksUITests/",
    )

    assert result.returncode == 1
    assert "unexpected executed tests:" in result.stderr
    assert "MakingTracksUITests/MakingTracksCoreLoopUITests/testUnexpected" in result.stderr
