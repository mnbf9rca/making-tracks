import json

import pytest

from mt_contracts.validation import is_valid, validate_instance


def _load_dir(root, sub):
    d = root / "fixtures/place" / sub
    return sorted(d.glob("*.json"))


def test_valid_place_fixtures_all_pass(contracts_root):
    files = _load_dir(contracts_root, "valid")
    assert files, "expected at least one valid place fixture"
    for fixture in files:
        validate_instance("place", json.loads(fixture.read_text()))


@pytest.mark.parametrize(
    "field",
    [
        "oversize_blurb",
        "http_image_url",
        "bad_tier",
        "lat_out_of_range",
        "missing_place_id",
        "control_char_name",
        "control_char_blurb",
        "bidi_name",
        "noncanonical_ref",
        "empty_source_refs",
    ],
)
def test_invalid_place_fixtures_all_fail(contracts_root, field):
    inst = json.loads(
        (contracts_root / f"fixtures/place/invalid/{field}.json").read_text()
    )
    assert not is_valid("place", inst), f"{field} should have failed validation"


def test_non_finite_floats_are_rejected():
    import math

    bad = {
        "place_id": "mt1_" + "0" * 26,
        "name": "X",
        "lat": math.nan,
        "lon": 0,
        "category": "c",
        "tier": 1,
        "score": 0.5,
        "source_refs": ["wd:Q1"],
    }
    assert not is_valid("place", bad)
