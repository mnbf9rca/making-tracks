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
