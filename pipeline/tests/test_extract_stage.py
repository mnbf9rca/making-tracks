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
        sources={"wikidata": True, "historic_england": True},
    )
    with pytest.raises(
        extract_stage.UnregisteredEnabledSourceError, match="historic_england"
    ):
        extract_stage.run_extract(
            conn, cfg, {"wikidata": str(FIXW)}, run_id="r1", registry=reg
        )
