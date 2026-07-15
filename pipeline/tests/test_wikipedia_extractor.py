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
        "uk", FIX, conn, run_id="r1"
    )
    rows = conn.execute(
        "SELECT source_ref FROM source_records ORDER BY source_ref"
    ).fetchall()
    assert count == 2
    assert rows == [("wp:12345",), ("wp:67890",)]


def test_valid_qid_rides_in_props_null_and_garbage_do_not(tmp_path):
    conn = _db(tmp_path)
    wikipedia.WikipediaExtractor({"en"}).extract("uk", FIX, conn, run_id="r1")
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
    wikipedia.WikipediaExtractor({"en"}).extract("uk", snap, conn, run_id="r1")
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
        "uk", snap, conn, run_id="r1"
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
    wikipedia.WikipediaExtractor({"en"}).extract("uk", snap, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert len(props["extract"]) <= wikipedia.MAX_EXTRACT_LEN
