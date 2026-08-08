from __future__ import annotations

import hashlib
import json
import stat
from dataclasses import replace
from pathlib import Path

import pytest

from app_store_archive_helpers import (
    APP_UUID,
    FULL_GIT_SHA,
    FakeDittoCommands,
    make_archive,
)
from mt_pipeline.app_store_archive import staging as archive_staging
from mt_pipeline.app_store_archive.archive import inspect_archive
from mt_pipeline.app_store_archive.manifest import (
    ManifestValidationError,
    build_manifest,
    parse_manifest,
    serialize_manifest,
)
from mt_pipeline.app_store_archive.model import DsymUUID
from mt_pipeline.app_store_archive.staging import StagingError, stage_archive


CAPTURED_AT = "2026-08-07T00:00:00Z"
ARCHIVE_KEY = f"app-store-archives/1.0/1/{FULL_GIT_SHA}/archive.xcarchive.zip"
ARCHIVE_SHA = hashlib.sha256(b"deterministic-xcarchive-zip").hexdigest()


def test_manifest_has_exact_incident_fields_and_deterministic_serialization(
    tmp_path: Path,
):
    fixture = make_archive(
        tmp_path,
        app_uuids=(
            DsymUUID("x86_64", "FFFFFFFF-BBBB-CCCC-DDDD-EEEEEEEEEEEE"),
            APP_UUID,
        ),
    )
    identity = inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)

    manifest = build_manifest(
        identity,
        ARCHIVE_KEY,
        ARCHIVE_SHA,
        len(b"deterministic-xcarchive-zip"),
        CAPTURED_AT,
    )

    assert manifest == _valid_manifest(
        dsym_uuids=[
            {
                "architecture": "arm64",
                "uuid": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            },
            {
                "architecture": "x86_64",
                "uuid": "FFFFFFFF-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            },
        ]
    )
    expected = (
        json.dumps(manifest, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")
    assert serialize_manifest(manifest) == expected
    assert serialize_manifest(manifest).endswith(b"\n")


def test_parse_manifest_returns_valid_exact_schema():
    manifest = _valid_manifest()
    encoded = _encode(manifest)

    parsed = parse_manifest(encoded, "1.0", "1", FULL_GIT_SHA)

    assert parsed == manifest


@pytest.mark.parametrize(
    "mutation",
    [
        ("add", (), "unexpected", True),
        ("delete", (), "version", None),
        ("add", ("archive_object",), "unexpected", True),
        ("delete", ("archive_object",), "bytes", None),
        ("add", ("tool",), "unexpected", True),
        ("delete", ("tool",), "schema_version", None),
        ("add", ("xcode",), "unexpected", True),
        ("delete", ("xcode",), "build_version", None),
        ("add", ("dsym_uuids", 0), "unexpected", True),
        ("delete", ("dsym_uuids", 0), "uuid", None),
    ],
)
def test_parse_manifest_rejects_unknown_or_missing_fields(mutation):
    manifest = _valid_manifest()
    _mutate(manifest, mutation)

    with pytest.raises(ManifestValidationError, match="fields"):
        parse_manifest(_encode(manifest), "1.0", "1", FULL_GIT_SHA)


@pytest.mark.parametrize(
    ("path", "value", "message"),
    [
        (("schema",), "other-schema", "schema"),
        (("bundle_id",), "example.invalid.Other", "bundle"),
        (("version",), "../1.0", "version"),
        (("build",), "1/2", "build"),
        (("git_sha",), "A" * 40, "Git SHA"),
        (("archive_object", "key"), "public/archive.zip", "archive key"),
        (("archive_object", "sha256"), "A" * 64, "archive digest"),
        (("archive_object", "bytes"), True, "archive bytes"),
        (("archive_object", "bytes"), -1, "archive bytes"),
        (("app_binary_sha256",), "g" * 64, "app binary digest"),
        (("captured_at_utc",), "2026-08-07T00:00:00+00:00", "timestamp"),
        (("captured_at_utc",), "2026-08-07T00:00:00.000Z", "timestamp"),
        (("tool", "name"), "other-tool", "tool"),
        (("tool", "schema_version"), True, "tool"),
        (("tool", "schema_version"), 1.0, "tool"),
        (("xcode", "version"), "", "Xcode"),
        (("dsym_uuids",), [], "dSYM"),
    ],
)
def test_parse_manifest_rejects_invalid_values(path, value, message: str):
    manifest = _valid_manifest()
    _set_path(manifest, path, value)

    with pytest.raises(ManifestValidationError, match=message):
        parse_manifest(_encode(manifest), "1.0", "1", FULL_GIT_SHA)


@pytest.mark.parametrize(
    "dsym_uuids",
    [
        [
            {
                "architecture": "x86_64",
                "uuid": "FFFFFFFF-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            },
            {
                "architecture": "arm64",
                "uuid": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            },
        ],
        [
            {
                "architecture": "arm64",
                "uuid": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            },
            {
                "architecture": "arm64",
                "uuid": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            },
        ],
    ],
)
def test_parse_manifest_rejects_unsorted_or_duplicate_dsym_uuids(dsym_uuids):
    manifest = _valid_manifest(dsym_uuids=dsym_uuids)

    with pytest.raises(ManifestValidationError, match="dSYM UUIDs"):
        parse_manifest(_encode(manifest), "1.0", "1", FULL_GIT_SHA)


@pytest.mark.parametrize(
    ("version", "build", "sha"),
    [("2.0", "1", FULL_GIT_SHA), ("1.0", "2", FULL_GIT_SHA), ("1.0", "1", "f" * 40)],
)
def test_parse_manifest_rejects_requested_identity_mismatch(
    version: str,
    build: str,
    sha: str,
):
    with pytest.raises(ManifestValidationError, match="identity"):
        parse_manifest(_encode(_valid_manifest()), version, build, sha)


@pytest.mark.parametrize("data", [b"not json", b"[]", b"{}"])
def test_parse_manifest_rejects_malformed_or_incomplete_json(data: bytes):
    with pytest.raises(ManifestValidationError):
        parse_manifest(data, "1.0", "1", FULL_GIT_SHA)


def test_stage_archive_builds_caller_owned_leaf_without_gate_markers(tmp_path: Path):
    fixture = make_archive(tmp_path / "source")
    identity = inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)
    application_support = tmp_path / "Library/Application Support/making-tracks-releases"
    ditto = FakeDittoCommands()

    artifact = stage_archive(
        identity,
        application_support,
        CAPTURED_AT,
        run=ditto.run,
    )

    expected = application_support / f"archives/1.0/1/{FULL_GIT_SHA}"
    assert artifact.leaf == expected
    assert artifact.archive == expected / "MakingTracks.xcarchive"
    assert artifact.archive_zip == expected / "archive.xcarchive.zip"
    assert artifact.manifest_path == expected / "manifest.json"
    assert artifact.archive_zip.read_bytes() == b"deterministic-xcarchive-zip"
    assert artifact.manifest_path.read_bytes() == artifact.manifest_bytes
    assert artifact.manifest_sha256 == hashlib.sha256(artifact.manifest_bytes).hexdigest()
    assert parse_manifest(artifact.manifest_bytes, "1.0", "1", FULL_GIT_SHA)[
        "archive_object"
    ] == {
        "bytes": len(b"deterministic-xcarchive-zip"),
        "key": ARCHIVE_KEY,
        "sha256": ARCHIVE_SHA,
    }
    assert not any(path.name.startswith(".release-gate-") for path in expected.iterdir())
    staged_archive = Path(ditto.calls[0][2])
    staged_zip = Path(ditto.calls[1][6])
    assert staged_archive.parent.name.startswith(".archive-staging-")
    assert staged_archive.name == "MakingTracks.xcarchive"
    assert staged_zip == staged_archive.parent / "archive.xcarchive.zip"
    assert ditto.calls == [
        ("ditto", str(fixture.archive), str(staged_archive)),
        (
            "ditto",
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            str(staged_archive),
            str(staged_zip),
        ),
    ]


def test_stage_archive_rejects_symlink_application_support_root(tmp_path: Path):
    fixture = make_archive(tmp_path / "source")
    identity = inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)
    real_root = tmp_path / "real-root"
    real_root.mkdir()
    application_support = tmp_path / "linked-root"
    application_support.symlink_to(real_root, target_is_directory=True)
    ditto = FakeDittoCommands()

    with pytest.raises(StagingError, match="Application Support"):
        stage_archive(identity, application_support, CAPTURED_AT, run=ditto.run)

    assert ditto.calls == []


def test_stage_archive_rejects_non_directory_root_component(tmp_path: Path):
    fixture = make_archive(tmp_path / "source")
    identity = inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)
    application_support = tmp_path / "not-a-directory"
    application_support.write_text("occupied", encoding="utf-8")
    ditto = FakeDittoCommands()

    with pytest.raises(StagingError, match="Application Support"):
        stage_archive(identity, application_support, CAPTURED_AT, run=ditto.run)

    assert ditto.calls == []


def test_stage_archive_rejects_unsafe_identity_before_creating_root(tmp_path: Path):
    fixture = make_archive(tmp_path / "source")
    identity = inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)
    identity = replace(identity, version="../1.0")
    application_support = tmp_path / "Application Support"
    ditto = FakeDittoCommands()

    with pytest.raises(StagingError, match="unsafe version"):
        stage_archive(identity, application_support, CAPTURED_AT, run=ditto.run)

    assert not application_support.exists()
    assert ditto.calls == []


