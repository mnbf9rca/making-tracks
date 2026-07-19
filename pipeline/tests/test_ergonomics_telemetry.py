from mt_pipeline.ergonomics import telemetry as T


def test_progress_line_format_is_pinned():
    assert (
        T.progress("extract", "united-kingdom", done=250, total=1000)
        == "PROGRESS stage=extract region=united-kingdom done=250 total=1000 pct=25"
    )


def test_phase_and_heartbeat_tokens_are_stable():
    assert (
        T.phase_start("extract", "united-kingdom")
        == "PHASE start stage=extract region=united-kingdom"
    )
    assert (
        T.phase_done(
            "reconcile",
            "united-kingdom",
            duration_s=12,
            counts={"places": 4200, "clusters": 4100},
        )
        == "PHASE done stage=reconcile region=united-kingdom duration_s=12 clusters=4100 places=4200"
    )
    assert (
        T.heartbeat("extract", "united-kingdom", done=10000, elapsed_s=40)
        == "HEARTBEAT stage=extract region=united-kingdom done=10000 elapsed_s=40 rate=250"
    )


def test_pct_truncates_and_handles_zero_total():
    assert T.progress("extract", "united-kingdom", done=2, total=3).endswith("pct=66")
    assert T.progress("extract", "united-kingdom", done=0, total=0).endswith("pct=0")


def test_log_path_line_uses_absolute_path(tmp_path):
    assert T.report_log_path(tmp_path / "run.log") == f"LOG path={(tmp_path / 'run.log')}"
