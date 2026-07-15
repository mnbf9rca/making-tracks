import itertools
import json

from mt_pipeline import categorize as CZ
from mt_pipeline import stages, store


TAX = {
    "categories": ["history", "culture", "memorials", "architecture"],
    "uncovered": "uncategorized",
    "precedence": ["wd_p31", "osm_tag", "hehle", "plaque"],
    "class_map": {"Q23413": "history", "Q33506": "culture"},
    "tag_map": {"historic=castle": "history", "memorial=*": "memorials"},
    "source_map": {"hehle": "architecture", "plaque": "memorials"},
}

A2_PLACES_DDL = """
CREATE TABLE places (
    place_id         TEXT PRIMARY KEY,
    region           TEXT NOT NULL,
    name             TEXT NOT NULL,
    lat              REAL NOT NULL,
    lon              REAL NOT NULL,
    refs_json        TEXT NOT NULL,
    member_refs_json TEXT NOT NULL,
    status           TEXT NOT NULL
)
"""


def _signals(**kwargs):
    return {"wd_p31": set(), "osm_tag": set(), "hehle": False, "plaque": False, **kwargs}


def test_wd_class_wins_by_precedence():
    assert (
        CZ.category_for(_signals(wd_p31={"Q33506"}, osm_tag={"historic=castle"}), TAX)
        == "culture"
    )


def test_osm_tag_wildcard():
    assert CZ.category_for(_signals(osm_tag={"memorial=statue"}), TAX) == "memorials"


def test_hehle_and_plaque_map_via_source_map():
    assert CZ.category_for(_signals(hehle=True), TAX) == "architecture"
    assert CZ.category_for(_signals(plaque=True), TAX) == "memorials"
    assert CZ.category_for(_signals(wd_p31={"Q23413"}, hehle=True), TAX) == "history"


def test_source_map_values_are_config_driven():
    tax = {
        **TAX,
        "categories": ["alpha", "beta"],
        "class_map": {},
        "tag_map": {},
        "source_map": {"hehle": "beta", "plaque": "alpha"},
    }

    assert CZ.category_for(_signals(hehle=True), tax) == "beta"
    assert CZ.category_for(_signals(plaque=True), tax) == "alpha"


def test_tiebreak_is_lexically_first_category_not_key():
    tax = {**TAX, "class_map": {"Q1": "zebra", "Q2": "apple"}, "categories": ["zebra", "apple"]}
    assert CZ.category_for(_signals(wd_p31={"Q1", "Q2"}), tax) == "apple"


def test_uncovered_goes_to_marker_never_crashes():
    assert (
        CZ.category_for(_signals(wd_p31={"Q999999"}, osm_tag={"amenity=bench"}), TAX)
        == "uncategorized"
    )


def test_only_config_labels_are_emittable():
    allowed = set(TAX["categories"]) | {TAX["uncovered"]}
    for p31, tag, hehle, plaque in itertools.product(
        ["Q23413", "QX"], ["historic=castle", "junk=1"], [False, True], [False, True]
    ):
        assert (
            CZ.category_for(
                _signals(wd_p31={p31}, osm_tag={tag}, hehle=hehle, plaque=plaque), TAX
            )
            in allowed
        )


