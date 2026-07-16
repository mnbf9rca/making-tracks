"""Runtime path resolution for files coupled to a SQLite working store."""

from __future__ import annotations

import pathlib


class RuntimePathError(RuntimeError):
    pass


def db_parent(conn) -> pathlib.Path | None:
    for _seq, name, filename in conn.execute("PRAGMA database_list").fetchall():
        if name == "main" and filename:
            return pathlib.Path(filename).resolve().parent
    return None


def resolve_near_db(conn, configured_path: str | pathlib.Path) -> pathlib.Path:
    path = pathlib.Path(configured_path)
    if path.is_absolute():
        return path
    base = db_parent(conn)
    if base is None:
        raise RuntimePathError(
            f"cannot resolve relative path {path}: SQLite main database has no file path"
        )
    return base / path
