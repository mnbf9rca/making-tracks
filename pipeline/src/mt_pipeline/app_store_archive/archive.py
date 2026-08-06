"""Inspect an Organizer archive and prove its release identity."""

from __future__ import annotations

import plistlib
import re
import subprocess
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path, PurePosixPath

from .model import (
    APP_BUNDLE_ID,
    ArchiveIdentity,
    ArchiveValidationError,
    DsymUUID,
    sha256_file,
    validate_full_sha,
    validate_key_component,
)


CommandRunner = Callable[[Sequence[str]], str]

_UUID_LINE = re.compile(
    r"^UUID: ([0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}) "
    r"\(([^()\s]+)\) .+$"
)
_GIT_STAMP = re.compile(r"[0-9a-fA-F]{4,40}")


def run_command(args: Sequence[str]) -> str:
    try:
        result = subprocess.run(
            list(args),
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        executable = Path(args[0]).name if args else "command"
        raise ArchiveValidationError(f"command failed: {executable}") from exc
    return result.stdout


def parse_dwarfdump(stdout: str) -> tuple[DsymUUID, ...]:
    nonempty_lines = [line for line in stdout.splitlines() if line.strip()]
    parsed = {
        DsymUUID(match.group(2), match.group(1).upper())
        for line in nonempty_lines
        if (match := _UUID_LINE.fullmatch(line))
    }
    if not parsed or len(parsed) != len(nonempty_lines):
        raise ArchiveValidationError("invalid dwarfdump UUID output")
    return tuple(sorted(parsed))


def inspect_archive(
    archive_path: Path,
    repo_root: Path,
    run: CommandRunner = run_command,
) -> ArchiveIdentity:
    archive_path = Path(archive_path)
    repo_root = Path(repo_root)
    if archive_path.is_symlink() or not archive_path.is_dir():
        raise ArchiveValidationError("archive path must be a real directory")
    if archive_path.suffix != ".xcarchive":
        raise ArchiveValidationError("archive path must end in .xcarchive")

    archive_info = _load_plist(archive_path / "Info.plist", "archive Info.plist")
    properties = archive_info.get("ApplicationProperties")
    if not isinstance(properties, Mapping):
        raise ArchiveValidationError("archive Info.plist has invalid ApplicationProperties")

    applications = archive_path / "Products/Applications"
    app_paths = (
        sorted(
            path
            for path in applications.iterdir()
            if path.suffix == ".app" and path.is_dir() and not path.is_symlink()
        )
        if applications.is_dir() and not applications.is_symlink()
        else []
    )
    if len(app_paths) != 1:
        raise ArchiveValidationError("archive must contain exactly one application")
    app_path = app_paths[0]

    application_path = _required_string(properties, "ApplicationPath", "archive")
    application_parts = PurePosixPath(application_path)
    if (
        application_parts.is_absolute()
        or application_parts.parts != ("Applications", app_path.name)
        or archive_path / "Products" / Path(*application_parts.parts) != app_path
    ):
        raise ArchiveValidationError("archive ApplicationPath does not name the application")

    app_info = _load_plist(app_path / "Info.plist", "app Info.plist")
    archive_bundle_id = _required_string(properties, "CFBundleIdentifier", "archive")
    app_bundle_id = _required_string(app_info, "CFBundleIdentifier", "app")
    if archive_bundle_id != app_bundle_id or archive_bundle_id != APP_BUNDLE_ID:
        raise ArchiveValidationError("invalid bundle identifier")

    version = _matching_identity(
        properties,
        app_info,
        "CFBundleShortVersionString",
        "version",
    )
    build = _matching_identity(properties, app_info, "CFBundleVersion", "build")
    validate_key_component(version, "version")
    validate_key_component(build, "build")

    executable = _required_string(app_info, "CFBundleExecutable", "app")
    if executable in {".", ".."} or Path(executable).name != executable:
        raise ArchiveValidationError("invalid app executable name")
    app_binary = app_path / executable
    _require_nonempty_file(app_binary, "app executable")

    dsym_binary = (
        archive_path
        / f"dSYMs/{app_path.name}.dSYM/Contents/Resources/DWARF/{executable}"
    )
    _require_nonempty_file(dsym_binary, "app dSYM")

    build_info = _load_plist(app_path / "BuildInfo.plist", "BuildInfo.plist")
    git_stamp = _required_string(build_info, "GitCommit", "BuildInfo.plist")
    if not _GIT_STAMP.fullmatch(git_stamp):
        raise ArchiveValidationError("archive Git commit is not an unambiguous full SHA")
    full_sha = run(
        [
            "git",
            "-C",
            str(repo_root),
            "rev-parse",
            "--verify",
            f"{git_stamp}^{{commit}}",
        ]
    ).strip()
    if (
        not re.fullmatch(r"[0-9a-f]{40}", full_sha)
        or not full_sha.startswith(git_stamp.lower())
    ):
        raise ArchiveValidationError("archive Git commit is not an unambiguous full SHA")
    validate_full_sha(full_sha)

    app_uuids = parse_dwarfdump(
        run(["xcrun", "dwarfdump", "--uuid", str(app_binary)])
    )
    dsym_uuids = parse_dwarfdump(
        run(["xcrun", "dwarfdump", "--uuid", str(dsym_binary)])
    )
    if app_uuids != dsym_uuids:
        raise ArchiveValidationError("app and dSYM UUIDs do not match")

    app_binary_sha256, _ = sha256_file(app_binary)
    xcode_version, xcode_build = _parse_xcode_version(run(["xcodebuild", "-version"]))
    return ArchiveIdentity(
        archive_path=archive_path,
        app_path=app_path,
        app_binary=app_binary,
        dsym_binary=dsym_binary,
        bundle_id=archive_bundle_id,
        version=version,
        build=build,
        git_sha=full_sha,
        app_binary_sha256=app_binary_sha256,
        dsym_uuids=dsym_uuids,
        xcode_version=xcode_version,
        xcode_build=xcode_build,
    )


def _load_plist(path: Path, label: str) -> Mapping[str, object]:
    _require_nonempty_file(path, label)
    try:
        with path.open("rb") as source:
            value = plistlib.load(source)
    except (OSError, plistlib.InvalidFileException, ValueError, TypeError) as exc:
        raise ArchiveValidationError(f"invalid {label}") from exc
    if not isinstance(value, Mapping):
        raise ArchiveValidationError(f"invalid {label}")
    return value


def _required_string(
    value: Mapping[str, object],
    key: str,
    label: str,
) -> str:
    result = value.get(key)
    if not isinstance(result, str) or not result:
        raise ArchiveValidationError(f"invalid {label} {key}")
    return result


def _matching_identity(
    archive: Mapping[str, object],
    app: Mapping[str, object],
    key: str,
    label: str,
) -> str:
    archive_value = _required_string(archive, key, "archive")
    app_value = _required_string(app, key, "app")
    if archive_value != app_value:
        raise ArchiveValidationError(f"archive and app {label} do not match")
    return archive_value


def _require_nonempty_file(path: Path, label: str) -> None:
    try:
        valid = not path.is_symlink() and path.is_file() and path.stat().st_size > 0
    except OSError:
        valid = False
    if not valid:
        raise ArchiveValidationError(f"invalid {label}")


def _parse_xcode_version(stdout: str) -> tuple[str, str]:
    lines = stdout.splitlines()
    if (
        len(lines) != 2
        or not lines[0].startswith("Xcode ")
        or not lines[0][len("Xcode ") :]
        or not lines[1].startswith("Build version ")
        or not lines[1][len("Build version ") :]
    ):
        raise ArchiveValidationError("invalid Xcode version output")
    return lines[0][len("Xcode ") :], lines[1][len("Build version ") :]
