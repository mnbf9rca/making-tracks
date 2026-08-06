from __future__ import annotations

import plistlib
import shutil
from dataclasses import dataclass
from io import BytesIO
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
        if len(call) == 4 and call[:3] == ("xcrun", "dwarfdump", "--uuid"):
            binary = Path(call[3])
            if any(part.endswith(".dSYM") for part in binary.parts):
                return self.dsym_dwarfdump_output or _dwarfdump(self.dsym_uuids, binary)
            return self.app_dwarfdump_output or _dwarfdump(self.app_uuids, binary)
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


class FakeS3Error(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.response = {"Error": {"Code": code}}


@dataclass
class InMemoryS3:
    page_size: int = 1_000

    def __post_init__(self) -> None:
        self.objects: dict[tuple[str, str], bytes] = {}
        self.calls: list[tuple[str, str, str]] = []
        self.corrupt_get_key: str | None = None
        self.read_failure_key: str | None = None
        self.failure_at: str | None = None
        self.precondition_races: dict[str, bytes] = {}

    def put_object(self, *, Bucket, Key, Body, IfNoneMatch=None):
        self.calls.append(("put", Bucket, Key))
        if self.failure_at == "put":
            raise RuntimeError("R2_SECRET_SENTINEL")
        if IfNoneMatch != "*":
            raise AssertionError("immutable writes require IfNoneMatch='*'")
        if Key in self.precondition_races:
            self.objects[(Bucket, Key)] = self.precondition_races.pop(Key)
            raise FakeS3Error("PreconditionFailed")
        if (Bucket, Key) in self.objects:
            raise FakeS3Error("PreconditionFailed")
        data = Body.read() if hasattr(Body, "read") else Body
        if not isinstance(data, bytes):
            raise AssertionError("put body must resolve to bytes")
        self.objects[(Bucket, Key)] = data
        return {"ETag": '"not-a-content-digest"'}

    def get_object(self, *, Bucket, Key):
        self.calls.append(("get", Bucket, Key))
        if self.failure_at == "get":
            raise RuntimeError("R2_SECRET_SENTINEL")
        try:
            data = self.objects[(Bucket, Key)]
        except KeyError as exc:
            raise FakeS3Error("NoSuchKey") from exc
        if Key == self.corrupt_get_key:
            data = data + b"corrupt"
        if Key == self.read_failure_key:
            class FailingBody:
                def read(self, _size: int) -> bytes:
                    raise RuntimeError("R2_SECRET_SENTINEL")

            return {"Body": FailingBody(), "ContentLength": len(data)}
        return {"Body": BytesIO(data), "ContentLength": len(data)}

    def list_objects_v2(
        self,
        *,
        Bucket,
        Prefix,
        Delimiter,
        ContinuationToken=None,
    ):
        self.calls.append(("list", Bucket, Prefix))
        if self.failure_at == "list":
            raise RuntimeError("R2_SECRET_SENTINEL")
        if Delimiter != "/":
            raise AssertionError("archive discovery must use Delimiter='/'")
        prefixes = sorted(
            {
                Prefix + remainder.split("/", 1)[0] + "/"
                for bucket, key in self.objects
                if bucket == Bucket
                and key.startswith(Prefix)
                and (remainder := key[len(Prefix) :])
                and "/" in remainder
            }
        )
        start = int(ContinuationToken or "0")
        page = prefixes[start : start + self.page_size]
        next_start = start + len(page)
        truncated = next_start < len(prefixes)
        result = {
            "CommonPrefixes": [{"Prefix": value} for value in page],
            "IsTruncated": truncated,
        }
        if truncated:
            result["NextContinuationToken"] = str(next_start)
        return result


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
