import os
import shutil
import stat
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(os.environ.get("MT_RELEASE_GATE_SCRIPT", REPO_ROOT / "scripts" / "release-gate.sh"))
UDID = "C4A64D49-24A2-4429-B6E2-AD9A14142A99"


def _run(args, cwd: Path, **kwargs):
    return subprocess.run(args, cwd=cwd, text=True, capture_output=True, **kwargs)


def _git(repo: Path, *args: str) -> None:
    result = _run(["git", *args], repo)
    assert result.returncode == 0, result.stderr


def _write_project(repo: Path, *, tests_target: bool = True) -> None:
    project = repo / "ios/App/MakingTracks.xcodeproj"
    project.mkdir(parents=True)
    target = 'PBXNativeTarget "MakingTracksTests"' if tests_target else "NoTestsHere"
    (project / "project.pbxproj").write_text(target, encoding="utf-8")


def _init_repo(tmp_path: Path, *, tests_target: bool = True, ios_derived: bool = True) -> Path:
    repo = tmp_path / "repo"
    repo.mkdir()
    _git(repo, "init", "-q")
    _git(repo, "config", "user.email", "agent@example.invalid")
    _git(repo, "config", "user.name", "Agent")
    _write_project(repo, tests_target=tests_target)
    _git(repo, "add", ".")
    _git(repo, "commit", "-q", "-m", "base")

    origin = tmp_path / "origin.git"
    _git(tmp_path, "init", "--bare", "-q", str(origin))
    _git(repo, "branch", "ios")
    _git(repo, "remote", "add", "origin", str(origin))
    _git(repo, "push", "-q", "origin", "ios")

    if ios_derived:
        _git(repo, "checkout", "-q", "-b", "work", "ios")
        (repo / "marker.txt").write_text("work\n", encoding="utf-8")
        _git(repo, "add", "marker.txt")
        _git(repo, "commit", "-q", "-m", "work")
    else:
        _git(repo, "checkout", "-q", "--orphan", "work")
        for path in list(repo.iterdir()):
            if path.name == ".git":
                continue
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink()
        _write_project(repo, tests_target=tests_target)
        _git(repo, "add", ".")
        _git(repo, "commit", "-q", "-m", "unrelated")
    return repo


def _fake_tools(tmp_path: Path) -> tuple[Path, Path]:
    fakebin = tmp_path / "fakebin"
    fakebin.mkdir()
    log = tmp_path / "release-gate.log"
    xcrun = fakebin / "xcrun"
    xcrun.write_text(
        "#!/bin/sh\n"
        'echo "xcrun:$*" >> "$MT_RELEASE_GATE_LOG"\n',
        encoding="utf-8",
    )
    xcodebuild = fakebin / "xcodebuild"
    xcodebuild.write_text(
        "#!/bin/sh\n"
        'echo "xcodebuild:$*" >> "$MT_RELEASE_GATE_LOG"\n'
        'if [ "${MT_RELEASE_GATE_FAKE_CREATE_RESULT:-}" = "1" ]; then\n'
        "  previous=\n"
        '  for argument in "$@"; do\n'
        '    if [ "$previous" = "-resultBundlePath" ]; then mkdir -p "$argument"; fi\n'
        '    previous="$argument"\n'
        "  done\n"
        "fi\n"
        'if [ -n "${MT_RELEASE_GATE_XCODEBUILD_STDOUT:-}" ]; then printf "%s\\n" "$MT_RELEASE_GATE_XCODEBUILD_STDOUT"; fi\n'
        'if [ "${MT_RELEASE_GATE_FAIL_TEST:-}" = "1" ] && [ "$1" = "test-without-building" ]; then exit 65; fi\n'
        'if [ "${MT_RELEASE_GATE_FAIL_XCODEBUILD:-}" = "1" ]; then exit 65; fi\n',
        encoding="utf-8",
    )
    for path in (xcrun, xcodebuild):
        path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return fakebin, log


