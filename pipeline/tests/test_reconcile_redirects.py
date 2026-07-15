import json

import pytest

from mt_pipeline.reconcile import redirects


def test_canonical_qid_follows_chain_transitively():
    mapping = {"Q1": "Q2", "Q2": "Q3"}

    assert redirects.canonical_qid("Q1", mapping) == "Q3"
    assert redirects.canonical_qid("Q3", mapping) == "Q3"
    assert redirects.canonical_qid("Q99", mapping) == "Q99"


def test_canonicalize_ref_only_touches_wd():
    mapping = {"Q1": "Q2"}

    assert redirects.canonicalize_ref("wd:Q1", mapping) == "wd:Q2"
    assert redirects.canonicalize_ref("osm:node/5", mapping) == "osm:node/5"


def test_cycle_is_safe_and_deterministic():
    mapping = {"Q1": "Q2", "Q2": "Q1"}

    assert redirects.canonical_qid("Q1", mapping) == "Q1"
    assert redirects.canonical_qid("Q2", mapping) == "Q1"


def test_load_rejects_hostile_or_incomplete_snapshot(tmp_path):
    path = tmp_path / "redirects.json"
    path.write_text(
        json.dumps(
            {
                "_meta": {
                    "complete": True,
                    "snapshot_date": "20260715T000000Z",
                    "wikidata_snapshot_date": "20260715T000000Z",
                },
                "redirects": {"not-a-qid": "Q1"},
            }
        )
    )

    with pytest.raises(redirects.RedirectMapError):
        redirects.load_redirect_snapshot(path)

    path.write_text(json.dumps({"_meta": {"complete": False}, "redirects": {}}))
    with pytest.raises(redirects.RedirectMapError):
        redirects.load_redirect_snapshot(path)


def test_load_accepts_acquire_redirect_snapshot_metadata_shape(tmp_path):
    path = tmp_path / "redirects.json"
    path.write_text(
        json.dumps(
            {
                "_meta": {
                    "complete": True,
                    "retrieved_at": "2026-07-15T08:16:53Z",
                    "wikidata_retrieved_at": "2026-07-15T07:22:48Z",
                },
                "redirects": {"Q1": "Q2"},
            }
        )
    )

    snapshot = redirects.load_redirect_snapshot(path)

    assert snapshot.map == {"Q1": "Q2"}
    assert snapshot.snapshot_date == "2026-07-15T08:16:53Z"
    assert snapshot.wikidata_snapshot_date == "2026-07-15T07:22:48Z"
    assert snapshot.complete is True


def test_freshness_gate_refuses_stale_redirect_map():
    snapshot = redirects.RedirectSnapshot(
        map={},
        snapshot_date="20260714T000000Z",
        wikidata_snapshot_date="20260714T000000Z",
        complete=True,
    )

    redirects.assert_fresh(snapshot, "20260714T000000Z")
    with pytest.raises(redirects.RedirectMapError):
        redirects.assert_fresh(snapshot, "20260715T000000Z")


def test_freshness_gate_compares_iso_acquire_dates():
    snapshot = redirects.RedirectSnapshot(
        map={},
        snapshot_date="2026-07-15T08:16:53Z",
        wikidata_snapshot_date="2026-07-15T07:22:48Z",
        complete=True,
    )

    redirects.assert_fresh(snapshot, "2026-07-15T07:22:48Z")
    with pytest.raises(redirects.RedirectMapError):
        redirects.assert_fresh(snapshot, "2026-07-15T09:00:00Z")
