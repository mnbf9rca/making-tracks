"""Immutable private-R2 publication and verified archive download."""

from __future__ import annotations

import hashlib
import json
import os
import re
import tempfile
from collections.abc import Mapping
from dataclasses import dataclass
from importlib import import_module
from pathlib import Path

from mt_pipeline.publish import r2 as publish_r2

from .manifest import ManifestValidationError, parse_manifest
from .model import (
    REMOTE_PREFIX,
    AppStoreArchiveError,
    ArchiveValidationError,
    sha256_file,
    validate_full_sha,
    validate_key_component,
)
from .staging import LocalArtifact


class ArchiveStorageError(AppStoreArchiveError):
    """Immutable archive storage or retrieval failed safely."""


@dataclass(frozen=True)
class RemotePublication:
    bucket: str
    prefix: str
    archive_sha256: str
    manifest_sha256: str


@dataclass(frozen=True)
class DownloadedPublication:
    root: Path
    archive_zip: Path
    manifest: Mapping[str, object]


class _MissingObject(Exception):
    pass


def private_bucket(layout_path: Path) -> str:
    try:
        layout = json.loads(Path(layout_path).read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ArchiveStorageError("R2 layout has no private_bucket") from exc
    if not isinstance(layout, dict):
        raise ArchiveStorageError("R2 layout has no private_bucket")
    bucket = layout.get("private_bucket")
    public_bucket = layout.get("public_bucket")
    if (
        not isinstance(bucket, str)
        or not bucket.strip()
        or bucket != bucket.strip()
        or bucket == public_bucket
    ):
        raise ArchiveStorageError("R2 layout has no distinct private_bucket")
    return bucket


def client_from_environment() -> object:
    try:
        publish_r2.require_boto3()
        publish_r2.require_upload_environment()
    except (publish_r2.Boto3Unavailable, publish_r2.R2EnvironmentUnavailable) as exc:
        raise ArchiveStorageError(str(exc)) from exc
    boto3 = import_module("boto3")
    try:
        return boto3.client(
            "s3",
            endpoint_url=os.environ["R2_S3_ENDPOINT"],
            aws_access_key_id=os.environ["R2_ACCESS_KEY_ID"],
            aws_secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"],
        )
    except Exception as exc:
        raise ArchiveStorageError("could not create R2 client") from exc


class R2ArchiveStore:
    def __init__(self, client: object, bucket: str):
        if not isinstance(bucket, str) or not bucket.strip():
            raise ArchiveStorageError("invalid private archive bucket")
        self.client = client
        self.bucket = bucket

    def publish(self, local: LocalArtifact) -> RemotePublication:
        version = local.leaf.parent.parent.name
        build = local.leaf.parent.name
        git_sha = local.leaf.name
        manifest = self._parse_manifest(local.manifest_bytes, version, build, git_sha)
        if hashlib.sha256(local.manifest_bytes).hexdigest() != local.manifest_sha256:
            raise ArchiveStorageError("local manifest digest mismatch")
        try:
            on_disk_manifest = local.manifest_path.read_bytes()
            archive_sha256, archive_bytes = sha256_file(local.archive_zip)
        except OSError as exc:
            raise ArchiveStorageError("local archive publication files are unavailable") from exc
        if on_disk_manifest != local.manifest_bytes:
            raise ArchiveStorageError("local manifest bytes mismatch")
        archive_object = manifest["archive_object"]
        if not isinstance(archive_object, Mapping):
            raise ArchiveStorageError("invalid local archive manifest")
        if (
            archive_sha256 != archive_object["sha256"]
            or archive_bytes != archive_object["bytes"]
        ):
            raise ArchiveStorageError("local archive digest mismatch")

        candidates = self._list_shas(version, build)
        conflicts = sorted(candidate for candidate in candidates if candidate != git_sha)
        if conflicts:
            raise ArchiveStorageError(
                "version/build already contains different SHA candidate(s): "
                + ", ".join(conflicts)
            )

        prefix = f"{REMOTE_PREFIX}/{version}/{build}/{git_sha}/"
        archive_key = str(archive_object["key"])
        manifest_key = prefix + "manifest.json"
        with tempfile.TemporaryDirectory(prefix="making-tracks-r2-verify-") as temporary:
            temporary_root = Path(temporary)
            self._ensure_object(
                archive_key,
                local.archive_zip,
                archive_sha256,
                archive_bytes,
                temporary_root,
            )
            self._ensure_object(
                manifest_key,
                local.manifest_path,
                local.manifest_sha256,
                len(local.manifest_bytes),
                temporary_root,
            )
        return RemotePublication(
            bucket=self.bucket,
            prefix=prefix,
            archive_sha256=archive_sha256,
            manifest_sha256=local.manifest_sha256,
        )

    def resolve_sha(
        self,
        version: str,
        build: str,
        requested_sha: str | None = None,
    ) -> str:
        version, build = _validate_version_build(version, build)
        candidates = self._list_shas(version, build)
        if requested_sha is not None:
            try:
                requested_sha = validate_full_sha(requested_sha)
            except ArchiveValidationError as exc:
                raise ArchiveStorageError("invalid requested archive SHA") from exc
            if requested_sha not in candidates:
                raise ArchiveStorageError("requested archive SHA is not present")
            return requested_sha
        if not candidates:
            raise ArchiveStorageError("no archive found for version/build")
        if len(candidates) != 1:
            raise ArchiveStorageError(
                "multiple archive SHA candidates: " + ", ".join(sorted(candidates))
            )
        return next(iter(candidates))

    def download(
        self,
        version: str,
        build: str,
        sha: str,
        temporary_root: Path,
    ) -> DownloadedPublication:
        version, build = _validate_version_build(version, build)
        try:
            sha = validate_full_sha(sha)
        except ArchiveValidationError as exc:
            raise ArchiveStorageError("invalid archive SHA") from exc
        temporary_root = Path(temporary_root)
        if temporary_root.is_symlink() or not temporary_root.is_dir():
            raise ArchiveStorageError("temporary download root must be a real directory")
        root = Path(tempfile.mkdtemp(prefix="app-store-archive-", dir=temporary_root))
        prefix = f"{REMOTE_PREFIX}/{version}/{build}/{sha}/"
        manifest_path = root / "manifest.json"
        try:
            self._download_to_path(prefix + "manifest.json", manifest_path)
            manifest_bytes = manifest_path.read_bytes()
            manifest = parse_manifest(manifest_bytes, version, build, sha)
        except (OSError, ManifestValidationError, ArchiveStorageError) as exc:
            raise ArchiveStorageError("invalid or unavailable archive manifest") from exc

        archive_object = manifest["archive_object"]
        if not isinstance(archive_object, Mapping):
            raise ArchiveStorageError("invalid archive manifest")
        archive_zip = root / "archive.xcarchive.zip"
        self._download_to_path(str(archive_object["key"]), archive_zip)
        try:
            digest, byte_count = sha256_file(archive_zip)
        except OSError as exc:
            raise ArchiveStorageError("downloaded archive is unavailable") from exc
        if digest != archive_object["sha256"] or byte_count != archive_object["bytes"]:
            raise ArchiveStorageError("downloaded archive digest mismatch")
        return DownloadedPublication(root=root, archive_zip=archive_zip, manifest=manifest)

    def _parse_manifest(
        self,
        data: bytes,
        version: str,
        build: str,
        git_sha: str,
    ) -> Mapping[str, object]:
        try:
            return parse_manifest(data, version, build, git_sha)
        except ManifestValidationError as exc:
            raise ArchiveStorageError("invalid local archive manifest") from exc

    def _list_shas(self, version: str, build: str) -> set[str]:
        version, build = _validate_version_build(version, build)
        prefix = f"{REMOTE_PREFIX}/{version}/{build}/"
        candidates: set[str] = set()
        continuation: str | None = None
        while True:
            arguments = {
                "Bucket": self.bucket,
                "Prefix": prefix,
                "Delimiter": "/",
            }
            if continuation is not None:
                arguments["ContinuationToken"] = continuation
            try:
                response = self.client.list_objects_v2(**arguments)
            except Exception as exc:
                raise ArchiveStorageError("could not list archive SHA candidates") from exc
            if not isinstance(response, Mapping):
                raise ArchiveStorageError("invalid archive SHA listing")
            common_prefixes = response.get("CommonPrefixes", [])
            if not isinstance(common_prefixes, list):
                raise ArchiveStorageError("invalid archive SHA listing")
            for item in common_prefixes:
                if not isinstance(item, Mapping) or not isinstance(item.get("Prefix"), str):
                    raise ArchiveStorageError("invalid archive SHA listing")
                child_prefix = item["Prefix"]
                if not child_prefix.startswith(prefix) or not child_prefix.endswith("/"):
                    raise ArchiveStorageError("invalid archive SHA listing")
                child = child_prefix[len(prefix) : -1]
                if re.fullmatch(r"[0-9a-f]{40}", child):
                    candidates.add(child)
            if response.get("IsTruncated") is not True:
                return candidates
            continuation_value = response.get("NextContinuationToken")
            if not isinstance(continuation_value, str) or not continuation_value:
                raise ArchiveStorageError("invalid archive SHA listing pagination")
            continuation = continuation_value

    def _ensure_object(
        self,
        key: str,
        source_path: Path,
        expected_digest: str,
        expected_bytes: int,
        temporary_root: Path,
    ) -> None:
        try:
            existing_matches = self._download_matches(
                key,
                expected_digest,
                expected_bytes,
                temporary_root,
            )
        except _MissingObject:
            try:
                with source_path.open("rb") as source:
                    self.client.put_object(
                        Bucket=self.bucket,
                        Key=key,
                        Body=source,
                        IfNoneMatch="*",
                    )
            except Exception as exc:
                if not _is_error(exc, "PreconditionFailed", "412"):
                    raise ArchiveStorageError("immutable archive object upload failed") from exc
                try:
                    race_matches = self._download_matches(
                        key,
                        expected_digest,
                        expected_bytes,
                        temporary_root,
                    )
                except _MissingObject as missing:
                    raise ArchiveStorageError("immutable archive precondition race lost") from missing
                if not race_matches:
                    raise ArchiveStorageError("different existing object at immutable key")
        else:
            if not existing_matches:
                raise ArchiveStorageError("different existing object at immutable key")

        try:
            round_trip_matches = self._download_matches(
                key,
                expected_digest,
                expected_bytes,
                temporary_root,
            )
        except _MissingObject as exc:
            raise ArchiveStorageError("archive object vanished during round-trip") from exc
        if not round_trip_matches:
            raise ArchiveStorageError("archive object round-trip digest mismatch")

    def _download_matches(
        self,
        key: str,
        expected_digest: str,
        expected_bytes: int,
        temporary_root: Path,
    ) -> bool:
        descriptor, raw_path = tempfile.mkstemp(prefix="object-", dir=temporary_root)
        os.close(descriptor)
        path = Path(raw_path)
        try:
            self._download_to_path(key, path, replace=True)
            digest, byte_count = sha256_file(path)
            return digest == expected_digest and byte_count == expected_bytes
        except _MissingObject:
            raise
        except OSError as exc:
            raise ArchiveStorageError("archive object verification failed") from exc

    def _download_to_path(self, key: str, path: Path, *, replace: bool = False) -> None:
        try:
            response = self.client.get_object(Bucket=self.bucket, Key=key)
        except Exception as exc:
            if _is_error(exc, "NoSuchKey", "NotFound", "404"):
                raise _MissingObject(key) from exc
            raise ArchiveStorageError("archive object download failed") from exc
        if not isinstance(response, Mapping) or not hasattr(response.get("Body"), "read"):
            raise ArchiveStorageError("archive object response is invalid")
        mode = "wb" if replace else "xb"
        try:
            with path.open(mode) as destination:
                body = response["Body"]
                while True:
                    chunk = body.read(1024 * 1024)
                    if not chunk:
                        break
                    if not isinstance(chunk, bytes):
                        raise ArchiveStorageError("archive object response is invalid")
                    destination.write(chunk)
        except ArchiveStorageError:
            raise
        except OSError as exc:
            raise ArchiveStorageError("archive object download path failed") from exc
        except Exception as exc:
            raise ArchiveStorageError("archive object body read failed") from exc


def _validate_version_build(version: str, build: str) -> tuple[str, str]:
    try:
        return (
            validate_key_component(version, "version"),
            validate_key_component(build, "build"),
        )
    except ArchiveValidationError as exc:
        raise ArchiveStorageError(str(exc)) from exc


def _is_error(exc: Exception, *codes: str) -> bool:
    response = getattr(exc, "response", None)
    if not isinstance(response, Mapping):
        return False
    error = response.get("Error")
    return isinstance(error, Mapping) and error.get("Code") in codes
