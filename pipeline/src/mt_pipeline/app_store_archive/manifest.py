"""Deterministic release-archive manifest construction and validation."""

from __future__ import annotations

import json
import re
from collections.abc import Mapping
from datetime import datetime, timezone

from .model import (
    APP_BUNDLE_ID,
    MANIFEST_SCHEMA,
    REMOTE_PREFIX,
    AppStoreArchiveError,
    ArchiveIdentity,
    ArchiveValidationError,
    validate_full_sha,
    validate_key_component,
)


class ManifestValidationError(AppStoreArchiveError):
    """A release-archive manifest is malformed or contradicts its key."""


_TOP_LEVEL_FIELDS = {
    "app_binary_sha256",
    "archive_object",
    "build",
    "bundle_id",
    "captured_at_utc",
    "dsym_uuids",
    "git_sha",
    "schema",
    "tool",
    "version",
    "xcode",
}
_ARCHIVE_FIELDS = {"bytes", "key", "sha256"}
_TOOL_FIELDS = {"name", "schema_version"}
_XCODE_FIELDS = {"build_version", "version"}
_DSYM_FIELDS = {"architecture", "uuid"}
_DIGEST = re.compile(r"[0-9a-f]{64}")
_UUID = re.compile(r"[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}")
_ARCHITECTURE = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}")


def build_manifest(
    identity: ArchiveIdentity,
    archive_key: str,
    archive_sha256: str,
    archive_bytes: int,
    captured_at: str,
) -> dict[str, object]:
    version = _safe_component(identity.version, "version")
    build = _safe_component(identity.build, "build")
    git_sha = _full_sha(identity.git_sha)
    expected_key = _archive_key(version, build, git_sha)
    if archive_key != expected_key:
        raise ManifestValidationError("invalid archive key")
    _require_digest(archive_sha256, "archive digest")
    _require_size(archive_bytes, "archive bytes")
    _require_digest(identity.app_binary_sha256, "app binary digest")
    _validate_timestamp(captured_at)
    dsym_uuids = [
        {"architecture": item.architecture, "uuid": item.uuid}
        for item in sorted(identity.dsym_uuids)
    ]
    _validate_dsym_uuids(dsym_uuids)
    if identity.bundle_id != APP_BUNDLE_ID:
        raise ManifestValidationError("invalid bundle identifier")
    if not identity.xcode_version or not identity.xcode_build:
        raise ManifestValidationError("invalid Xcode fields")
    return {
        "app_binary_sha256": identity.app_binary_sha256,
        "archive_object": {
            "bytes": archive_bytes,
            "key": archive_key,
            "sha256": archive_sha256,
        },
        "build": build,
        "bundle_id": identity.bundle_id,
        "captured_at_utc": captured_at,
        "dsym_uuids": dsym_uuids,
        "git_sha": git_sha,
        "schema": MANIFEST_SCHEMA,
        "tool": {"name": "scripts/app-store-archive.py", "schema_version": 1},
        "version": version,
        "xcode": {
            "build_version": identity.xcode_build,
            "version": identity.xcode_version,
        },
    }


def serialize_manifest(value: Mapping[str, object]) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")


