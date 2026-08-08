from __future__ import annotations

import re
import time

from mt_pipeline.app_store_archive.progress import (
    HEARTBEAT_INTERVAL_SECONDS,
    run_blocking_phase,
)


def test_blocking_archive_phase_uses_the_30_second_stderr_progress_protocol(
    capsys,
):
    result = run_blocking_phase(
        "app_store_archive.copy",
        total_bytes=12,
        operation=lambda: (time.sleep(0.02), "copied")[1],
        heartbeat_every_seconds=0.005,
    )

    assert result == "copied"
    assert HEARTBEAT_INTERVAL_SECONDS == 30.0
    lines = capsys.readouterr().err.splitlines()
    assert lines[0] == (
        "PHASE START app_store_archive.copy region=app-store-archive bytes=12"
    )
    assert any(
        re.fullmatch(
            r"PHASE HEARTBEAT app_store_archive\.copy region=app-store-archive "
            r"processed=0/12 rate=0\.0/s elapsed=0\.\ds",
            line,
        )
        for line in lines
    )
    assert re.fullmatch(
        r"PHASE DONE app_store_archive\.copy region=app-store-archive "
        r"processed=12/12 elapsed=0\.\ds",
        lines[-1],
    )
