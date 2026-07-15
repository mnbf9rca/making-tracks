import json

from mt_pipeline.score import rarity as R


RARITY_KEYS = {
    "historic",
    "tourism",
    "memorial",
    "amenity",
    "building",
    "man_made",
    "leisure",
    "natural",
}


def test_rare_categorical_tag_scores_higher_than_common():
    freq = R.tag_value_frequency_from_tagsets(
        [
            {"historic": "castle"},
            {"historic": "castle"},
            {"historic": "folly"},
        ],
        RARITY_KEYS,
    )

    assert R.rarity_score({"historic=folly"}, freq) > R.rarity_score(
        {"historic=castle"}, freq
    )


def test_identifier_and_name_tags_are_not_counted():
    freq = R.tag_value_frequency_from_tagsets(
        [
            {"name": "Unique Place A", "historic": "castle"},
            {"name": "Unique Place B", "historic": "castle"},
        ],
        RARITY_KEYS,
    )

    assert "name=Unique Place A" not in freq
    assert R.rarity_score({"name=Something Never Seen"}, freq) == 0.0


def test_tag_value_frequency_reads_osm_props_for_region_only(conn):
    conn.execute(
        """
        INSERT INTO source_records
            (region, source, source_ref, name, lat, lon, props_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            "malaysia",
            "osm",
            "node/1",
            "A",
            3.0,
            101.0,
            json.dumps({"tags": {"historic": "fort", "name": "A"}}),
            "r1",
        ),
    )
    conn.execute(
        """
        INSERT INTO source_records
            (region, source, source_ref, name, lat, lon, props_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            "uk",
            "osm",
            "node/2",
            "B",
            51.0,
            -0.1,
            json.dumps({"tags": {"historic": "castle"}}),
            "r1",
        ),
    )

    assert R.tag_value_frequency(conn, "malaysia", rarity_keys=RARITY_KEYS) == {
        "historic=fort": 1
    }


def test_malformed_props_and_frequency_values_do_not_crash(conn):
    conn.execute(
        """
        INSERT INTO source_records
            (region, source, source_ref, name, lat, lon, props_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            "malaysia",
            "osm",
            "node/1",
            "A",
            3.0,
            101.0,
            json.dumps(["not", "an", "object"]),
            "r1",
        ),
    )

    assert R.tag_value_frequency(conn, "malaysia", rarity_keys=RARITY_KEYS) == {}
    assert R.rarity_score({"historic=fort"}, {"historic=fort": "bad"}) == 0.0
