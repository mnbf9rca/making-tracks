import pytest

from mt_contracts.registry import AmbiguousRefsError, RegistryRecord, resolve_by_refs
from mt_contracts.validation import is_valid, validate_instance


def _rec(pid, refs, status="live", superseded_by=None):
    return RegistryRecord(
        place_id=pid,
        refs=set(refs),
        mint_anchor=sorted(refs)[0],
        status=status,
        superseded_by=superseded_by,
        first_shipped_version="20260714T000000Z",
        last_seen_version="20260714T000000Z",
    )


def test_resolve_rides_a_non_anchor_ref():
    pid = "mt1_" + "0" * 26
    records = [_rec(pid, ["wd:Q100", "osm:node/5"])]
    assert records[0].mint_anchor == "osm:node/5"
    assert resolve_by_refs(records, {"wd:Q100"}) == pid


def test_qid_merge_keeps_place_id_stable():
    pid = "mt1_" + "1" * 26
    records = [_rec(pid, ["wd:Q100", "osm:way/9"])]
    assert records[0].mint_anchor == "osm:way/9"
    assert resolve_by_refs(records, {"wd:Q100", "wd:Q200"}) == pid


def test_unknown_refs_resolve_to_none():
    records = [_rec("mt1_" + "0" * 26, ["wd:Q100"])]
    assert resolve_by_refs(records, {"wd:Q999"}) is None


def test_ambiguous_refs_raise_and_carry_candidates():
    p1 = _rec("mt1_" + "a" * 26, ["wd:Q1"])
    p2 = _rec("mt1_" + "b" * 26, ["wd:Q2"])
    with pytest.raises(AmbiguousRefsError) as exc:
        resolve_by_refs([p1, p2], {"wd:Q1", "wd:Q2"})
    assert exc.value.place_ids == {"mt1_" + "a" * 26, "mt1_" + "b" * 26}


def test_tombstoned_record_still_resolves_and_is_never_reassigned():
    pid = "mt1_" + "2" * 26
    records = [_rec(pid, ["wd:Q7"], status="tombstoned")]
    assert resolve_by_refs(records, {"wd:Q7"}) == pid


def test_superseded_by_points_at_a_valid_place_id():
    from mt_contracts.place_id import is_valid_place_id

    keeper = "mt1_" + "3" * 26
    dup = _rec("mt1_" + "4" * 26, ["wd:Q8"], superseded_by=keeper)
    assert is_valid_place_id(dup.superseded_by)


def test_resolve_superseded_is_transitive():
    from mt_contracts.registry import resolve_superseded

    a, b, c = ("mt1_" + ch * 26 for ch in "567")
    records = [
        _rec(a, ["wd:Q1"], superseded_by=b),
        _rec(b, ["wd:Q2"], superseded_by=c),
        _rec(c, ["wd:Q3"]),
    ]
    assert resolve_superseded(records, a) == c
    assert resolve_superseded(records, c) == c


def test_supersede_cycle_is_rejected_at_write():
    from mt_contracts.registry import assert_no_supersede_cycles

    a, b = ("mt1_" + ch * 26 for ch in "89")
    records = [
        _rec(a, ["wd:Q1"], superseded_by=b),
        _rec(b, ["wd:Q2"], superseded_by=a),
    ]
    with pytest.raises(ValueError):
        assert_no_supersede_cycles(records)


def test_tile_winner_violations_flags_superseded_ids():
    from mt_contracts.registry import tile_winner_violations

    winner = "mt1_" + "3" * 26
    loser = "mt1_" + "4" * 26
    records = [_rec(loser, ["wd:Q8"], superseded_by=winner), _rec(winner, ["wd:Q9"])]
    assert tile_winner_violations([winner], records) == []
    assert tile_winner_violations([loser], records) == [loser]


def test_registry_record_schema_accepts_valid_serialized_shape():
    inst = {
        "schema_version": 1,
        "place_id": "mt1_" + "5" * 26,
        "refs": ["wd:Q1", "foo:bar"],
        "mint_anchor": "wd:Q1",
        "status": "live",
        "superseded_by": None,
        "first_shipped_version": "20260714T000000Z",
        "last_seen_version": "20260714T000000Z",
    }
    validate_instance("registry-record", inst)


def test_registry_record_schema_rejects_bad_status_and_noncanonical_refs():
    base = {
        "schema_version": 1,
        "place_id": "mt1_" + "5" * 26,
        "refs": ["wd:Q1"],
        "mint_anchor": "wd:Q1",
        "status": "live",
    }
    assert not is_valid("registry-record", {**base, "status": "deleted"})
    assert not is_valid("registry-record", {**base, "refs": ["wd:q1"]})
    assert not is_valid("registry-record", {**base, "mint_anchor": "osm:Way/1"})
    assert not is_valid(
        "registry-record",
        {**base, "refs": ["wd:Q1"], "mint_anchor": "osm:node/1"},
    )
