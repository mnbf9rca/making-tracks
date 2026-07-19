import json
import pathlib

from mt_pipeline import store
from mt_pipeline.extractors import wikipedia

FIX = pathlib.Path(__file__).parent / "fixtures/wikipedia/snapshot.json"


def _db(tmp_path):
    conn = store.connect(tmp_path / "w.db")
    store.init_schema(conn)
    return conn


def _snap(tmp_path, obj):
    obj = {"_meta": {"complete": True}, **obj}
    path = tmp_path / "s.json"
    path.write_text(json.dumps(obj))
    return path


def test_emits_wp_pageid_refs_skips_malformed(tmp_path):
    conn = _db(tmp_path)
    count = wikipedia.WikipediaExtractor({"en"}).extract(
        "united-kingdom", FIX, conn, run_id="r1"
    )
    rows = conn.execute(
        "SELECT source_ref FROM source_records ORDER BY source_ref"
    ).fetchall()
    assert count == 2
    assert rows == [("wp:12345",), ("wp:67890",)]


def test_valid_qid_rides_in_props_null_and_garbage_do_not(tmp_path):
    conn = _db(tmp_path)
    wikipedia.WikipediaExtractor({"en"}).extract("united-kingdom", FIX, conn, run_id="r1")
    p1 = json.loads(
        conn.execute(
            "SELECT props_json FROM source_records WHERE source_ref='wp:12345'"
        ).fetchone()[0]
    )
    p2 = json.loads(
        conn.execute(
            "SELECT props_json FROM source_records WHERE source_ref='wp:67890'"
        ).fetchone()[0]
    )
    assert p1["wikidata"] == "Q42"
    assert "wikidata" not in p2


def test_garbage_qid_dropped_but_record_kept(tmp_path):
    conn = _db(tmp_path)
    snap = _snap(
        tmp_path,
        {
            "lang": "en",
            "pages": [
                {
                    "pageid": 1,
                    "title": "T",
                    "lat": 1,
                    "lon": 1,
                    "extract": "e",
                    "wikidata": "Qwerty; nonsense",
                }
            ],
        },
    )
    wikipedia.WikipediaExtractor({"en"}).extract("united-kingdom", snap, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert "wikidata" not in props


def test_oversized_lang_does_not_nuke_all_records(tmp_path):
    conn = _db(tmp_path)
    snap = _snap(
        tmp_path,
        {
            "lang": "x" * 10_000,
            "pages": [{"pageid": 1, "title": "T", "lat": 1, "lon": 1, "extract": "e"}],
        },
    )
    assert wikipedia.WikipediaExtractor({"en"}).extract(
        "united-kingdom", snap, conn, run_id="r1"
    ) == 0


def test_extract_length_bounded(tmp_path):
    conn = _db(tmp_path)
    snap = _snap(
        tmp_path,
        {
            "lang": "en",
            "pages": [
                {"pageid": 1, "title": "T", "lat": 1, "lon": 1, "extract": "y" * 5000}
            ],
        },
    )
    wikipedia.WikipediaExtractor({"en"}).extract("united-kingdom", snap, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert len(props["extract"]) <= wikipedia.MAX_EXTRACT_LEN


def test_description_extract_preserves_longer_snapshot_text_for_publish(tmp_path):
    conn = _db(tmp_path)
    long_extract = "A complete first sentence. " + ("Second sentence continues. " * 40)
    snap = _snap(
        tmp_path,
        {
            "lang": "en",
            "pages": [
                {"pageid": 1, "title": "T", "lat": 1, "lon": 1, "extract": long_extract}
            ],
        },
    )

    wikipedia.WikipediaExtractor({"en"}).extract("united-kingdom", snap, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])

    assert len(props["extract"]) <= wikipedia.MAX_EXTRACT_LEN
    assert props["description_extract"].startswith("A complete first sentence.")
    assert len(props["description_extract"]) > wikipedia.MAX_EXTRACT_LEN


def test_pageviews_are_materialized_from_cache_when_threaded(tmp_path):
    conn = _db(tmp_path)
    snap = _snap(
        tmp_path,
        {
            "lang": "en",
            "pages": [
                {
                    "pageid": 1,
                    "title": "Big Ben",
                    "lat": 1,
                    "lon": 1,
                    "extract": "e",
                }
            ],
        },
    )
    window = ("2025-07-14", "2026-07-14")
    cache_dir = tmp_path / "pageviews"
    from mt_pipeline.extractors import pageviews

    cache_path = pageviews._cache_path(cache_dir, "Big Ben", window)
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(
        '{"title":"Big Ben","window":["2025-07-14","2026-07-14"],"daily":[5,8,13]}'
    )

    wikipedia.WikipediaExtractor({"en"}).extract(
        "united-kingdom",
        snap,
        conn,
        run_id="r1",
        pageview_cache_dir=cache_dir,
        pageview_window=window,
    )

    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert props["pageviews"] == [5, 8, 13]


def test_pageview_cache_title_normalization_matches_materialization(tmp_path):
    conn = _db(tmp_path)
    long_title = "A" * 400
    snap = _snap(
        tmp_path,
        {
            "lang": "en",
            "pages": [
                {
                    "pageid": 1,
                    "title": long_title,
                    "lat": 1,
                    "lon": 1,
                    "extract": "e",
                }
            ],
        },
    )
    window = ("2025-07-14", "2026-07-14")
    cache_dir = tmp_path / "pageviews"
    from mt_pipeline.extractors import pageviews

    normalized_title = pageviews.cache_title(long_title)
    cache_path = pageviews._cache_path(cache_dir, normalized_title, window)
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(
        json.dumps(
            {
                "title": normalized_title,
                "window": ["2025-07-14", "2026-07-14"],
                "daily": [21],
            }
        )
    )

    wikipedia.WikipediaExtractor({"en"}).extract(
        "united-kingdom",
        snap,
        conn,
        run_id="r1",
        pageview_cache_dir=cache_dir,
        pageview_window=window,
    )

    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert props["pageviews"] == [21]


def test_emits_in_stable_lexical_source_ref_order(tmp_path):
    conn = _db(tmp_path)
    snap = _snap(
        tmp_path,
        {
            "lang": "en",
            "pages": [
                {"pageid": 9, "title": "Nine", "lat": 1, "lon": 1},
                {"pageid": 100, "title": "Hundred", "lat": 1, "lon": 1},
            ],
        },
    )
    wikipedia.WikipediaExtractor({"en"}).extract("united-kingdom", snap, conn, run_id="r1")
    order = [
        row[0]
        for row in conn.execute("SELECT source_ref FROM source_records ORDER BY id")
    ]
    assert order == ["wp:100", "wp:9"]


def test_malformed_pages_container_is_dropped_cleanly(tmp_path):
    conn = _db(tmp_path)
    snap = _snap(tmp_path, {"lang": "en", "pages": None})
    assert wikipedia.WikipediaExtractor({"en"}).extract("united-kingdom", snap, conn, run_id="r1") == 0
