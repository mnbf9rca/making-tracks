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
