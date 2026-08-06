from __future__ import annotations

import plistlib
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

from mt_pipeline.app_store_archive.model import DsymUUID


FULL_GIT_SHA = "1234567890abcdef1234567890abcdef12345678"
APP_UUID = DsymUUID("arm64", "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")


@dataclass
class FakeArchiveCommands:
    app_binary: Path
    dsym_binary: Path
    app_uuids: tuple[DsymUUID, ...]
    dsym_uuids: tuple[DsymUUID, ...]
    git_output: str = FULL_GIT_SHA
    xcode_output: str = "Xcode 16.4\nBuild version 16F6\n"
    app_dwarfdump_output: str | None = None
    dsym_dwarfdump_output: str | None = None

    def __post_init__(self) -> None:
        self.calls: list[tuple[str, ...]] = []

    def run(self, args: Sequence[str]) -> str:
        call = tuple(args)
        self.calls.append(call)
        if len(call) >= 4 and call[0] == "git" and call[1] == "-C" and call[3] == "rev-parse":
            return self.git_output
        if call == ("xcrun", "dwarfdump", "--uuid", str(self.app_binary)):
            return self.app_dwarfdump_output or _dwarfdump(self.app_uuids, self.app_binary)
        if call == ("xcrun", "dwarfdump", "--uuid", str(self.dsym_binary)):
            return self.dsym_dwarfdump_output or _dwarfdump(self.dsym_uuids, self.dsym_binary)
        if call == ("xcodebuild", "-version"):
            return self.xcode_output
        raise AssertionError(f"unexpected command: {call!r}")


@dataclass(frozen=True)
class ArchiveFixture:
    archive: Path
    app_path: Path
    app_plist: Path
    app_binary: Path
    dsym_binary: Path
    commands: FakeArchiveCommands


@dataclass
class FakeDittoCommands:
    package_bytes: bytes = b"deterministic-xcarchive-zip"
    fail_at: str | None = None

    def __post_init__(self) -> None:
        self.calls: list[tuple[str, ...]] = []

    def run(self, args: Sequence[str]) -> str:
        call = tuple(args)
        self.calls.append(call)
        if len(call) == 3 and call[0] == "ditto":
            if self.fail_at == "copy":
                raise RuntimeError("ditto copy failed")
            shutil.copytree(Path(call[1]), Path(call[2]))
            return ""
        if len(call) == 7 and call[:5] == (
            "ditto",
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
        ):
            if self.fail_at == "package":
                raise RuntimeError("ditto package failed")
            Path(call[6]).write_bytes(self.package_bytes)
            return ""
        raise AssertionError(f"unexpected command: {call!r}")


def make_archive(
    tmp_path: Path,
    *,
    version: str = "1.0",
    build: str = "1",
    bundle_id: str = "app.making-tracks.MakingTracks",
    git_commit: str = "1234567",
    app_uuids: tuple[DsymUUID, ...] = (APP_UUID,),
    dsym_uuids: tuple[DsymUUID, ...] | None = None,
) -> ArchiveFixture:
    archive = tmp_path / "MakingTracks.xcarchive"
    app_path = archive / "Products/Applications/MakingTracks.app"
    app_binary = app_path / "MakingTracks"
    dsym_binary = (
        archive
        / "dSYMs/MakingTracks.app.dSYM/Contents/Resources/DWARF/MakingTracks"
    )
    app_path.mkdir(parents=True)
    dsym_binary.parent.mkdir(parents=True)

    archive_info = {
        "ApplicationProperties": {
            "ApplicationPath": "Applications/MakingTracks.app",
            "CFBundleIdentifier": bundle_id,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
        }
    }
    app_info = {
        "CFBundleExecutable": "MakingTracks",
        "CFBundleIdentifier": bundle_id,
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
    }
    _write_plist(archive / "Info.plist", archive_info)
    _write_plist(app_path / "Info.plist", app_info)
    _write_plist(app_path / "BuildInfo.plist", {"GitCommit": git_commit})
    app_binary.write_bytes(b"app-binary")
    dsym_binary.write_bytes(b"dsym-binary")

    commands = FakeArchiveCommands(
        app_binary=app_binary,
        dsym_binary=dsym_binary,
        app_uuids=app_uuids,
        dsym_uuids=dsym_uuids if dsym_uuids is not None else app_uuids,
    )
    return ArchiveFixture(
        archive=archive,
        app_path=app_path,
        app_plist=app_path / "Info.plist",
        app_binary=app_binary,
        dsym_binary=dsym_binary,
        commands=commands,
    )


def read_plist(path: Path) -> dict[str, object]:
    with path.open("rb") as source:
        value = plistlib.load(source)
    assert isinstance(value, dict)
    return value


def write_plist(path: Path, value: dict[str, object]) -> None:
    _write_plist(path, value)


def _write_plist(path: Path, value: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as destination:
        plistlib.dump(value, destination, fmt=plistlib.FMT_BINARY, sort_keys=True)


def _dwarfdump(uuids: tuple[DsymUUID, ...], binary: Path) -> str:
    return "".join(
        f"UUID: {item.uuid} ({item.architecture}) {binary}\n" for item in uuids
    )
