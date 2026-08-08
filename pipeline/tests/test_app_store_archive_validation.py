from __future__ import annotations

import hashlib
import plistlib
import shutil
import subprocess
from pathlib import Path

import pytest

from app_store_archive_helpers import (
    APP_UUID,
    FULL_GIT_SHA,
    make_archive,
    read_plist,
    write_plist,
)
from mt_pipeline.app_store_archive.archive import inspect_archive, run_command
from mt_pipeline.app_store_archive.model import (
    ArchiveValidationError,
    DsymUUID,
    sha256_file,
    validate_full_sha,
    validate_key_component,
)


def test_valid_archive_yields_release_identity_and_symbolication_evidence(tmp_path: Path):
    fixture = make_archive(tmp_path)

    identity = inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)

    assert identity.archive_path == fixture.archive
    assert identity.app_path == fixture.app_path
    assert identity.app_binary == fixture.app_binary
    assert identity.dsym_binary == fixture.dsym_binary
    assert identity.bundle_id == "app.making-tracks.MakingTracks"
    assert identity.version == "1.0"
    assert identity.build == "1"
    assert identity.git_sha == FULL_GIT_SHA
    assert identity.dsym_uuids == (APP_UUID,)
    assert identity.app_binary_sha256 == hashlib.sha256(b"app-binary").hexdigest()
    assert identity.xcode_version == "16.4"
    assert identity.xcode_build == "16F6"
    assert fixture.commands.calls == [
        (
            "git",
            "-C",
            str(tmp_path),
            "rev-parse",
            "--verify",
            "1234567^{commit}",
        ),
        ("xcrun", "dwarfdump", "--uuid", str(fixture.app_binary)),
        ("xcrun", "dwarfdump", "--uuid", str(fixture.dsym_binary)),
        ("xcodebuild", "-version"),
    ]


@pytest.mark.parametrize("value", ["1", "1.2.3", "build-42", "A_b.c"])
def test_safe_key_components_are_returned_unchanged(value: str):
    assert validate_key_component(value, "version") == value


@pytest.mark.parametrize(
    "value",
    ["", ".", "..", "../1", "1/2", " space", "space here", "a" * 129],
)
def test_unsafe_key_components_are_rejected(value: str):
    with pytest.raises(ArchiveValidationError, match="unsafe version"):
        validate_key_component(value, "version")


@pytest.mark.parametrize(
    "value",
    ["1234567", "A" * 40, "g" * 40, "0" * 39, "0" * 41, "0" * 40 + "\n"],
)
def test_full_sha_requires_exact_lowercase_hex(value: str):
    with pytest.raises(
        ArchiveValidationError,
        match="Git SHA must be 40 lowercase hexadecimal characters",
    ):
        validate_full_sha(value)


def test_sha256_file_streams_the_exact_bytes(tmp_path: Path):
    source = tmp_path / "artifact"
    source.write_bytes(b"abc" * 500_000)

    digest, byte_count = sha256_file(source)

    assert digest == hashlib.sha256(b"abc" * 500_000).hexdigest()
    assert byte_count == 1_500_000


def test_symlink_archive_root_is_rejected_before_commands(tmp_path: Path):
    fixture = make_archive(tmp_path)
    real_archive = tmp_path / "real.xcarchive"
    fixture.archive.rename(real_archive)
    fixture.archive.symlink_to(real_archive, target_is_directory=True)

    with pytest.raises(ArchiveValidationError, match="archive path"):
        inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)

    assert fixture.commands.calls == []


def test_wrong_archive_suffix_is_rejected_before_commands(tmp_path: Path):
    fixture = make_archive(tmp_path)
    wrong_suffix = tmp_path / "MakingTracks.archive"
    fixture.archive.rename(wrong_suffix)

    with pytest.raises(ArchiveValidationError, match="xcarchive"):
        inspect_archive(wrong_suffix, tmp_path, run=fixture.commands.run)

    assert fixture.commands.calls == []


@pytest.mark.parametrize("app_count", [0, 2])
def test_archive_requires_exactly_one_application(tmp_path: Path, app_count: int):
    fixture = make_archive(tmp_path)
    if app_count == 0:
        shutil.rmtree(fixture.app_path)
    else:
        (fixture.app_path.parent / "Other.app").mkdir()

    with pytest.raises(ArchiveValidationError, match="exactly one application"):
        inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)

    assert fixture.commands.calls == []


def test_archive_application_path_must_name_the_only_application(tmp_path: Path):
    fixture = make_archive(tmp_path)
    archive_plist = read_plist(fixture.archive / "Info.plist")
    properties = archive_plist["ApplicationProperties"]
    assert isinstance(properties, dict)
    properties["ApplicationPath"] = "Applications/Other.app"
    write_plist(fixture.archive / "Info.plist", archive_plist)

    with pytest.raises(ArchiveValidationError, match="ApplicationPath"):
        inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)

    assert fixture.commands.calls == []


def test_unexpected_bundle_identifier_is_rejected_before_commands(tmp_path: Path):
    fixture = make_archive(tmp_path, bundle_id="example.invalid.Other")

    with pytest.raises(ArchiveValidationError, match="bundle identifier"):
        inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)

    assert fixture.commands.calls == []


@pytest.mark.parametrize(
    ("field", "replacement", "message"),
    [
        ("CFBundleIdentifier", "example.invalid.Other", "bundle identifier"),
        ("CFBundleShortVersionString", "2.0", "version"),
        ("CFBundleVersion", "2", "build"),
    ],
)
def test_app_and_archive_identity_must_agree(
    tmp_path: Path,
    field: str,
    replacement: str,
    message: str,
):
    fixture = make_archive(tmp_path)
    app_plist = read_plist(fixture.app_plist)
    app_plist[field] = replacement
    write_plist(fixture.app_plist, app_plist)

    with pytest.raises(ArchiveValidationError, match=message):
        inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)

    assert fixture.commands.calls == []