@pytest.mark.parametrize("fail_at", ["copy", "package"])
def test_stage_failure_preserves_unique_staging_directory(
    tmp_path: Path,
    fail_at: str,
):
    fixture = make_archive(tmp_path / "source")
    identity = inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)
    application_support = tmp_path / "Application Support"
    ditto = FakeDittoCommands(fail_at=fail_at)

    with pytest.raises(StagingError, match=r"\.archive-staging-") as caught:
        stage_archive(identity, application_support, CAPTURED_AT, run=ditto.run)

    sha_parent = application_support / "archives/1.0/1"
    staging = list(sha_parent.glob(".archive-staging-*"))
    assert len(staging) == 1
    assert str(staging[0]) in str(caught.value)
    assert not (sha_parent / FULL_GIT_SHA).exists()


def test_existing_different_packaged_archive_is_preserved_and_rejected(tmp_path: Path):
    fixture = make_archive(tmp_path / "source")
    identity = inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)
    application_support = tmp_path / "Application Support"
    first = stage_archive(
        identity,
        application_support,
        CAPTURED_AT,
        run=FakeDittoCommands().run,
    )
    original_zip = first.archive_zip.read_bytes()

    with pytest.raises(StagingError, match="different archive"):
        stage_archive(
            identity,
            application_support,
            "2026-08-07T00:01:00Z",
            run=FakeDittoCommands(package_bytes=b"different-archive-zip").run,
        )

    assert first.archive_zip.read_bytes() == original_zip
    assert len(list(first.leaf.parent.glob(".archive-staging-*"))) == 1


