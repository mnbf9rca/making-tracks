"""Caller-owned local staging for retained App Store archives."""

from __future__ import annotations

import ctypes
import errno
import hashlib
import os
import shutil
import tempfile
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

from .archive import CommandRunner, inspect_archive, run_command
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
from .progress import run_blocking_phase


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
    *,
    repo_root: Path | None = None,
    source_tree_digest: str | None = None,
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
        run_blocking_phase(
            "app_store_archive.copy",
            total_bytes=_archive_tree_bytes(identity.archive_path),
            operation=lambda: run(
                ["ditto", str(identity.archive_path), str(staging_archive)]
            ),
        )
        if (repo_root is None) != (source_tree_digest is None):
            raise StagingError("archive staging source evidence is incomplete")
        if repo_root is not None and source_tree_digest is not None:
            _verify_staged_archive(
                staging_archive,
                identity,
                source_tree_digest,
                Path(repo_root),
                run,
            )
        run_blocking_phase(
            "app_store_archive.zip",
            total_bytes=_archive_tree_bytes(staging_archive),
            operation=lambda: run(
                [
                    "ditto",
                    "-c",
                    "-k",
                    "--sequesterRsrc",
                    "--keepParent",
                    str(staging_archive),
                    str(staging_zip),
                ]
            ),
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
        _rename_no_replace(staging, final_leaf)
    except OSError as exc:
        raise StagingError(f"archive rename failed; preserved at {staging}") from exc
    _fsync_directory(parent)
    return _artifact_at(final_leaf, manifest_bytes)


def _verify_staged_archive(
    staging_archive: Path,
    source_identity: ArchiveIdentity,
    source_tree_digest: str,
    repo_root: Path,
    run: CommandRunner,
) -> None:
    try:
        staged_identity = inspect_archive(staging_archive, repo_root, run=run)
        intrinsic_matches = (
            staged_identity.bundle_id,
            staged_identity.version,
            staged_identity.build,
            staged_identity.git_sha,
            staged_identity.app_binary_sha256,
            staged_identity.dsym_uuids,
        ) == (
            source_identity.bundle_id,
            source_identity.version,
            source_identity.build,
            source_identity.git_sha,
            source_identity.app_binary_sha256,
            source_identity.dsym_uuids,
        )
        if not intrinsic_matches or _archive_tree_digest(staging_archive) != source_tree_digest:
            raise StagingError("staged archive differs from inspected source")
    except (ArchiveValidationError, OSError) as exc:
        raise StagingError("staged archive differs from inspected source") from exc


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
    if _without_capture_environment(existing_manifest) != _without_capture_environment(
        candidate_manifest
    ):
        raise StagingError(
            f"existing leaf contains a different archive; staging preserved at {candidate.leaf}"
        )
    try:
        if _archive_tree_digest(existing_archive) != _archive_tree_digest(candidate.archive):
            raise StagingError(
                f"existing leaf contains a different archive; staging preserved at {candidate.leaf}"
            )
    except OSError as exc:
        raise StagingError(
            f"existing archive is invalid; staging preserved at {candidate.leaf}"
        ) from exc

    shutil.rmtree(candidate.leaf)
    return _artifact_at(final_leaf, existing_bytes)


def _without_capture_environment(value: Mapping[str, object]) -> dict[str, object]:
    comparable = dict(value)
    comparable.pop("captured_at_utc", None)
    comparable.pop("xcode", None)
    return comparable


def _archive_tree_digest(root: Path) -> str:
    if root.is_symlink() or not root.is_dir():
        raise OSError("invalid archive tree")
    digest = hashlib.sha256()
    root_mode = root.stat().st_mode & 0o7777
    digest.update(b"D\0.\0" + oct(root_mode).encode("ascii") + b"\0")
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix().encode("utf-8")
        if path.is_symlink():
            raise OSError("symlink in archive tree")
        mode = path.stat().st_mode & 0o7777
        if path.is_dir():
            digest.update(b"D\0" + relative + b"\0" + oct(mode).encode("ascii") + b"\0")
        elif path.is_file():
            file_digest, byte_count = sha256_file(path)
            digest.update(
                b"F\0"
                + relative
                + b"\0"
                + oct(mode).encode("ascii")
                + b"\0"
                + str(byte_count).encode("ascii")
                + b"\0"
                + file_digest.encode("ascii")
                + b"\0"
            )
        else:
            raise OSError("invalid archive tree entry")
    return digest.hexdigest()


def _archive_tree_bytes(root: Path) -> int:
    if root.is_symlink() or not root.is_dir():
        raise OSError("invalid archive tree")
    total = 0
    for path in root.rglob("*"):
        if path.is_symlink():
            raise OSError("symlink in archive tree")
        if path.is_file():
            total += path.stat().st_size
        elif not path.is_dir():
            raise OSError("invalid archive tree entry")
    return total


def _rename_no_replace(source: Path, destination: Path) -> None:
    try:
        renamex_np = ctypes.CDLL(None, use_errno=True).renamex_np
    except AttributeError as exc:
        raise OSError(errno.ENOTSUP, "no-replace rename is unavailable") from exc
    renamex_np.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    renamex_np.restype = ctypes.c_int
    if renamex_np(os.fsencode(source), os.fsencode(destination), 0x00000004) != 0:
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), destination)


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
