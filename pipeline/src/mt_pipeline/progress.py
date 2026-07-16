"""Greppable progress telemetry for long-running pipeline phases."""

from __future__ import annotations

import sys
import time
from collections.abc import Callable

HEARTBEAT_EVERY_RECORDS = 10_000
HEARTBEAT_EVERY_SECONDS = 30.0


class PhaseProgress:
    def __init__(
        self,
        name: str,
        *,
        region: str,
        total: int | None,
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

    def _total_display(self) -> str:
        return "unknown" if self.total is None else str(self.total)

    def start(self) -> None:
        print(
            f"PHASE START {self.name} region={self.region} "
            f"{self.total_label}={self._total_display()}",
            file=sys.stderr,
        )

    def tick(
        self,
        processed: int,
        *,
        extra: str | Callable[[], str] = "",
        force: bool = False,
    ) -> None:
        now = time.monotonic()
        if force or processed % self.heartbeat_every_records == 0 or (
            now - self.last_heartbeat
        ) >= self.heartbeat_every_seconds:
            self.last_heartbeat = now
            elapsed = now - self.started
            rate = processed / elapsed if elapsed > 0 else 0.0
            extra_text = extra() if callable(extra) else extra
            print(
                f"PHASE HEARTBEAT {self.name} region={self.region} "
                f"processed={processed}/{self._total_display()} rate={rate:.1f}/s "
                f"elapsed={elapsed:.1f}s{extra_text}",
                file=sys.stderr,
            )

    def done(self, processed: int, *, extra: str = "") -> None:
        elapsed = time.monotonic() - self.started
        print(
            f"PHASE DONE {self.name} region={self.region} "
            f"processed={processed}/{self._total_display()} elapsed={elapsed:.1f}s{extra}",
            file=sys.stderr,
        )


class LivePhaseProgress:
    def __init__(
        self,
        *,
        model_id: str,
        total: int,
        cache_hits: int,
        initial_cost: float = 0.0,
        heartbeat_every_calls: int = 10,
        heartbeat_every_seconds: float = 15.0,
    ) -> None:
        self.model_id = model_id
        self.total = total
        self.completed = cache_hits
        self.cache_hits = cache_hits
        self.cost = initial_cost
        self.heartbeat_every_calls = heartbeat_every_calls
        self.heartbeat_every_seconds = heartbeat_every_seconds
        self.started = time.monotonic()
        self.last_heartbeat = self.started
        self.last_heartbeat_completed = cache_hits

    def start(self) -> None:
        print(
            f"PHASE START model={self.model_id} total={self.total} "
            f"completed={self.completed}/{self.total} cache_hits={self.cache_hits} "
            f"cost_usd={self.cost:.8f}",
            file=sys.stderr,
        )

    def tick(self, cost_usd: float, *, completed_delta: int = 1) -> None:
        self.completed += completed_delta
        self.cost += cost_usd
        now = time.monotonic()
        if (
            self.completed - self.last_heartbeat_completed >= self.heartbeat_every_calls
            or now - self.last_heartbeat >= self.heartbeat_every_seconds
        ):
            self._print("HEARTBEAT", now)
            self.last_heartbeat = now
            self.last_heartbeat_completed = self.completed

    def done(self) -> None:
        self._print("PHASE DONE", time.monotonic())

    def _print(self, label: str, now: float) -> None:
        elapsed = max(now - self.started, 1e-9)
        rate = self.completed / elapsed
        print(
            f"{label} model={self.model_id} completed={self.completed}/{self.total} "
            f"rate_per_s={rate:.2f} cache_hits={self.cache_hits} cost_usd={self.cost:.8f}",
            file=sys.stderr,
        )
