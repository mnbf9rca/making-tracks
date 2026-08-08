from __future__ import annotations

import json
from pathlib import Path

import pytest

from app_store_archive_helpers import (
    FULL_GIT_SHA,
    FakeDittoCommands,
    InMemoryS3,
    make_archive,
)
from mt_pipeline.app_store_archive.archive import inspect_archive
from mt_pipeline.app_store_archive.manifest import parse_manifest
from mt_pipeline.app_store_archive.r2_store import (
    ArchiveStorageError,
    R2ArchiveStore,
    private_bucket,
)
from mt_pipeline.app_store_archive.staging import LocalArtifact, stage_archive


BUCKET = "making-tracks-state"
PREFIX = f"app-store-archives/1.0/1/{FULL_GIT_SHA}/"
ARCHIVE_KEY = PREFIX + "archive.xcarchive.zip"
MANIFEST_KEY = PREFIX + "manifest.json"


def test_private_bucket_is_read_from_layout_and_must_be_distinct(tmp_path: Path):
    layout = tmp_path / "r2_layout.json"
    layout.write_text(
        json.dumps(
            {
                "public_bucket": "making-tracks-tiles",
                "private_bucket": BUCKET,
            }
        ),
        encoding="utf-8",
    )

    assert private_bucket(layout) == BUCKET

    layout.write_text(
        json.dumps(
            {
                "public_bucket": "making-tracks-tiles",
                "private_bucket": "making-tracks-tiles",
            }
        ),
        encoding="utf-8",
    )
    with pytest.raises(ArchiveStorageError, match="private_bucket"):
        private_bucket(layout)


@pytest.mark.parametrize("value", [{}, {"private_bucket": ""}, []])
def test_private_bucket_rejects_invalid_layout(tmp_path: Path, value: object):
    layout = tmp_path / "r2_layout.json"
    layout.write_text(json.dumps(value), encoding="utf-8")

    with pytest.raises(ArchiveStorageError, match="private_bucket"):
        private_bucket(layout)


def test_publish_conditionally_writes_archive_then_manifest_and_round_trips(
    tmp_path: Path,
):
    local = _local_artifact(tmp_path)
    client = InMemoryS3()
    store = R2ArchiveStore(client, BUCKET)

    publication = store.publish(local)

    assert client.objects[(BUCKET, ARCHIVE_KEY)] == local.archive_zip.read_bytes()
    assert client.objects[(BUCKET, MANIFEST_KEY)] == local.manifest_bytes
    assert [call[2] for call in client.calls if call[0] == "put"] == [
        ARCHIVE_KEY,
        MANIFEST_KEY,
    ]
    assert client.calls == [
        ("list", BUCKET, "app-store-archives/1.0/1/"),
        ("get", BUCKET, ARCHIVE_KEY),
        ("put", BUCKET, ARCHIVE_KEY),
        ("get", BUCKET, ARCHIVE_KEY),
        ("get", BUCKET, MANIFEST_KEY),
        ("put", BUCKET, MANIFEST_KEY),
        ("get", BUCKET, MANIFEST_KEY),
    ]
    manifest = parse_manifest(local.manifest_bytes, "1.0", "1", FULL_GIT_SHA)
    archive_object = manifest["archive_object"]
    assert isinstance(archive_object, dict)
    assert publication.bucket == BUCKET
    assert publication.prefix == PREFIX
    assert publication.archive_sha256 == archive_object["sha256"]
    assert publication.manifest_sha256 == local.manifest_sha256


def test_publish_emits_upload_and_fresh_download_phase_boundaries(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
):
    local = _local_artifact(tmp_path)

    R2ArchiveStore(InMemoryS3(), BUCKET).publish(local)

    lines = capsys.readouterr().err.splitlines()
    assert any(line.startswith("PHASE START app_store_archive.upload ") for line in lines)
    assert any(line.startswith("PHASE DONE app_store_archive.upload ") for line in lines)
    assert any(line.startswith("PHASE START app_store_archive.download ") for line in lines)
    assert any(line.startswith("PHASE DONE app_store_archive.download ") for line in lines)


