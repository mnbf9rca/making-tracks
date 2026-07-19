from mt_pipeline.reconcile import cluster as C


def _m(source_ref, refs, name="X", lat=1.0, lon=1.0):
    return C.Member(
        source=source_ref.split(":", 1)[0],
        source_ref=source_ref,
        name=name,
        lat=lat,
        lon=lon,
        refs=frozenset(refs),
    )


def test_qid_join_clusters_osm_wp_wd_into_one_place():
    members = [
        _m("wd:Q42", {"wd:Q42"}),
        _m("osm:node/5", {"osm:node/5", "wd:Q42"}),
        _m("wp:99", {"wp:99", "wd:Q42"}),
        _m("osm:node/6", {"osm:node/6"}),
    ]

    clusters = C.cluster_by_refs(members)

    assert len(clusters) == 2
    big = max(clusters, key=lambda cluster: len(cluster.members))
    assert big.refs == {"wd:Q42", "osm:node/5", "wp:99"}
    assert len(big.members) == 3


def test_clustering_is_order_independent():
    members = [
        _m("wd:Q1", {"wd:Q1"}),
        _m("osm:node/1", {"osm:node/1", "wd:Q1"}),
    ]

    clusters_a = C.cluster_by_refs(members)
    clusters_b = C.cluster_by_refs(list(reversed(members)))

    assert [sorted(cluster.refs) for cluster in clusters_a] == [
        sorted(cluster.refs) for cluster in clusters_b
    ]


FUZZY = C.FuzzyConfig(sim_defer=0.85, dist_defer_m=150.0, min_alnum=4)


def test_normalize_name_keeps_non_latin_letters():
    assert C.normalize_name("Café — 观音亭") == "cafe 观音亭"


def test_close_similar_pair_defers_never_merges():
    a = C.Cluster(
        members=[
            _m(
                "osm:node/1",
                {"osm:node/1"},
                name="St Mary's Church",
                lat=51.5000,
                lon=-0.1200,
            )
        ],
        refs={"osm:node/1"},
    )
    b = C.Cluster(
        members=[
            _m(
                "hehle:9",
                {"hehle:9"},
                name="St Marys Church",
                lat=51.50003,
                lon=-0.12001,
            )
        ],
        refs={"hehle:9"},
    )

    deferred = C.fuzzy_defer([a, b], FUZZY)

    assert len(deferred) == 1
    assert [cluster.refs for cluster in [a, b]] == [{"osm:node/1"}, {"hehle:9"}]


def test_distinct_non_latin_names_do_not_defer_or_merge():
    a = C.Cluster(
        members=[
            _m(
                "osm:node/1",
                {"osm:node/1"},
                name="观音亭",
                lat=3.1500,
                lon=101.7000,
            )
        ],
        refs={"osm:node/1"},
    )
    b = C.Cluster(
        members=[
            _m(
                "osm:node/2",
                {"osm:node/2"},
                name="天后宫",
                lat=3.15003,
                lon=101.70001,
            )
        ],
        refs={"osm:node/2"},
    )

    assert C.fuzzy_defer([a, b], FUZZY) == []


def test_generic_name_close_pair_defers_never_merges():
    a = C.Cluster(
        members=[
            _m(
                "osm:node/1",
                {"osm:node/1"},
                name="Surau Al-Hidayah",
                lat=3.15,
                lon=101.70,
            )
        ],
        refs={"osm:node/1"},
    )
    b = C.Cluster(
        members=[
            _m(
                "osm:node/2",
                {"osm:node/2"},
                name="Surau Al-Hidayah",
                lat=3.15012,
                lon=101.70,
            )
        ],
        refs={"osm:node/2"},
    )

    assert len(C.fuzzy_defer([a, b], FUZZY)) == 1
    assert a.refs == {"osm:node/1"}
    assert b.refs == {"osm:node/2"}


def test_far_apart_same_name_splits():
    a = C.Cluster(
        members=[
            _m(
                "osm:node/1",
                {"osm:node/1"},
                name="St Mary's Church",
                lat=51.5,
                lon=-0.12,
            )
        ],
        refs={"osm:node/1"},
    )
    b = C.Cluster(
        members=[
            _m(
                "osm:node/2",
                {"osm:node/2"},
                name="St Mary's Church",
                lat=52.0,
                lon=-1.0,
            )
        ],
        refs={"osm:node/2"},
    )

    assert C.fuzzy_defer([a, b], FUZZY) == []


