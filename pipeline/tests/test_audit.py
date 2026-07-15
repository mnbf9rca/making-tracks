import json

from mt_pipeline import audit, store


def _seed(rows):
    conn = store.connect(":memory:")
    store.init_schema(conn)
    for row in rows:
        conn.execute(
            """
            INSERT INTO source_records
                (region, source, source_ref, name, lat, lon, props_json, run_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            row,
        )
    conn.commit()
    return conn


def test_audit_counts_p31_and_candidate_osm_tags_sorted():
    rows = [
        ("uk", "wd", "wd:Q1", "A", 1, 1, json.dumps({"p31": "Q16970"}), "r"),
        ("uk", "wd", "wd:Q2", "B", 1, 1, json.dumps({"p31": "Q16970"}), "r"),
        ("uk", "wd", "wd:Q3", "C", 1, 1, json.dumps({"p31": "Q33506"}), "r"),
        ("uk", "osm", "osm:node/1", "D", 1, 1, json.dumps({"historic": "castle"}), "r"),
        ("uk", "osm", "osm:node/2", "E", 1, 1, json.dumps({"historic": "castle"}), "r"),
        ("uk", "osm", "osm:node/3", "Hotel", 1, 1, json.dumps({"tourism": "hotel"}), "r"),
        ("uk", "osm", "osm:node/4", "Art", 1, 1, json.dumps({"tourism": "artwork"}), "r"),
        ("uk", "hehle", "hehle:9", "F", 1, 1, json.dumps({"grade": "I"}), "r"),
        ("uk", "plaque", "plaque:1", "G", 1, 1, json.dumps({}), "r"),
        ("malaysia", "wd", "wd:Q9", "Other", 1, 1, json.dumps({"p31": "Q999"}), "r"),
    ]
    rep = audit.audit_region(_seed(rows), "uk")

    assert rep.n_records == 9
    assert rep.by_source == {"hehle": 1, "osm": 4, "plaque": 1, "wd": 3}
    assert rep.p31_counts[0] == ("Q16970", 2)
    assert ("Q33506", 1) in rep.p31_counts
    assert rep.osm_tag_counts == [("historic=castle", 2), ("tourism=artwork", 1)]
    assert rep.grade_counts == [("I", 1)]
    assert rep.plaque_count == 1
    assert "Q16970" in audit.render_markdown(rep)


def test_audit_skips_oversized_or_deeply_nested_props_json():
    deep_json = "[" * 10_000 + "]" * 10_000
    oversized = "{" + '"p31":"' + ("Q" * 70_000) + '"}'
    rows = [
        ("uk", "wd", "wd:Q1", "Deep", 1, 1, deep_json, "r"),
        ("uk", "wd", "wd:Q2", "Large", 1, 1, oversized, "r"),
        ("uk", "wd", "wd:Q3", "OK", 1, 1, json.dumps({"p31": "Q16970"}), "r"),
    ]

    rep = audit.audit_region(_seed(rows), "uk")

    assert rep.n_records == 3
    assert rep.p31_counts == [("Q16970", 1)]


def test_markdown_escapes_source_derived_table_cells():
    rows = [
        (
            "uk",
            "osm",
            "osm:node/1",
            "Pipe",
            1,
            1,
            json.dumps({"historic": "castle | 999 | fake"}),
            "r",
        )
    ]

    rendered = audit.render_markdown(audit.audit_region(_seed(rows), "uk"))

    assert "historic=castle \\| 999 \\| fake" in rendered
    assert "| historic=castle | 999 | fake | 1 |" not in rendered


def test_audit_is_deterministic_across_row_order_with_ties():
    rows = [
        ("uk", "wd", "wd:Q1", "N", 1, 1, json.dumps({"p31": "Q300"}), "r"),
        ("uk", "wd", "wd:Q2", "N", 1, 1, json.dumps({"p31": "Q200"}), "r"),
        ("uk", "wd", "wd:Q3", "N", 1, 1, json.dumps({"p31": "Q100"}), "r"),
        ("uk", "wd", "wd:Q4", "N", 1, 1, json.dumps({"p31": "Q300"}), "r"),
        ("uk", "wd", "wd:Q5", "N", 1, 1, json.dumps({"p31": "Q200"}), "r"),
        ("uk", "wd", "wd:Q6", "N", 1, 1, json.dumps({"p31": "Q100"}), "r"),
    ]

    rep_a = audit.audit_region(_seed(rows), "uk")
    rep_b = audit.audit_region(_seed(list(reversed(rows))), "uk")

    assert rep_a.p31_counts == [("Q100", 2), ("Q200", 2), ("Q300", 2)]
    assert audit.render_json(rep_a) == audit.render_json(rep_b)


def test_audit_consumes_osm_candidate_config_value_restrictions(tmp_path, monkeypatch):
    candidate_config = tmp_path / "osm_candidate_tags.json"
    candidate_config.write_text(json.dumps({"tags": {"tourism": ["hotel"]}}))
    monkeypatch.setattr(audit, "_OSM_CANDIDATE_TAGS", candidate_config)

    rep = audit.audit_region(
        _seed(
            [
                ("uk", "osm", "osm:node/1", "Hotel", 1, 1, json.dumps({"tourism": "hotel"}), "r"),
                ("uk", "osm", "osm:node/2", "Art", 1, 1, json.dumps({"tourism": "artwork"}), "r"),
            ]
        ),
        "uk",
    )

    assert rep.osm_tag_counts == [("tourism=hotel", 1)]