def test_existing_leaf_with_tampered_uploadable_archive_is_rejected(tmp_path: Path):
    fixture = make_archive(tmp_path / "source")
    identity = inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)
    application_support = tmp_path / "Application Support"
    first = stage_archive(
        identity,
        application_support,
        CAPTURED_AT,
        run=FakeDittoCommands().run,
    )
    existing_binary = (
        first.archive / "Products/Applications/MakingTracks.app/MakingTracks"
    )
    existing_binary.write_bytes(b"tampered-uploadable-archive")

    with pytest.raises(StagingError, match="different archive"):
        stage_archive(
            identity,
            application_support,
            "2026-08-07T00:01:00Z",
            run=FakeDittoCommands().run,
        )

    assert existing_binary.read_bytes() == b"tampered-uploadable-archive"
    assert len(list(first.leaf.parent.glob(".archive-staging-*"))) == 1


def test_existing_leaf_with_mode_drift_is_rejected(tmp_path: Path):
    fixture = make_archive(tmp_path / "source")
    identity = inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)
    application_support = tmp_path / "Application Support"
    first = stage_archive(
        identity,
        application_support,
        CAPTURED_AT,
        run=FakeDittoCommands().run,
    )
    existing_binary = (
        first.archive / "Products/Applications/MakingTracks.app/MakingTracks"
    )
    original_mode = existing_binary.stat().st_mode
    existing_binary.chmod(original_mode ^ stat.S_IXUSR)

    with pytest.raises(StagingError, match="different archive"):
        stage_archive(
            identity,
            application_support,
            "2026-08-07T00:01:00Z",
            run=FakeDittoCommands().run,
        )

    assert existing_binary.stat().st_mode == (original_mode ^ stat.S_IXUSR)
    assert len(list(first.leaf.parent.glob(".archive-staging-*"))) == 1


