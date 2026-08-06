"""Caller-owned local staging for retained App Store archives."""

from __future__ import annotations

import hashlib
import os
import shutil
import tempfile
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

from .archive import CommandRunner, run_command
from .manifest import (
    ManifestValidationError,
    build_manifest,
    parse_manifest,
    serialize_manifest,
)
from .model import (
    REMOTE_PREFIX,
    AppStoreArchiveError,
    ArchiveIdentity,
    ArchiveValidationError,
    sha256_file,
    validate_full_sha,
    validate_key_component,
)


class StagingError(AppStoreArchiveError):
    """Caller-owned archive staging failed without replacing existing evidence."""


@dataclass(frozen=True)
class LocalArtifact:
    leaf: Path
    archive: Path
    archive_zip: Path
    manifest_path: Path
    manifest_bytes: bytes
    manifest_sha256: str


def stage_archive(
    identity: ArchiveIdentity,
    application_support_root: Path,
    captured_at: str,
    run: CommandRunner = run_command,
) -> LocalArtifact:
    application_support_root = Path(application_support_root)
    try:
        version = validate_key_component(identity.version, "version")
        build = validate_key_component(identity.build, "build")
        git_sha = validate_full_sha(identity.git_sha)
    except ArchiveValidationError as exc:
        raise StagingError(str(exc)) from exc
    _ensure_real_directory(application_support_root, "Application Support")

    parent = application_support_root
    for component in ("archives", version, build):
        parent = parent / component
        _ensure_real_directory(parent, "Application Support")
    final_leaf = parent / git_sha
    staging = Path(tempfile.mkdtemp(prefix=".archive-staging-", dir=parent))
    staging_archive = staging / "MakingTracks.xcarchive"
    staging_zip = staging / "archive.xcarchive.zip"
    manifest_path = staging / "manifest.json"

    try:
        run(["ditto", str(identity.archive_path), str(staging_archive)])
        run(
            [
                "ditto",
                "-c",
                "-k",
                "--sequesterRsrc",
                "--keepParent",
                str(staging_archive),
                str(staging_zip),
            ]
        )
    except Exception as exc:
        raise StagingError(f"archive staging failed; preserved at {staging}") from exc
    if staging_zip.is_symlink() or not staging_zip.is_file():
        raise StagingError(f"archive package missing; preserved at {staging}")

    try:
        archive_sha256, archive_bytes = sha256_file(staging_zip)
        archive_key = (
            f"{REMOTE_PREFIX}/{version}/{build}/{git_sha}/archive.xcarchive.zip"
        )
        manifest = build_manifest(
            identity,
            archive_key,
            archive_sha256,
            archive_bytes,
            captured_at,
        )
        manifest_bytes = serialize_manifest(manifest)
        manifest_sha256 = hashlib.sha256(manifest_bytes).hexdigest()
        _fsync_file(staging_zip)
        _write_exclusive(manifest_path, manifest_bytes)
        _fsync_directory(staging)
    except (OSError, ManifestValidationError) as exc:
        raise StagingError(f"archive staging failed; preserved at {staging}") from exc

    candidate = LocalArtifact(
        leaf=staging,
        archive=staging_archive,
        archive_zip=staging_zip,
        manifest_path=manifest_path,
        manifest_bytes=manifest_bytes,
        manifest_sha256=manifest_sha256,
    )
    if final_leaf.exists() or final_leaf.is_symlink():
        return _accept_existing_or_preserve(
            candidate,
            final_leaf,
            version,
            build,
            git_sha,
            manifest,
        )
    try:
        staging.rename(final_leaf)
    except OSError as exc:
        raise StagingError(f"archive rename failed; preserved at {staging}") from exc
    _fsync_directory(parent)
    return _artifact_at(final_leaf, manifest_bytes)


def _accept_existing_or_preserve(
    candidate: LocalArtifact,
    final_leaf: Path,
    version: str,
    build: str,
    git_sha: str,
    candidate_manifest: Mapping[str, object],
) -> LocalArtifact:
    if final_leaf.is_symlink() or not final_leaf.is_dir():
        raise StagingError(
            f"existing archive leaf is invalid; staging preserved at {candidate.leaf}"
        )
    existing_manifest_path = final_leaf / "manifest.json"
    try:
        if existing_manifest_path.is_symlink() or not existing_manifest_path.is_file():
            raise ManifestValidationError("invalid existing manifest")
        existing_bytes = existing_manifest_path.read_bytes()
        existing_manifest = parse_manifest(existing_bytes, version, build, git_sha)
    except (OSError, ManifestValidationError) as exc:
        raise StagingError(
            f"invalid existing manifest; staging preserved at {candidate.leaf}"
        ) from exc

    existing_zip = final_leaf / "archive.xcarchive.zip"
    existing_archive = final_leaf / "MakingTracks.xcarchive"
    try:
        if (
            existing_zip.is_symlink()
            or not existing_zip.is_file()
            or existing_archive.is_symlink()
            or not existing_archive.is_dir()
        ):
            raise OSError("invalid existing archive files")
        digest, byte_count = sha256_file(existing_zip)
    except OSError as exc:
        raise StagingError(
            f"existing archive is invalid; staging preserved at {candidate.leaf}"
        ) from exc
    archive_object = existing_manifest["archive_object"]
    if not isinstance(archive_object, Mapping):
        raise StagingError(
            f"invalid existing manifest; staging preserved at {candidate.leaf}"
        )
    if digest != archive_object["sha256"] or byte_count != archive_object["bytes"]:
        raise StagingError(
            f"existing leaf contains a different archive; staging preserved at {candidate.leaf}"
        )
    if _without_capture(existing_manifest) != _without_capture(candidate_manifest):
        raise StagingError(
            f"existing leaf contains a different archive; staging preserved at {candidate.leaf}"
        )

    shutil.rmtree(candidate.leaf)
    return _artifact_at(final_leaf, existing_bytes)


def _without_capture(value: Mapping[str, object]) -> dict[str, object]:
    comparable = dict(value)
    comparable.pop("captured_at_utc", None)
    return comparable


def _artifact_at(leaf: Path, manifest_bytes: bytes) -> LocalArtifact:
    return LocalArtifact(
        leaf=leaf,
        archive=leaf / "MakingTracks.xcarchive",
        archive_zip=leaf / "archive.xcarchive.zip",
        manifest_path=leaf / "manifest.json",
        manifest_bytes=manifest_bytes,
        manifest_sha256=hashlib.sha256(manifest_bytes).hexdigest(),
    )


def _ensure_real_directory(path: Path, label: str) -> None:
    missing: list[Path] = []
    cursor = path
    while not cursor.exists() and not cursor.is_symlink():
        missing.append(cursor)
        if cursor == cursor.parent:
            break
        cursor = cursor.parent
    if cursor.is_symlink() or not cursor.is_dir():
        raise StagingError(f"invalid {label} directory")
    for directory in reversed(missing):
        try:
            directory.mkdir()
        except OSError as exc:
            raise StagingError(f"invalid {label} directory") from exc
        if directory.is_symlink() or not directory.is_dir():
            raise StagingError(f"invalid {label} directory")


def _write_exclusive(path: Path, data: bytes) -> None:
    with path.open("xb") as destination:
        destination.write(data)
        destination.flush()
        os.fsync(destination.fileno())


def _fsync_file(path: Path) -> None:
    with path.open("rb") as source:
        os.fsync(source.fileno())


def _fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
