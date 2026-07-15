"""Command-line entry point for the region-parameterised pipeline."""

from __future__ import annotations

import argparse
import json
import pathlib
import sqlite3
import sys

from . import acquire, config, extract_stage, stages, store
from .eval import golden, report as eval_report

_DEFAULT_RUN_ID = "manual"
_COMMANDS = ("acquire", "acquire-redirects", *stages.STAGE_ORDER)
_PIPELINE_ROOT = pathlib.Path(__file__).resolve().parents[2]
_DEFAULT_GOLDEN_AREAS = _PIPELINE_ROOT / "config" / "golden_areas.json"
_DEFAULT_EVAL_OUT_DIR = _PIPELINE_ROOT.parent / "docs" / "superpowers" / "eval"


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
    parser.add_argument(
        "--only-source",
        help="for extract, replace only one enabled source from cached snapshot",
    )
    return parser


def _build_eval_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mt-pipeline eval",
        description="Making Tracks ranking eval tools.",
    )
    subparsers = parser.add_subparsers(dest="eval_command", required=True)

    dump = subparsers.add_parser("dump", help="dump a golden area TSV+JSONL pair")
    dump.add_argument("area", help="golden area id, e.g. london or kl")
    dump.add_argument("--db", default="work.db", help="path to the SQLite store")
    dump.add_argument("--run-id", default=_DEFAULT_RUN_ID, help="data version tag")
    dump.add_argument(
        "--areas-config",
        default=str(_DEFAULT_GOLDEN_AREAS),
        help="path to golden_areas.json",
    )
    dump.add_argument(
        "--out-dir",
        default=str(_DEFAULT_EVAL_OUT_DIR),
        help="directory for TSV+JSONL dumps",
    )

    report = subparsers.add_parser("report", help="score a labeled golden TSV")
    report.add_argument("labeled_tsv", help="hand-labeled golden TSV")
    report.add_argument("--config", required=True, help="scoring JSON config")
    return parser


def _snapshot_dir(args) -> pathlib.Path:
    if args.snapshot_dir:
        return pathlib.Path(args.snapshot_dir)
    return pathlib.Path(args.data_dir) / args.region


def _initial_extract_statuses(sources: dict, *, only_source: str | None = None) -> dict:
    return {
        source: {
            "status": (
                "disabled"
                if enabled is not True
                else "preserved"
                if only_source is not None and source != only_source
                else "not_run"
            )
        }
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


def _load_json(path: pathlib.Path):
    with path.open() as f:
        return json.load(f)


def _run_eval(argv) -> int:
    args = _build_eval_parser().parse_args(argv)
    if args.eval_command == "report":
        parsed = golden.parse_labeled_tsv(pathlib.Path(args.labeled_tsv).read_text())
        if parsed.skipped:
            print("label parse skipped rows:", file=sys.stderr)
            for ident, reason in parsed.skipped:
                print(f"- {ident}: {reason}", file=sys.stderr)
            return 1
        try:
            config_data = _load_json(pathlib.Path(args.config))
            result = eval_report.eval_report(parsed.rows, config_data)
        except (OSError, json.JSONDecodeError) as exc:
            print(f"eval report error: {exc}", file=sys.stderr)
            return 1
        except RuntimeError as exc:
            print(str(exc), file=sys.stderr)
            return 1
        for key, value in sorted(result.metrics.items()):
            rendered = "undefined" if value is None else f"{value:.3f}"
            print(f"{key}\t{rendered}")
        return 0

    if args.eval_command == "dump":
        try:
            areas_config = _load_json(pathlib.Path(args.areas_config))
            bbox = areas_config["areas"][args.area]
        except (KeyError, OSError, json.JSONDecodeError) as exc:
            print(f"eval dump config error: {exc}", file=sys.stderr)
            return 1
        try:
            conn = store.connect(args.db)
            rows = golden.dump_area(conn, args.area, bbox, data_version=args.run_id)
        except (sqlite3.Error, RuntimeError, ValueError) as exc:
            print(str(exc), file=sys.stderr)
            return 1
        out_dir = pathlib.Path(args.out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        stem = f"{args.run_id}-golden-{args.area}"
        tsv_path = out_dir / f"{stem}.tsv"
        jsonl_path = out_dir / f"{stem}.jsonl"
        tsv_path.write_text(golden.render_tsv(rows))
        jsonl_path.write_text(golden.render_jsonl(rows))
        print(f"wrote {tsv_path}")
        print(f"wrote {jsonl_path}")
        return 0

    raise AssertionError(f"unhandled eval command: {args.eval_command}")


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else list(argv)
    if argv and argv[0] == "eval":
        return _run_eval(argv[1:])

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
            statuses = _initial_extract_statuses(
                region.sources, only_source=args.only_source
            )

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
                    only_source=args.only_source,
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
