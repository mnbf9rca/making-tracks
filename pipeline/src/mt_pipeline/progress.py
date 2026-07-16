"""Greppable progress telemetry for long-running pipeline phases."""

from __future__ import annotations

import sys
import time

HEARTBEAT_EVERY_RECORDS = 10_000
HEARTBEAT_EVERY_SECONDS = 30.0


class PhaseProgress:
    def __init__(
        self,
        name: str,
        *,
        region: str,
        total: int,
        total_label: str,
        heartbeat_every_records: int = HEARTBEAT_EVERY_RECORDS,
        heartbeat_every_seconds: float = HEARTBEAT_EVERY_SECONDS,
    ):
        self.name = name
        self.region = region
        self.total = total
        self.total_label = total_label
        self.heartbeat_every_records = heartbeat_every_records
        self.heartbeat_every_seconds = heartbeat_every_seconds
        self.started = time.monotonic()
        self.last_heartbeat = self.started

    def start(self) -> None:
        print(
            f"PHASE START {self.name} region={self.region} "
            f"{self.total_label}={self.total}",
            file=sys.stderr,
        )

    def tick(self, processed: int) -> None:
        now = time.monotonic()
        if processed % self.heartbeat_every_records == 0 or (
            now - self.last_heartbeat
        ) >= self.heartbeat_every_seconds:
            self.last_heartbeat = now
            elapsed = now - self.started
            rate = processed / elapsed if elapsed > 0 else 0.0
            print(
                f"PHASE HEARTBEAT {self.name} region={self.region} "
                f"processed={processed}/{self.total} rate={rate:.1f}/s "
                f"elapsed={elapsed:.1f}s",
                file=sys.stderr,
            )

    def done(self, processed: int, *, extra: str = "") -> None:
        elapsed = time.monotonic() - self.started
        print(
            f"PHASE DONE {self.name} region={self.region} "
            f"processed={processed}/{self.total} elapsed={elapsed:.1f}s{extra}",
            file=sys.stderr,
        )
