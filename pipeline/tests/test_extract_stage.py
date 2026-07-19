import json
import pathlib
import os
import time
from dataclasses import dataclass

import pytest

from mt_pipeline import extract_stage, source_record, store

FIXW = pathlib.Path(__file__).parent / "fixtures/wikidata/snapshot.json"


@dataclass(frozen=True)
class FakeRegionConfig:
    region_id: str
    sources: dict


class ParallelWritingExtractor:
    def __init__(self, stored_source: str, ref: str, name: str, *, delay_s: float = 0):
        self.stored_source = stored_source
        self.ref = ref
        self.name = name
        self.delay_s = delay_s

    def extract(self, region, snapshot_path, conn, *, run_id):
        if self.delay_s:
            time.sleep(self.delay_s)
        source_record.persist(
            conn,
            source_record.parse(
                region,
                self.stored_source,
                self.ref,
                self.name,
                1.0,
                2.0,
                {"snapshot": str(snapshot_path)},
            ),
            run_id=run_id,
        )
        return 1


class OptionRecordingExtractor:
    def extract(
        self,
        region,
        snapshot_path,
        conn,
        *,
        run_id,
        pageview_cache_dir,
        pageview_window,
    ):
        source_record.persist(
            conn,
            source_record.parse(
                region,
                "wp",
                "wp:123",
                "A",
                1.0,
                2.0,
                {
                    "snapshot": str(snapshot_path),
                    "pageview_cache_dir": str(pageview_cache_dir),
                    "pageview_window": list(pageview_window),
                },
            ),
            run_id=run_id,
        )
        return 1


class OptionRecordingRegistry:
    def registered_sources(self):
        return {"wikipedia"}

    def enabled_for(self, _sources):
        return [("wikipedia", OptionRecordingExtractor())]


class ParallelFakeRegistry:
    def __init__(self, order, *, delays=None):
        self.order = tuple(order)
        delays = delays or {}
        self.extractors = {
            "wikidata": ParallelWritingExtractor(
                "wd", "wd:Q1", "WD", delay_s=delays.get("wikidata", 0.05)
            ),
            "osm": ParallelWritingExtractor(
                "osm",
                "osm:node/1",
                "OSM",
                delay_s=delays.get("osm", 0),
            ),
        }

    def registered_sources(self):
        return set(self.extractors)

    def enabled_for(self, _sources):
        return [(source, self.extractors[source]) for source in self.order]


class CrashingExtractor:
    def extract(self, *_args, **_kwargs):
        os._exit(9)


class CrashRegistry:
    def registered_sources(self):
        return {"wikidata"}

    def enabled_for(self, _sources):
        return [("wikidata", CrashingExtractor())]


def _conn(tmp_path):
    tmp_path.mkdir(parents=True, exist_ok=True)
    conn = store.connect(tmp_path / "w.db")
    store.init_schema(conn)
    return conn


def _insert_record(conn, *, source, source_ref, name):
    source_record.persist(
        conn,
        source_record.parse(
            "united-kingdom",
            source,
            source_ref,
            name,
            1.0,
            2.0,
            {"name": name},
        ),
        run_id="old",
    )


def test_runs_only_enabled_extractors_from_regionconfig(tmp_path):
    conn = _conn(tmp_path)
    reg = extract_stage.build_registry(
        pathlib.Path(__file__).parents[1] / "config/wikidata_class_allowlist.json",
        languages={"en"},
    )
    cfg = FakeRegionConfig(
        region_id="united-kingdom",
        sources={
            "wikidata": True,
            "wikipedia": False,
            "osm": False,
            "historic_england": False,
            "open_plaques": False,
            "national_register": {"id": "national_register", "enabled": False},
        },
    )
    counts = extract_stage.run_extract(
        conn, cfg, {"wikidata": str(FIXW)}, run_id="r1", registry=reg
    )
    assert counts == {"wikidata": 1}
    assert conn.execute("SELECT COUNT(*) FROM source_records").fetchone()[0] == 1