def parse_manifest(
    data: bytes,
    expected_version: str,
    expected_build: str,
    expected_sha: str,
) -> Mapping[str, object]:
    try:
        value = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError, TypeError) as exc:
        raise ManifestValidationError("invalid manifest JSON") from exc
    if not isinstance(value, dict):
        raise ManifestValidationError("invalid manifest fields")
    _require_fields(value, _TOP_LEVEL_FIELDS, "manifest")

    version = _safe_component(_required_string(value, "version", "version"), "version")
    build = _safe_component(_required_string(value, "build", "build"), "build")
    git_sha = _full_sha(_required_string(value, "git_sha", "Git SHA"))
    try:
        requested_version = validate_key_component(expected_version, "version")
        requested_build = validate_key_component(expected_build, "build")
        requested_sha = validate_full_sha(expected_sha)
    except ArchiveValidationError as exc:
        raise ManifestValidationError("invalid requested manifest identity") from exc
    if (version, build, git_sha) != (
        requested_version,
        requested_build,
        requested_sha,
    ):
        raise ManifestValidationError("manifest identity does not match requested key")

    if value["schema"] != MANIFEST_SCHEMA:
        raise ManifestValidationError("invalid manifest schema")
    if value["bundle_id"] != APP_BUNDLE_ID:
        raise ManifestValidationError("invalid manifest bundle identifier")
    _require_digest(value["app_binary_sha256"], "app binary digest")
    captured_at = _required_string(value, "captured_at_utc", "capture timestamp")
    _validate_timestamp(captured_at)

    archive_object = value["archive_object"]
    if not isinstance(archive_object, dict):
        raise ManifestValidationError("invalid archive object fields")
    _require_fields(archive_object, _ARCHIVE_FIELDS, "archive object")
    archive_key = _required_string(archive_object, "key", "archive key")
    if archive_key != _archive_key(version, build, git_sha):
        raise ManifestValidationError("invalid archive key")
    _require_digest(archive_object["sha256"], "archive digest")
    _require_size(archive_object["bytes"], "archive bytes")

    tool = value["tool"]
    if not isinstance(tool, dict):
        raise ManifestValidationError("invalid tool fields")
    _require_fields(tool, _TOOL_FIELDS, "tool")
    if (
        tool["name"] != "scripts/app-store-archive.py"
        or type(tool["schema_version"]) is not int
        or tool["schema_version"] != 1
    ):
        raise ManifestValidationError("invalid manifest tool")

    xcode = value["xcode"]
    if not isinstance(xcode, dict):
        raise ManifestValidationError("invalid Xcode fields")
    _require_fields(xcode, _XCODE_FIELDS, "Xcode")
    _required_string(xcode, "version", "Xcode version")
    _required_string(xcode, "build_version", "Xcode build version")

    _validate_dsym_uuids(value["dsym_uuids"])
    return value


def _archive_key(version: str, build: str, git_sha: str) -> str:
    return f"{REMOTE_PREFIX}/{version}/{build}/{git_sha}/archive.xcarchive.zip"


def _safe_component(value: str, label: str) -> str:
    try:
        return validate_key_component(value, label)
    except ArchiveValidationError as exc:
        raise ManifestValidationError(str(exc)) from exc


def _full_sha(value: str) -> str:
    try:
        return validate_full_sha(value)
    except ArchiveValidationError as exc:
        raise ManifestValidationError(str(exc)) from exc


def _require_fields(
    value: Mapping[str, object],
    expected: set[str],
    label: str,
) -> None:
    if set(value) != expected:
        raise ManifestValidationError(f"invalid {label} fields")


def _required_string(
    value: Mapping[str, object],
    key: str,
    label: str,
) -> str:
    result = value.get(key)
    if not isinstance(result, str) or not result:
        raise ManifestValidationError(f"invalid {label}")
    return result


def _require_digest(value: object, label: str) -> None:
    if not isinstance(value, str) or not _DIGEST.fullmatch(value):
        raise ManifestValidationError(f"invalid {label}")


def _require_size(value: object, label: str) -> None:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ManifestValidationError(f"invalid {label}")


def _validate_timestamp(value: str) -> None:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise ManifestValidationError("invalid capture timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ManifestValidationError("invalid capture timestamp") from exc
    normalized = parsed.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if parsed.utcoffset() != timezone.utc.utcoffset(parsed) or normalized != value:
        raise ManifestValidationError("invalid capture timestamp")


def _validate_dsym_uuids(value: object) -> None:
    if not isinstance(value, list) or not value:
        raise ManifestValidationError("invalid dSYM UUIDs")
    normalized: list[tuple[str, str]] = []
    for entry in value:
        if not isinstance(entry, dict):
            raise ManifestValidationError("invalid dSYM UUID fields")
        _require_fields(entry, _DSYM_FIELDS, "dSYM UUID")
        architecture = entry.get("architecture")
        uuid = entry.get("uuid")
        if (
            not isinstance(architecture, str)
            or not _ARCHITECTURE.fullmatch(architecture)
            or not isinstance(uuid, str)
            or not _UUID.fullmatch(uuid)
        ):
            raise ManifestValidationError("invalid dSYM UUIDs")
        normalized.append((architecture, uuid))
    if normalized != sorted(normalized) or len(set(normalized)) != len(normalized):
        raise ManifestValidationError("invalid dSYM UUIDs")
