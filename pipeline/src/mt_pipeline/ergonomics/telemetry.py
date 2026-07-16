"""Pinned greppable telemetry lines for pipeline monitors."""

from __future__ import annotations

import pathlib
import sys


def progress(stage: str, region: str, *, done: int, total: int, extra: str = "") -> str:
    pct = 0 if total == 0 else int((100 * done) // total)
    line = f"PROGRESS stage={stage} region={region} done={done} total={total} pct={pct}"
    if extra:
        line = f"{line} {extra}"
    return line


def phase_start(stage: str, region: str) -> str:
    return f"PHASE start stage={stage} region={region}"


def phase_done(
    stage: str,
    region: str,
    *,
    duration_s: int | float,
    counts: dict[str, int] | None = None,
) -> str:
    parts = [
        f"PHASE done stage={stage} region={region} duration_s={_render_number(duration_s)}"
    ]
    for key, value in sorted((counts or {}).items()):
        parts.append(f"{key}={value}")
    return " ".join(parts)


def heartbeat(stage: str, region: str, *, done: int, elapsed_s: int | float) -> str:
    rate = int(done / elapsed_s) if elapsed_s > 0 else 0
    return (
        f"HEARTBEAT stage={stage} region={region} done={done} "
        f"elapsed_s={_render_number(elapsed_s)} rate={rate}"
    )


def report_log_path(path: str | pathlib.Path) -> str:
    return f"LOG path={pathlib.Path(path).resolve()}"


def emit(line: str) -> None:
    print(line, file=sys.stderr)


def _render_number(value: int | float) -> str:
    number = float(value)
    if number.is_integer():
        return str(int(number))
    return f"{number:.1f}"
