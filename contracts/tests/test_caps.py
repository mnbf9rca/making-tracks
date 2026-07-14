from mt_contracts import caps
from mt_contracts.validation import load_schema


def test_place_schema_literals_match_caps():
    props = load_schema("place")["properties"]
    assert props["name"]["maxLength"] == caps.NAME_MAX
    assert props["blurb"]["maxLength"] == caps.BLURB_MAX
    assert props["image_url"]["maxLength"] == caps.IMAGE_URL_MAX
    assert props["wikipedia_title"]["maxLength"] == caps.WIKIPEDIA_TITLE_MAX
    assert props["category"]["maxLength"] == caps.CATEGORY_MAX
    assert props["source_refs"]["maxItems"] == caps.SOURCE_REFS_MAX
    assert props["alt_names"]["maxItems"] == caps.ALT_NAMES_MAX


def test_tile_schema_literals_match_caps():
    schema = load_schema("tile")
    assert schema["properties"]["z"]["const"] == caps.TILE_ZOOM
    assert schema["properties"]["places"]["maxItems"] == caps.MAX_PLACES_PER_TILE


def test_overflow_is_deterministic_and_keeps_best():
    places = [
        {"place_id": "mt1_" + "a" * 26, "tier": 4, "score": 0.1},
        {"place_id": "mt1_" + "b" * 26, "tier": 1, "score": 0.9},
        {"place_id": "mt1_" + "c" * 26, "tier": 2, "score": 0.5},
    ]
    kept, dropped = caps.select_tile_places(places, max_per_tile=2)
    assert [p["place_id"] for p in kept] == [
        "mt1_" + "b" * 26,
        "mt1_" + "c" * 26,
    ]
    assert [p["place_id"] for p in dropped] == ["mt1_" + "a" * 26]
    assert caps.select_tile_places(places, max_per_tile=2) == (kept, dropped)


def test_overflow_stable_tie_break_by_place_id():
    a = {"place_id": "mt1_" + "1" * 26, "tier": 1, "score": 0.5}
    b = {"place_id": "mt1_" + "2" * 26, "tier": 1, "score": 0.5}
    kept, dropped = caps.select_tile_places([b, a], max_per_tile=1)
    assert [p["place_id"] for p in kept] == ["mt1_" + "1" * 26]
    assert [p["place_id"] for p in dropped] == ["mt1_" + "2" * 26]
