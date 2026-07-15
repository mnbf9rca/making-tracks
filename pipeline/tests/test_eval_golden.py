from mt_contracts.place_id import is_valid_place_id
from mt_pipeline.eval import golden as G

A = "mt1_" + "0" * 26
B = "mt1_" + "1" * 26
C = "mt1_" + "2" * 26
Z = "mt1_" + "Z" * 26

assert all(map(is_valid_place_id, (A, B, C, Z)))


def row(pid, name, score, label=None, active=True, dv="v1", **sig):
    return G.GoldenRow(
        pid,
        "london",
        name,
        51.5,
        -0.1,
        "cat",
        1,
        score,
        {"article": sig.get("article", 0.0), "llm_curiosity": None},
        label,
        data_version=dv,
        active=active,
    )


ROWS = [
    row(A, "St Paul's", 0.9, article=0.9),
    row(B, "A Bench", 0.1, article=0.0),
]


def test_loader_uses_the_shipped_place_id_validator():
    assert not is_valid_place_id("mt1_" + "I" * 26)
    assert not is_valid_place_id("mt1_" + "a" * 26)
    hdr = "\t".join(
        [
            "place_id",
            "name",
            "lat",
            "lon",
            "category",
            "tier",
            "score",
            "article",
            "llm_curiosity",
            "label",
        ]
    )
    bad = (
        "# x\n# data_version: v1\n"
        + hdr
        + "\n"
        + ("mt1_" + "I" * 26)
        + "\tX\t0\t0\tc\t1\t0\t0\t\tyes\n"
    )
    res = G.parse_labeled_tsv(bad)
    assert res.parsed == 0
    assert len(res.skipped) == 1
    assert "place_id" in res.skipped[0][1]


def test_tsv_layout_and_is_deterministic():
    tsv = G.render_tsv(ROWS)
    assert G.render_tsv(ROWS) == tsv
    lines = tsv.splitlines()
    assert lines[0].startswith("# Label the 'label' column")
    assert lines[1] == "# data_version: v1"
    assert lines[2].startswith("place_id\t")
    assert "\tlabel" in lines[2]
    assert "\tNone" not in tsv


def test_jsonl_is_deterministic_and_carries_active_data_version_and_signals():
    jsonl = G.render_jsonl(list(reversed(ROWS)))
    assert G.render_jsonl(list(reversed(ROWS))) == jsonl
    assert '"data_version":"v1"' in jsonl
    assert '"active":true' in jsonl
    assert '"signals":{"article":0.0,"llm_curiosity":null}' in jsonl


def test_fresh_dump_round_trips_as_all_unlabeled():
    res = G.parse_labeled_tsv(G.render_tsv(ROWS))
    assert res.parsed == 2
    assert res.labeled == 0
    assert res.skipped == []
    assert [r.place_id for r in res.rows] == [A, B]
    assert all(r.label is None for r in res.rows)
    assert res.data_version == "v1"


def _set_label(tsv, pid, raw):
    out = []
    for ln in tsv.splitlines():
        f = ln.split("\t")
        if f and f[0] == pid:
            f[-1] = raw
        out.append("\t".join(f))
    return "\n".join(out) + "\n"


def test_label_survives_edit_and_is_normalised():
    edited = _set_label(G.render_tsv(ROWS), A, "YES ")
    res = G.parse_labeled_tsv(edited)
    assert res.labeled == 1
    assert {r.place_id: r.label for r in res.rows}[A] == "yes"


def test_malformed_row_is_counted_not_silently_dropped():
    bad = G.render_tsv(ROWS) + "mt1_BADID\tx\n"
    res = G.parse_labeled_tsv(bad)
    assert res.parsed == 2
    assert len(res.skipped) == 1
    assert "place_id" in res.skipped[0][1]


def test_duplicate_conflicting_non_blank_label_is_counted_warning_and_last_wins():
    edited = _set_label(G.render_tsv(ROWS), A, "yes")
    duplicate = edited + f"{A}\tX\t0\t0\tc\t1\t0\t0\t\tno\n"
    res = G.parse_labeled_tsv(duplicate)
    assert {r.place_id: r.label for r in res.rows}[A] == "no"
    assert len(res.skipped) == 1
    assert "conflicting" in res.skipped[0][1]


def test_labels_survive_and_resurrect_across_two_refreshes():
    labeled = [
        row(A, "St Paul's", 0.9, "yes", dv="v1"),
        row(B, "A Bench", 0.1, "no", dv="v1"),
    ]
    m1, retired1 = G.merge_labels(
        [
            row(A, "St Paul's", 0.92, dv="v2"),
            row(C, "New Find", 0.6, dv="v2"),
        ],
        labeled,
    )
    assert {r.place_id: r.label for r in m1} == {A: "yes", C: None}
    assert [r.place_id for r in retired1] == [B]
    assert retired1[0].label == "no"
    assert not retired1[0].active

    m2, _ = G.merge_labels(
        [
            row(A, "St Paul's", 0.9, dv="v3"),
            row(B, "A Bench", 0.1, dv="v3"),
        ],
        m1 + retired1,
    )
    assert {r.place_id: r.label for r in m2}[B] == "no"

