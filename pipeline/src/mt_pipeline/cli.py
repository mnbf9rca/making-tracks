"""Command-line entry point for the region-parameterised pipeline."""

from __future__ import annotations

import argparse
import pathlib
import sqlite3
import sys

from . import acquire, config, extract_stage, stages, store

_DEFAULT_RUN_ID = "manual"
_COMMANDS = ("acquire", "acquire-redirects", *stages.STAGE_ORDER)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mt-pipeline",
        description="Making Tracks data pipeline.",
    )
    parser.add_argument("--region", required=True, help="region id, e.g. uk")
    parser.add_argument("stage", choices=_COMMANDS, help="pipeline stage or acquisition step")
    parser.add_argument("--db", default="work.db", help="path to the SQLite store")
    parser.add_argument("--run-id", default=_DEFAULT_RUN_ID, help="run metadata tag")
    parser.add_argument(
        "--data-dir",
        default=".mt-data",
        help="base directory for acquired snapshots; region subdir is used",
    )
    parser.add_argument(
        "--snapshot-dir",
        help="directory containing snapshots for extract or redirect-map acquisition",
    )
    parser.add_argument(
        "--osm-index-type",
        default="flex_mem",
        help="pyosmium location index type for OSM extraction",
    )
    return parser


def _snapshot_dir(args) -> pathlib.Path:
    if args.snapshot_dir:
        return pathlib.Path(args.snapshot_dir)
    return pathlib.Path(args.data_dir) / args.region


def _initial_extract_statuses(sources: dict) -> dict:
    return {
        source: {"status": "not_run" if enabled is True else "disabled"}
        for source, enabled in sorted(sources.items())
    }


def _record_extract_metadata(conn, region, run_id: str, snap_dir, statuses: dict) -> None:
    wikidata_date = ""
    if region.sources.get("wikidata") is True:
        wikidata_date = acquire.wikidata_snapshot_retrieved_at(
            acquire.snapshot_paths(snap_dir)["wikidata"]
        )
    store.record_extract_run_metadata(
        conn,
        region=region.region_id,
        run_id=run_id,
        wikidata_snapshot_date=wikidata_date,
        source_statuses=statuses,
    )


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

    if args.stage == "acquire":
        try:
            paths = acquire.acquire_all(_snapshot_dir(args), region_config=region)
        except acquire.AcquireError as exc:
            print(f"acquisition error: {exc}", file=sys.stderr)
            return 1
        for source, path in sorted(paths.items()):
            print(f"{source}: {path}")
        return 0

    try:
        conn = store.connect(args.db)
        store.init_schema(conn)
    except sqlite3.Error as exc:
        print(f"database error opening {args.db!r}: {exc}", file=sys.stderr)
        return 3

    if args.stage == "acquire-redirects":
        try:
            snap_dir = _snapshot_dir(args)
            path = acquire.acquire_wikidata_redirect_map(
                snap_dir,
                qids=acquire.qids_from_store(conn, region=region.region_id),
                config=acquire.load_config()["wikidata"],
                wikidata_retrieved_at=acquire.wikidata_snapshot_retrieved_at(
                    acquire.snapshot_paths(snap_dir)["wikidata"]
                ),
            )
        except acquire.AcquireError as exc:
            print(f"acquisition error: {exc}", file=sys.stderr)
            return 1
        except sqlite3.Error as exc:
            print(f"database error running {args.stage!r}: {exc}", file=sys.stderr)
            return 3
        print(f"wikidata_redirects: {path}")
        return 0

    try:
        if args.stage == "extract" and args.snapshot_dir:
            snap_dir = pathlib.Path(args.snapshot_dir)
            registry = extract_stage.build_registry(
                acquire.DEFAULT_ALLOWLIST,
                languages=set(region.languages),
            )
            statuses = _initial_extract_statuses(region.sources)

            def record_status(source, status):
                statuses[source] = status

            try:
                counts = extract_stage.run_extract(
                    conn,
                    region,
                    acquire.snapshot_paths(snap_dir),
                    run_id=args.run_id,
                    registry=registry,
                    extractor_options={"osm": {"index_type": args.osm_index_type}},
                    status_recorder=record_status,
                )
            except (
                extract_stage.MissingSnapshotError,
                extract_stage.UnregisteredEnabledSourceError,
                extract_stage.DiskSpaceError,
            ) as exc:
                _record_extract_metadata(conn, region, args.run_id, snap_dir, statuses)
                print(str(exc), file=sys.stderr)
                return 1
            except Exception as exc:
                _record_extract_metadata(conn, region, args.run_id, snap_dir, statuses)
                print(f"extract error: {exc}", file=sys.stderr)
                return 1
            _record_extract_metadata(conn, region, args.run_id, snap_dir, statuses)
            stages.run_stage(conn, region.region_id, args.stage, run_id=args.run_id)
            print(f"{args.stage} complete for {region.region_id}: {counts}")
            return 0
        stages.run_stage(conn, region.region_id, args.stage, run_id=args.run_id)
    except stages.StageOrderError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except (
        extract_stage.MissingSnapshotError,
        extract_stage.UnregisteredEnabledSourceError,
        extract_stage.DiskSpaceError,
    ) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except sqlite3.Error as exc:
        print(f"database error running {args.stage!r}: {exc}", file=sys.stderr)
        return 3

    print(f"{args.stage} complete for {region.region_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
