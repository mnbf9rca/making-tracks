from mt_contracts.place_id import mint_place_id
from mt_pipeline.reconcile import cluster as C
from mt_pipeline.reconcile import reconcile as R

V1 = "20260714T000000Z"
V2 = "20260715T000000Z"
SUCCEEDED = {"wd", "osm", "wp", "hehle", "plaque"}
FUZZY = C.FuzzyConfig(sim_defer=0.85, dist_defer_m=150.0, min_alnum=4)


def _m(source_ref, refs, name="X", lat=1.0, lon=1.0):
    return C.Member(
        source=source_ref.split(":", 1)[0],
        source_ref=source_ref,
        name=name,
        lat=lat,
        lon=lon,
        refs=frozenset(refs),
    )


def test_new_cluster_mints_stable_id():
    result = R.reconcile(
        [_m("wd:Q42", {"wd:Q42"})],
        [],
        {},
        version=V1,
        succeeded_sources=SUCCEEDED,
        cfg=FUZZY,
    )

    assert len(result.records) == 1
    assert result.records[0].place_id == mint_place_id("wd:Q42")


def test_rerun_same_input_same_id():
    first = R.reconcile(
        [_m("wd:Q42", {"wd:Q42"})],
        [],
        {},
        version=V1,
        succeeded_sources=SUCCEEDED,
        cfg=FUZZY,
    )
    second = R.reconcile(
        [_m("wd:Q42", {"wd:Q42"})],
        first.records,
        {},
        version=V2,
        succeeded_sources=SUCCEEDED,
        cfg=FUZZY,
    )

    assert second.records[0].place_id == first.records[0].place_id


def test_qid_merge_keeps_place_id_stable():
    first = R.reconcile(
        [_m("wd:Q123", {"wd:Q123"})],
        [],
        {},
        version=V1,
        succeeded_sources=SUCCEEDED,
        cfg=FUZZY,
    )
    place_id = first.records[0].place_id

    second = R.reconcile(
        [_m("wd:Q456", {"wd:Q456"})],
        first.records,
        {"Q123": "Q456"},
        version=V2,
        succeeded_sources=SUCCEEDED,
        cfg=FUZZY,
    )

    assert len(second.records) == 1
    assert second.records[0].place_id == place_id
    assert {"wd:Q123", "wd:Q456"} <= second.records[0].refs


def test_osm_gains_wikidata_tag_keeps_id():
    first = R.reconcile(
        [_m("osm:node/5", {"osm:node/5"})],
        [],
        {},
        version=V1,
        succeeded_sources=SUCCEEDED,
        cfg=FUZZY,
    )
    place_id = first.records[0].place_id

    second = R.reconcile(
        [_m("osm:node/5", {"osm:node/5", "wd:Q42"})],
        first.records,
        {},
        version=V2,
        succeeded_sources=SUCCEEDED,
        cfg=FUZZY,
    )

    assert second.records[0].place_id == place_id
    assert second.records[0].mint_anchor == "osm:node/5"


def test_ambiguous_bridge_defers_never_merges():
    first = R.reconcile(
        [_m("wd:Q1", {"wd:Q1"})],
        [],
        {},
        version=V1,
        succeeded_sources=SUCCEEDED,
        cfg=FUZZY,
    ).records
    second = R.reconcile(
        [_m("wd:Q2", {"wd:Q2"})],
        first,
        {},
        version=V1,
        succeeded_sources=SUCCEEDED,
        cfg=FUZZY,
    ).records
    bridging = _m("osm:node/9", {"osm:node/9", "wd:Q1", "wd:Q2"})

    result = R.reconcile(
        [bridging],
        second,
        {},
        version=V2,
        succeeded_sources=SUCCEEDED,
        cfg=FUZZY,
    )

    assert result.review
    assert {record.place_id for record in result.records} == {
        record.place_id for record in second
    }


def test_absence_ages_a_place_only_when_vanish_is_verified():
    first = R.reconcile(
        [_m("hehle:7", {"hehle:7"})],
        [],
        {},
        version=V1,
        succeeded_sources={"hehle"},
        cfg=FUZZY,
    )
    assert first.records[0].last_seen_version == V1

    failed_source_run = R.reconcile(
        [],
        first.records,
        {},
        version=V2,
        succeeded_sources={"wd", "osm"},
        cfg=FUZZY,
    )
    assert failed_source_run.records[0].last_seen_version == V2
    assert failed_source_run.records[0].status == "live"

    verified_vanish_run = R.reconcile(
        [],
        first.records,
        {},
        version=V2,
        succeeded_sources={"hehle"},
        cfg=FUZZY,
    )
    assert verified_vanish_run.records[0].last_seen_version == V1
    assert verified_vanish_run.records[0].status == "live"
