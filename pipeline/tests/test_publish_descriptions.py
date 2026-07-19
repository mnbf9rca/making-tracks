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


def _desc(place_id, *, lat=3.1, lon=101.7, source_ref="wp:1", excerpt="Extract."):
    return D.PlaceDescription(
        place_id=place_id,
        lat=lat,
        lon=lon,
        tier=2,
        score=0.5,
        wikipedia_lang="en",
        wikipedia_title=f"Title {source_ref.removeprefix('wp:')}",
        excerpt=excerpt,
        source_ref=source_ref,
        source_url=(
            "https://en.wikipedia.org/wiki/"
            f"Title_{source_ref.removeprefix('wp:')}"
        ),
        license_code="CC-BY-SA-4.0",
        license_name="Creative Commons Attribution-ShareAlike 4.0",
        license_url="https://creativecommons.org/licenses/by-sa/4.0/",
        modified=True,
        excerpted=True,
    )


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
    assert desc.excerpted is True


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


def test_description_excerpt_prefers_preserved_description_extract_over_capped_extract():
    first = "A" * 320 + "."
    second = "B" * 120 + "."
    third = "C" * 120 + "."
    rows = [
        {
            "source_ref": "wp:1",
            "props": {
                "lang": "en",
                "title": "Long",
                "extract": first[:300],
                "description_extract": f"{first} {second} {third}",
            },
        }
    ]

    descriptions = D.descriptions_from_source_records([_place(["wp:1"])], rows)

    assert descriptions[0].excerpt == f"{first} {second}"
    assert len(descriptions[0].excerpt) > 300
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


def test_description_extraction_normalizes_paragraphs_and_strips_markup_markers():
    rows = [
        {
            "source_ref": "wp:1",
            "props": {
                "lang": "en",
                "title": "Unsafe <Title>",
                "description_extract": "First paragraph.\nSecond <b>paragraph</b>.",
            },
        }
    ]

    descriptions = D.descriptions_from_source_records([_place(["wp:1"])], rows)

    assert descriptions[0].wikipedia_title == "Unsafe Title"
    assert descriptions[0].excerpt == "First paragraph. Second bparagraph/b."


def test_description_extraction_uses_first_valid_retained_wikipedia_ref():
    rows = [
        {
            "source_ref": "wp:1",
            "props": {"lang": "x", "title": "Invalid", "extract": "Bad lang."},
        },
        {
            "source_ref": "wp:2",
            "props": {"lang": "en", "title": "Valid", "extract": "Valid extract."},
        },
    ]

    descriptions = D.descriptions_from_source_records([_place(["wp:1", "wp:2"])], rows)

    assert len(descriptions) == 1
    assert descriptions[0].source_ref == "wp:2"
    assert descriptions[0].excerpt == "Valid extract."


def test_emit_description_artifacts_validates_schema_and_keeps_tile_coordinates():
    descriptions = [
        _desc(
            "mt1_" + "0" * 26,
            source_ref="wp:12345",
            excerpt="Kellie's Castle is an unfinished mansion.",
        )
    ]

    artifacts = D.emit_description_artifacts(descriptions)

    assert len(artifacts) == 1
    payload = json.loads(artifacts[0].json_bytes)
    assert payload["schema_version"] == 1
    assert payload["places"][0]["place_id"] == "mt1_" + "0" * 26
    assert payload["places"][0]["wikipedia_lang"] == "en"
    assert payload["places"][0]["source_ref"] == "wp:12345"
    assert payload["places"][0]["excerpted"] is True


def test_emit_description_artifacts_enforces_utf8_byte_cap(monkeypatch):
    monkeypatch.setattr(D, "MAX_DESCRIPTION_INDEX_BYTES", 1600, raising=False)
    descriptions = [
        _desc(
            place_id="mt1_" + str(i) * 26,
            excerpt="é" * 500,
            source_ref=f"wp:{i + 1}",
        )
        for i in range(2)
    ]

    artifacts = D.emit_description_artifacts(descriptions)

    assert len(artifacts) == 1
    assert artifacts[0].byte_len <= 1600
    payload = json.loads(artifacts[0].json_bytes)
    assert [place["place_id"] for place in payload["places"]] == ["mt1_" + "0" * 26]
    assert payload["places"][0]["excerpt"] == "é" * 500


def test_emit_description_result_trims_by_tier_score_and_reports_drops(monkeypatch, caplog):
    monkeypatch.setattr(D, "MAX_DESCRIPTION_INDEX_BYTES", 1600, raising=False)
    low = _desc(
        "mt1_" + "0" * 26,
        source_ref="wp:1",
        excerpt="L" * 500,
    )
    high = D.PlaceDescription(
        **{**low.__dict__, "place_id": "mt1_" + "1" * 26, "tier": 1, "score": 0.99, "source_ref": "wp:2"}
    )

    caplog.set_level("WARNING")
    result = D.emit_description_result([low, high], region="united-kingdom")

    assert result.dropped_count == 1
    payload = json.loads(result.artifacts[0].json_bytes)
    assert [place["place_id"] for place in payload["places"]] == ["mt1_" + "1" * 26]
    assert "description sidecar trimmed" in caplog.text


def test_emit_description_artifacts_is_deterministic_by_tile_and_place_order():
    descriptions = [
        _desc("mt1_" + "3" * 26, lat=51.5, lon=-0.1, source_ref="wp:3"),
        _desc("mt1_" + "2" * 26, lat=3.1, lon=101.7, source_ref="wp:2"),
        _desc("mt1_" + "1" * 26, lat=3.1, lon=101.7, source_ref="wp:1"),
    ]

    first = D.emit_description_artifacts(descriptions)
    second = D.emit_description_artifacts(reversed(descriptions))

    assert [(art.x, art.y) for art in first] == sorted((art.x, art.y) for art in first)
    assert [art.json_bytes for art in first] == [art.json_bytes for art in second]
    grouped_place_ids = [
        [place["place_id"] for place in json.loads(art.json_bytes)["places"]]
        for art in first
    ]
    assert grouped_place_ids == [sorted(place_ids) for place_ids in grouped_place_ids]
