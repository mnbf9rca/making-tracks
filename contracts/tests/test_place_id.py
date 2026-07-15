import json
import pytest

from mt_contracts.place_id import (
    PLACE_ID_PREFIX,
    canonical_ref,
    is_valid_place_id,
    mint_place_id,
    select_mint_anchor,
)


def test_format_and_prefix():
    pid = mint_place_id("wd:Q42")
    assert pid.startswith(PLACE_ID_PREFIX)
    assert is_valid_place_id(pid)
    assert len(pid) == len(PLACE_ID_PREFIX) + 26


def test_mint_is_deterministic():
    assert mint_place_id("wd:Q42") == mint_place_id("wd:Q42")


def test_distinct_keys_distinct_ids():
    assert mint_place_id("wd:Q42") != mint_place_id("wd:Q43")


def test_rejects_malformed_ids():
    assert not is_valid_place_id("mt1_short")
    assert not is_valid_place_id("Q42")
    assert not is_valid_place_id("mt1_" + "I" * 26)
    assert not is_valid_place_id("mt2_" + "0" * 26)


def test_validation_regex_is_derived_from_known_schemes_not_current():
    from mt_contracts.place_id import _build_place_id_re

    both = _build_place_id_re(frozenset({1, 2}))
    assert both.fullmatch("mt1_" + "0" * 26)
    assert both.fullmatch("mt2_" + "0" * 26)
    only1 = _build_place_id_re(frozenset({1}))
    assert only1.fullmatch("mt1_" + "0" * 26)
    assert not only1.fullmatch("mt2_" + "0" * 26)


def test_current_mint_scheme_is_a_known_scheme():
    from mt_contracts.place_id import KNOWN_ID_SCHEMES, _ID_SCHEME_VERSION

    assert _ID_SCHEME_VERSION in KNOWN_ID_SCHEMES


def test_independent_frozen_vector_cross_check():
    assert mint_place_id("wd:Q42") == "mt1_1Q831BXYQ8GP7ZXKVQZH87G0R5"


def test_canonical_ref():
    assert canonical_ref("wd", "Q42") == "wd:Q42"


def test_mint_rejects_noncanonical_key():
    for bad in [
        "WD:Q42",
        "wd: Q42",
        "wd:Q42 ",
        "osm:Way/456",
        "wd:Qé",
        "foo:1",
        "wd:Q42\n",
        "wp:",
        "wp:abc",
        "wp:-1",
        "wp:123/4",
    ]:
        with pytest.raises(ValueError):
            mint_place_id(bad)


def test_wikipedia_page_id_is_a_canonical_mint_key():
    assert canonical_ref("wp", "12345") == "wp:12345"
    assert mint_place_id("wp:12345") == "mt1_5FAJ9QTWS33BNY38TA4QZJX3FY"


def test_conformance_vectors_cover_every_source_type(contracts_root):
    vectors = json.loads((contracts_root / "fixtures/place_id/frozen_vectors.json").read_text())
    prefixes = {row["mint_key"].split(":", 1)[0] for row in vectors}
    assert {"wd", "osm", "hehle", "plaque", "wp"} <= prefixes


def test_frozen_vectors_are_append_only(contracts_root):
    vectors = json.loads((contracts_root / "fixtures/place_id/frozen_vectors.json").read_text())
    assert vectors[:5] == [
        {"mint_key": "wd:Q42", "place_id": "mt1_1Q831BXYQ8GP7ZXKVQZH87G0R5"},
        {"mint_key": "osm:node/9", "place_id": "mt1_3M2432K5GF3ZMWBQGTXV4VSYY3"},
        {"mint_key": "osm:way/456", "place_id": "mt1_65HZT2JBN7RQDWJT7A5B23TD16"},
        {"mint_key": "hehle:1234567", "place_id": "mt1_0V2SX8GR1EJSRW7FGBW06E64C4"},
        {
            "mint_key": "plaque:openplaques/9876",
            "place_id": "mt1_71TWYPX9FM12XK5WG3RPHPEJ3J",
        },
    ]
    assert {"mint_key": "wp:12345", "place_id": "mt1_5FAJ9QTWS33BNY38TA4QZJX3FY"} in vectors[5:]


def test_anchor_priority_prefers_wikidata():
    refs = ["osm:way/10", "wd:Q7", "plaque:openplaques/3"]
    assert select_mint_anchor(refs) == "wd:Q7"


def test_anchor_priority_places_wikipedia_page_ids_last():
    refs = ["wp:12345", "plaque:openplaques/3", "hehle:5", "osm:relation/9"]
    assert select_mint_anchor(refs) == "osm:relation/9"
    assert select_mint_anchor(["wp:12345", "plaque:openplaques/3"]) == "plaque:openplaques/3"


def test_anchor_priority_osm_type_and_numeric_order():
    refs = ["osm:way/2", "osm:node/100", "osm:node/9"]
    assert select_mint_anchor(refs) == "osm:node/9"


def test_anchor_is_order_independent():
    a = select_mint_anchor(["wd:Q9", "osm:node/1", "hehle:5"])
    b = select_mint_anchor(["hehle:5", "osm:node/1", "wd:Q9"])
    assert a == b == "wd:Q9"


def test_frozen_vectors_never_change(contracts_root):
    vectors = json.loads(
        (contracts_root / "fixtures/place_id/frozen_vectors.json").read_text()
    )
    for row in vectors:
        assert mint_place_id(row["mint_key"]) == row["place_id"], row["mint_key"]