def test_enabled_but_unregistered_source_fails_loudly(tmp_path):
    conn = _conn(tmp_path)
    reg = extract_stage.build_registry(
        pathlib.Path(__file__).parents[1] / "config/wikidata_class_allowlist.json",
        languages={"en"},
    )
    cfg = FakeRegionConfig(
        region_id="united-kingdom",
        sources={"wikidata": True, "unknown_register": True},
    )
    with pytest.raises(
        extract_stage.UnregisteredEnabledSourceError, match="unknown_register"
    ):
        extract_stage.run_extract(
            conn, cfg, {"wikidata": str(FIXW)}, run_id="r1", registry=reg
        )


def test_run_extract_passes_source_specific_options(tmp_path):
    conn = _conn(tmp_path)

    class FakeExtractor:
        def extract(self, region, snapshot_path, conn, *, run_id, index_type):
            assert region == "united-kingdom"
            assert snapshot_path == "osm.pbf"
            assert run_id == "r1"
            assert index_type == "sparse_file_array,/tmp/osm.idx"
            return 7

    class FakeRegistry:
        def registered_sources(self):
            return {"osm"}

        def enabled_for(self, sources):
            assert sources == {"osm": True}
            return [("osm", FakeExtractor())]

    cfg = FakeRegionConfig(region_id="united-kingdom", sources={"osm": True})

    counts = extract_stage.run_extract(
        conn,
        cfg,
        {"osm": "osm.pbf"},
        run_id="r1",
        registry=FakeRegistry(),
        extractor_options={"osm": {"index_type": "sparse_file_array,/tmp/osm.idx"}},
    )

    assert counts == {"osm": 7}


def test_run_extract_parallel_passes_source_specific_options_to_worker(tmp_path):
    conn = _conn(tmp_path)
    snapshot = tmp_path / "wikipedia.snapshot.json"
    snapshot.write_text("{}")
    cache_dir = tmp_path / "pageviews"

    counts = extract_stage.run_extract(
        conn,
        FakeRegionConfig(region_id="malaysia-singapore-brunei", sources={"wikipedia": True}),
        {"wikipedia": snapshot},
        run_id="r1",
        registry=OptionRecordingRegistry(),
        extractor_options={
            "wikipedia": {
                "pageview_cache_dir": cache_dir,
                "pageview_window": ("2025-07-15", "2026-07-15"),
            }
        },
        parallel=True,
        staging_root=tmp_path / "staging",
    )

    assert counts == {"wikipedia": 1}
    props = json.loads(
        conn.execute(
            "SELECT props_json FROM source_records WHERE source_ref = ?",
            ("wp:123",),
        ).fetchone()[0]
    )
    assert props["pageview_cache_dir"] == str(cache_dir)
    assert props["pageview_window"] == ["2025-07-15", "2026-07-15"]


def test_run_extract_records_disk_floor_failure(monkeypatch, tmp_path):
    conn = _conn(tmp_path)
    statuses = {}

    class FakeExtractor:
        def extract(self, *_args, **_kwargs):
            raise AssertionError("disk guard should run before extractor")

    class FakeRegistry:
        def registered_sources(self):
            return {"wikidata"}

        def enabled_for(self, _sources):
            return [("wikidata", FakeExtractor())]

    monkeypatch.setattr(
        extract_stage,
        "assert_disk_floor",
        lambda _path: (_ for _ in ()).throw(extract_stage.DiskSpaceError("low disk")),
    )

    with pytest.raises(extract_stage.DiskSpaceError, match="low disk"):
        extract_stage.run_extract(
            conn,
            FakeRegionConfig(region_id="united-kingdom", sources={"wikidata": True}),
            {"wikidata": tmp_path / "wikidata.snapshot.json"},
            run_id="r1",
            registry=FakeRegistry(),
            status_recorder=lambda source, status: statuses.update({source: status}),
        )

    assert statuses == {
        "wikidata": {"status": "failure", "error": "DiskSpaceError: low disk"}
    }


