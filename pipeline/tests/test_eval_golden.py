import json

import pytest

from mt_contracts.place_id import is_valid_place_id
from mt_pipeline import store
from mt_pipeline.eval import golden as G

A = "mt1_" + "0" * 26
B = "mt1_" + "1" * 26
C = "mt1_" + "2" * 26
Z = "mt1_" + "Z" * 26

assert all(map(is_valid_place_id, (A, B, C, Z)))


def row(
    pid,
    name,
    score,
    label=None,
    active=True,
    dv="v1",
    labeled_by=None,
    evidence="",
    sample_weight=1.0,
    **sig,
):
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
        sample_weight=sample_weight,
        active=active,
        labeled_by=labeled_by,
        evidence=evidence,
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
    assert lines[0].startswith("# Edit only: label, labeled_by, evidence.")
    assert lines[1] == "# data_version: v1"
    assert lines[2] == "# sample_weight: inverse-propensity design weight; do not edit"
    assert "Edit only: label, labeled_by, evidence." in lines[0]
    assert "Do NOT edit: place_id, area, active" in lines[0]
    assert lines[3].startswith("place_id\t")
    assert "\tarea\tactive\t" in lines[3]
    assert "\tdata_version\tsample_weight\tarticle\t" in lines[3]
    assert "\tlabeled_by\tevidence\tlabel" in lines[3]
    assert "\tlabel" in lines[3]
    assert "\tNone" not in tsv


def test_sample_weight_round_trips_and_is_not_a_signal():
    weighted = [row(A, "Sampled Tail", 0.4, "meh", sample_weight=47.0)]
    parsed = G.parse_labeled_tsv(G.render_tsv(weighted))

    assert parsed.skipped == []
    assert parsed.rows[0].sample_weight == 47.0
    assert "sample_weight" not in parsed.rows[0].signals


def test_old_tsv_without_sample_weight_defaults_to_one():
    old_header = "place_id\tname\tlat\tlon\tcategory\ttier\tscore\tarticle\tlabel"
    old_row = f"{A}\tOld\t0\t0\tc\t1\t0.5\t0.25\tyes"
    parsed = G.parse_labeled_tsv(f"# data_version: v1\n{old_header}\n{old_row}\n")

    assert parsed.skipped == []
    assert parsed.rows[0].sample_weight == 1.0
    assert parsed.rows[0].signals == {"article": 0.25}


def test_oversized_sample_weight_is_counted_skip():
    header = "place_id\tname\tlat\tlon\tcategory\ttier\tscore\tdata_version\tsample_weight\tarticle\tlabel"
    bad_row = f"{A}\tBad\t0\t0\tc\t1\t0.5\tv1\t1000001\t0.25\tyes"
    parsed = G.parse_labeled_tsv(f"# data_version: v1\n{header}\n{bad_row}\n")

    assert parsed.parsed == 0
    assert len(parsed.skipped) == 1
    assert "sample_weight" in parsed.skipped[0][1]


def test_merged_labels_keep_new_dump_sample_weight():
    existing = [row(A, "Old", 0.4, "yes", dv="v1", sample_weight=47.0)]
    new_rows = [row(A, "New", 0.5, dv="v2", sample_weight=1.0)]

    merged, retired = G.merge_labels(new_rows, existing)

    assert retired == []
    assert merged[0].label == "yes"
    assert merged[0].sample_weight == 1.0


def test_render_tsv_escapes_spreadsheet_formula_text():
    tsv = G.render_tsv([row(A, "=HYPERLINK(\"https://bad\")", 0.9)])
    assert "\t'=HYPERLINK" in tsv


def test_active_retired_metadata_survives_tsv_round_trip():
    rows = [
        row(A, "Current", 0.9, "yes", dv="v2", active=True, labeled_by="rob"),
        row(B, "Retired", 0.1, "no", dv="v1", active=False, labeled_by="llm-research", evidence="source note"),
    ]
    tsv = G.render_tsv(rows)
    assert tsv.splitlines()[1] == "# data_version: v2"

    parsed = G.parse_labeled_tsv(tsv)

    by_id = {r.place_id: r for r in parsed.rows}
    assert parsed.data_version == "v2"
    assert by_id[A].area == "london" and by_id[A].active and by_id[A].data_version == "v2"
    assert by_id[B].area == "london" and not by_id[B].active and by_id[B].data_version == "v1"
    assert by_id[A].sample_weight == 1.0
    assert by_id[B].labeled_by == "llm-research"
    assert by_id[B].evidence == "source note"