def test_empty_normalized_name_is_not_a_candidate():
    a = C.Cluster(
        members=[
            _m("osm:node/1", {"osm:node/1"}, name="★☆♥", lat=3.15, lon=101.70)
        ],
        refs={"osm:node/1"},
    )
    b = C.Cluster(
        members=[
            _m("osm:node/2", {"osm:node/2"}, name="♦♣", lat=3.15001, lon=101.70)
        ],
        refs={"osm:node/2"},
    )

    assert C.fuzzy_defer([a, b], FUZZY) == []


def _single_cluster(index, *, lat, lon, name="Boundary Place"):
    ref = f"osm:node/{index}"
    return C.Cluster(
        members=[_m(ref, {ref}, name=name, lat=lat, lon=lon)],
        refs={ref},
    )


def _defer_key(item):
    return (item.anchor_a, item.anchor_b, round(item.sim, 12), round(item.dist_m, 6))


def _synthetic_fuzzy_fixture():
    dispersed = [
        _single_cluster(
            1000 + index,
            lat=50.0 + index * 0.004,
            lon=-2.0 + (index % 7) * 0.02,
            name=f"Dispersed Place {index}",
        )
        for index in range(240)
    ]
    boundary = [
        _single_cluster(1, lat=51.500000, lon=-0.120000),
        _single_cluster(2, lat=51.500000, lon=-0.117860),
        _single_cluster(3, lat=51.501340, lon=-0.120000),
        _single_cluster(4, lat=51.501340, lon=-0.117860),
        _single_cluster(5, lat=51.501360, lon=-0.117830),
        _single_cluster(6, lat=51.510000, lon=-0.120000),
    ]
    multi_member = C.Cluster(
        members=[
            _m(
                "osm:node/500",
                {"osm:node/500"},
                name="Boundary Place",
                lat=51.500020,
                lon=-0.120020,
            ),
            _m(
                "plaque:500",
                {"plaque:500"},
                name="Boundary Place",
                lat=51.501330,
                lon=-0.117850,
            ),
        ],
        refs={"osm:node/500", "plaque:500"},
    )
    return dispersed + boundary + [multi_member]


def test_spatial_fuzzy_matches_bruteforce_at_cell_boundaries():
    clusters = _synthetic_fuzzy_fixture()

    brute = C.fuzzy_defer(clusters, FUZZY, spatial_index=False)
    bucketed = C.fuzzy_defer(clusters, FUZZY)

    assert [_defer_key(item) for item in bucketed] == [
        _defer_key(item) for item in brute
    ]


def test_spatial_fuzzy_avoids_all_pairs_on_dispersed_fixture():
    clusters = [
        _single_cluster(
            index,
            lat=51.0 + index * 0.01,
            lon=-1.0,
            name="Distant Place",
        )
        for index in range(320)
    ]
    brute_counter = C.FuzzyStats()
    bucketed_counter = C.FuzzyStats()

    brute = C.fuzzy_defer(
        clusters,
        FUZZY,
        spatial_index=False,
        stats=brute_counter,
    )
    bucketed = C.fuzzy_defer(clusters, FUZZY, stats=bucketed_counter)

    assert bucketed == brute == []
    assert brute_counter.cluster_pairs_considered == 51_040
    assert bucketed_counter.cluster_pairs_considered < 1_000
    assert brute_counter.member_pairs_considered > 0
    assert bucketed_counter.member_pairs_considered == 0


def test_pair_iterators_do_not_materialize_pair_lists():
    clusters = [_single_cluster(index, lat=51.0 + index, lon=-1.0) for index in range(4)]
    ordered = sorted(clusters, key=lambda cluster: min(cluster.refs))
    all_pairs = C._all_cluster_pairs(ordered)
    nearby_pairs = C._nearby_cluster_pairs(ordered, FUZZY)

    assert not isinstance(all_pairs, list)
    assert not isinstance(nearby_pairs, list)


def test_spatial_fuzzy_emits_phase_telemetry(capsys):
    clusters = [
        _single_cluster(1, lat=51.500000, lon=-0.120000),
        _single_cluster(2, lat=51.500010, lon=-0.120010),
    ]

    C.fuzzy_defer(
        clusters,
        FUZZY,
        telemetry_region="united-kingdom",
        heartbeat_every_pairs=1,
    )

    err = capsys.readouterr().err
    assert "PHASE START reconcile.fuzzy_defer region=united-kingdom candidate_pairs=1" in err
    assert "PHASE HEARTBEAT reconcile.fuzzy_defer region=united-kingdom processed=1/1" in err
    assert "PHASE DONE reconcile.fuzzy_defer region=united-kingdom processed=1/1" in err