def test_run_extract_only_source_replaces_that_source_after_staged_success(tmp_path):
    conn = _conn(tmp_path)
    _insert_record(conn, source="wd", source_ref="wd:Q1", name="Old WD")
    _insert_record(conn, source="osm", source_ref="osm:node/1", name="Keep OSM")

    class FakeExtractor:
        def extract(self, region, snapshot_path, conn, *, run_id):
            source_record.persist(
                conn,
                source_record.parse(
                    region,
                    "wd",
                    "wd:Q2",
                    "New WD",
                    3.0,
                    4.0,
                    {"snapshot": str(snapshot_path)},
                ),
                run_id=run_id,
            )
            return 1

    class FakeRegistry:
        def registered_sources(self):
            return {"wd", "osm"}

        def enabled_for(self, _sources):
            return [("wd", FakeExtractor())]

    counts = extract_stage.run_extract(
        conn,
        FakeRegionConfig(region_id="united-kingdom", sources={"wd": True, "osm": True}),
        {"wd": tmp_path / "wd.json"},
        run_id="new",
        registry=FakeRegistry(),
        only_source="wd",
    )

    assert counts == {"wd": 1}
    assert conn.execute(
        "SELECT source, source_ref, name, run_id FROM source_records ORDER BY source_ref"
    ).fetchall() == [
        ("osm", "osm:node/1", "Keep OSM", "old"),
        ("wd", "wd:Q2", "New WD", "new"),
    ]


def test_run_extract_only_source_preserves_existing_rows_when_staging_fails(tmp_path):
    conn = _conn(tmp_path)
    _insert_record(conn, source="wd", source_ref="wd:Q1", name="Old WD")
    statuses = {}

    class FailingExtractor:
        def extract(self, *_args, **_kwargs):
            raise RuntimeError("bad snapshot")

    class FakeRegistry:
        def registered_sources(self):
            return {"wd"}

        def enabled_for(self, _sources):
            return [("wd", FailingExtractor())]

    with pytest.raises(RuntimeError, match="bad snapshot"):
        extract_stage.run_extract(
            conn,
            FakeRegionConfig(region_id="united-kingdom", sources={"wd": True}),
            {"wd": tmp_path / "wd.json"},
            run_id="new",
            registry=FakeRegistry(),
            only_source="wd",
            status_recorder=lambda source, status: statuses.update({source: status}),
        )

    assert conn.execute(
        "SELECT source_ref, name, run_id FROM source_records"
    ).fetchall() == [("wd:Q1", "Old WD", "old")]
    assert statuses == {
        "wd": {"status": "failure", "error": "RuntimeError: bad snapshot"}
    }


def test_run_extract_parallel_merge_is_deterministic_across_worker_order(tmp_path):
    cfg = FakeRegionConfig(region_id="united-kingdom", sources={"wikidata": True, "osm": True})
    snapshots = {}
    for source in cfg.sources:
        snapshot = tmp_path / f"{source}.snapshot"
        snapshot.write_text(source)
        snapshots[source] = snapshot

    rows_by_order = []
    for index, order in enumerate((("osm", "wikidata"), ("wikidata", "osm"))):
        conn = _conn(tmp_path / str(index))
        counts = extract_stage.run_extract(
            conn,
            cfg,
            snapshots,
            run_id="r1",
            registry=ParallelFakeRegistry(order),
            parallel=True,
            staging_root=tmp_path / f"staging-{index}",
        )
        rows_by_order.append(
            conn.execute(
                """
                SELECT id, source, source_ref, name, run_id
                FROM source_records
                ORDER BY id
                """
            ).fetchall()
        )
        assert counts == {"osm": 1, "wikidata": 1}

    assert rows_by_order[0] == rows_by_order[1] == [
        (1, "wd", "wd:Q1", "WD", "r1"),
        (2, "osm", "osm:node/1", "OSM", "r1"),
    ]


