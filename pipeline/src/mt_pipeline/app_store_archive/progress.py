"""Archive-transfer telemetry using the pipeline's stable stderr protocol."""

from __future__ import annotations

from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor, TimeoutError
from typing import TypeVar

from mt_pipeline.progress import HEARTBEAT_EVERY_SECONDS, PhaseProgress


HEARTBEAT_INTERVAL_SECONDS = HEARTBEAT_EVERY_SECONDS
_T = TypeVar("_T")


def run_blocking_phase(
    name: str,
    *,
    total_bytes: int | None,
    operation: Callable[[], _T],
    heartbeat_every_seconds: float = HEARTBEAT_INTERVAL_SECONDS,
) -> _T:
    """Run one blocking transfer while preserving 30-second liveness evidence."""
    phase = PhaseProgress(
        name,
        region="app-store-archive",
        total=total_bytes,
        total_label="bytes",
        heartbeat_every_seconds=heartbeat_every_seconds,
    )
    phase.start()
    with ThreadPoolExecutor(max_workers=1) as executor:
        future = executor.submit(operation)
        while True:
            try:
                result = future.result(timeout=heartbeat_every_seconds)
            except TimeoutError:
                phase.tick(0, force=True)
                continue
            break
    phase.done(total_bytes or 0)
    return result