@pytest.mark.parametrize("missing", [True, False])
def test_app_executable_must_exist_and_be_nonempty(tmp_path: Path, missing: bool):
    fixture = make_archive(tmp_path)
    if missing:
        fixture.app_binary.unlink()
    else:
        fixture.app_binary.write_bytes(b"")

    with pytest.raises(ArchiveValidationError, match="app executable"):
        inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)

    assert fixture.commands.calls == []


@pytest.mark.parametrize("missing", [True, False])
def test_app_dsym_must_exist_and_be_nonempty(tmp_path: Path, missing: bool):
    fixture = make_archive(tmp_path)
    if missing:
        fixture.dsym_binary.unlink()
    else:
        fixture.dsym_binary.write_bytes(b"")

    with pytest.raises(ArchiveValidationError, match="dSYM"):
        inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)

    assert fixture.commands.calls == []


@pytest.mark.parametrize("git_output", ["", "f" * 40 + "\n" + "e" * 40, "g" * 40])
def test_archive_git_commit_must_resolve_to_one_full_sha(
    tmp_path: Path,
    git_output: str,
):
    fixture = make_archive(tmp_path)
    fixture.commands.git_output = git_output

    with pytest.raises(ArchiveValidationError, match="unambiguous full SHA"):
        inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)

    assert not _called(fixture.commands.calls, "xcodebuild")


def test_resolved_git_sha_must_match_the_archive_stamp(tmp_path: Path):
    fixture = make_archive(tmp_path, git_commit="abcdef0")

    with pytest.raises(ArchiveValidationError, match="unambiguous full SHA"):
        inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)

    assert not _called(fixture.commands.calls, "xcodebuild")


@pytest.mark.parametrize(
    "output",
    [
        "not a UUID line\n",
        "UUID: AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE (arm64)\n",
        "UUID: AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE (arm64) app\nnoise\n",
    ],
)
def test_malformed_dwarfdump_output_is_rejected(tmp_path: Path, output: str):
    fixture = make_archive(tmp_path)
    fixture.commands.app_dwarfdump_output = output

    with pytest.raises(ArchiveValidationError, match="invalid dwarfdump UUID output"):
        inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)

    assert not _called(fixture.commands.calls, "xcodebuild")


def test_empty_uuid_sets_are_rejected(tmp_path: Path):
    fixture = make_archive(tmp_path, app_uuids=(), dsym_uuids=())

    with pytest.raises(ArchiveValidationError, match="invalid dwarfdump UUID output"):
        inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)

    assert not _called(fixture.commands.calls, "xcodebuild")


@pytest.mark.parametrize(
    "dsym_uuids",
    [
        (DsymUUID("arm64", "FFFFFFFF-BBBB-CCCC-DDDD-EEEEEEEEEEEE"),),
        (APP_UUID, DsymUUID("x86_64", "FFFFFFFF-BBBB-CCCC-DDDD-EEEEEEEEEEEE")),
    ],
)
def test_app_and_dsym_uuid_sets_must_match_exactly(
    tmp_path: Path,
    dsym_uuids: tuple[DsymUUID, ...],
):
    fixture = make_archive(tmp_path, dsym_uuids=dsym_uuids)

    with pytest.raises(ArchiveValidationError, match="dSYM UUIDs"):
        inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)

    assert not _called(fixture.commands.calls, "xcodebuild")


@pytest.mark.parametrize(
    "xcode_output",
    ["", "Xcode 16.4\n", "Xcode 16.4\nBuild 16F6\n", "Xcode\nBuild version 16F6\n"],
)
def test_xcode_version_output_requires_two_expected_fields(
    tmp_path: Path,
    xcode_output: str,
):
    fixture = make_archive(tmp_path)
    fixture.commands.xcode_output = xcode_output

    with pytest.raises(ArchiveValidationError, match="Xcode version output"):
        inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)


def test_command_failure_is_redacted(monkeypatch: pytest.MonkeyPatch):
    sentinel = "R2_SECRET_SENTINEL"

    def fail(*_args, **_kwargs):
        raise subprocess.CalledProcessError(1, ["git"], stderr=sentinel)

    monkeypatch.setattr(subprocess, "run", fail)

    with pytest.raises(ArchiveValidationError) as caught:
        run_command(["git", "rev-parse"])

    assert sentinel not in str(caught.value)
    assert "git" in str(caught.value)


def test_invalid_plist_is_rejected_before_commands(tmp_path: Path):
    fixture = make_archive(tmp_path)
    (fixture.archive / "Info.plist").write_bytes(b"not a plist")

    with pytest.raises(ArchiveValidationError, match="archive Info.plist"):
        inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)

    assert fixture.commands.calls == []


def test_non_dictionary_plist_is_rejected_before_commands(tmp_path: Path):
    fixture = make_archive(tmp_path)
    with (fixture.archive / "Info.plist").open("wb") as destination:
        plistlib.dump(["unexpected"], destination, fmt=plistlib.FMT_BINARY)

    with pytest.raises(ArchiveValidationError, match="archive Info.plist"):
        inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)

    assert fixture.commands.calls == []


def _called(calls: list[tuple[str, ...]], executable: str) -> bool:
    return any(call and call[0] == executable for call in calls)