def test_run_extract_parallel_merge_is_deterministic_across_completion_order(tmp_path):
    cfg = FakeRegionConfig(region_id="united-kingdom", sources={"wikidata": True, "osm": True})
    snapshots = {}
    for source in cfg.sources:
        snapshot = tmp_path / f"{source}.snapshot"
        snapshot.write_text(source)
        snapshots[source] = snapshot

    rows_by_delay = []
    for index, delays in enumerate(
        (
            {"wikidata": 0.08, "osm": 0},
            {"wikidata": 0, "osm": 0.08},
        )
    ):
        conn = _conn(tmp_path / f"db-{index}")
        extract_stage.run_extract(
            conn,
            cfg,
            snapshots,
            run_id="r1",
            registry=ParallelFakeRegistry(("wikidata", "osm"), delays=delays),
            parallel=True,
            staging_root=tmp_path / f"staging-completion-{index}",
        )
        rows_by_delay.append(
            conn.execute(
                """
                SELECT id, source, source_ref, name, props_json, run_id
                FROM source_records
                ORDER BY id
                """
            ).fetchall()
        )

    assert rows_by_delay[0] == rows_by_delay[1]


def test_run_extract_parallel_workers_stage_before_parent_merge(monkeypatch, tmp_path):
    from mt_pipeline.ergonomics import merge as merge_module

    original_merge = merge_module.merge_sources
    observed = {}

    def assert_staged_before_merge(main_conn, staged, succeeded, **kwargs):
        observed["succeeded"] = set(succeeded)
        observed["staged"] = {source: pathlib.Path(path) for source, path in staged.items()}
        assert main_conn.execute("SELECT COUNT(*) FROM source_records").fetchone()[0] == 0
        assert set(staged) == {"wikidata", "osm"}
        assert set(succeeded) == {"wikidata", "osm"}
        assert observed["staged"]["wikidata"] != observed["staged"]["osm"]
        for path in observed["staged"].values():
            assert path.exists()
        original_merge(main_conn, staged, succeeded, **kwargs)

    monkeypatch.setattr(merge_module, "merge_sources", assert_staged_before_merge)

    cfg = FakeRegionConfig(region_id="united-kingdom", sources={"wikidata": True, "osm": True})
    snapshots = {}
    for source in cfg.sources:
        snapshot = tmp_path / f"{source}.snapshot"
        snapshot.write_text(source)
        snapshots[source] = snapshot
    conn = _conn(tmp_path / "db")

    extract_stage.run_extract(
        conn,
        cfg,
        snapshots,
        run_id="r1",
        registry=ParallelFakeRegistry(("wikidata", "osm")),
        parallel=True,
        staging_root=tmp_path / "staging-proof",
    )

    assert observed["succeeded"] == {"wikidata", "osm"}


def test_run_extract_parallel_cleans_staging_after_success(tmp_path):
    cfg = FakeRegionConfig(region_id="united-kingdom", sources={"wikidata": True})
    snapshot = tmp_path / "wikidata.snapshot"
    snapshot.write_text("wikidata")
    staging_root = tmp_path / "staging-clean"

    extract_stage.run_extract(
        _conn(tmp_path / "db"),
        cfg,
        {"wikidata": snapshot},
        run_id="../hostile",
        registry=ParallelFakeRegistry(("wikidata",)),
        parallel=True,
        staging_root=staging_root,
    )

    assert not any((staging_root / "staging").glob("*"))


