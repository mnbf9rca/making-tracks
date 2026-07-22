import json
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


def test_decoy_accessibility_wait_validation_accepts_property_specific_wait(tmp_path):
    source = tmp_path / "MakingTracksCoreLoopUITests.swift"
    source.write_text(
        """
        final class MakingTracksCoreLoopUITests: XCTestCase {
            func testSpecificWait() {
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
