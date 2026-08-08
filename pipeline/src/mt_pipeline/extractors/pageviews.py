"""Resumable pageview acquisition cache; A4 computes signals from the cache."""

from __future__ import annotations

import datetime
import hashlib
import json
import pathlib
import os
from collections.abc import Callable

MAX_TITLE_LEN = 300
MAX_DAILY_POINTS = 4000
MAX_CACHE_BYTES = 1_000_000
MANIFEST_NAME = "manifest.json"


def cache_title(title: str) -> str | None:
    if not isinstance(title, str):
        return None
    value = title[:MAX_TITLE_LEN]
    return value or None


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


def manifest_window(cache_dir) -> tuple[str, str] | None:
    path = pathlib.Path(cache_dir) / MANIFEST_NAME
    try:
        too_large = not path.exists() or path.stat().st_size > MAX_CACHE_BYTES
    except OSError:
        return None
    if too_large:
        return None
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError, RecursionError):
        return None
    window = data.get("window") if isinstance(data, dict) else None
    if (
        not isinstance(window, list)
        or len(window) != 2
        or not all(isinstance(value, str) for value in window)
    ):
        return None
    try:
        start = datetime.date.fromisoformat(window[0])
        end = datetime.date.fromisoformat(window[1])
    except ValueError:
        return None
    if start > end:
        return None
    return (window[0], window[1])


def ensure_manifest(cache_dir, window: tuple[str, str]) -> None:
    cache = pathlib.Path(cache_dir)
    cache.mkdir(parents=True, exist_ok=True)
    if manifest_window(cache) is not None:
        return
    tmp_path = cache / f".{MANIFEST_NAME}.tmp"
    tmp_path.write_text(json.dumps({"window": [window[0], window[1]]}, sort_keys=True))
    os.replace(tmp_path, cache / MANIFEST_NAME)


def _cache_file_within_limit(path: pathlib.Path) -> bool:
    try:
        return (
            path.exists()
            and not path.is_symlink()
            and path.stat().st_size <= MAX_CACHE_BYTES
        )
    except OSError:
        return False


def acquire(
    titles,
    window,
    cache_dir,
    *,
    fetch,
    enabled: bool = False,
    sleep=None,
    polite_interval_seconds: float = 0.0,
    on_progress: Callable[[int, int, int, int], None] | None = None,
) -> int:
    if not enabled:
        return 0

    pathlib.Path(cache_dir).mkdir(parents=True, exist_ok=True)
    existing_window = manifest_window(cache_dir)
    if existing_window is not None:
        window = existing_window
    else:
        ensure_manifest(cache_dir, window)
    deduped_titles = _deduped_titles(titles)
    total = len(deduped_titles)
    fetched = 0
    cached = 0
    processed = 0
    for title in deduped_titles:
        cache_path = _cache_path(cache_dir, title, window)
        if _cache_complete(cache_path, title, window):
            cached += 1
            processed += 1
            if on_progress is not None:
                on_progress(processed, total, fetched, cached)
            continue
        data = fetch(title, window)
        tmp_path = cache_path.with_suffix(".tmp")
        tmp_path.write_text(json.dumps(data, sort_keys=True))
        os.replace(tmp_path, cache_path)
        fetched += 1
        processed += 1
        if on_progress is not None:
            on_progress(processed, total, fetched, cached)
        if sleep is not None and polite_interval_seconds > 0:
            sleep(float(polite_interval_seconds))
    return fetched


def read(cache_dir, title: str, window: tuple[str, str]) -> list[int] | None:
    normalized_title = cache_title(title)
    if normalized_title is None:
        return None
    cache_path = _cache_path(cache_dir, normalized_title, window)
    if not _cache_file_within_limit(cache_path):
        return None
    try:
        data = json.loads(cache_path.read_text())
    except (OSError, ValueError, RecursionError):
        return None
    return _daily_values(data, title=normalized_title, window=window)


def entry_from_api_response(
    title: str,
    window: tuple[str, str],
    data: dict,
    *,
    project: str | None = None,
    access: str | None = None,
    agent: str | None = None,
    granularity: str | None = None,
) -> dict[str, object]:
    normalized_title = cache_title(title)
    if normalized_title is None:
        raise ValueError("pageview title is empty")
    values = _daily_values(
        data,
        title=normalized_title,
        window=window,
        project=project,
        access=access,
        agent=agent,
        granularity=granularity,
    )
    if values is None:
        raise ValueError("invalid pageview response")
    return {
        "title": normalized_title,
        "window": [window[0], window[1]],
        "daily": values,
    }


def _cache_complete(cache_path: pathlib.Path, title: str, window: tuple[str, str]) -> bool:
    if not _cache_file_within_limit(cache_path):
        return False
    try:
        data = json.loads(cache_path.read_text())
    except (OSError, ValueError, RecursionError):
        return False
    return _daily_values(data, title=title, window=window) is not None


def _deduped_titles(titles) -> list[str]:
    out = set()
    for raw_title in titles:
        title = cache_title(raw_title)
        if title is not None:
            out.add(title)
    return sorted(out)


def _daily_values(
    data,
    *,
    title: str,
    window: tuple[str, str],
    project: str | None = None,
    access: str | None = None,
    agent: str | None = None,
    granularity: str | None = None,
) -> list[int] | None:
    if not isinstance(data, dict):
        return None

    if "daily" in data:
        if data.get("title") != title or data.get("window") != [window[0], window[1]]:
            return None
        raw_values = data.get("daily")
    elif "items" in data:
        raw_items = data.get("items")
        if not isinstance(raw_items, list) or len(raw_items) > MAX_DAILY_POINTS:
            return None
        if any(value is None for value in (project, access, agent, granularity)):
            return None
        for item in raw_items:
            if not _item_matches_request(
                item,
                title=title,
                window=window,
                project=project,
                access=access,
                agent=agent,
                granularity=granularity,
            ):
                return None
        raw_values = [
            item.get("views")
            for item in raw_items
            if isinstance(item, dict) and "views" in item
        ]
    else:
        return None

    if not isinstance(raw_values, list) or len(raw_values) > MAX_DAILY_POINTS:
        return None
    values = []
    for raw_value in raw_values:
        if isinstance(raw_value, bool):
            return None
        try:
            number = int(raw_value)
        except (TypeError, ValueError):
            return None
        values.append(max(0, number))
    return values


def _item_matches_request(
    item,
    *,
    title: str,
    window: tuple[str, str],
    project: str | None,
    access: str | None,
    agent: str | None,
    granularity: str | None,
) -> bool:
    if not isinstance(item, dict):
        return False
    expected_article = title.replace(" ", "_")
    if item.get("article") != expected_article:
        return False
    for key, expected in (
        ("project", project),
        ("access", access),
        ("agent", agent),
        ("granularity", granularity),
    ):
        if expected is not None and item.get(key) != expected:
            return False
    timestamp = item.get("timestamp")
    if not isinstance(timestamp, str) or len(timestamp) < 8:
        return False
    try:
        item_date = datetime.date.fromisoformat(
            f"{timestamp[0:4]}-{timestamp[4:6]}-{timestamp[6:8]}"
        )
        start = datetime.date.fromisoformat(window[0])
        end = datetime.date.fromisoformat(window[1])
    except ValueError:
        return False
    return start <= item_date <= end