def _seed_run(rows, places):
    conn = store.connect(":memory:")
    store.init_schema(conn)
    conn.execute(A2_PLACES_DDL)
    for row in rows:
        conn.execute(
            """
            INSERT INTO source_records
                (region, source, source_ref, name, lat, lon, props_json, run_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            row,
        )
    for place_id, member_refs in places:
        conn.execute(
            """
            INSERT INTO places
                (place_id, region, name, lat, lon, refs_json, member_refs_json, status)
            VALUES (?, 'uk', ?, 1, 1, '[]', ?, 'live')
            """,
            (place_id, place_id, json.dumps(member_refs)),
        )
    conn.commit()
    return conn


def test_run_requires_a2_places_table():
    conn = store.connect(":memory:")
    store.init_schema(conn)

    try:
        CZ.run(conn, "uk", run_id="cat1", taxonomy=TAX)
    except CZ.PlacesTableMissingError as exc:
        assert "A2 places table" in str(exc)
    else:
        raise AssertionError("categorize.run should fail closed until A2 places exists")


def test_run_writes_place_categories_from_a2_places_shape():
    conn = _seed_run(
        [
            ("uk", "wd", "wd:Q1", "Museum", 1, 1, json.dumps({"p31": "Q33506"}), "r"),
            ("uk", "osm", "osm:node/1", "Castle", 1, 1, json.dumps({"historic": "castle"}), "r"),
            ("uk", "hehle", "hehle:1", "Listed", 1, 1, json.dumps({"grade": "I"}), "r"),
            ("uk", "plaque", "plaque:1", "Plaque", 1, 1, json.dumps({}), "r"),
            ("uk", "wd", "wd:QX", "Tail", 1, 1, json.dumps({"p31": "Q999999"}), "r"),
        ],
        [
            ("place-culture", ["wd:Q1", "osm:node/1"]),
            ("place-architecture", ["hehle:1"]),
            ("place-memorial", ["plaque:1"]),
            ("place-tail", ["wd:QX"]),
        ],
    )

    hist = CZ.run(conn, "uk", run_id="cat1", taxonomy=TAX)

    assert list(hist.items()) == [
        ("culture", 1),
        ("memorials", 1),
        ("architecture", 1),
        ("uncategorized", 1),
    ]
    rows = conn.execute(
        "SELECT place_id, category, run_id FROM place_categories ORDER BY place_id"
    ).fetchall()
    assert rows == [
        ("place-architecture", "architecture", "cat1"),
        ("place-culture", "culture", "cat1"),
        ("place-memorial", "memorials", "cat1"),
        ("place-tail", "uncategorized", "cat1"),
    ]


def test_run_removes_stale_place_categories_for_region():
    conn = _seed_run(
        [("uk", "wd", "wd:Q1", "Museum", 1, 1, json.dumps({"p31": "Q33506"}), "r")],
        [("p", ["wd:Q1"])],
    )
    CZ.run(conn, "uk", run_id="cat1", taxonomy=TAX)
    conn.execute("UPDATE places SET status = 'tombstoned' WHERE place_id = 'p'")
    conn.commit()

    assert CZ.run(conn, "uk", run_id="cat2", taxonomy=TAX) == {}
    assert conn.execute("SELECT * FROM place_categories WHERE place_id = 'p'").fetchall() == []


def test_run_treats_hostile_json_as_empty_without_crashing():
    deep_json = "[" * 10_000 + "]" * 10_000
    oversized_members = json.dumps(["wd:Q1"]) + (" " * 70_000)
    conn = store.connect(":memory:")
    store.init_schema(conn)
    conn.execute(A2_PLACES_DDL)
    conn.execute(
        """
        INSERT INTO source_records
            (region, source, source_ref, name, lat, lon, props_json, run_id)
        VALUES ('uk', 'wd', 'wd:Q1', 'Deep', 1, 1, ?, 'r')
        """,
        (deep_json,),
    )
    conn.execute(
        """
        INSERT INTO places
            (place_id, region, name, lat, lon, refs_json, member_refs_json, status)
        VALUES ('p1', 'uk', 'P1', 1, 1, '[]', '["wd:Q1"]', 'live')
        """
    )
    conn.execute(
        """
        INSERT INTO places
            (place_id, region, name, lat, lon, refs_json, member_refs_json, status)
        VALUES ('p2', 'uk', 'P2', 1, 1, '[]', ?, 'live')
        """,
        (oversized_members,),
    )
    conn.commit()

    assert CZ.run(conn, "uk", run_id="cat1", taxonomy=TAX) == {"uncategorized": 2}


def test_run_is_deterministic_across_member_and_record_order():
    records = [
        ("uk", "wd", "wd:Q1", "Museum", 1, 1, json.dumps({"p31": "Q33506"}), "r"),
        ("uk", "osm", "osm:node/1", "Castle", 1, 1, json.dumps({"historic": "castle"}), "r"),
    ]
    places_a = [("p", ["wd:Q1", "osm:node/1"])]
    places_b = [("p", ["osm:node/1", "wd:Q1"])]

    a = _seed_run(records, places_a)
    b = _seed_run(list(reversed(records)), places_b)
    CZ.run(a, "uk", run_id="cat1", taxonomy=TAX)
    CZ.run(b, "uk", run_id="cat1", taxonomy=TAX)

    rows_a = a.execute("SELECT place_id, category, run_id FROM place_categories").fetchall()
    rows_b = b.execute("SELECT place_id, category, run_id FROM place_categories").fetchall()
    assert rows_a == rows_b == [("p", "culture", "cat1")]


def test_stage_dispatches_categorize_body_after_score():
    conn = _seed_run(
        [("uk", "wd", "wd:Q1", "Museum", 1, 1, json.dumps({"p31": "Q33506"}), "r")],
        [("p", ["wd:Q1"])],
    )
    for stage in ("extract", "reconcile", "score"):
        stages.run_stage(conn, "uk", stage, run_id="r1")

    stages.run_stage(conn, "uk", "categorize", run_id="cat1")

    assert store.stage_completed(conn, "uk", "categorize")
    assert conn.execute("SELECT category FROM place_categories WHERE place_id = 'p'").fetchone()[
        0
    ] == "culture"