def test_jsonl_is_deterministic_and_carries_active_data_version_and_signals():
    jsonl = G.render_jsonl(list(reversed(ROWS)))
    assert G.render_jsonl(list(reversed(ROWS))) == jsonl
    assert '"data_version":"v1"' in jsonl
    assert '"sample_weight":1.0' in jsonl
    assert '"active":true' in jsonl
    assert '"labeled_by":null' in jsonl
    assert '"evidence":""' in jsonl
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


def test_labeled_by_and_evidence_survive_edit_and_are_validated():
    tsv = G.render_tsv(ROWS)
    header = tsv.splitlines()[3].split("\t")
    labeled_by_idx = header.index("labeled_by")
    evidence_idx = header.index("evidence")
    out = []
    for line in tsv.splitlines():
        fields = line.split("\t")
        if fields and fields[0] == A:
            fields[labeled_by_idx] = "llm-research"
            fields[evidence_idx] = "Cited source summary"
            fields[-1] = "meh"
        out.append("\t".join(fields))

    res = G.parse_labeled_tsv("\n".join(out) + "\n")

    parsed = {r.place_id: r for r in res.rows}[A]
    assert parsed.label == "meh"
    assert parsed.labeled_by == "llm-research"
    assert parsed.evidence == "Cited source summary"


def test_invalid_labeled_by_is_counted_skip():
    tsv = G.render_tsv([row(A, "x", 1.0, "yes", labeled_by="rob")])
    bad = tsv.replace("\trob\t", "\trobot\t")
    res = G.parse_labeled_tsv(bad)
    assert res.parsed == 0
    assert len(res.skipped) == 1
    assert "labeled_by" in res.skipped[0][1]


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
    duplicate = edited + f"{A}\tlondon\ttrue\tX\t0\t0\tc\t1\t0\tv1\t1\t0\t\trob\tmanual note\tno\n"
    res = G.parse_labeled_tsv(duplicate)
    parsed = {r.place_id: r for r in res.rows}[A]
    assert parsed.label == "no"
    assert parsed.labeled_by == "rob"
    assert parsed.evidence == "manual note"
    assert len(res.skipped) == 1
    assert "conflicting" in res.skipped[0][1]


def test_labels_survive_and_resurrect_across_two_refreshes():
    labeled = [
        row(A, "St Paul's", 0.9, "yes", dv="v1", labeled_by="rob"),
        row(B, "A Bench", 0.1, "no", dv="v1", labeled_by="llm-research", evidence="batch note"),
    ]
    m1, retired1 = G.merge_labels(
        [
            row(A, "St Paul's", 0.92, dv="v2"),
            row(C, "New Find", 0.6, dv="v2"),
        ],
        labeled,
    )
    assert {r.place_id: r.label for r in m1} == {A: "yes", C: None}
    assert {r.place_id: r.labeled_by for r in m1} == {A: "rob", C: None}
    assert [r.place_id for r in retired1] == [B]
    assert retired1[0].label == "no"
    assert retired1[0].labeled_by == "llm-research"
    assert retired1[0].evidence == "batch note"
    assert not retired1[0].active

    m2, _ = G.merge_labels(
        [
            row(A, "St Paul's", 0.9, dv="v3"),
            row(B, "A Bench", 0.1, dv="v3"),
        ],
        m1 + retired1,
    )
    resurrected = {r.place_id: r for r in m2}[B]
    assert resurrected.label == "no"
    assert resurrected.labeled_by == "llm-research"
    assert resurrected.evidence == "batch note"


