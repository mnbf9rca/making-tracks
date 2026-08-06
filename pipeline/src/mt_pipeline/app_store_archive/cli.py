"""Operator CLI for durable App Store archive publication and recovery."""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from datetime import datetime, timezone
from pathlib import Path

from .model import AppStoreArchiveError
from .r2_store import client_from_environment
from .workflow import PublishResult, RetrieveResult, publish_archive, retrieve_archive


def main(argv: Sequence[str] | None = None) -> int:
    parser = _parser()
    arguments = parser.parse_args(argv)
    try:
        client = client_from_environment()
        if arguments.command == "publish":
            result = publish_archive(
                Path(arguments.archive),
                repo_root=_repo_root(),
                application_support_root=_application_support_root(),
                layout_path=_layout_path(),
                client=client,
                captured_at=_utc_now(),
            )
            _print_publish_result(result)
        else:
            result = retrieve_archive(
                arguments.version,
                arguments.build,
                Path(arguments.destination),
                repo_root=_repo_root(),
                layout_path=_layout_path(),
                client=client,
                requested_sha=arguments.sha,
            )
            _print_retrieve_result(result)
    except AppStoreArchiveError as exc:
        print(f"app-store-archive: {exc}", file=sys.stderr)
        return 1
    return 0


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="app-store-archive",
        description="Retain and recover immutable Making Tracks App Store archives.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    publish = subparsers.add_parser("publish")
    publish.add_argument("--archive", required=True)
    retrieve = subparsers.add_parser("retrieve")
    retrieve.add_argument("--version", required=True)
    retrieve.add_argument("--build", required=True)
    retrieve.add_argument("--destination", required=True)
    retrieve.add_argument("--sha")
    return parser


def _print_publish_result(result: PublishResult) -> None:
    dsym_uuids = ",".join(
        f"{item.architecture}={item.uuid}" for item in result.identity.dsym_uuids
    )
    print("READY FOR APP STORE UPLOAD")
    print(f"version: {result.identity.version}")
    print(f"build: {result.identity.build}")
    print(f"git_sha: {result.identity.git_sha}")
    print(f"local_archive: {result.local.archive}")
    print(f"remote_prefix: s3://{result.remote.bucket}/{result.remote.prefix}")
    print(f"archive_sha256: {result.remote.archive_sha256}")
    print(f"dsym_uuids: {dsym_uuids}")


def _print_retrieve_result(result: RetrieveResult) -> None:
    print("RESTORED APP STORE ARCHIVE")
    print(f"version: {result.identity.version}")
    print(f"build: {result.identity.build}")
    print(f"git_sha: {result.identity.git_sha}")
    print(f"archive: {result.archive_path}")


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def _layout_path() -> Path:
    return _repo_root() / "pipeline/config/r2_layout.json"


def _application_support_root() -> Path:
    return Path.home() / "Library/Application Support/making-tracks-releases"


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
