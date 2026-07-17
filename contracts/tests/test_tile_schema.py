import json

from mt_contracts import caps
from mt_contracts.validation import is_valid, load_schema, validate_instance


def test_tile_schema_literals_match_caps():
    schema = load_schema("tile")
    assert schema["properties"]["z"]["const"] == caps.TILE_ZOOM
    assert schema["properties"]["places"]["maxItems"] == caps.MAX_PLACES_PER_TILE


def test_valid_tile_fixture_passes(contracts_root):
    inst = json.loads((contracts_root / "fixtures/tile/valid/one_place.json").read_text())
    validate_instance("tile", inst)


def test_tile_with_bad_place_fails(contracts_root):
    inst = json.loads((contracts_root / "fixtures/tile/invalid/bad_place.json").read_text())
    assert not is_valid("tile", inst)


def test_tile_rejects_nested_noncanonical_known_source_ref(contracts_root):
    inst = json.loads((contracts_root / "fixtures/tile/valid/one_place.json").read_text())
    inst["places"][0]["source_refs"] = ["wd:q1"]
    assert not is_valid("tile", inst)


def test_tile_wrong_zoom_fails(contracts_root):
    inst = json.loads((contracts_root / "fixtures/tile/invalid/wrong_zoom.json").read_text())
    assert not is_valid("tile", inst)


def test_tile_xy_out_of_range_fails(contracts_root):
    inst = json.loads(
        (contracts_root / "fixtures/tile/invalid/xy_out_of_range.json").read_text()
    )
    assert not is_valid("tile", inst)
