import json
import pathlib

import pytest

from mt_pipeline import store
from mt_pipeline.extractors import wikidata

FIX = pathlib.Path(__file__).parent / "fixtures/wikidata/snapshot.json"


def _db(tmp_path, name="w.db"):
    conn = store.connect(tmp_path / name)
    store.init_schema(conn)
    return conn


def _write(tmp_path, snap, name="s.json"):
    obj = {"_meta": {"complete": True}, **snap}
    path = tmp_path / name
    path.write_text(json.dumps(obj))
    return path


@pytest.mark.parametrize(
    "meta",
    [
        None,
        {},
        {"complete": False},
        {"complete": 1},
        {"complete": "true"},
        "x",
    ],
)
def test_incomplete_or_malformed_meta_is_refused(tmp_path, meta):
    obj = {"results": {"bindings": []}}
    if meta is not None:
        obj["_meta"] = meta
    path = tmp_path / "s.json"
    path.write_text(json.dumps(obj))
    with pytest.raises(wikidata.SnapshotIncompleteError):
        wikidata.WikidataExtractor({"Q33506"}).extract(
            "united-kingdom", path, _db(tmp_path), run_id="r1"
        )


def test_complete_true_snapshot_is_accepted(tmp_path):
    path = tmp_path / "ok.json"
    path.write_text(
        json.dumps({"_meta": {"complete": True}, "results": {"bindings": []}})
    )
    assert wikidata.WikidataExtractor({"Q33506"}).extract(
        "united-kingdom", path, _db(tmp_path), run_id="r1"
    ) == 0


def test_keeps_allowlisted_dedups_by_qid_drops_others_and_survives_malformed(
    tmp_path,
):
    conn = _db(tmp_path)
    count = wikidata.WikidataExtractor({"Q33506", "Q570116"}).extract(
        "united-kingdom", FIX, conn, run_id="r1"
    )
    rows = conn.execute(
        "SELECT source, source_ref, name FROM source_records ORDER BY source_ref"
    ).fetchall()
    assert count == 1
    assert rows == [("wd", "wd:Q42", "Big Ben")]


def test_captures_section4_signals(tmp_path):
    conn = _db(tmp_path)
    wikidata.WikidataExtractor({"Q33506", "Q570116"}).extract(
        "united-kingdom", FIX, conn, run_id="r1"
    )
    props = json.loads(
        conn.execute(
            "SELECT props_json FROM source_records WHERE source_ref='wd:Q42'"
        ).fetchone()[0]
    )
    assert props["sitelinks"] == 42
    assert props["image"].startswith("https://")


def test_matched_class_allows_subclass_hit_but_props_keep_actual_p31s(tmp_path):
    snap = {
        "results": {
            "bindings": [
                {
                    "item": {"value": ".../Q42"},
                    "lat": {"value": "1"},
                    "lon": {"value": "1"},
                    "p31": {"value": ".../Q123"},
                    "p31s": {
                        "value": "http://www.wikidata.org/entity/Q123|http://www.wikidata.org/entity/Q456"
                    },
                    "matched_class": {"value": ".../Q33506"},
                    "label": {"value": "Subclass Place"},
                }
            ]
        }
    }
    path = _write(tmp_path, snap, "subclass.json")
    conn = _db(tmp_path)

    assert wikidata.WikidataExtractor({"Q33506"}).extract(
        "united-kingdom", path, conn, run_id="r1"
    ) == 1

    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert props["p31"] == "Q123"
    assert props["p31s"] == ["Q123", "Q456"]
    assert props["matched_p31"] == "Q33506"


def test_deterministic_stable_order_multi_record(tmp_path):
    snap = {
        "results": {
            "bindings": [
                {
                    "item": {"value": ".../Q9"},
                    "lat": {"value": "1"},
                    "lon": {"value": "1"},
                    "p31": {"value": ".../Q33506"},
                    "label": {"value": "Nine"},
                },
                {
                    "item": {"value": ".../Q100"},
                    "lat": {"value": "1"},
                    "lon": {"value": "1"},
                    "p31": {"value": ".../Q33506"},
                    "label": {"value": "Hundred"},
                },
            ]
        }
    }
    path = _write(tmp_path, snap, "s.json")
    conn = _db(tmp_path)
    wikidata.WikidataExtractor({"Q33506"}).extract("united-kingdom", path, conn, run_id="r1")
    order = [row[0] for row in conn.execute("SELECT source_ref FROM source_records ORDER BY id")]
    assert order == ["wd:Q100", "wd:Q9"]


def test_bad_coordinate_row_is_dropped_via_a1_parse(tmp_path):
    snap = {
        "results": {
            "bindings": [
                {
                    "item": {"value": ".../Q42"},
                    "lat": {"value": "999"},
                    "lon": {"value": "0"},
                    "p31": {"value": ".../Q33506"},
                    "label": {"value": "Off-globe"},
                }
            ]
        }
    }
    path = _write(tmp_path, snap, "b.json")
    conn = _db(tmp_path)
    assert wikidata.WikidataExtractor({"Q33506"}).extract(
        "united-kingdom", path, conn, run_id="r1"
    ) == 0


def test_hostile_oversized_label_is_bounded_before_parse(tmp_path):
    snap = {
        "results": {
            "bindings": [
                {
                    "item": {"value": ".../Q42"},
                    "lat": {"value": "1"},
                    "lon": {"value": "1"},
                    "p31": {"value": ".../Q33506"},
                    "label": {"value": "x" * 5000},
                }
            ]
        }
    }
    path = _write(tmp_path, snap, "h.json")
    conn = _db(tmp_path)
    wikidata.WikidataExtractor({"Q33506"}).extract("united-kingdom", path, conn, run_id="r1")
    name = conn.execute("SELECT name FROM source_records").fetchone()[0]
    assert len(name) <= wikidata.MAX_LABEL_LEN


def test_oversized_snapshot_file_is_rejected(tmp_path, monkeypatch):
    path = tmp_path / "big.json"
    path.write_text("{}")
    monkeypatch.setattr(wikidata, "MAX_SNAPSHOT_BYTES", 1)
    with pytest.raises(wikidata.SnapshotTooLargeError):
        wikidata.WikidataExtractor({"Q33506"}).extract(
            "united-kingdom", path, _db(tmp_path), run_id="r1"
        )


def test_bootstrap_allowlist_loads_and_is_minimal():
    allow = wikidata.load_allowlist(
        pathlib.Path(__file__).parents[1] / "config/wikidata_class_allowlist.json"
    )
    assert allow
    assert all(q.startswith("Q") for q in allow)
    assert len(allow) <= 12


def test_malformed_results_container_is_dropped_cleanly(tmp_path):
    path = _write(tmp_path, {"results": []}, "malformed.json")
    conn = _db(tmp_path)
    assert wikidata.WikidataExtractor({"Q33506"}).extract(
        "united-kingdom", path, conn, run_id="r1"
    ) == 0
