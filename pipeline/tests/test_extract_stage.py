import pathlib
from dataclasses import dataclass

import pytest

from mt_pipeline import extract_stage, source_record, store

FIXW = pathlib.Path(__file__).parent / "fixtures/wikidata/snapshot.json"


@dataclass(frozen=True)
class FakeRegionConfig:
    region_id: str
    sources: dict


def _conn(tmp_path):
    conn = store.connect(tmp_path / "w.db")
    store.init_schema(conn)
    return conn


def _insert_record(conn, *, source, source_ref, name):
    source_record.persist(
        conn,
        source_record.parse(
            "uk",
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
        region_id="uk",
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
        region_id="uk",
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
            assert region == "uk"
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

    cfg = FakeRegionConfig(region_id="uk", sources={"osm": True})

    counts = extract_stage.run_extract(
        conn,
        cfg,
        {"osm": "osm.pbf"},
        run_id="r1",
        registry=FakeRegistry(),
        extractor_options={"osm": {"index_type": "sparse_file_array,/tmp/osm.idx"}},
    )

    assert counts == {"osm": 7}


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
            FakeRegionConfig(region_id="uk", sources={"wikidata": True}),
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
        FakeRegionConfig(region_id="uk", sources={"wd": True, "osm": True}),
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
            FakeRegionConfig(region_id="uk", sources={"wd": True}),
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
