import json

import pytest

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
    assert "\tarea\tactive\t" in lines[2]
    assert "\tdata_version\t" in lines[2]
    assert "\tlabel" in lines[2]
    assert "\tNone" not in tsv


def test_render_tsv_escapes_spreadsheet_formula_text():
    tsv = G.render_tsv([row(A, "=HYPERLINK(\"https://bad\")", 0.9)])
    assert "\t'=HYPERLINK" in tsv


def test_active_retired_metadata_survives_tsv_round_trip():
    rows = [
        row(A, "Current", 0.9, "yes", dv="v2", active=True),
        row(B, "Retired", 0.1, "no", dv="v1", active=False),
    ]
    tsv = G.render_tsv(rows)
    assert tsv.splitlines()[1] == "# data_version: v2"

    parsed = G.parse_labeled_tsv(tsv)

    by_id = {r.place_id: r for r in parsed.rows}
    assert parsed.data_version == "v2"
    assert by_id[A].area == "london" and by_id[A].active and by_id[A].data_version == "v2"
    assert by_id[B].area == "london" and not by_id[B].active and by_id[B].data_version == "v1"


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


def test_valid_short_and_extra_rows_are_padded_and_truncated():
    header = "place_id\tname\tlat\tlon\tcategory\ttier\tscore\tarticle\tlabel"
    short = f"{A}\tShort\t0\t0\tc\t1\t0.5\t"
    extra = f"{B}\tExtra\t0\t0\tc\t1\t0.4\t0.2\tyes\tignored"
    res = G.parse_labeled_tsv(f"# data_version: v1\n{header}\n{short}\n{extra}\n")
    assert res.skipped == []
    assert [r.place_id for r in res.rows] == [A, B]
    assert res.rows[0].signals["article"] is None
    assert res.rows[1].label == "yes"


def test_duplicate_conflicting_non_blank_label_is_counted_warning_and_last_wins():
    edited = _set_label(G.render_tsv(ROWS), A, "yes")
    duplicate = edited + f"{A}\tlondon\ttrue\tX\t0\t0\tc\t1\t0\tv1\t0\t\tno\n"
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


def test_labels_survive_and_resurrect_through_tsv_persistence():
    labeled = [
        row(A, "St Paul's", 0.9, "yes", dv="v1"),
        row(B, "A Bench", 0.1, "no", dv="v1"),
    ]
    m1, retired1 = G.merge_labels(
        [row(A, "St Paul's", 0.92, dv="v2"), row(C, "New Find", 0.6, dv="v2")],
        labeled,
    )
    persisted = G.parse_labeled_tsv(G.render_tsv(m1 + retired1)).rows
    m2, _ = G.merge_labels(
        [row(A, "St Paul's", 0.9, dv="v3"), row(B, "A Bench", 0.1, dv="v3")],
        persisted,
    )
    assert {r.place_id: r.label for r in m2}[B] == "no"


def test_same_data_version_with_changed_candidate_set_is_rejected():
    with pytest.raises(ValueError, match="candidate set changed"):
        G.merge_labels([row(A, "St Paul's", 0.9, dv="v1")], ROWS)


def test_dump_area_reads_planned_a2_a3_a4_tables(conn):
    conn.executescript(
        """
        CREATE TABLE places (
            place_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL
        );
        CREATE TABLE place_categories (
            place_id TEXT PRIMARY KEY,
            category TEXT NOT NULL
        );
        CREATE TABLE place_scores (
            place_id TEXT PRIMARY KEY,
            tier INTEGER NOT NULL,
            score REAL NOT NULL,
            signals_json TEXT NOT NULL
        );
        """
    )
    conn.execute("INSERT INTO places VALUES (?, ?, ?, ?)", (A, "In", 51.51, -0.11))
    conn.execute("INSERT INTO places VALUES (?, ?, ?, ?)", (B, "Out", 52.0, -0.11))
    conn.execute("INSERT INTO place_categories VALUES (?, ?)", (A, "history"))
    conn.execute("INSERT INTO place_categories VALUES (?, ?)", (B, "history"))
    conn.execute(
        "INSERT INTO place_scores VALUES (?, ?, ?, ?)",
        (A, 2, 0.8, json.dumps({"article": 0.8, "llm_curiosity": None})),
    )
    conn.execute(
        "INSERT INTO place_scores VALUES (?, ?, ?, ?)",
        (B, 3, 0.9, json.dumps({"article": 0.9, "llm_curiosity": None})),
    )

    rows = G.dump_area(conn, "london", [-0.2, 51.5, -0.1, 51.6], data_version="run-1")

    assert rows == [
        G.GoldenRow(
            A,
            "london",
            "In",
            51.51,
            -0.11,
            "history",
            2,
            0.8,
            {"article": 0.8, "llm_curiosity": None},
            None,
            "run-1",
        )
    ]


def test_dump_area_rejects_malformed_signals_json(conn):
    conn.executescript(
        """
        CREATE TABLE places (
            place_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL
        );
        CREATE TABLE place_categories (
            place_id TEXT PRIMARY KEY,
            category TEXT NOT NULL
        );
        CREATE TABLE place_scores (
            place_id TEXT PRIMARY KEY,
            tier INTEGER NOT NULL,
            score REAL NOT NULL,
            signals_json TEXT NOT NULL
        );
        """
    )
    conn.execute("INSERT INTO places VALUES (?, ?, ?, ?)", (A, "In", 51.51, -0.11))
    conn.execute("INSERT INTO place_categories VALUES (?, ?)", (A, "history"))
    conn.execute("INSERT INTO place_scores VALUES (?, ?, ?, ?)", (A, 2, 0.8, '["bad"]'))

    with pytest.raises(ValueError, match="signals_json"):
        G.dump_area(conn, "london", [-0.2, 51.5, -0.1, 51.6], data_version="run-1")