def test_run_extract_parallel_only_source_replaces_selected_source(tmp_path):
    conn = _conn(tmp_path)
    _insert_record(conn, source="wd", source_ref="wd:Q0", name="Old WD")
    _insert_record(conn, source="osm", source_ref="osm:node/1", name="Keep OSM")
    cfg = FakeRegionConfig(region_id="united-kingdom", sources={"wikidata": True, "osm": True})
    wikidata_snapshot = tmp_path / "wikidata.snapshot"
    wikidata_snapshot.write_text("wikidata")

    counts = extract_stage.run_extract(
        conn,
        cfg,
        {"wikidata": wikidata_snapshot},
        run_id="r2",
        registry=ParallelFakeRegistry(("wikidata", "osm")),
        only_source="wikidata",
        parallel=True,
        staging_root=tmp_path / "staging-only",
    )

    assert counts == {"wikidata": 1}
    assert conn.execute(
        """
        SELECT source, source_ref, name, run_id
        FROM source_records
        ORDER BY source, source_ref
        """
    ).fetchall() == [
        ("osm", "osm:node/1", "Keep OSM", "old"),
        ("wd", "wd:Q1", "WD", "r2"),
    ]


def test_run_extract_parallel_fail_fast_records_failure_without_partial_merge(tmp_path):
    conn = _conn(tmp_path)
    statuses = {}
    cfg = FakeRegionConfig(region_id="united-kingdom", sources={"wikidata": True, "osm": True})
    wd_snapshot = tmp_path / "wikidata.snapshot"
    wd_snapshot.write_text("wikidata")

    with pytest.raises(extract_stage.MissingSnapshotError, match="osm"):
        extract_stage.run_extract(
            conn,
            cfg,
            {"wikidata": wd_snapshot},
            run_id="r1",
            registry=ParallelFakeRegistry(("wikidata", "osm")),
            parallel=True,
            staging_root=tmp_path / "staging",
            status_recorder=lambda source, status: statuses.update({source: status}),
        )

    assert conn.execute("SELECT COUNT(*) FROM source_records").fetchone()[0] == 0
    assert statuses["osm"] == {"status": "failure", "error": "missing snapshot"}
    assert "wikidata" not in statuses


def test_run_extract_parallel_continue_records_failed_not_absent(tmp_path):
    conn = _conn(tmp_path)
    statuses = {}
    cfg = FakeRegionConfig(region_id="united-kingdom", sources={"wikidata": True, "osm": True})
    wd_snapshot = tmp_path / "wikidata.snapshot"
    wd_snapshot.write_text("wikidata")

    counts = extract_stage.run_extract(
        conn,
        cfg,
        {"wikidata": wd_snapshot},
        run_id="r1",
        registry=ParallelFakeRegistry(("wikidata", "osm")),
        parallel=True,
        continue_on_source_failure=True,
        staging_root=tmp_path / "staging",
        status_recorder=lambda source, status: statuses.update({source: status}),
    )

    assert counts == {"wikidata": 1}
    assert statuses == {
        "osm": {"status": "failure", "error": "missing snapshot"},
        "wikidata": {"status": "success", "count": 1},
    }
    assert conn.execute(
        "SELECT source, source_ref FROM source_records"
    ).fetchall() == [("wd", "wd:Q1")]


def test_run_extract_parallel_worker_crash_uses_exitcode_not_exception(tmp_path):
    conn = _conn(tmp_path)
    statuses = {}
    snapshot = tmp_path / "wikidata.snapshot"
    snapshot.write_text("wikidata")

    with pytest.raises(RuntimeError, match="worker exitcode 9"):
        extract_stage.run_extract(
            conn,
            FakeRegionConfig(region_id="united-kingdom", sources={"wikidata": True}),
            {"wikidata": snapshot},
            run_id="r1",
            registry=CrashRegistry(),
            parallel=True,
            staging_root=tmp_path / "staging",
            status_recorder=lambda source, status: statuses.update({source: status}),
        )

    assert statuses == {
        "wikidata": {"status": "failure", "error": "worker exitcode 9"}
    }
    assert conn.execute("SELECT COUNT(*) FROM source_records").fetchone()[0] == 0
