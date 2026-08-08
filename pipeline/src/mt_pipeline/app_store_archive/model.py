"""Shared archive-retention records and validation helpers."""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path


APP_BUNDLE_ID = "app.making-tracks.MakingTracks"
REMOTE_PREFIX = "app-store-archives"
MANIFEST_SCHEMA = "making-tracks-app-store-archive-v1"


class AppStoreArchiveError(RuntimeError):
    """Expected, redaction-safe release archive failure."""


class ArchiveValidationError(AppStoreArchiveError):
    """Archive identity or symbolication evidence is invalid."""


@dataclass(frozen=True, order=True)
class DsymUUID:
    architecture: str
    uuid: str


@dataclass(frozen=True)
class ArchiveIdentity:
    archive_path: Path
    app_path: Path
    app_binary: Path
    dsym_binary: Path
    bundle_id: str
    version: str
    build: str
    git_sha: str
    app_binary_sha256: str
    dsym_uuids: tuple[DsymUUID, ...]
    xcode_version: str
    xcode_build: str


def validate_key_component(value: str, label: str) -> str:
    if (
        not isinstance(value, str)
        or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", value)
        or value in {".", ".."}
    ):
        raise ArchiveValidationError(f"unsafe {label}")
    return value


def validate_full_sha(value: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{40}", value):
        raise ArchiveValidationError(
            "Git SHA must be 40 lowercase hexadecimal characters"
        )
    return value


def sha256_file(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size
