import pytest

from mt_pipeline.extractors import pageviews


def test_window_is_derived_from_config_date_not_wallclock():
    assert pageviews.window_for("2026-07-14", 12) == ("2025-07-14", "2026-07-14")


def test_window_is_leap_day_safe():
    assert pageviews.window_for("2024-02-29", 12) == ("2023-02-28", "2024-02-29")


def test_non_year_window_uses_deterministic_fractional_month_approximation():
    assert pageviews.window_for("2026-07-15", 3) == ("2026-04-15", "2026-07-15")


def test_acquire_is_gated_by_the_per_run_flag(tmp_path):
    calls = []

    def fake_fetch(title, window):
        calls.append(title)
        return {"items": [{"views": 1}]}

    count = pageviews.acquire(
        ["Big_Ben"],
        ("2025-07-14", "2026-07-14"),
        tmp_path,
        fetch=fake_fetch,
        enabled=False,
    )
    assert count == 0
    assert calls == []


def test_acquire_is_resumable_and_cached(tmp_path):
    calls = []
    window = ("2025-07-14", "2026-07-14")

    def crashing_fetch(title, window):
        calls.append(title)
        if title == "B":
            raise RuntimeError("crash")
        return {"title": title, "window": list(window), "daily": [1]}

    try:
        pageviews.acquire(["A", "B", "C"], window, tmp_path, fetch=crashing_fetch, enabled=True)
    except RuntimeError:
        pass
    assert "A" in calls

    calls.clear()

    def fake_fetch(title, window):
        calls.append(title)
        return {"title": title, "window": list(window), "daily": [1]}

    pageviews.acquire(["A", "B", "C"], window, tmp_path, fetch=fake_fetch, enabled=True)
    assert "A" not in calls
    assert set(calls) == {"B", "C"}


def test_acquire_cache_key_includes_title_and_window(tmp_path):
    first = ("2025-07-14", "2026-07-14")
    second = ("2024-07-14", "2025-07-14")
    assert pageviews._cache_path(tmp_path, "A", first) != pageviews._cache_path(
        tmp_path, "A", second
    )
    assert pageviews._cache_path(tmp_path, "A", first) != pageviews._cache_path(
        tmp_path, "B", first
    )


def test_acquire_reuses_manifest_window_for_resume(tmp_path):
    calls = []
    cache_dir = tmp_path / "cache"
    original = ("2025-07-14", "2026-07-14")
    recomputed = ("2025-07-15", "2026-07-15")
    pageviews.ensure_manifest(cache_dir, original)

    def fake_fetch(title, window):
        calls.append((title, window))
        return {"title": title, "window": list(window), "daily": [1]}

    pageviews.acquire(["A"], recomputed, cache_dir, fetch=fake_fetch, enabled=True)

    assert calls == [("A", original)]


def test_acquire_dedupes_titles_and_paces_only_new_fetches(tmp_path):
    calls = []
    sleeps = []
    window = ("2025-07-14", "2026-07-14")

    def fake_fetch(title, window):
        calls.append(title)
        return {"title": title, "window": list(window), "daily": [1]}

    count = pageviews.acquire(
        ["B", "A", "A", "B"],
        window,
        tmp_path,
        fetch=fake_fetch,
        enabled=True,
        sleep=sleeps.append,
        polite_interval_seconds=0.25,
    )

    assert count == 2
    assert calls == ["A", "B"]
    assert sleeps == [0.25, 0.25]


def test_corrupt_cache_file_is_refetched(tmp_path):
    window = ("2025-07-14", "2026-07-14")
    cache_path = pageviews._cache_path(tmp_path, "A", window)
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text("{")
    calls = []

    def fake_fetch(title, window):
        calls.append(title)
        return {"title": title, "window": list(window), "daily": [2]}

    assert pageviews.acquire(["A"], window, tmp_path, fetch=fake_fetch, enabled=True) == 1
    assert calls == ["A"]


def test_read_validates_cache_schema_and_returns_daily_values(tmp_path):
    window = ("2025-07-14", "2026-07-14")
    cache_path = pageviews._cache_path(tmp_path, "A", window)
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(
        '{"title":"A","window":["2025-07-14","2026-07-14"],"daily":[3,0,7]}'
    )

    assert pageviews.read(tmp_path, "A", window) == [3, 0, 7]

    cache_path.write_text(
        '{"title":"A","window":["2025-07-14","2026-07-14"],"daily":["bad"]}'
    )
    assert pageviews.read(tmp_path, "A", window) is None


def test_read_rejects_raw_api_shaped_cache_entry(tmp_path):
    window = ("2025-07-14", "2026-07-14")
    cache_path = pageviews._cache_path(tmp_path, "A", window)
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text('{"items":[{"views":99}]}')

    assert pageviews.read(tmp_path, "A", window) is None


def test_acquire_refetches_raw_api_shaped_cache_entry(tmp_path):
    calls = []
    window = ("2025-07-14", "2026-07-14")
    cache_path = pageviews._cache_path(tmp_path, "A", window)
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text('{"items":[{"views":99}]}')

    def fake_fetch(title, window):
        calls.append(title)
        return {"title": title, "window": list(window), "daily": [1]}

    assert pageviews.acquire(["A"], window, tmp_path, fetch=fake_fetch, enabled=True) == 1
    assert calls == ["A"]
    assert pageviews.read(tmp_path, "A", window) == [1]


def test_manifest_window_rejects_inverted_window(tmp_path):
    cache_dir = tmp_path / "cache"
    cache_dir.mkdir()
    (cache_dir / "manifest.json").write_text(
        '{"window":["2026-07-14","2025-07-14"]}'
    )

    assert pageviews.manifest_window(cache_dir) is None


def test_entry_from_api_response_rejects_invalid_payload():
    with pytest.raises(ValueError, match="invalid pageview response"):
        pageviews.entry_from_api_response(
            "A",
            ("2025-07-14", "2026-07-14"),
            {"items": "not-a-list"},
        )


def test_entry_from_api_response_rejects_mismatched_rest_item_metadata():
    with pytest.raises(ValueError, match="invalid pageview response"):
        pageviews.entry_from_api_response(
            "A",
            ("2025-07-14", "2026-07-14"),
            {
                "items": [
                    {
                        "project": "en.wikipedia",
                        "article": "Other",
                        "access": "all-access",
                        "agent": "user",
                        "granularity": "daily",
                        "timestamp": "2025071400",
                        "views": 1,
                    }
                ]
            },
            project="en.wikipedia",
            access="all-access",
            agent="user",
            granularity="daily",
        )
