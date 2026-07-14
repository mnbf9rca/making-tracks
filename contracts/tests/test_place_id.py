import json

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


def test_shipped_ids_validate_after_a_future_mint_scheme_bump(monkeypatch):
    from mt_contracts import place_id as pid

    shipped = pid.mint_place_id("wd:Q42")
    monkeypatch.setattr(pid, "_ID_SCHEME_VERSION", 2)
    monkeypatch.setattr(pid, "PLACE_ID_PREFIX", "mt2_")
    assert pid.is_valid_place_id(shipped)


def test_current_mint_scheme_is_a_known_scheme():
    from mt_contracts.place_id import KNOWN_ID_SCHEMES, _ID_SCHEME_VERSION

    assert _ID_SCHEME_VERSION in KNOWN_ID_SCHEMES


def test_canonical_ref():
    assert canonical_ref("wd", "Q42") == "wd:Q42"


def test_mint_rejects_noncanonical_key():
    import pytest

    for bad in ["WD:Q42", "wd: Q42", "wd:Q42 ", "osm:Way/456", "wd:Qé", "foo:1"]:
        with pytest.raises(ValueError):
            mint_place_id(bad)


def test_conformance_vectors_cover_every_source_type(contracts_root):
    vectors = json.loads((contracts_root / "fixtures/place_id/frozen_vectors.json").read_text())
    prefixes = {row["mint_key"].split(":", 1)[0] for row in vectors}
    assert {"wd", "osm", "hehle", "plaque"} <= prefixes


def test_anchor_priority_prefers_wikidata():
    refs = ["osm:way/10", "wd:Q7", "plaque:openplaques/3"]
    assert select_mint_anchor(refs) == "wd:Q7"


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
