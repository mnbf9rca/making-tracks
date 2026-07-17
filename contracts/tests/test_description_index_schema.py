import copy

from mt_contracts.validation import is_valid, validate_instance


VALID_INDEX = {
    "schema_version": 1,
    "min_reader_version": 1,
    "z": 10,
    "x": 511,
    "y": 340,
    "places": [
        {
            "place_id": "mt1_00000000000000000000000001",
            "wikipedia_lang": "ms",
            "wikipedia_title": "Kellie's Castle",
            "excerpt": "Kellie's Castle is an unfinished mansion in Batu Gajah, Perak.",
            "source_ref": "wp:12345",
            "source_url": "https://ms.wikipedia.org/wiki/Kellie%27s_Castle",
            "license_code": "CC-BY-SA-4.0",
            "license_name": "Creative Commons Attribution-ShareAlike 4.0",
            "license_url": "https://creativecommons.org/licenses/by-sa/4.0/",
            "modified": True,
            "excerpted": True,
        }
    ],
}


def test_valid_description_index_passes():
    validate_instance("description-index", VALID_INDEX)


def test_description_index_requires_modified_true_for_excerpted_wikipedia_text():
    inst = copy.deepcopy(VALID_INDEX)
    inst["places"][0]["modified"] = False

    assert not is_valid("description-index", inst)


def test_description_index_requires_excerpted_true_for_excerpted_wikipedia_text():
    inst = copy.deepcopy(VALID_INDEX)
    del inst["places"][0]["excerpted"]
    assert not is_valid("description-index", inst)

    inst = copy.deepcopy(VALID_INDEX)
    inst["places"][0]["excerpted"] = False
    assert not is_valid("description-index", inst)


def test_description_index_rejects_control_chars_and_oversize_excerpt():
    inst = copy.deepcopy(VALID_INDEX)
    inst["places"][0]["excerpt"] = "A\u202eB"
    assert not is_valid("description-index", inst)

    inst = copy.deepcopy(VALID_INDEX)
    inst["places"][0]["excerpt"] = "x" * 501
    assert not is_valid("description-index", inst)

    inst = copy.deepcopy(VALID_INDEX)
    inst["places"][0]["excerpt"] = "A <b>bold</b> place."
    assert not is_valid("description-index", inst)

    inst = copy.deepcopy(VALID_INDEX)
    inst["places"][0]["wikipedia_title"] = "Unsafe <Title>"
    assert not is_valid("description-index", inst)


def test_description_index_requires_language_specific_wikipedia_source_url():
    inst = copy.deepcopy(VALID_INDEX)
    inst["places"][0]["source_url"] = "https://example.org/wiki/Kellie"
    assert not is_valid("description-index", inst)

    inst = copy.deepcopy(VALID_INDEX)
    inst["places"][0]["source_url"] = "https://en.wikipedia.org/wiki/Bad?x=1"
    assert not is_valid("description-index", inst)

    inst = copy.deepcopy(VALID_INDEX)
    inst["places"][0]["source_url"] = "https://x.wikipedia.org/wiki/Bad"
    assert not is_valid("description-index", inst)


def test_description_index_requires_source_url_host_to_match_wikipedia_lang():
    inst = copy.deepcopy(VALID_INDEX)
    inst["places"][0]["source_url"] = "https://en.wikipedia.org/wiki/Kellie%27s_Castle"

    assert not is_valid("description-index", inst)


def test_description_index_requires_explicit_language_code():
    inst = copy.deepcopy(VALID_INDEX)
    del inst["places"][0]["wikipedia_lang"]
    assert not is_valid("description-index", inst)

    inst = copy.deepcopy(VALID_INDEX)
    inst["places"][0]["wikipedia_lang"] = "EN"
    assert not is_valid("description-index", inst)


def test_description_index_rejects_non_wikipedia_license():
    inst = copy.deepcopy(VALID_INDEX)
    inst["places"][0]["license_code"] = "CC-BY-4.0"
    inst["places"][0]["license_url"] = "https://creativecommons.org/licenses/by/4.0/"

    assert not is_valid("description-index", inst)
