import json
import pathlib

import pytest

from mt_pipeline import store
from mt_pipeline.extractors import open_plaques as op


def _db(path):
    conn = store.connect(str(path) + ".db")
    store.init_schema(conn)
    return conn


FIX = pathlib.Path(__file__).parent / "fixtures/registers/plaques_sample.json"


def test_extracts_geolocated_plaques_skips_ungeolocated_and_bad_id(tmp_path):
    conn = _db(tmp_path / "w")

    count = op.OpenPlaquesExtractor().extract("uk", FIX, conn, run_id="r1")
    rows = conn.execute(
        "SELECT source_ref, name FROM source_records ORDER BY source_ref"
    ).fetchall()

    assert count == 2
    assert rows[0][0] == "plaque:openplaques/9876"
    assert rows[1][0] == "plaque:openplaques/9877"


def test_name_falls_back_to_lead_subject_when_title_missing(tmp_path):
    conn = _db(tmp_path / "w")

    op.OpenPlaquesExtractor().extract("uk", FIX, conn, run_id="r1")
    name = conn.execute(
        "SELECT name FROM source_records WHERE source_ref='plaque:openplaques/9877'"
    ).fetchone()[0]

    assert name == "Grace Hopper"


def test_inscription_rides_in_props(tmp_path):
    conn = _db(tmp_path / "w")

    op.OpenPlaquesExtractor().extract("uk", FIX, conn, run_id="r1")
    props = json.loads(
        conn.execute(
            "SELECT props_json FROM source_records WHERE source_ref='plaque:openplaques/9876'"
        ).fetchone()[0]
    )

    assert "Ada Lovelace" in props["inscription"]


def test_corrupt_dump_is_a_loud_typed_error(tmp_path):
    bad = tmp_path / "b.json"
    bad.write_text("{ not json")

    with pytest.raises(op._snapshot.SnapshotParseError):
        op.OpenPlaquesExtractor().extract("uk", bad, _db(tmp_path / "b"), run_id="r1")


def test_non_array_dump_is_rejected(tmp_path):
    bad = tmp_path / "o.json"
    bad.write_text('{"plaques": []}')

    with pytest.raises(op._snapshot.SnapshotParseError):
        op.OpenPlaquesExtractor().extract("uk", bad, _db(tmp_path / "o"), run_id="r1")


def test_hostile_huge_inscription_does_not_crash_record_kept(tmp_path):
    path = tmp_path / "h.json"
    path.write_text(
        json.dumps(
            [
                {
                    "id": 5,
                    "title": "T",
                    "inscription": "z" * 5000,
                    "latitude": 51.5,
                    "longitude": -0.1,
                }
            ]
        )
    )
    conn = _db(tmp_path / "h")

    assert op.OpenPlaquesExtractor().extract("uk", path, conn, run_id="r1") == 1
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert len(props["inscription"]) == 300
