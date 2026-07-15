import pathlib
from dataclasses import dataclass

import pytest

from mt_pipeline import extract_stage, store

FIX = pathlib.Path(__file__).parent / "fixtures/osm/sample.osm"
CFG = pathlib.Path(__file__).parents[1] / "config/osm_candidate_tags.json"
ALLOWLIST = pathlib.Path(__file__).parents[1] / "config/wikidata_class_allowlist.json"


@dataclass(frozen=True)
class RC:
    region_id: str
    sources: dict


def _enabled_osm_config():
    return RC(
        "uk",
        {
            "wikidata": False,
            "wikipedia": False,
            "osm": True,
            "historic_england": False,
            "open_plaques": False,
            "national_register": None,
        },
    )


def test_osm_registered_and_run_when_enabled(tmp_path):
    conn = store.connect(tmp_path / "w.db")
    store.init_schema(conn)
    registry = extract_stage.build_registry(
        allowlist_path=ALLOWLIST,
        languages={"en"},
        osm_tag_config_path=CFG,
    )

    counts = extract_stage.run_extract(
        conn,
        _enabled_osm_config(),
        {"osm": str(FIX)},
        run_id="r1",
        registry=registry,
    )

    assert counts == {"osm": 2}


def test_osm_registered_by_default_without_explicit_config_path(tmp_path):
    conn = store.connect(tmp_path / "w.db")
    store.init_schema(conn)
    registry = extract_stage.build_registry(allowlist_path=ALLOWLIST, languages={"en"})

    counts = extract_stage.run_extract(
        conn,
        _enabled_osm_config(),
        {"osm": str(FIX)},
        run_id="r1",
        registry=registry,
    )

    assert counts == {"osm": 2}


def test_enabled_osm_without_snapshot_fails_loudly(tmp_path):
    conn = store.connect(tmp_path / "w.db")
    store.init_schema(conn)
    registry = extract_stage.build_registry(allowlist_path=ALLOWLIST, languages={"en"})

    with pytest.raises(extract_stage.MissingSnapshotError, match="osm"):
        extract_stage.run_extract(
            conn,
            _enabled_osm_config(),
            {},
            run_id="r1",
            registry=registry,
        )
