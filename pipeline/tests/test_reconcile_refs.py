from mt_pipeline.reconcile import refs


def test_own_ref_plus_qid_join_canonicalized():
    out = refs.refs_of("osm", "osm:node/5", {"wikidata": "Q1"}, {"Q1": "Q2"})

    assert out == {"osm:node/5", "wd:Q2"}


def test_wd_record_own_ref_is_canonicalized():
    out = refs.refs_of("wd", "wd:Q1", {}, {"Q1": "Q2"})

    assert out == {"wd:Q2"}


def test_garbage_qid_join_is_dropped():
    out = refs.refs_of("wp", "wp:12345", {"wikidata": "not-a-qid"}, {})

    assert out == {"wp:12345"}
