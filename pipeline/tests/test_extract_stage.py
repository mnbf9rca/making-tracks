import pathlib
from dataclasses import dataclass

import pytest

from mt_pipeline import extract_stage, store

FIXW = pathlib.Path(__file__).parent / "fixtures/wikidata/snapshot.json"


@dataclass(frozen=True)
class FakeRegionConfig:
    region_id: str
    sources: dict


def _conn(tmp_path):
    conn = store.connect(tmp_path / "w.db")
    store.init_schema(conn)
    return conn


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
