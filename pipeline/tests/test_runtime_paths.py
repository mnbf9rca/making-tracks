import sqlite3

import pytest

from mt_pipeline import runtime_paths


def test_relative_paths_resolve_beside_file_backed_db(tmp_path):
    conn = sqlite3.connect(tmp_path / "work.db")
    try:
        assert runtime_paths.resolve_near_db(conn, "registry/united-kingdom.jsonl") == (
            tmp_path / "registry/united-kingdom.jsonl"
        )
    finally:
        conn.close()


def test_relative_paths_fail_closed_without_file_backed_db():
    conn = sqlite3.connect(":memory:")
    try:
        with pytest.raises(runtime_paths.RuntimePathError):
            runtime_paths.resolve_near_db(conn, "registry/united-kingdom.jsonl")
    finally:
        conn.close()
