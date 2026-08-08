from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
from typing import Sequence

import pytest

from app_store_archive_helpers import (
    FULL_GIT_SHA,
    FakeArchiveCommands,
    FakeDittoCommands,
    InMemoryS3,
    make_archive,
)
from mt_pipeline.app_store_archive import cli
from mt_pipeline.app_store_archive.archive import ArchiveValidationError
from mt_pipeline.app_store_archive.r2_store import ArchiveStorageError
from mt_pipeline.app_store_archive.workflow import (
    WorkflowError,
    publish_archive,
    retrieve_archive,
)


BUCKET = "making-tracks-state"


class ReleaseCommands:
    def __init__(self, archive_commands: FakeArchiveCommands):
        self.archive_commands = archive_commands
        self.ditto = FakeDittoCommands()
        self.extract_source: Path | None = None
        self.tamper_extracted_app = False
        self.calls: list[tuple[str, ...]] = []

    def run(self, args: Sequence[str]) -> str:
        call = tuple(args)
        self.calls.append(call)
        if len(call) == 5 and call[:3] == ("ditto", "-x", "-k"):
            if self.extract_source is None:
                raise AssertionError("extract_source must be set before retrieval")
            destination = Path(call[4]) / "MakingTracks.xcarchive"
            shutil.copytree(self.extract_source, destination)
            if self.tamper_extracted_app:
                app_binary = (
                    destination
                    / "Products/Applications/MakingTracks.app/MakingTracks"
                )
                app_binary.write_bytes(b"tampered-restored-binary")
            return ""
        if call and call[0] == "ditto":
            return self.ditto.run(call)
        return self.archive_commands.run(call)


def test_publish_workflow_inspects_stages_then_publishes(tmp_path: Path):
    fixture = make_archive(tmp_path / "source")
    commands = ReleaseCommands(fixture.commands)
    client = InMemoryS3()
    layout = _layout(tmp_path)
    application_support = tmp_path / "Application Support"

    result = publish_archive(
        fixture.archive,
        repo_root=tmp_path,
        application_support_root=application_support,
        layout_path=layout,
        client=client,
        captured_at="2026-08-07T00:00:00Z",
        run=commands.run,
    )

    assert result.identity.git_sha == FULL_GIT_SHA
    assert result.local.archive.is_dir()
    assert result.remote.bucket == BUCKET
    assert commands.calls[0][0] == "git"
    assert [call[0] for call in commands.calls].count("ditto") == 2
    assert client.calls[0][0] == "list"


def test_publish_invalid_archive_fails_before_local_or_remote_mutation(tmp_path: Path):
    fixture = make_archive(tmp_path / "source", bundle_id="example.invalid.Other")
    commands = ReleaseCommands(fixture.commands)
    client = InMemoryS3()
    application_support = tmp_path / "Application Support"

    with pytest.raises(ArchiveValidationError, match="bundle identifier"):
        publish_archive(
            fixture.archive,
            repo_root=tmp_path,
            application_support_root=application_support,
            layout_path=_layout(tmp_path),
            client=client,
            captured_at="2026-08-07T00:00:00Z",
            run=commands.run,
        )

    assert not application_support.exists()
    assert client.calls == []


def test_publish_rejects_source_mutated_at_copy_boundary_before_ready(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
):
    fixture = make_archive(tmp_path / "source")
    commands = ReleaseCommands(fixture.commands)
    original_ditto_run = commands.ditto.run

    def mutate_source_during_copy(args: Sequence[str]) -> str:
        if len(args) == 3 and args[0] == "ditto":
            fixture.app_binary.write_bytes(b"mutated-after-inspection")
        return original_ditto_run(args)

    commands.ditto.run = mutate_source_during_copy
    client = InMemoryS3()
    application_support = tmp_path / "Application Support"
    layout = _layout(tmp_path)

    def publish(archive_path: Path, **_kwargs):
        return publish_archive(
            archive_path,
            repo_root=tmp_path,
            application_support_root=application_support,
            layout_path=layout,
            client=client,
            captured_at="2026-08-07T00:00:00Z",
            run=commands.run,
        )

    monkeypatch.setattr(cli, "client_from_environment", lambda: client)
    monkeypatch.setattr(cli, "publish_archive", publish)

    exit_code = cli.main(["publish", "--archive", str(fixture.archive)])

    output = capsys.readouterr()
    assert exit_code == 1
    assert "READY FOR APP STORE UPLOAD" not in output.out
    assert "READY FOR APP STORE UPLOAD" not in output.err
    assert client.calls == []