def test_labels_survive_and_resurrect_through_tsv_persistence():
    labeled = [
        row(A, "St Paul's", 0.9, "yes", dv="v1", labeled_by="rob-confirmed", evidence="confirmed"),
        row(B, "A Bench", 0.1, "no", dv="v1", labeled_by="llm-research", evidence="batch note"),
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
    resurrected = {r.place_id: r for r in m2}[B]
    assert resurrected.label == "no"
    assert resurrected.labeled_by == "llm-research"
    assert resurrected.evidence == "batch note"


def test_same_data_version_with_changed_candidate_set_is_rejected():
    with pytest.raises(ValueError, match="candidate set changed"):
        G.merge_labels([row(A, "St Paul's", 0.9, dv="v1")], ROWS)


def test_same_version_guard_uses_active_rows_with_retired_older_history():
    existing = [
        row(A, "Active A", 0.9, "yes", dv="v2"),
        row(B, "Retired B", 0.1, "no", active=False, dv="v1"),
    ]

    with pytest.raises(ValueError, match="candidate set changed"):
        G.merge_labels(
            [row(A, "Active A", 0.9, dv="v2"), row(C, "Unexpected C", 0.2, dv="v2")],
            existing,
        )


@pytest.mark.parametrize("signal_name", ["=formula", "+formula", "-formula", "@formula"])
def test_database_signal_names_cannot_produce_tsv_headers_parser_rejects(signal_name):
    with pytest.raises(ValueError, match="spreadsheet-unsafe signal name"):
        G._validate_signals_json(json.dumps({signal_name: 1.0}))


def test_dump_area_reads_planned_a2_a3_a4_tables(conn):
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS place_categories (
            place_id TEXT PRIMARY KEY,
            category TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS place_scores (
            place_id TEXT PRIMARY KEY,
            tier INTEGER NOT NULL,
            score REAL NOT NULL,
            signals_json TEXT NOT NULL
        );
        """
    )
    store.replace_places(
        conn,
        region="united-kingdom",
        places=[
            {
                "place_id": A,
                "name": "In",
                "lat": 51.51,
                "lon": -0.11,
                "refs": ["wd:Q1"],
                "member_refs": ["wd:Q1"],
                "status": "active",
            },
            {
                "place_id": B,
                "name": "Out",
                "lat": 52.0,
                "lon": -0.11,
                "refs": ["wd:Q2"],
                "member_refs": ["wd:Q2"],
                "status": "active",
            },
        ],
    )
    conn.execute(
        """
        INSERT INTO place_categories (place_id, region, category, run_id)
        VALUES (?, ?, ?, ?)
        """,
        (A, "united-kingdom", "history", "cat1"),
    )
    conn.execute(
        """
        INSERT INTO place_categories (place_id, region, category, run_id)
        VALUES (?, ?, ?, ?)
        """,
        (B, "united-kingdom", "history", "cat1"),
    )
    conn.execute(
        """
        INSERT INTO place_scores (place_id, region, tier, score, signals_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (A, "united-kingdom", 2, 0.8, json.dumps({"article": 0.8, "llm_curiosity": None}), "score1"),
    )
    conn.execute(
        """
        INSERT INTO place_scores (place_id, region, tier, score, signals_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (B, "united-kingdom", 3, 0.9, json.dumps({"article": 0.9, "llm_curiosity": None}), "score1"),
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
            labeled_by=None,
            evidence="",
        )
    ]


def test_dump_area_rejects_malformed_signals_json(conn):
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS place_categories (
            place_id TEXT PRIMARY KEY,
            category TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS place_scores (
            place_id TEXT PRIMARY KEY,
            tier INTEGER NOT NULL,
            score REAL NOT NULL,
            signals_json TEXT NOT NULL
        );
        """
    )
    store.replace_places(
        conn,
        region="united-kingdom",
        places=[
            {
                "place_id": A,
                "name": "In",
                "lat": 51.51,
                "lon": -0.11,
                "refs": ["wd:Q1"],
                "member_refs": ["wd:Q1"],
                "status": "active",
            }
        ],
    )
    conn.execute(
        """
        INSERT INTO place_categories (place_id, region, category, run_id)
        VALUES (?, ?, ?, ?)
        """,
        (A, "united-kingdom", "history", "cat1"),
    )
    conn.execute(
        """
        INSERT INTO place_scores (place_id, region, tier, score, signals_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (A, "united-kingdom", 2, 0.8, '["bad"]', "score1"),
    )

    with pytest.raises(ValueError, match="signals_json"):
        G.dump_area(conn, "london", [-0.2, 51.5, -0.1, 51.6], data_version="run-1")
