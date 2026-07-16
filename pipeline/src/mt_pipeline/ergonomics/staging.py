"""Ephemeral per-source SQLite staging stores for extract parallelism."""

from __future__ import annotations

import pathlib
import shutil
import sqlite3
import hashlib

from .. import store


def _run_dir(run_id: str) -> str:
    return hashlib.sha256(run_id.encode("utf-8")).hexdigest()


def staging_path(root: str | pathlib.Path, run_id: str, source: str) -> pathlib.Path:
    return staging_root(root, run_id) / f"{source}.db"


def staging_root(root: str | pathlib.Path, run_id: str) -> pathlib.Path:
    root_path = pathlib.Path(root).resolve()
    path = (root_path / "staging" / _run_dir(run_id)).resolve()
    if not path.is_relative_to(root_path / "staging"):
        raise ValueError("staging path escaped staging root")
    return path


def clean_run(root: str | pathlib.Path, run_id: str) -> None:
    shutil.rmtree(staging_root(root, run_id), ignore_errors=True)


def open_staging(root: str | pathlib.Path, run_id: str, source: str) -> sqlite3.Connection:
    path = staging_path(root, run_id, source)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()
    conn = store.connect(path)
    store.init_schema(conn)
    return conn
