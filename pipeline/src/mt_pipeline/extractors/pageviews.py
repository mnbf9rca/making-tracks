"""Resumable pageview acquisition cache; A4 computes signals from the cache."""

from __future__ import annotations

import datetime
import hashlib
import json
import pathlib
import os


def window_for(snapshot_date: str, months: int = 12) -> tuple[str, str]:
    end = datetime.date.fromisoformat(snapshot_date)
    if months % 12 == 0:
        target_year = end.year - months // 12
        try:
            start = end.replace(year=target_year)
        except ValueError:
            start = end.replace(year=target_year, day=28)
    else:
        start = end - datetime.timedelta(days=int(months * 30.4375))
    return (start.isoformat(), end.isoformat())


def _cache_path(cache_dir, title: str, window: tuple[str, str]) -> pathlib.Path:
    key = hashlib.sha256(f"{title}|{window[0]}|{window[1]}".encode()).hexdigest()
    return pathlib.Path(cache_dir) / f"{key}.json"


def acquire(titles, window, cache_dir, *, fetch, enabled: bool = False) -> int:
    if not enabled:
        return 0

    pathlib.Path(cache_dir).mkdir(parents=True, exist_ok=True)
    fetched = 0
    for title in titles:
        cache_path = _cache_path(cache_dir, title, window)
        if _cache_complete(cache_path):
            continue
        data = fetch(title, window)
        tmp_path = cache_path.with_suffix(".tmp")
        tmp_path.write_text(json.dumps(data))
        os.replace(tmp_path, cache_path)
        fetched += 1
    return fetched


def _cache_complete(cache_path: pathlib.Path) -> bool:
    if not cache_path.exists():
        return False
    try:
        json.loads(cache_path.read_text())
    except (OSError, ValueError, RecursionError):
        return False
    return True
