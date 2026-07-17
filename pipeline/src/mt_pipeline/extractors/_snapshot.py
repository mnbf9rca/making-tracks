"""Shared register snapshot acquisition and provenance helpers."""

from __future__ import annotations

import hashlib
import json
import logging
import pathlib
import time

from .. import fetch

MAX_SIDECAR_BYTES = 64 * 1024
MAX_SNAPSHOT_BYTES = 512 * 1024 * 1024

_log = logging.getLogger(__name__)


class SnapshotError(Exception):
    pass


class SnapshotParseError(SnapshotError):
    pass


class SnapshotTooLargeError(SnapshotError):
    pass


class SnapshotPendingError(SnapshotParseError):
    pass


class ProvenanceError(SnapshotError):
    pass


def check_snapshot_size(path) -> None:
    snapshot = pathlib.Path(path)
    if not snapshot.exists():
        raise SnapshotParseError(f"snapshot not found: {snapshot}")
    if snapshot.stat().st_size > MAX_SNAPSHOT_BYTES:
        raise SnapshotTooLargeError(f"{snapshot} exceeds {MAX_SNAPSHOT_BYTES} bytes")


def _sha256_file(path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _validate_downloaded_snapshot(source_key: str, path: pathlib.Path) -> None:
    if source_key != "historic_england":
        return
    try:
        data = json.loads(path.read_text())
    except (UnicodeDecodeError, ValueError, RecursionError) as exc:
        raise SnapshotParseError(f"{path} is not valid GeoJSON JSON: {exc}") from exc
    if isinstance(data, dict) and data.get("status") == "ExportingData":
        raise SnapshotPendingError(f"{path} is still exporting")
    if not isinstance(data, dict) or data.get("type") != "FeatureCollection":
        raise SnapshotParseError(f"{path} is not a GeoJSON FeatureCollection")


def download_snapshot(
    source_key,
    dest_dir,
    *,
    config,
    fetch_fn=fetch.get_to_file,
    enabled=False,
    retries: int = 6,
    sleep=time.sleep,
) -> pathlib.Path:
    entry = config[source_key]
    dest = pathlib.Path(dest_dir) / f"{source_key}.snapshot"
    if not enabled:
        _log.info("acquisition disabled for %s; expecting snapshot at %s", source_key, dest)
        return dest
    for attempt in range(retries + 1):
        size = fetch_fn(
            entry["url"],
            dest,
            expected_hosts=set(entry["allowed_hosts"]),
            max_bytes=entry.get("max_bytes", fetch.MAX_RESPONSE_BYTES),
        )
        try:
            _validate_downloaded_snapshot(source_key, dest)
            break
        except SnapshotPendingError:
            dest.unlink(missing_ok=True)
            pathlib.Path(str(dest) + ".meta.json").unlink(missing_ok=True)
            if attempt >= retries:
                raise
            sleep(float(2**attempt))
        except Exception:
            dest.unlink(missing_ok=True)
            pathlib.Path(str(dest) + ".meta.json").unlink(missing_ok=True)
            raise
    else:
        raise SnapshotError("unreachable snapshot retry state")
    sidecar = {
        "source_url": entry["url"],
        "snapshot_date": entry.get("snapshot_date"),
        "sha256": _sha256_file(dest),
        "size": size,
    }
    pathlib.Path(str(dest) + ".meta.json").write_text(json.dumps(sidecar, sort_keys=True))
    return dest


def verify_sha256_sidecar(snapshot_path) -> None:
    meta_path = pathlib.Path(str(snapshot_path) + ".meta.json")
    if not meta_path.exists():
        _log.warning(
            "no provenance sidecar for %s; proceeding with hand-placed dev file",
            snapshot_path,
        )
        return
    if meta_path.stat().st_size > MAX_SIDECAR_BYTES:
        raise ProvenanceError(
            f"provenance sidecar for {snapshot_path} exceeds {MAX_SIDECAR_BYTES} bytes"
        )
    try:
        meta = json.loads(meta_path.read_text())
    except (ValueError, RecursionError) as exc:
        raise ProvenanceError(
            f"unparseable provenance sidecar for {snapshot_path}: {exc}"
        ) from exc
    if not isinstance(meta, dict):
        raise ProvenanceError(f"provenance sidecar for {snapshot_path} must be an object")
    for field, typ in (("sha256", str), ("source_url", str), ("size", int)):
        if not isinstance(meta.get(field), typ):
            raise ProvenanceError(
                f"provenance sidecar for {snapshot_path} lacks {field}"
            )
    actual_size = pathlib.Path(snapshot_path).stat().st_size
    if actual_size != meta["size"]:
        raise ProvenanceError(
            f"size mismatch for {snapshot_path}: {actual_size} != {meta['size']}"
        )
    actual = _sha256_file(snapshot_path)
    if actual != meta["sha256"]:
        raise ProvenanceError(
            f"sha256 mismatch for {snapshot_path}: {actual} != {meta['sha256']}"
        )
