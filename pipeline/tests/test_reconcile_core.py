import pytest

from mt_contracts.registry import AmbiguousRefsError, RegistryRecord, resolve_by_refs
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


def _record(place_id, refs, *, mint_anchor=None):
    return RegistryRecord(
        place_id=place_id,
        refs=set(refs),
        mint_anchor=mint_anchor or sorted(refs)[0],
        status="live",
        first_shipped_version=V1,
        last_seen_version=V1,
    )


def _assert_resolves_like_contract(resolver, records, refs):
    try:
        expected = resolve_by_refs(records, set(refs))
    except AmbiguousRefsError as exc:
        with pytest.raises(AmbiguousRefsError) as actual:
            resolver.resolve(set(refs))
        assert actual.value.place_ids == exc.place_ids
    else:
        assert resolver.resolve(set(refs)) == expected


def test_indexed_resolver_matches_contract_scan_and_updates_incrementally():
    records = [_record("p1", {"wd:Q1"}), _record("p2", {"wd:Q2"})]
    resolver = R._RegistryRefIndex(records)

    _assert_resolves_like_contract(resolver, records, {"wd:Q9"})
    minted = _record("p9", {"wd:Q9"})
    records.append(minted)
    resolver.add_record(minted)
    _assert_resolves_like_contract(resolver, records, {"wd:Q9"})

    minted.refs.add("osm:node/9")
    resolver.update_record(minted)
    _assert_resolves_like_contract(resolver, records, {"osm:node/9"})

    _assert_resolves_like_contract(resolver, records, {"wd:Q1", "wd:Q2"})


def test_indexed_resolver_matches_redirect_bridged_contract_scan():
    records = [_record("p-old", {"wd:Q123"})]
    bridged_records = R._bridge_records(records, {"Q123": "Q456"})
    resolver = R._RegistryRefIndex(bridged_records)

    _assert_resolves_like_contract(resolver, bridged_records, {"wd:Q456"})


def test_indexed_resolver_updates_post_trim_refs():
    record = _record("p-trim", {"osm:node/1"}, mint_anchor="osm:node/1")
    records = [record]
    resolver = R._RegistryRefIndex(records)
    record.refs.update({f"plaque:{index:03d}" for index in range(300)})
    record.refs.add("wd:Q500")
    R._trim_refs(record, [])
    resolver.update_record(record)

    _assert_resolves_like_contract(resolver, records, {"wd:Q500"})
    assert "plaque:000" in record.refs
    assert "plaque:299" not in record.refs
    assert resolver.resolve({"plaque:000"}) == "p-trim"
    assert resolver.resolve({"plaque:299"}) is None
    _assert_resolves_like_contract(resolver, records, {"plaque:000"})
    _assert_resolves_like_contract(resolver, records, {"plaque:299"})


def test_indexed_resolver_avoids_repeated_record_scans_on_mints():
    indexed_stats = R.ResolveStats()
    scan_stats = R.ResolveStats()
    resolver = R._RegistryRefIndex([], stats=indexed_stats)
    records = []

    for index in range(500):
        refs = {f"osm:node/{index}"}
        assert R._scan_resolve_by_refs(records, refs, stats=scan_stats) is None
        assert resolver.resolve(refs) is None
        record = _record(f"p{index}", refs)
        records.append(record)
        resolver.add_record(record)

    assert scan_stats.records_scanned == sum(range(500))
    assert indexed_stats.records_scanned == 0


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


def test_cluster_representative_uses_source_priority_before_ref_sort():
    result = R.reconcile(
        [
            _m("osm:node/5", {"osm:node/5", "wd:Q42"}, name="OSM", lat=1.0, lon=2.0),
            _m("wd:Q42", {"wd:Q42"}, name="Wikidata", lat=3.0, lon=4.0),
        ],
        [],
        {},
        version=V1,
        succeeded_sources=SUCCEEDED,
        cfg=FUZZY,
    )

    assert result.places[0]["name"] == "Wikidata"
    assert result.places[0]["lat"] == 3.0
    assert result.places[0]["lon"] == 4.0


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


def test_reconcile_threads_region_to_fuzzy_telemetry(capsys):
    R.reconcile(
        [
            _m("osm:node/1", {"osm:node/1"}, name="Same Place", lat=51.5, lon=-0.12),
            _m("osm:node/2", {"osm:node/2"}, name="Same Place", lat=51.50001, lon=-0.12),
        ],
        [],
        {},
        version=V1,
        succeeded_sources=SUCCEEDED,
        cfg=FUZZY,
        telemetry_region="united-kingdom",
        fuzzy_heartbeat_every_pairs=1,
    )

    err = capsys.readouterr().err
    assert "PHASE START reconcile.fuzzy_defer region=united-kingdom candidate_pairs=1" in err
    assert "PHASE HEARTBEAT reconcile.fuzzy_defer region=united-kingdom processed=1/1" in err
    assert "PHASE DONE reconcile.fuzzy_defer region=united-kingdom processed=1/1" in err


def test_reconcile_emits_resolve_mint_phase_telemetry(capsys):
    existing = [_record("p-existing", {"wd:Q1"})]

    R.reconcile(
        [
            _m("wd:Q1", {"wd:Q1"}, name="Existing"),
            _m("wd:Q2", {"wd:Q2"}, name="New"),
        ],
        existing,
        {},
        version=V2,
        succeeded_sources=SUCCEEDED,
        cfg=FUZZY,
        telemetry_region="united-kingdom",
        resolve_heartbeat_every_clusters=1,
    )

    err = capsys.readouterr().err
    assert "PHASE START reconcile.resolve_mint region=united-kingdom clusters=2" in err
    assert "PHASE HEARTBEAT reconcile.resolve_mint region=united-kingdom processed=1/2" in err
    assert "PHASE DONE reconcile.resolve_mint region=united-kingdom processed=2/2" in err
    assert "minted=1 matched=1" in err
