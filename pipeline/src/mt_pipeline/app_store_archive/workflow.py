"""Publish and recovery orchestration for retained App Store archives."""

from __future__ import annotations

import tempfile
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from tempfile import TemporaryDirectory

from .archive import CommandRunner, inspect_archive, run_command
from .model import (
    APP_BUNDLE_ID,
    AppStoreArchiveError,
    ArchiveIdentity,
    DsymUUID,
)
from .r2_store import (
    DownloadedPublication,
    R2ArchiveStore,
    RemotePublication,
    private_bucket,
)
from .staging import LocalArtifact, _rename_no_replace, stage_archive


class WorkflowError(AppStoreArchiveError):
    """Archive publication or recovery orchestration failed safely."""


@dataclass(frozen=True)
class PublishResult:
    identity: ArchiveIdentity
    local: LocalArtifact
    remote: RemotePublication


@dataclass(frozen=True)
class RetrieveResult:
    identity: ArchiveIdentity
    destination: Path
    archive_path: Path


def publish_archive(
    archive_path: Path,
    *,
    repo_root: Path,
    application_support_root: Path,
    layout_path: Path,
    client: object,
    captured_at: str,
    run: CommandRunner = run_command,
) -> PublishResult:
    identity = inspect_archive(archive_path, repo_root, run=run)
    local = stage_archive(identity, application_support_root, captured_at, run=run)
    store = R2ArchiveStore(client, private_bucket(layout_path))
    remote = store.publish(local)
    return PublishResult(identity=identity, local=local, remote=remote)


def retrieve_archive(
    version: str,
    build: str,
    destination: Path,
    *,
    repo_root: Path,
    layout_path: Path,
    client: object,
    requested_sha: str | None = None,
    run: CommandRunner = run_command,
) -> RetrieveResult:
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        raise WorkflowError("destination already exists")
    store = R2ArchiveStore(client, private_bucket(layout_path))
    sha = store.resolve_sha(version, build, requested_sha)
    with TemporaryDirectory(prefix="making-tracks-archive-download-") as temporary:
        downloaded = store.download(version, build, sha, Path(temporary))
        return restore_and_validate(
            downloaded,
            destination=destination,
            repo_root=repo_root,
            run=run,
        )


def restore_and_validate(
    downloaded: DownloadedPublication,
    destination: Path,
    repo_root: Path,
    run: CommandRunner = run_command,
) -> RetrieveResult:
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        raise WorkflowError("destination already exists")
    parent = destination.parent
    if parent.is_symlink() or not parent.is_dir():
        raise WorkflowError("destination parent must be a real directory")
    staging = Path(
        tempfile.mkdtemp(prefix=f".{destination.name}-staging-", dir=parent)
    )
    try:
        run(
            [
                "ditto",
                "-x",
                "-k",
                str(downloaded.archive_zip),
                str(staging),
            ]
        )
    except Exception as exc:
        raise WorkflowError(f"archive extraction failed; preserved at {staging}") from exc

    archive_paths = sorted(staging.glob("*.xcarchive"))
    if len(archive_paths) != 1 or archive_paths[0].name != "MakingTracks.xcarchive":
        raise WorkflowError(
            f"restored package has invalid archive layout; preserved at {staging}"
        )
    archive_path = archive_paths[0]
    try:
        identity = inspect_archive(archive_path, repo_root, run=run)
        _verify_restored_identity(identity, downloaded.manifest)
    except AppStoreArchiveError as exc:
        raise WorkflowError(
            f"restored archive identity mismatch; preserved at {staging}"
        ) from exc

    try:
        _rename_no_replace(staging, destination)
    except OSError as exc:
        raise WorkflowError(f"archive restore collision; preserved at {staging}") from exc
    return RetrieveResult(
        identity=identity,
        destination=destination,
        archive_path=destination / "MakingTracks.xcarchive",
    )


def _verify_restored_identity(
    identity: ArchiveIdentity,
    manifest: Mapping[str, object],
) -> None:
    dsym_values = manifest.get("dsym_uuids")
    if not isinstance(dsym_values, list):
        raise WorkflowError("manifest dSYM UUIDs are invalid")
    expected_dsyms: list[DsymUUID] = []
    for value in dsym_values:
        if not isinstance(value, Mapping):
            raise WorkflowError("manifest dSYM UUIDs are invalid")
        architecture = value.get("architecture")
        uuid = value.get("uuid")
        if not isinstance(architecture, str) or not isinstance(uuid, str):
            raise WorkflowError("manifest dSYM UUIDs are invalid")
        expected_dsyms.append(DsymUUID(architecture, uuid))
    expected = (
        manifest.get("bundle_id"),
        manifest.get("version"),
        manifest.get("build"),
        manifest.get("git_sha"),
        manifest.get("app_binary_sha256"),
        tuple(expected_dsyms),
    )
    actual = (
        identity.bundle_id,
        identity.version,
        identity.build,
        identity.git_sha,
        identity.app_binary_sha256,
        identity.dsym_uuids,
    )
    if identity.bundle_id != APP_BUNDLE_ID or actual != expected:
        raise WorkflowError("restored archive identity does not match manifest")