def test_existing_leaf_with_archive_root_mode_drift_is_rejected(tmp_path: Path):
    fixture = make_archive(tmp_path / "source")
    identity = inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)
    application_support = tmp_path / "Application Support"
    first = stage_archive(
        identity,
        application_support,
        CAPTURED_AT,
        run=FakeDittoCommands().run,
    )
    original_mode = first.archive.stat().st_mode
    first.archive.chmod(original_mode ^ stat.S_IWGRP)

    with pytest.raises(StagingError, match="different archive"):
        stage_archive(
            identity,
            application_support,
            "2026-08-07T00:01:00Z",
            run=FakeDittoCommands().run,
        )

    assert first.archive.stat().st_mode == (original_mode ^ stat.S_IWGRP)
    assert len(list(first.leaf.parent.glob(".archive-staging-*"))) == 1


def test_existing_invalid_manifest_is_preserved_and_rejected(tmp_path: Path):
    fixture = make_archive(tmp_path / "source")
    identity = inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)
    application_support = tmp_path / "Application Support"
    first = stage_archive(
        identity,
        application_support,
        CAPTURED_AT,
        run=FakeDittoCommands().run,
    )
    first.manifest_path.write_bytes(b"invalid manifest")

    with pytest.raises(StagingError, match="existing manifest"):
        stage_archive(
            identity,
            application_support,
            "2026-08-07T00:01:00Z",
            run=FakeDittoCommands().run,
        )

    assert first.manifest_path.read_bytes() == b"invalid manifest"
    assert len(list(first.leaf.parent.glob(".archive-staging-*"))) == 1


def test_existing_identical_leaf_is_idempotent_without_replacement(tmp_path: Path):
    fixture = make_archive(tmp_path / "source")
    identity = inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)
    application_support = tmp_path / "Application Support"
    first = stage_archive(
        identity,
        application_support,
        CAPTURED_AT,
        run=FakeDittoCommands().run,
    )
    inode = first.leaf.stat().st_ino

    second = stage_archive(
        identity,
        application_support,
        "2026-08-07T00:01:00Z",
        run=FakeDittoCommands().run,
    )

    assert second.leaf == first.leaf
    assert second.leaf.stat().st_ino == inode
    assert second.manifest_bytes == first.manifest_bytes
    assert list(first.leaf.parent.glob(".archive-staging-*")) == []


def test_rename_collision_preserves_staging_and_does_not_replace_final_leaf(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
):
    fixture = make_archive(tmp_path / "source")
    identity = inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)
    application_support = tmp_path / "Application Support"
    final_leaf = application_support / f"archives/1.0/1/{FULL_GIT_SHA}"
    original_finalize = archive_staging._rename_no_replace

    def collide(source: Path, target: Path):
        if source.name.startswith(".archive-staging-"):
            target.mkdir(parents=True)
            return original_finalize(source, target)
        return original_finalize(source, target)

    monkeypatch.setattr(archive_staging, "_rename_no_replace", collide)

    with pytest.raises(StagingError, match=r"\.archive-staging-"):
        stage_archive(
            identity,
            application_support,
            CAPTURED_AT,
            run=FakeDittoCommands().run,
        )

    assert final_leaf.is_dir()
    assert list(final_leaf.iterdir()) == []
    assert len(list(final_leaf.parent.glob(".archive-staging-*"))) == 1


def _valid_manifest(*, dsym_uuids=None) -> dict[str, object]:
    return {
        "app_binary_sha256": hashlib.sha256(b"app-binary").hexdigest(),
        "archive_object": {
            "bytes": len(b"deterministic-xcarchive-zip"),
            "key": ARCHIVE_KEY,
            "sha256": ARCHIVE_SHA,
        },
        "build": "1",
        "bundle_id": "app.making-tracks.MakingTracks",
        "captured_at_utc": CAPTURED_AT,
        "dsym_uuids": dsym_uuids
        if dsym_uuids is not None
        else [
            {
                "architecture": "arm64",
                "uuid": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            }
        ],
        "git_sha": FULL_GIT_SHA,
        "schema": "making-tracks-app-store-archive-v1",
        "tool": {"name": "scripts/app-store-archive.py", "schema_version": 1},
        "version": "1.0",
        "xcode": {"build_version": "16F6", "version": "16.4"},
    }


def _encode(value: object) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")


def _set_path(root: dict[str, object], path: tuple[object, ...], value: object) -> None:
    target: object = root
    for component in path[:-1]:
        target = target[component]  # type: ignore[index]
    target[path[-1]] = value  # type: ignore[index]


def _mutate(root: dict[str, object], mutation: tuple[object, ...]) -> None:
    operation, path, key, value = mutation
    target: object = root
    for component in path:
        target = target[component]  # type: ignore[index]
    if operation == "add":
        target[key] = value  # type: ignore[index]
    else:
        del target[key]  # type: ignore[index]
