"""Command-line entry point for the region-parameterised pipeline."""

from __future__ import annotations

import argparse
import sqlite3
import sys

from . import config, stages, store

_DEFAULT_RUN_ID = "manual"


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mt-pipeline",
        description="Making Tracks data pipeline.",
    )
    parser.add_argument("--region", required=True, help="region id, e.g. uk")
    parser.add_argument("stage", choices=stages.STAGE_ORDER, help="pipeline stage to run")
    parser.add_argument("--db", default="work.db", help="path to the SQLite store")
    parser.add_argument("--run-id", default=_DEFAULT_RUN_ID, help="run metadata tag")
    return parser


def main(argv=None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        region = config.load(args.region)
    except config.UnknownRegionError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except config.ConfigError as exc:
        print(f"config error: {exc}", file=sys.stderr)
        return 3

    try:
        conn = store.connect(args.db)
        store.init_schema(conn)
    except sqlite3.Error as exc:
        print(f"database error opening {args.db!r}: {exc}", file=sys.stderr)
        return 3

    try:
        stages.run_stage(conn, region.region_id, args.stage, run_id=args.run_id)
    except stages.StageOrderError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    print(f"{args.stage} complete for {region.region_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