def test_retrieve_downloads_extracts_and_revalidates_archive(tmp_path: Path):
    fixture = make_archive(tmp_path / "source")
    commands = ReleaseCommands(fixture.commands)
    client = InMemoryS3()
    published = publish_archive(
        fixture.archive,
        repo_root=tmp_path,
        application_support_root=tmp_path / "Application Support",
        layout_path=_layout(tmp_path),
        client=client,
        captured_at="2026-08-07T00:00:00Z",
        run=commands.run,
    )
    commands.extract_source = published.local.archive
    client.calls.clear()
    destination = tmp_path / "recovery"

    restored = retrieve_archive(
        "1.0",
        "1",
        destination,
        repo_root=tmp_path,
        layout_path=_layout(tmp_path),
        client=client,
        requested_sha=None,
        run=commands.run,
    )

    assert restored.destination == destination
    assert restored.archive_path == destination / "MakingTracks.xcarchive"
    assert restored.archive_path.is_dir()
    assert restored.identity.git_sha == FULL_GIT_SHA
    get_keys = [call[2] for call in client.calls if call[0] == "get"]
    assert get_keys == [
        f"app-store-archives/1.0/1/{FULL_GIT_SHA}/manifest.json",
        f"app-store-archives/1.0/1/{FULL_GIT_SHA}/archive.xcarchive.zip",
    ]


def test_retrieve_refuses_existing_destination_before_remote_access(tmp_path: Path):
    destination = tmp_path / "recovery"
    destination.mkdir()
    client = InMemoryS3()

    with pytest.raises(WorkflowError, match="destination already exists"):
        retrieve_archive(
            "1.0",
            "1",
            destination,
            repo_root=tmp_path,
            layout_path=_layout(tmp_path),
            client=client,
            requested_sha=None,
        )

    assert client.calls == []


def test_post_extraction_mismatch_preserves_staging_path(tmp_path: Path):
    fixture = make_archive(tmp_path / "source")
    commands = ReleaseCommands(fixture.commands)
    client = InMemoryS3()
    published = publish_archive(
        fixture.archive,
        repo_root=tmp_path,
        application_support_root=tmp_path / "Application Support",
        layout_path=_layout(tmp_path),
        client=client,
        captured_at="2026-08-07T00:00:00Z",
        run=commands.run,
    )
    commands.extract_source = published.local.archive
    commands.tamper_extracted_app = True
    destination = tmp_path / "recovery"

    with pytest.raises(WorkflowError, match=r"\.recovery-staging-") as caught:
        retrieve_archive(
            "1.0",
            "1",
            destination,
            repo_root=tmp_path,
            layout_path=_layout(tmp_path),
            client=client,
            requested_sha=None,
            run=commands.run,
        )

    staging = list(tmp_path.glob(".recovery-staging-*"))
    assert len(staging) == 1
    assert str(staging[0]) in str(caught.value)
    assert not destination.exists()


def test_cli_publish_prints_ready_only_after_workflow_result(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
):
    fixture = make_archive(tmp_path / "source")
    commands = ReleaseCommands(fixture.commands)
    result = publish_archive(
        fixture.archive,
        repo_root=tmp_path,
        application_support_root=tmp_path / "Application Support",
        layout_path=_layout(tmp_path),
        client=InMemoryS3(),
        captured_at="2026-08-07T00:00:00Z",
        run=commands.run,
    )
    calls: list[tuple[Path, object]] = []

    def published(archive_path, **kwargs):
        calls.append((archive_path, kwargs["client"]))
        return result

    client = object()
    monkeypatch.setattr(cli, "client_from_environment", lambda: client)
    monkeypatch.setattr(cli, "publish_archive", published)
    monkeypatch.setattr(cli, "_utc_now", lambda: "2026-08-07T00:00:00Z")
    monkeypatch.setattr(cli, "_repo_root", lambda: tmp_path)
    monkeypatch.setattr(cli, "_application_support_root", lambda: tmp_path / "support")
    monkeypatch.setattr(cli, "_layout_path", lambda: tmp_path / "layout.json")

    exit_code = cli.main(["publish", "--archive", str(fixture.archive)])

    output = capsys.readouterr()
    assert exit_code == 0
    assert "PHASE START app_store_archive.copy " in output.err
    assert "PHASE DONE app_store_archive.download " in output.err
    assert output.out == (
        "READY FOR APP STORE UPLOAD\n"
        "version: 1.0\n"
        "build: 1\n"
        f"git_sha: {FULL_GIT_SHA}\n"
        f"local_archive: {result.local.archive}\n"
        f"remote_prefix: s3://{BUCKET}/{result.remote.prefix}\n"
        f"archive_sha256: {result.remote.archive_sha256}\n"
        "dsym_uuids: arm64=AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\n"
    )
    assert calls == [(fixture.archive, client)]