def _env(fakebin: Path, log: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["PATH"] = f"{fakebin}:{env['PATH']}"
    env["AM_ME"] = "test-agent"
    env["MT_SIM_LOCK"] = "1"
    env["MT_SIM_LOCK_UDID"] = UDID
    env["MT_SIM_LOCK_DESTINATION"] = f"platform=iOS Simulator,id={UDID}"
    env["MT_RELEASE_GATE_TEST_MODE"] = "1"
    env["MT_RELEASE_GATE_RUN_DIR"] = str(log.parent / "release-gate-run")
    env["MT_RELEASE_GATE_LOG"] = str(log)
    env.pop("GITHUB_ACTIONS", None)
    env.pop("MT_RELEASE_GATE_SKIP_LOCK", None)
    return env


def test_release_gate_refuses_when_making_tracks_tests_target_is_missing(tmp_path):
    repo = _init_repo(tmp_path, tests_target=False)
    fakebin, log = _fake_tools(tmp_path)

    result = _run([str(SCRIPT)], repo, env=_env(fakebin, log))

    assert result.returncode == 1
    assert result.stderr.strip() == (
        "release-gate: refused: MakingTracksTests target missing from "
        "ios/App/MakingTracks.xcodeproj"
    )
    assert not log.exists()


def test_release_gate_refuses_when_head_is_not_current_ios_derived(tmp_path):
    repo = _init_repo(tmp_path, ios_derived=False)
    fakebin, log = _fake_tools(tmp_path)

    result = _run([str(SCRIPT)], repo, env=_env(fakebin, log))

    assert result.returncode == 1
    assert result.stderr.strip() == (
        "release-gate: refused: HEAD is not based on current origin/ios"
    )
    assert not log.exists()


def test_release_gate_refuses_when_not_run_through_sim_lock(tmp_path):
    """The gate must not take the lock itself, and must not run without it.

    sim-lock.sh owns the lock and exports MT_SIM_LOCK. Without that marker the
    gate would run against the shared simulator unserialised, which is the
    regression the single-entry-point change exists to prevent.
    """
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env.pop("MT_SIM_LOCK")

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 1
    assert result.stderr.strip() == (
        "release-gate: refused: must be run through scripts/sim-lock.sh --seat <seat> "
        "(which holds the simulator lock)"
    )
    assert not log.exists()


def test_release_gate_refuses_when_lock_identity_is_missing(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env.pop("MT_SIM_LOCK_UDID")

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 1
    assert "lock identity is missing" in result.stderr
    assert not log.exists()


def test_release_gate_ignores_removed_public_destination_contract(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env.pop("MT_SIM_LOCK_DESTINATION")
    env["MT_RELEASE_GATE_DESTINATION"] = f"platform=iOS Simulator,id={UDID}"

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 1
    assert "MT_SIM_LOCK_DESTINATION is missing" in result.stderr
    assert not log.exists()


def test_release_gate_ignores_ci_destination_outside_actions_skip_lock(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env.pop("MT_SIM_LOCK_DESTINATION")
    env["MT_RELEASE_GATE_CI_DESTINATION"] = f"platform=iOS Simulator,id={UDID}"

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 1
    assert "MT_SIM_LOCK_DESTINATION is missing" in result.stderr
    assert not log.exists()


def test_release_gate_refuses_when_lock_is_for_another_simulator(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env["MT_SIM_LOCK_UDID"] = "ANOTHER-UDID"

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 1
    assert f"lock is for simulator ANOTHER-UDID, not {UDID}" in result.stderr
    assert not log.exists()


def test_release_gate_refuses_destination_without_exact_id_field(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env["MT_SIM_LOCK_DESTINATION"] = "platform=iOS Simulator,grid=NOT-AN-ID"

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 1
    assert "must include id=<simulator-udid>" in result.stderr
    assert not log.exists()


def test_release_gate_refuses_multiple_destination_id_fields(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env["MT_SIM_LOCK_DESTINATION"] = (
        "platform=iOS Simulator,id=FIRST-UDID,id=SECOND-UDID"
    )
    env["MT_SIM_LOCK_UDID"] = "FIRST-UDID"

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 1
    assert "must contain exactly one id=<simulator-udid>" in result.stderr
    assert not log.exists()


def test_release_gate_refuses_fleet_wide_destination_selector(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env["MT_SIM_LOCK_DESTINATION"] = "platform=iOS Simulator,id=all"
    env["MT_SIM_LOCK_UDID"] = "all"

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 1
    assert "valid CoreSimulator UUID" in result.stderr
    assert not log.exists()


def test_release_gate_skip_lock_refuses_outside_github_actions(tmp_path):
    """An accidental local SKIP_LOCK must not drop the shared-simulator lock."""
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env.pop("MT_SIM_LOCK")
    env["MT_RELEASE_GATE_SKIP_LOCK"] = "1"
    env.pop("GITHUB_ACTIONS", None)

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 1
    assert result.stderr.strip() == (
        "release-gate: refused: must be run through scripts/sim-lock.sh --seat <seat> "
        "(which holds the simulator lock)"
    )
    assert not log.exists()


def test_release_gate_github_actions_refuses_without_skip_lock(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env.pop("MT_SIM_LOCK")
    env["GITHUB_ACTIONS"] = "true"

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 1
    assert result.stderr.strip() == (
        "release-gate: refused: must be run through scripts/sim-lock.sh --seat <seat> "
        "(which holds the simulator lock)"
    )
    assert not log.exists()


def test_release_gate_skip_lock_runs_only_inside_github_actions(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    xcbeautify = fakebin / "xcbeautify"
    xcbeautify.write_text("cat\n", encoding="utf-8")
    xcbeautify.chmod(xcbeautify.stat().st_mode | stat.S_IXUSR)
    env = _env(fakebin, log)
    env.pop("MT_SIM_LOCK")
    env.pop("MT_SIM_LOCK_DESTINATION")
    env["MT_RELEASE_GATE_SKIP_LOCK"] = "1"
    env["MT_RELEASE_GATE_CI_DESTINATION"] = f"platform=iOS Simulator,id={UDID}"
    env["GITHUB_ACTIONS"] = "true"

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 0, result.stderr
    assert log.exists()


def test_release_gate_private_destination_replaces_all_udid_uses(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    runner_udid = "22222222-2222-4222-8222-222222222222"
    env["MT_SIM_LOCK_DESTINATION"] = f"platform=iOS Simulator,id={runner_udid}"
    env["MT_SIM_LOCK_UDID"] = runner_udid

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 0, result.stderr
    lines = log.read_text(encoding="utf-8").splitlines()
    assert lines[0] == f"xcrun:simctl bootstatus {runner_udid} -b"
    destination_lines = [line for line in lines if "-destination" in line]
    assert len(destination_lines) == 3
    assert all(f"platform=iOS Simulator,id={runner_udid}" in line for line in destination_lines)
    assert not any(UDID in line for line in lines)


def test_release_gate_runs_release_build_for_testing_and_tests_without_rebuilding(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    stale_result_bundle = log.parent / "release-gate-run" / "MakingTracksTests.xcresult"
    stale_result_bundle.mkdir(parents=True)
    (stale_result_bundle / "stale").write_text("stale\n", encoding="utf-8")
    derived_data = log.parent / "release-gate-run" / "DerivedData"
    derived_data.mkdir(parents=True)
    (derived_data / "stale").write_text("stale\n", encoding="utf-8")

    result = _run([str(SCRIPT)], repo, env=_env(fakebin, log))

    assert result.returncode == 0, result.stderr
    assert not stale_result_bundle.exists()
    assert derived_data.exists()
    assert (derived_data / "stale").exists()
    lines = log.read_text(encoding="utf-8").splitlines()
    assert not any(line.startswith("flock:") for line in lines), (
        "release-gate must not take the lock; sim-lock.sh owns it"
    )
    assert lines[0] == f"xcrun:simctl bootstatus {UDID} -b"
    assert any(
        line.startswith("xcodebuild:build -configuration Release ")
        and "-project ios/App/MakingTracks.xcodeproj" in line
        and "-scheme MakingTracks" in line
        and f"-destination platform=iOS Simulator,id={UDID}" in line
        and f"-derivedDataPath {log.parent}/release-gate-run/DerivedData" in line
        for line in lines
    )
    assert any(
        line.startswith("xcodebuild:build-for-testing ")
        and "-project ios/App/MakingTracks.xcodeproj" in line
        and "-scheme MakingTracks" in line
        and f"-destination platform=iOS Simulator,id={UDID}" in line
        and "-parallel-testing-enabled NO" in line
        and "-disable-concurrent-destination-testing" in line
        and f"-derivedDataPath {log.parent}/release-gate-run/DerivedData" in line
        for line in lines
    )
    assert any(
        line.startswith("xcodebuild:test-without-building ")
        and "-project ios/App/MakingTracks.xcodeproj" in line
        and "-scheme MakingTracks" in line
        and f"-destination platform=iOS Simulator,id={UDID}" in line
        and "-parallel-testing-enabled NO" in line
        and "-disable-concurrent-destination-testing" in line
        and f"-derivedDataPath {log.parent}/release-gate-run/DerivedData" in line
        and f"-resultBundlePath {log.parent}/release-gate-run/MakingTracksTests.xcresult" in line
        for line in lines
    )


def test_release_gate_build_mode_skips_test_execution(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env["MT_RELEASE_GATE_MODE"] = "build"

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 0, result.stderr
    lines = log.read_text(encoding="utf-8").splitlines()
    assert any(line.startswith("xcodebuild:build -configuration Release ") for line in lines)
    assert any(line.startswith("xcodebuild:build-for-testing ") for line in lines)
    assert not any(line.startswith("xcodebuild:test-without-building ") for line in lines)


def test_release_gate_test_mode_skips_builds_and_uses_only_testing_file(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    only_testing = tmp_path / "only-testing.txt"
    only_testing.write_text(
        "\n".join(
            [
                "# generated shard",
                "  MakingTracksUITests/MakingTracksCoreLoopUITests/testOne  ",
                "\tMakingTracksUITests/MakingTracksCoreLoopUITests/testTwo\t",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    env = _env(fakebin, log)
    env["MT_RELEASE_GATE_MODE"] = "test"
    env["MT_RELEASE_GATE_ONLY_TESTING_FILE"] = str(only_testing)
    env["MT_RELEASE_GATE_RESULT_BUNDLE"] = str(tmp_path / "Shard.xcresult")
    env["MT_RELEASE_GATE_XCTESTRUN_FILE"] = str(tmp_path / "MakingTracks.xctestrun")
    (tmp_path / "MakingTracks.xctestrun").write_text("fake\n", encoding="utf-8")

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 0, result.stderr
    lines = log.read_text(encoding="utf-8").splitlines()
    assert not any(line.startswith("xcodebuild:build ") for line in lines)
    assert not any(line.startswith("xcodebuild:build-for-testing ") for line in lines)
    test_lines = [line for line in lines if line.startswith("xcodebuild:test-without-building ")]
    assert len(test_lines) == 1
    assert "-xctestrun " + str(tmp_path / "MakingTracks.xctestrun") in test_lines[0]
    assert "-only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testOne" in test_lines[0]
    assert "-only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testTwo" in test_lines[0]
    assert "-only-testing:  MakingTracksUITests/MakingTracksCoreLoopUITests/testOne" not in test_lines[0]
    assert "testOne  " not in test_lines[0]
    assert "-only-testing:\tMakingTracksUITests/MakingTracksCoreLoopUITests/testTwo" not in test_lines[0]
    assert "testTwo\t" not in test_lines[0]
    assert "-resultBundlePath " + str(tmp_path / "Shard.xcresult") in test_lines[0]


def test_release_gate_prunes_stale_warm_derived_data_before_running(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    derived_data = log.parent / "release-gate-run" / "DerivedData"
    stale = derived_data / "stale-cache"
    stale.mkdir(parents=True)
    old_timestamp = 1
    os.utime(derived_data, (old_timestamp, old_timestamp))
    os.utime(stale, (old_timestamp, old_timestamp))

    result = _run([str(SCRIPT)], repo, env=_env(fakebin, log))

    assert result.returncode == 0, result.stderr
    assert derived_data.exists()
    assert not stale.exists()


def test_release_gate_clean_derived_data_override_prunes_warm_cache(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    derived_data = log.parent / "release-gate-run" / "DerivedData"
    stale = derived_data / "stale-cache"
    stale.mkdir(parents=True)
    env = _env(fakebin, log)
    env["MT_RELEASE_GATE_CLEAN_DERIVED_DATA"] = "1"

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 0, result.stderr
    assert derived_data.exists()
    assert not stale.exists()
    assert "MT_RELEASE_GATE_CLEAN_DERIVED_DATA=1" in result.stderr


def test_release_gate_keeps_derived_data_when_xcodebuild_fails(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env["MT_RELEASE_GATE_FAIL_XCODEBUILD"] = "1"
    derived_data = log.parent / "release-gate-run" / "DerivedData"
    derived_data.mkdir(parents=True)
    (derived_data / "diagnostics").write_text("keep\n", encoding="utf-8")

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 65
    assert derived_data.exists()


def test_release_gate_preserves_result_bundle_after_success(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env["MT_RELEASE_GATE_FAKE_CREATE_RESULT"] = "1"
    result_bundle = log.parent / "release-gate-run" / "MakingTracksTests.xcresult"

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 0, result.stderr
    assert result_bundle.is_dir()


def test_release_gate_preserves_result_bundle_after_failure(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env["MT_RELEASE_GATE_FAKE_CREATE_RESULT"] = "1"
    env["MT_RELEASE_GATE_FAIL_TEST"] = "1"
    result_bundle = log.parent / "release-gate-run" / "MakingTracksTests.xcresult"

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 65
    assert result_bundle.is_dir()


def test_release_gate_preserves_caller_named_result_bundle(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env["MT_RELEASE_GATE_FAKE_CREATE_RESULT"] = "1"
    result_bundle = tmp_path / "caller-owned" / "Shard.xcresult"
    env["MT_RELEASE_GATE_RESULT_BUNDLE"] = str(result_bundle)

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 0, result.stderr
    assert result_bundle.is_dir()


def test_release_gate_logs_failed_phase_timing_before_exiting(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env["MT_RELEASE_GATE_FAIL_XCODEBUILD"] = "1"

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 65
    assert "release-gate: phase start: release build" in result.stderr
    assert "release-gate: phase end: release build status=65 elapsed=" in result.stderr


def test_release_gate_ci_prettifies_xcodebuild_and_preserves_raw_logs(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    xcbeautify = fakebin / "xcbeautify"
    xcbeautify.write_text(
        "#!/bin/sh\n"
        'while IFS= read -r line; do printf "pretty:%s\\n" "$line"; done\n',
        encoding="utf-8",
    )
    xcbeautify.chmod(xcbeautify.stat().st_mode | stat.S_IXUSR)
    env = _env(fakebin, log)
    env.pop("MT_SIM_LOCK")
    env.pop("MT_SIM_LOCK_DESTINATION")
    env["MT_RELEASE_GATE_SKIP_LOCK"] = "1"
    env["MT_RELEASE_GATE_CI_DESTINATION"] = f"platform=iOS Simulator,id={UDID}"
    env["GITHUB_ACTIONS"] = "true"
    env["MT_RELEASE_GATE_XCODEBUILD_STDOUT"] = "raw xcodebuild output"

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 0, result.stderr
    assert "pretty:raw xcodebuild output" in result.stdout
    run_dir = log.parent / "release-gate-run"
    assert (run_dir / "release-build.xcodebuild.log").read_text(encoding="utf-8") == (
        "raw xcodebuild output\n"
    )
    assert (run_dir / "debug-build-for-testing.xcodebuild.log").read_text(
        encoding="utf-8"
    ) == "raw xcodebuild output\n"
    assert (run_dir / "tests-without-building.xcodebuild.log").read_text(
        encoding="utf-8"
    ) == "raw xcodebuild output\n"


def test_release_gate_ci_formatter_does_not_mask_xcodebuild_failure(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    xcbeautify = fakebin / "xcbeautify"
    xcbeautify.write_text("cat\n", encoding="utf-8")
    xcbeautify.chmod(xcbeautify.stat().st_mode | stat.S_IXUSR)
    env = _env(fakebin, log)
    env.pop("MT_SIM_LOCK")
    env.pop("MT_SIM_LOCK_DESTINATION")
    env["MT_RELEASE_GATE_SKIP_LOCK"] = "1"
    env["MT_RELEASE_GATE_CI_DESTINATION"] = f"platform=iOS Simulator,id={UDID}"
    env["GITHUB_ACTIONS"] = "true"
    env["MT_RELEASE_GATE_FAIL_XCODEBUILD"] = "1"
    env["MT_RELEASE_GATE_XCODEBUILD_STDOUT"] = "raw failed output"

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 65
    assert "raw failed output" in result.stdout
    raw_log = log.parent / "release-gate-run" / "release-build.xcodebuild.log"
    assert raw_log.read_text(encoding="utf-8") == "raw failed output\n"
