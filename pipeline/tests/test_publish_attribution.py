import json
import pathlib

import jsonschema
import pytest

from mt_pipeline.publish import attribution as A


PIPELINE_ROOT = pathlib.Path(__file__).resolve().parents[1]
A1D = json.loads((PIPELINE_ROOT / "config/a1d_sources.json").read_text())


def _pid(suffix: str) -> str:
    return "mt1_" + "0" * 25 + suffix


def test_HE_OGL_ships_verbatim_when_an_HE_place_is_present():
    places = [
        {"place_id": _pid("A"), "source_refs": ["hehle:12345"]},
        {"place_id": _pid("B"), "source_refs": ["wd:Q1"]},
    ]
    used = A.sources_used(places)
    assert used == {"historic_england", "wikidata"}
    he = [
        attr
        for attr in A.attribution_for(used, A1D)
        if attr["source"] == "historic_england"
    ][0]
    assert he["license"] == "OGL-UK-3.0"
    assert he["text"] == A1D["historic_england"]["attribution"]
    assert "Open Government Licence" in he["text"]


def test_OSM_is_ODbL_and_ships_attribution():
    out = A.attribution_for(
        A.sources_used([{"place_id": _pid("A"), "source_refs": ["osm:node/1"]}]),
        A1D,
    )
    osm = [attr for attr in out if attr["source"] == "osm"][0]
    assert osm["license"] == "ODbL-1.0"
    assert osm["text"] == A1D["osm"]["attribution"]


def test_basemap_forces_osm_attribution_even_without_osm_place_refs():
    out = A.attribution_for(
        A.sources_used([{"place_id": _pid("A"), "source_refs": ["wd:Q1"]}]),
        A1D,
        includes_osm_basemap=True,
    )

    assert [attr["source"] for attr in out] == ["osm"]
    assert out[0]["license"] == "ODbL-1.0"


def test_cc0_only_region_needs_no_attribution():
    assert A.attribution_for({"wikidata"}, A1D) == []


def test_wikipedia_refs_emit_wikipedia_attribution_not_wikidata():
    sources = A.sources_used(
        [
            {"place_id": _pid("A"), "source_refs": ["wp:12345"]},
            {"place_id": _pid("B"), "source_refs": ["wd:Q1"]},
        ]
    )

    out = A.attribution_for(sources, A1D)

    assert sources == {"wikidata", "wikipedia"}
    assert [attr["source"] for attr in out] == ["wikipedia"]
    assert out[0]["license"] == "CC-BY-SA-4.0"
    assert out[0]["text"] == A1D["wikipedia"]["attribution"]


def test_heuristic_score_provenance_and_current_pointer_are_contracted():
    schema = json.loads((PIPELINE_ROOT.parent / "contracts/schemas/manifest.schema.json").read_text())
    task_id = schema["properties"]["provenance"]["items"]["properties"]["task_id"]
    assert "score" in task_id["enum"]
    assert "attribution" in schema["properties"]
    assert "attribution" not in schema["required"]

    current = json.loads((PIPELINE_ROOT.parent / "contracts/schemas/current.schema.json").read_text())
    assert "publish_version" in current["properties"]
    assert current["additionalProperties"] is False

    from mt_contracts.caps import CAPS_SCHEMA_MAP

    assert any(
        schema_name == "manifest" and "attribution" in path
        for schema_name, path, _keyword in CAPS_SCHEMA_MAP
    )


def test_attribution_string_with_a_control_char_fails_validation():
    schema = json.loads((PIPELINE_ROOT.parent / "contracts/schemas/manifest.schema.json").read_text())
    for key in ("source", "license", "text"):
        bad_attr = {"source": "x", "license": "y", "text": "credit"}
        bad_attr[key] = f"{bad_attr[key]}\u202eevil"
        with pytest.raises(jsonschema.ValidationError):
            jsonschema.validate(
                {"attribution": [bad_attr]},
                {
                    "type": "object",
                    "properties": {"attribution": schema["properties"]["attribution"]},
                },
            )
