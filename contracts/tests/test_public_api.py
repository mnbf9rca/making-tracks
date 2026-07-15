import pytest

import mt_contracts
from mt_contracts.text import SAFE_TEXT_PATTERN, SAFE_TEXT_RE
from mt_contracts.validation import load_schema


def test_is_canonical_ref_export_validates_known_sources():
    assert mt_contracts.is_canonical_ref("wd:Q42")
    assert mt_contracts.is_canonical_ref("wp:12345")
    assert mt_contracts.is_canonical_ref("foo:bar")
    assert not mt_contracts.is_canonical_ref("wd:q42")
    assert not mt_contracts.is_canonical_ref("osm:Way/1")
    assert not mt_contracts.is_canonical_ref("wp:abc")


def test_strip_unsafe_text_matches_schema_denylist_and_preserves_lrm_rlm():
    unsafe = "\x00\x1f\x7f\x85\u200b\u200c\u200d\u2028\u2029\u202a\u202e\u2060\u2066\u2069\ufeff"
    value = f"A{unsafe}\u200eB\u200f"
    assert mt_contracts.strip_unsafe_text(value) == "A\u200eB\u200f"


def test_safe_text_pattern_is_shared_with_all_schema_literals():
    place = load_schema("place")
    region_config = load_schema("region-config")
    schema_patterns = [
        place["properties"]["name"]["pattern"],
        place["properties"]["alt_names"]["items"]["pattern"],
        place["properties"]["category"]["pattern"],
        place["properties"]["blurb"]["pattern"],
        place["properties"]["wikipedia_title"]["pattern"],
        region_config["properties"]["display_name"]["pattern"],
    ]
    assert schema_patterns == [SAFE_TEXT_PATTERN] * len(schema_patterns)


def test_strip_unsafe_text_matches_safe_text_regex_for_control_ranges():
    for codepoint in [*range(0x2100), 0xFEFF]:
        ch = chr(codepoint)
        kept = mt_contracts.strip_unsafe_text(ch)
        assert (kept == ch) == bool(SAFE_TEXT_RE.fullmatch(ch)), hex(codepoint)
    assert mt_contracts.strip_unsafe_text("\u200e\u200f") == "\u200e\u200f"


def test_region_config_accessors_load_valid_configs():
    assert mt_contracts.available_regions() == ["malaysia", "uk"]
    uk = mt_contracts.load_region_config("uk")
    assert uk["region_id"] == "uk"
    assert set(uk) == {
        "schema_version",
        "region_id",
        "display_name",
        "bbox",
        "languages",
        "sources",
        "basemap",
    }


def test_load_region_config_rejects_traversal():
    with pytest.raises(ValueError):
        mt_contracts.load_region_config("../uk")