def test_publish_refuses_another_sha_before_any_object_get_or_put(tmp_path: Path):
    local = _local_artifact(tmp_path)
    client = InMemoryS3()
    other_sha = "f" * 40
    client.objects[(BUCKET, f"app-store-archives/1.0/1/{other_sha}/manifest.json")] = b"{}"

    with pytest.raises(ArchiveStorageError, match=other_sha):
        R2ArchiveStore(client, BUCKET).publish(local)

    assert [call[0] for call in client.calls] == ["list"]


def test_archive_only_interruption_resumes_without_rewriting_archive(tmp_path: Path):
    local = _local_artifact(tmp_path)
    client = InMemoryS3()
    client.objects[(BUCKET, ARCHIVE_KEY)] = local.archive_zip.read_bytes()

    R2ArchiveStore(client, BUCKET).publish(local)

    assert [call[2] for call in client.calls if call[0] == "put"] == [MANIFEST_KEY]
    assert client.objects[(BUCKET, MANIFEST_KEY)] == local.manifest_bytes


def test_identical_complete_publication_is_idempotent_without_put(tmp_path: Path):
    local = _local_artifact(tmp_path)
    client = InMemoryS3()
    client.objects[(BUCKET, ARCHIVE_KEY)] = local.archive_zip.read_bytes()
    client.objects[(BUCKET, MANIFEST_KEY)] = local.manifest_bytes

    publication = R2ArchiveStore(client, BUCKET).publish(local)

    assert not [call for call in client.calls if call[0] == "put"]
    assert publication.manifest_sha256 == local.manifest_sha256


@pytest.mark.parametrize("key", [ARCHIVE_KEY, MANIFEST_KEY])
def test_differing_existing_object_is_preserved_and_rejected(
    tmp_path: Path,
    key: str,
):
    local = _local_artifact(tmp_path)
    client = InMemoryS3()
    client.objects[(BUCKET, ARCHIVE_KEY)] = local.archive_zip.read_bytes()
    if key == MANIFEST_KEY:
        client.objects[(BUCKET, MANIFEST_KEY)] = b"different-manifest"
    else:
        client.objects[(BUCKET, ARCHIVE_KEY)] = b"different-archive"
    before = dict(client.objects)

    with pytest.raises(ArchiveStorageError, match="different existing object"):
        R2ArchiveStore(client, BUCKET).publish(local)

    assert client.objects == before
    assert not [call for call in client.calls if call[0] == "put"]


@pytest.mark.parametrize("identical", [True, False])
def test_precondition_race_accepts_only_identical_winner(
    tmp_path: Path,
    identical: bool,
):
    local = _local_artifact(tmp_path)
    client = InMemoryS3()
    client.precondition_races[ARCHIVE_KEY] = (
        local.archive_zip.read_bytes() if identical else b"racing-different-archive"
    )

    if identical:
        R2ArchiveStore(client, BUCKET).publish(local)
        assert client.objects[(BUCKET, MANIFEST_KEY)] == local.manifest_bytes
    else:
        with pytest.raises(ArchiveStorageError, match="different existing object"):
            R2ArchiveStore(client, BUCKET).publish(local)
        assert (BUCKET, MANIFEST_KEY) not in client.objects


def test_corrupt_archive_round_trip_keeps_publication_incomplete(tmp_path: Path):
    local = _local_artifact(tmp_path)
    client = InMemoryS3()
    client.corrupt_get_key = ARCHIVE_KEY

    with pytest.raises(ArchiveStorageError, match="round-trip"):
        R2ArchiveStore(client, BUCKET).publish(local)

    assert (BUCKET, ARCHIVE_KEY) in client.objects
    assert (BUCKET, MANIFEST_KEY) not in client.objects
    assert [call[2] for call in client.calls if call[0] == "put"] == [ARCHIVE_KEY]


def test_streaming_failure_is_redacted(tmp_path: Path):
    local = _local_artifact(tmp_path)
    client = InMemoryS3()
    client.objects[(BUCKET, ARCHIVE_KEY)] = local.archive_zip.read_bytes()
    client.read_failure_key = ARCHIVE_KEY

    with pytest.raises(ArchiveStorageError) as caught:
        R2ArchiveStore(client, BUCKET).publish(local)

    assert "R2_SECRET_SENTINEL" not in str(caught.value)


@pytest.mark.parametrize("failure_at", ["list", "get", "put"])
def test_client_operation_failures_are_redacted(tmp_path: Path, failure_at: str):
    local = _local_artifact(tmp_path)
    client = InMemoryS3()
    client.failure_at = failure_at

    with pytest.raises(ArchiveStorageError) as caught:
        R2ArchiveStore(client, BUCKET).publish(local)

    assert "R2_SECRET_SENTINEL" not in str(caught.value)


