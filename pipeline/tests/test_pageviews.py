from mt_pipeline.extractors import pageviews


def test_window_is_derived_from_config_date_not_wallclock():
    assert pageviews.window_for("2026-07-14", 12) == ("2025-07-14", "2026-07-14")


def test_window_is_leap_day_safe():
    assert pageviews.window_for("2024-02-29", 12) == ("2023-02-28", "2024-02-29")


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
        return {"items": [{"views": 1}]}

    try:
        pageviews.acquire(["A", "B", "C"], window, tmp_path, fetch=crashing_fetch, enabled=True)
    except RuntimeError:
        pass
    assert "A" in calls

    calls.clear()

    def fake_fetch(title, window):
        calls.append(title)
        return {"items": [{"views": 1}]}

    pageviews.acquire(["A", "B", "C"], window, tmp_path, fetch=fake_fetch, enabled=True)
    assert "A" not in calls
    assert set(calls) == {"B", "C"}


def test_corrupt_cache_file_is_refetched(tmp_path):
    window = ("2025-07-14", "2026-07-14")
    cache_path = pageviews._cache_path(tmp_path, "A", window)
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text("{")
    calls = []

    def fake_fetch(title, window):
        calls.append(title)
        return {"items": [{"views": 2}]}

    assert pageviews.acquire(["A"], window, tmp_path, fetch=fake_fetch, enabled=True) == 1
    assert calls == ["A"]
