import pathlib
from dataclasses import dataclass

from mt_pipeline import extract_stage, store

REG_FIX = pathlib.Path(__file__).parent / "fixtures/registers"
ALLOWLIST = pathlib.Path(__file__).parents[1] / "config/wikidata_class_allowlist.json"


@dataclass(frozen=True)
class RC:
    region_id: str
    sources: dict


def _registry():
    return extract_stage.build_registry(allowlist_path=ALLOWLIST, languages={"en"})


def test_registers_are_registered_by_default_and_run_when_enabled(tmp_path):
    conn = store.connect(tmp_path / "w.db")
    store.init_schema(conn)
    registry = _registry()
    cfg = RC(
        "united-kingdom",
        {
            "wikidata": False,
            "wikipedia": False,
            "osm": False,
            "historic_england": True,
            "open_plaques": True,
        },
    )

    counts = extract_stage.run_extract(
        conn,
        cfg,
        {
            "historic_england": str(REG_FIX / "he_sample.geojson"),
            "open_plaques": str(REG_FIX / "plaques_sample.json"),
        },
        run_id="r1",
        registry=registry,
    )

    assert counts == {"historic_england": 2, "open_plaques": 2}


def test_national_register_object_is_not_treated_as_enabled(tmp_path):
    conn = store.connect(tmp_path / "w.db")
    store.init_schema(conn)
    registry = _registry()
    cfg = RC(
        "united-kingdom",
        {
            "historic_england": False,
            "open_plaques": True,
            "national_register": {"id": "malaysia_heritage", "enabled": False},
        },
    )

    counts = extract_stage.run_extract(
        conn,
        cfg,
        {"open_plaques": str(REG_FIX / "plaques_sample.json")},
        run_id="r1",
        registry=registry,
    )

    assert counts == {"open_plaques": 2}


def test_registered_key_with_truthy_non_true_value_does_not_run(tmp_path):
    conn = store.connect(tmp_path / "w.db")
    store.init_schema(conn)
    registry = _registry()
    cfg = RC("united-kingdom", {"open_plaques": {"enabled": True}})

    counts = extract_stage.run_extract(
        conn,
        cfg,
        {"open_plaques": str(REG_FIX / "plaques_sample.json")},
        run_id="r1",
        registry=registry,
    )

    assert counts == {}