def test_resolve_sha_reports_zero_and_multiple_candidates(tmp_path: Path):
    client = InMemoryS3(page_size=1)
    store = R2ArchiveStore(client, BUCKET)

    with pytest.raises(ArchiveStorageError, match="no archive"):
        store.resolve_sha("1.0", "1")

    first = "a" * 40
    second = "b" * 40
    client.objects[(BUCKET, f"app-store-archives/1.0/1/{first}/manifest.json")] = b"{}"
    client.objects[(BUCKET, f"app-store-archives/1.0/1/{second}/manifest.json")] = b"{}"
    client.objects[(BUCKET, "app-store-archives/1.0/1/not-a-sha/manifest.json")] = b"{}"

    with pytest.raises(ArchiveStorageError) as caught:
        store.resolve_sha("1.0", "1")

    assert first in str(caught.value)
    assert second in str(caught.value)
    assert len([call for call in client.calls if call[0] == "list"]) == 4


def test_resolve_sha_honors_requested_sha_only_when_present(tmp_path: Path):
    client = InMemoryS3()
    requested = "a" * 40
    client.objects[(BUCKET, f"app-store-archives/1.0/1/{requested}/manifest.json")] = b"{}"
    store = R2ArchiveStore(client, BUCKET)

    assert store.resolve_sha("1.0", "1", requested) == requested
    with pytest.raises(ArchiveStorageError, match="requested archive"):
        store.resolve_sha("1.0", "1", "b" * 40)


def test_download_validates_manifest_before_archive_and_verifies_bytes(tmp_path: Path):
    local = _local_artifact(tmp_path)
    client = InMemoryS3()
    client.objects[(BUCKET, MANIFEST_KEY)] = local.manifest_bytes
    client.objects[(BUCKET, ARCHIVE_KEY)] = local.archive_zip.read_bytes()
    download_root = tmp_path / "downloads"
    download_root.mkdir()

    downloaded = R2ArchiveStore(client, BUCKET).download(
        "1.0",
        "1",
        FULL_GIT_SHA,
        download_root,
    )

    assert downloaded.root.parent == download_root
    assert downloaded.archive_zip.read_bytes() == local.archive_zip.read_bytes()
    assert downloaded.manifest["git_sha"] == FULL_GIT_SHA
    assert [call[2] for call in client.calls if call[0] == "get"] == [
        MANIFEST_KEY,
        ARCHIVE_KEY,
    ]


def test_download_invalid_manifest_never_requests_archive(tmp_path: Path):
    client = InMemoryS3()
    client.objects[(BUCKET, MANIFEST_KEY)] = b"invalid"
    client.objects[(BUCKET, ARCHIVE_KEY)] = b"archive"
    download_root = tmp_path / "downloads"
    download_root.mkdir()

    with pytest.raises(ArchiveStorageError, match="manifest"):
        R2ArchiveStore(client, BUCKET).download(
            "1.0",
            "1",
            FULL_GIT_SHA,
            download_root,
        )

    assert [call[2] for call in client.calls if call[0] == "get"] == [MANIFEST_KEY]


def test_download_corrupt_archive_is_rejected(tmp_path: Path):
    local = _local_artifact(tmp_path)
    client = InMemoryS3()
    client.objects[(BUCKET, MANIFEST_KEY)] = local.manifest_bytes
    client.objects[(BUCKET, ARCHIVE_KEY)] = local.archive_zip.read_bytes()
    client.corrupt_get_key = ARCHIVE_KEY
    download_root = tmp_path / "downloads"
    download_root.mkdir()

    with pytest.raises(ArchiveStorageError, match="archive digest"):
        R2ArchiveStore(client, BUCKET).download(
            "1.0",
            "1",
            FULL_GIT_SHA,
            download_root,
        )


def _local_artifact(tmp_path: Path) -> LocalArtifact:
    fixture = make_archive(tmp_path / "source")
    identity = inspect_archive(fixture.archive, tmp_path, run=fixture.commands.run)
    return stage_archive(
        identity,
        tmp_path / "Application Support",
        "2026-08-07T00:00:00Z",
        run=FakeDittoCommands().run,
    )
