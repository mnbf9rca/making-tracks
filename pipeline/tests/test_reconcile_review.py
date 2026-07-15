import pytest

from mt_contracts.place_id import mint_place_id
from mt_contracts.registry import RegistryRecord, resolve_superseded
from mt_pipeline.reconcile import review


def _record(ref):
    return RegistryRecord(
        place_id=mint_place_id(ref),
        refs={ref},
        mint_anchor=ref,
        status="live",
        first_shipped_version="20260715T000000Z",
        last_seen_version="20260715T000000Z",
    )


def test_review_item_sorts_list_fields():
    item = review.ReviewItem(
        kind="ambiguous_refs",
        reason="refs matched multiple places",
        cluster_refs=["wd:Q2", "wd:Q1"],
        candidate_place_ids=["mt1_" + "2" * 26, "mt1_" + "1" * 26],
        members=["wp:2", "osm:node/1"],
    )

    assert item.to_json()["cluster_refs"] == ["wd:Q1", "wd:Q2"]
    assert item.to_json()["candidate_place_ids"] == [
        "mt1_" + "1" * 26,
        "mt1_" + "2" * 26,
    ]
    assert item.to_json()["members"] == ["osm:node/1", "wp:2"]


def test_write_review_is_deterministic_jsonl(tmp_path):
    path = tmp_path / "review.jsonl"
    items = [
        review.ReviewItem(
            kind="fuzzy_defer",
            reason="close name",
            cluster_refs=["osm:node/2", "osm:node/1"],
            candidate_place_ids=[],
            members=["osm:node/2", "osm:node/1"],
        )
    ]

    review.write_review(path, items)
    first = path.read_bytes()
    review.write_review(path, items)
    second = path.read_bytes()

    assert first == second
    assert first.endswith(b"\n")


def test_supersede_sets_loser_and_resolves_to_winner():
    loser = _record("wd:Q1")
    winner = _record("wd:Q2")

    records = review.supersede([loser, winner], loser.place_id, winner.place_id)

    assert resolve_superseded(records, loser.place_id) == winner.place_id
    assert resolve_superseded(records, winner.place_id) == winner.place_id


def test_supersede_cycle_is_rejected():
    first = _record("wd:Q1")
    second = _record("wd:Q2")
    first.superseded_by = second.place_id

    with pytest.raises(ValueError):
        review.supersede([first, second], second.place_id, first.place_id)