def test_cli_expected_failure_is_nonzero_redacted_and_never_ready(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
):
    sentinel = "R2_SECRET_SENTINEL"
    monkeypatch.setenv("R2_SECRET_ACCESS_KEY", sentinel)
    monkeypatch.setattr(
        cli,
        "client_from_environment",
        lambda: (_ for _ in ()).throw(ArchiveStorageError("missing R2_SECRET_ACCESS_KEY")),
    )

    exit_code = cli.main(["publish", "--archive", "/tmp/archive.xcarchive"])

    output = capsys.readouterr()
    assert exit_code == 1
    assert "READY FOR APP STORE UPLOAD" not in output.out
    assert sentinel not in output.out
    assert sentinel not in output.err
    assert output.err == "app-store-archive: missing R2_SECRET_ACCESS_KEY\n"


def test_cli_does_not_mislabel_unexpected_exceptions(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(cli, "client_from_environment", lambda: object())
    monkeypatch.setattr(
        cli,
        "publish_archive",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(ValueError("programmer error")),
    )

    with pytest.raises(ValueError, match="programmer error"):
        cli.main(["publish", "--archive", "/tmp/archive.xcarchive"])


def test_real_script_exposes_publish_and_retrieve_help(tmp_path: Path):
    repo_root = Path(__file__).resolve().parents[2]
    result = subprocess.run(
        [str(repo_root / ".venv/bin/python"), "scripts/app-store-archive.py", "--help"],
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "publish" in result.stdout
    assert "retrieve" in result.stdout


@pytest.mark.parametrize(
    ("command", "expected_usage"),
    [
        (
            "publish",
            "usage: app-store-archive publish [-h] --archive ARCHIVE",
        ),
        (
            "retrieve",
            (
                "usage: app-store-archive retrieve [-h] --version VERSION "
                "--build BUILD\n"
                "                                  --destination DESTINATION "
                "[--sha SHA]"
            ),
        ),
    ],
)
def test_real_script_help_exposes_documented_operands_only(
    command: str,
    expected_usage: str,
):
    repo_root = Path(__file__).resolve().parents[2]

    result = subprocess.run(
        [
            str(repo_root / ".venv/bin/python"),
            "scripts/app-store-archive.py",
            command,
            "--help",
        ],
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.split("\n\n", 1)[0] == expected_usage


@pytest.mark.parametrize(
    "arguments",
    [
        ["delete"],
        ["upload"],
        ["export"],
        ["publish", "--archive", "/tmp/archive.xcarchive", "--upload"],
        ["publish", "--archive", "/tmp/archive.xcarchive", "--export"],
        ["publish", "--archive", "/tmp/archive.xcarchive", "--apple-id", "x"],
        ["publish", "--archive", "/tmp/archive.xcarchive", "--password", "x"],
    ],
)
def test_real_script_rejects_unsupported_release_actions_and_credentials(
    arguments: list[str],
):
    repo_root = Path(__file__).resolve().parents[2]

    result = subprocess.run(
        [str(repo_root / ".venv/bin/python"), "scripts/app-store-archive.py", *arguments],
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 2
    assert result.stdout == ""
    assert "usage: app-store-archive" in result.stderr


def _layout(tmp_path: Path) -> Path:
    layout = tmp_path / "r2_layout.json"
    layout.write_text(
        '{"private_bucket":"making-tracks-state","public_bucket":"making-tracks-tiles"}\n',
        encoding="utf-8",
    )
    return layout
