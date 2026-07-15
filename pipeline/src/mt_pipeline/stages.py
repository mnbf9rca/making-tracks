"""No-op-but-dispatchable pipeline stages with order enforcement."""

from __future__ import annotations

from . import store

STAGE_ORDER = ("extract", "reconcile", "score", "categorize", "publish")


class StageOrderError(RuntimeError):
    pass


def predecessor(stage: str) -> str | None:
    if stage not in STAGE_ORDER:
        raise ValueError(f"unknown stage: {stage!r}")
    index = STAGE_ORDER.index(stage)
    return None if index == 0 else STAGE_ORDER[index - 1]


def run_stage(conn, region: str, stage: str, *, run_id: str) -> None:
    previous = predecessor(stage)
    if previous is not None and not store.stage_completed(conn, region, previous):
        raise StageOrderError(
            f"cannot run {stage!r} for region {region!r}: run {previous!r} first"
        )
    if stage == "categorize":
        from . import categorize

        categorize.run(conn, region, run_id=run_id)
    store.mark_stage_complete(
        conn,
        region,
        stage,
        run_id=run_id,
        completed_at=_completed_at(),
    )


def _completed_at() -> str:
    import datetime

    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
