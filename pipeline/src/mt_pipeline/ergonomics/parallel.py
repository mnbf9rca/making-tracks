"""Process-isolated source extraction with deterministic parent-side merge."""

from __future__ import annotations

import multiprocessing
import pathlib
import sqlite3
import sys
from dataclasses import dataclass

from . import merge, staging


@dataclass(frozen=True)
class WorkerResult:
    source: str
    status: str
    count: int = 0
    error: str = ""


def run_extract_parallel(
    conn,
    region_config,
    snapshots: dict,
    *,
    run_id: str,
    enabled_extractors,
    extractor_options: dict,
    status_recorder=None,
    only_source: str | None = None,
    continue_on_source_failure: bool = False,
    staging_root: str | pathlib.Path = ".mt-data",
    worker_timeout_s: float | None = None,
    commit: bool = True,
) -> dict[str, int]:
    root = pathlib.Path(staging_root)
    staging.clean_run(root, run_id)
    processes = []
    try:
        selected = list(enabled_extractors)
        missing = [source for source, _extractor in selected if snapshots.get(source) is None]
        if missing and not continue_on_source_failure:
            source = missing[0]
            _record(
                status_recorder,
                source,
                {"status": "failure", "error": "missing snapshot"},
            )
            raise _missing_snapshot(source)

        staged: dict[str, pathlib.Path] = {}
        ctx = multiprocessing.get_context("spawn")
        for source, extractor in selected:
            snapshot_path = snapshots.get(source)
            if snapshot_path is None:
                _record(
                    status_recorder,
                    source,
                    {"status": "failure", "error": "missing snapshot"},
                )
                continue
            staged[source] = staging.staging_path(root, run_id, source)
            process = ctx.Process(
                target=_worker_main,
                args=(
                    root,
                    run_id,
                    source,
                    extractor,
                    region_config,
                    snapshot_path,
                    extractor_options.get(source, {}),
                ),
            )
            try:
                process.start()
            except Exception as exc:
                _record(
                    status_recorder,
                    source,
                    {
                        "status": "failure",
                        "error": f"{type(exc).__name__}: {exc}"[:500],
                    },
                )
                raise
            processes.append((source, process))

        results: dict[str, WorkerResult] = {}
        for source, process in processes:
            process.join(worker_timeout_s)
            if process.is_alive():
                process.terminate()
                process.join(timeout=1)
                if process.is_alive():
                    process.kill()
                    process.join(timeout=1)
                results[source] = WorkerResult(
                    source,
                    "failure",
                    error="worker timed out",
                )
                continue
            results[source] = _worker_result(source, process.exitcode, staged[source])

        failures = [result for result in results.values() if result.status != "success"]
        if failures and not continue_on_source_failure:
            result = failures[0]
            _record(
                status_recorder,
                result.source,
                {"status": "failure", "error": result.error},
            )
            raise RuntimeError(f"extract worker failed for {result.source}: {result.error}")

        succeeded = {
            source
            for source, result in results.items()
            if result.status == "success"
        }
        if commit:
            with conn:
                merge.merge_sources(
                    conn,
                    staged,
                    succeeded,
                    full=only_source is None,
                    region=region_config.region_id,
                )
        else:
            merge.merge_sources(
                conn,
                staged,
                succeeded,
                full=only_source is None,
                region=region_config.region_id,
            )

        counts = {source: results[source].count for source in sorted(succeeded)}
        for source, result in sorted(results.items()):
            if result.status == "success":
                _record(
                    status_recorder,
                    source,
                    {"status": "success", "count": result.count},
                )
            else:
                _record(status_recorder, source, {"status": "failure", "error": result.error})
        return counts
    finally:
        for _source, process in processes:
            if process.is_alive():
                process.terminate()
                process.join(timeout=1)
        staging.clean_run(root, run_id)


def _worker_main(
    root: pathlib.Path,
    run_id: str,
    source: str,
    extractor,
    region_config,
    snapshot_path,
    extractor_options: dict,
) -> None:
    conn = staging.open_staging(root, run_id, source)
    try:
        from .. import extract_stage

        count = extract_stage._run_one_extract(
            conn,
            source=source,
            extractor=extractor,
            region_config=region_config,
            snapshot_path=snapshot_path,
            run_id=run_id,
            extractor_options={source: extractor_options},
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS extract_worker_success (
                source TEXT PRIMARY KEY,
                count  INTEGER NOT NULL
            )
            """
        )
        conn.execute(
            """
            INSERT INTO extract_worker_success (source, count)
            VALUES (?, ?)
            ON CONFLICT(source) DO UPDATE SET count = excluded.count
            """,
            (source, int(count)),
        )
        conn.commit()
    except Exception as exc:
        _write_worker_failure(conn, source, f"{type(exc).__name__}: {exc}"[:500])
        sys.exit(1)
    finally:
        conn.close()


def _worker_result(source: str, exitcode: int | None, path: pathlib.Path) -> WorkerResult:
    count, failure = _read_worker_sentinel(source, path)
    if exitcode == 0 and count is not None:
        return WorkerResult(source, "success", count=count)
    if failure:
        return WorkerResult(source, "failure", error=failure)
    if exitcode == 0:
        return WorkerResult(source, "failure", error="worker missing success sentinel")
    return WorkerResult(source, "failure", error=f"worker exitcode {exitcode}")


def _read_worker_sentinel(source: str, path: pathlib.Path) -> tuple[int | None, str]:
    if not path.exists():
        return None, "worker produced no staging database"
    conn = sqlite3.connect(path)
    try:
        try:
            row = conn.execute(
                "SELECT count FROM extract_worker_success WHERE source = ?",
                (source,),
            ).fetchone()
            if row is not None:
                return int(row[0]), ""
        except sqlite3.OperationalError:
            pass
        try:
            row = conn.execute(
                "SELECT error FROM extract_worker_failure WHERE source = ?",
                (source,),
            ).fetchone()
            if row is not None:
                return None, str(row[0])
        except sqlite3.OperationalError:
            pass
    finally:
        conn.close()
    return None, ""


def _write_worker_failure(conn, source: str, error: str) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS extract_worker_failure (
            source TEXT PRIMARY KEY,
            error  TEXT NOT NULL
        )
        """
    )
    conn.execute(
        """
        INSERT INTO extract_worker_failure (source, error)
        VALUES (?, ?)
        ON CONFLICT(source) DO UPDATE SET error = excluded.error
        """,
        (source, error),
    )
    conn.commit()


def _missing_snapshot(source: str) -> Exception:
    from .. import extract_stage

    return extract_stage.MissingSnapshotError(f"enabled source {source!r} has no snapshot")


def _record(status_recorder, source: str, status: dict) -> None:
    if status_recorder is not None:
        status_recorder(source, status)
