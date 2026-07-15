"""Command-line entry point for the region-parameterised pipeline."""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import re
import sqlite3
import sys
from collections.abc import Sequence

from . import acquire, audit, categorize, config, extract_stage, stages, store
from .eval import golden, report as eval_report

_DEFAULT_RUN_ID = "manual"
_COMMANDS = ("acquire", "acquire-redirects", "audit", *stages.STAGE_ORDER)
_PIPELINE_ROOT = pathlib.Path(__file__).resolve().parents[2]
_DEFAULT_GOLDEN_AREAS = _PIPELINE_ROOT / "config" / "golden_areas.json"
_DEFAULT_EVAL_OUT_DIR = _PIPELINE_ROOT.parent / "docs" / "superpowers" / "eval"
_MAX_JSON_BYTES = 1_000_000
_MAX_TSV_BYTES = 10_000_000
_SAFE_FILENAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")
_VERSION_RE = re.compile(r"^[0-9]{8}T[0-9]{6}Z$")


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
    parser.add_argument(
        "--audit-format",
        choices=("markdown", "json"),
        default="markdown",
        help="output format for the audit command",
    )
    parser.add_argument(
        "--version",
        help="publish version for reconcile, formatted YYYYMMDDThhmmssZ",
    )
    return parser

def _normalize_argv(argv: Sequence[str] | None) -> list[str]:
    """Normalize argv, including the `mt audit <region>` shortcut."""
    if argv is None:
        args = sys.argv[1:]
    else:
        args = list(argv)
    if len(args) >= 2 and args[0] == "audit" and not args[1].startswith("-"):
        return ["--region", args[1], "audit", *args[2:]]
    return args


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
    report.add_argument("--baseline", help="optional metric baseline JSON for regression gate")
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


def _read_text_limited(path: pathlib.Path, *, max_bytes: int) -> str:
    if path.stat().st_size > max_bytes:
        raise ValueError(f"{path} exceeds {max_bytes} byte limit")
    return path.read_text()


def _load_json(path: pathlib.Path, *, max_bytes: int = _MAX_JSON_BYTES):
    return json.loads(_read_text_limited(path, max_bytes=max_bytes))


def _load_mapping_json(path: pathlib.Path) -> dict:
    data = _load_json(path)
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return data


def _load_metric_baseline(path: pathlib.Path) -> dict[str, float]:
    data = _load_mapping_json(path)
    baseline = {}
    for key, value in data.items():
        if not isinstance(key, str):
            raise ValueError("baseline metric keys must be strings")
        if not isinstance(value, int | float) or isinstance(value, bool):
            raise ValueError(f"baseline metric {key!r} must be numeric")
        number = float(value)
        if not math.isfinite(number):
            raise ValueError(f"baseline metric {key!r} must be finite")
        baseline[key] = number
    return baseline


def _safe_filename_token(value: str) -> str:
    if not _SAFE_FILENAME_RE.fullmatch(value):
        raise ValueError(f"{value!r} is not a safe filename token")
    return value


def _load_area_bbox(path: pathlib.Path, area: str) -> list[float]:
    data = _load_mapping_json(path)
    if data.get("version") != "1":
        raise ValueError("golden areas config version must be '1'")
    areas = data.get("areas")
    if not isinstance(areas, dict):
        raise ValueError("golden areas config must contain an areas object")
    bbox = areas.get(area)
    if not isinstance(bbox, list | tuple) or len(bbox) != 4:
        raise ValueError(f"golden area {area!r} must be a four-number bbox")
    out = []
    for value in bbox:
        if not isinstance(value, int | float) or isinstance(value, bool):
            raise ValueError(f"golden area {area!r} bbox values must be numeric")
        number = float(value)
        if not math.isfinite(number):
            raise ValueError(f"golden area {area!r} bbox values must be finite")
        out.append(number)
    minlon, minlat, maxlon, maxlat = out
    if not (-180 <= minlon < maxlon <= 180 and -90 <= minlat < maxlat <= 90):
        raise ValueError(f"golden area {area!r} bbox is out of range")
    return out


def _run_eval(argv) -> int:
    args = _build_eval_parser().parse_args(argv)
    if args.eval_command == "report":
        try:
            labeled_text = _read_text_limited(
                pathlib.Path(args.labeled_tsv), max_bytes=_MAX_TSV_BYTES
            )
            parsed = golden.parse_labeled_tsv(labeled_text)
        except (OSError, ValueError) as exc:
            print(f"eval report error: {exc}", file=sys.stderr)
            return 1
        if parsed.skipped:
            print("label parse skipped rows:", file=sys.stderr)
            for ident, reason in parsed.skipped:
                print(f"- {ident}: {reason}", file=sys.stderr)
            return 1
        try:
            config_data = _load_mapping_json(pathlib.Path(args.config))
            result = eval_report.eval_report(parsed.rows, config_data)
            if args.baseline:
                baseline = _load_metric_baseline(pathlib.Path(args.baseline))
                eval_report.assert_no_regression(parsed.rows, config_data, baseline)
        except (OSError, json.JSONDecodeError) as exc:
            print(f"eval report error: {exc}", file=sys.stderr)
            return 1
        except (AssertionError, RuntimeError, ValueError) as exc:
            print(str(exc), file=sys.stderr)
            return 1
        for key, value in sorted(result.metrics.items()):
            rendered = "undefined" if value is None else f"{value:.3f}"
            print(f"{key}\t{rendered}")
        return 0

    if args.eval_command == "dump":
        try:
            area_token = _safe_filename_token(args.area)
            run_token = _safe_filename_token(args.run_id)
            bbox = _load_area_bbox(pathlib.Path(args.areas_config), args.area)
        except (OSError, json.JSONDecodeError, ValueError) as exc:
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
        stem = f"{run_token}-golden-{area_token}"
        tsv_path = out_dir / f"{stem}.tsv"
        jsonl_path = out_dir / f"{stem}.jsonl"
        tsv_path.write_text(golden.render_tsv(rows))
        jsonl_path.write_text(golden.render_jsonl(rows))
        print(f"wrote {tsv_path}")
        print(f"wrote {jsonl_path}")
        return 0

    raise AssertionError(f"unhandled eval command: {args.eval_command}")


def main(argv=None) -> int:
    argv = _normalize_argv(argv)
    if argv and argv[0] == "eval":
        return _run_eval(argv[1:])

    args = _build_parser().parse_args(argv)
    if args.version is not None and not _VERSION_RE.fullmatch(args.version):
        print("--version must match YYYYMMDDThhmmssZ", file=sys.stderr)
        return 2
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

    if args.stage == "audit":
        try:
            report = audit.audit_region(conn, region.region_id)
        except sqlite3.Error as exc:
            print(f"database error running {args.stage!r}: {exc}", file=sys.stderr)
            return 3
        rendered = (
            audit.render_json(report)
            if args.audit_format == "json"
            else audit.render_markdown(report)
        )
        print(rendered, end="" if rendered.endswith("\n") else "\n")
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
        stages.run_stage(
            conn,
            region.region_id,
            args.stage,
            run_id=args.run_id,
            version=args.version,
        )
    except stages.StageOrderError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except categorize.PlacesTableMissingError as exc:
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
