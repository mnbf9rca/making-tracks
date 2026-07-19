import os
import shutil
import stat
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "release-gate.sh"
UDID = "C4A64D49-24A2-4429-B6E2-AD9A14142A99"
LOCK = "/private/tmp/making-tracks-ios-tests.lock"


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
    flock = fakebin / "flock"
    flock.write_text(
        "#!/bin/sh\n"
        'echo "flock:$1" >> "$MT_RELEASE_GATE_LOG"\n'
        "shift\n"
        'exec "$@"\n',
        encoding="utf-8",
    )
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
        'if [ "${MT_RELEASE_GATE_FAIL_XCODEBUILD:-}" = "1" ]; then exit 65; fi\n',
        encoding="utf-8",
    )
    for path in (flock, xcrun, xcodebuild):
        path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return fakebin, log


def _env(fakebin: Path, log: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["PATH"] = f"{fakebin}:{env['PATH']}"
    env["AM_ME"] = "test-agent"
    env["MT_RELEASE_GATE_FLOCK_BIN"] = str(fakebin / "flock")
    env["MT_RELEASE_GATE_TEST_MODE"] = "1"
    env["MT_RELEASE_GATE_RUN_DIR"] = str(log.parent / "release-gate-run")
    env["MT_RELEASE_GATE_LOG"] = str(log)
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


def test_release_gate_refuses_flock_override_outside_test_mode(tmp_path):
    repo = _init_repo(tmp_path)
    fakebin, log = _fake_tools(tmp_path)
    env = _env(fakebin, log)
    env.pop("MT_RELEASE_GATE_TEST_MODE")

    result = _run([str(SCRIPT)], repo, env=env)

    assert result.returncode == 1
    assert result.stderr.strip() == (
        "release-gate: refused: MT_RELEASE_GATE_FLOCK_BIN is only allowed in test mode"
    )
    assert not log.exists()


def test_release_gate_runs_release_build_and_tests_under_canonical_lock(tmp_path):
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
    assert not derived_data.exists()
    lines = log.read_text(encoding="utf-8").splitlines()
    assert lines[0] == f"flock:{LOCK}"
    assert lines[1] == f"xcrun:simctl bootstatus {UDID} -b"
    assert any(
        line.startswith("xcodebuild:build -configuration Release ")
        and "-project ios/App/MakingTracks.xcodeproj" in line
        and "-scheme MakingTracks" in line
        and f"-destination platform=iOS Simulator,id={UDID}" in line
        and f"-derivedDataPath {log.parent}/release-gate-run/DerivedData" in line
        for line in lines
    )
    assert any(
        line.startswith("xcodebuild:-project ios/App/MakingTracks.xcodeproj ")
        and "-scheme MakingTracks" in line
        and f"-destination platform=iOS Simulator,id={UDID}" in line
        and "-parallel-testing-enabled NO" in line
        and "-disable-concurrent-destination-testing" in line
        and f"-derivedDataPath {log.parent}/release-gate-run/DerivedData" in line
        and f"-resultBundlePath {log.parent}/release-gate-run/MakingTracksTests.xcresult" in line
        and line.endswith(" test")
        for line in lines
    )


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
