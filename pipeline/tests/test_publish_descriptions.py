import json

from mt_pipeline.publish import descriptions as D


def _place(member_refs):
    return {
        "place_id": "mt1_" + "0" * 26,
        "name": "Place",
        "lat": 3.1,
        "lon": 101.7,
        "category": "history",
        "tier": 2,
        "score": 0.7,
        "source_refs": member_refs,
    }


def test_descriptions_use_snapshot_extract_and_non_english_source_url():
    rows = [
        {
            "source_ref": "wp:12345",
            "props": {
                "lang": "ms",
                "title": "Kellie's Castle",
                "extract": "Kellie's Castle ialah sebuah bangunan bersejarah di Perak.",
            },
        }
    ]

    descriptions = D.descriptions_from_source_records([_place(["wp:12345"])], rows)

    assert len(descriptions) == 1
    desc = descriptions[0]
    assert desc.place_id == "mt1_" + "0" * 26
    assert desc.wikipedia_lang == "ms"
    assert desc.wikipedia_title == "Kellie's Castle"
    assert desc.excerpt == "Kellie's Castle ialah sebuah bangunan bersejarah di Perak."
    assert desc.source_ref == "wp:12345"
    assert desc.source_url == "https://ms.wikipedia.org/wiki/Kellie%27s_Castle"
    assert desc.license_code == "CC-BY-SA-4.0"
    assert desc.modified is True


def test_description_excerpt_prefers_sentence_boundary_under_500_chars():
    first = "A" * 240 + "."
    second = "B" * 240 + "."
    third = "C" * 240 + "."
    rows = [
        {
            "source_ref": "wp:1",
            "props": {"lang": "en", "title": "Long", "extract": f"{first} {second} {third}"},
        }
    ]

    descriptions = D.descriptions_from_source_records([_place(["wp:1"])], rows)

    assert descriptions[0].excerpt == f"{first} {second}"
    assert len(descriptions[0].excerpt) <= 500
    assert descriptions[0].excerpt.endswith(".")


def test_description_extraction_sanitizes_control_chars_and_skips_empty_results():
    rows = [
        {
            "source_ref": "wp:1",
            "props": {"lang": "en", "title": "Unsafe", "extract": "A\u202eB"},
        },
        {
            "source_ref": "wp:2",
            "props": {"lang": "en", "title": "Empty", "extract": "\u202e"},
        },
    ]

    descriptions = D.descriptions_from_source_records(
        [_place(["wp:1"]), {**_place(["wp:2"]), "place_id": "mt1_" + "1" * 26}],
        rows,
    )

    assert [desc.excerpt for desc in descriptions] == ["AB"]


def test_emit_description_artifacts_validates_schema_and_keeps_tile_coordinates():
    descriptions = [
        D.PlaceDescription(
            place_id="mt1_" + "0" * 26,
            lat=3.1,
            lon=101.7,
            wikipedia_lang="en",
            wikipedia_title="Kellie's Castle",
            excerpt="Kellie's Castle is an unfinished mansion.",
            source_ref="wp:12345",
            source_url="https://en.wikipedia.org/wiki/Kellie%27s_Castle",
            license_code="CC-BY-SA-4.0",
            license_name="Creative Commons Attribution-ShareAlike 4.0",
            license_url="https://creativecommons.org/licenses/by-sa/4.0/",
            modified=True,
        )
    ]

    artifacts = D.emit_description_artifacts(descriptions)

    assert len(artifacts) == 1
    payload = json.loads(artifacts[0].json_bytes)
    assert payload["schema_version"] == 1
    assert payload["places"][0]["place_id"] == "mt1_" + "0" * 26
    assert payload["places"][0]["wikipedia_lang"] == "en"
    assert payload["places"][0]["source_ref"] == "wp:12345"
