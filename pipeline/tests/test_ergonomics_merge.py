import itertools
import sqlite3

from mt_pipeline import store
from mt_pipeline.ergonomics import merge as M
from mt_pipeline.ergonomics import staging as S


def _main_conn():
    conn = sqlite3.connect(":memory:")
    store.init_schema(conn)
    return conn


def _stage(root, run_id, source, rows):
    conn = S.open_staging(root, run_id, source)
    stored_source = M.stored_source(source)
    for source_ref, name in rows:
        conn.execute(
            """
            INSERT INTO source_records
                (source, source_ref, region, name, lat, lon, props_json, run_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (stored_source, source_ref, "united-kingdom", name, 0.0, 0.0, "{}", run_id),
        )
    conn.commit()
    conn.close()
    return S.staging_path(root, run_id, source)


def _merged_dump(order, staged, succeeded):
    main = _main_conn()
    M.merge_sources(
        main,
        {source: staged[source] for source in order},
        succeeded,
        order=M.STAGING_ORDER,
        full=True,
    )
    return main.execute(
        """
        SELECT id, source, source_ref, name
        FROM source_records
        ORDER BY id
        """
    ).fetchall()


def test_merge_is_byte_identical_across_completion_orders(tmp_path):
    staged = {
        "wikidata": _stage(
            tmp_path, "r", "wikidata", [("wd:Q2", "B"), ("wd:Q1", "A")]
        ),
        "osm": _stage(tmp_path, "r", "osm", [("osm:node/9", "W")]),
    }
    succeeded = {"wikidata", "osm"}
    baseline = _merged_dump(["wikidata", "osm"], staged, succeeded)

    for perm in itertools.permutations(staged):
        assert _merged_dump(list(perm), staged, succeeded) == baseline


def test_failed_source_is_not_merged(tmp_path):
    staged = {
        "wikidata": _stage(tmp_path, "r", "wikidata", [("wd:Q1", "A")]),
        "osm": _stage(tmp_path, "r", "osm", [("osm:node/9", "W")]),
    }

    dump = _merged_dump(["wikidata", "osm"], staged, succeeded={"wikidata"})

    assert dump == [(1, "wd", "wd:Q1", "A")]


def test_partial_merge_without_region_preserves_other_regions(tmp_path):
    main = _main_conn()
    main.executemany(
        """
        INSERT INTO source_records
            (source, source_ref, region, name, lat, lon, props_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
            ("osm", "osm:node/old-uk", "united-kingdom", "Old UK", 0.0, 0.0, "{}", "old"),
            (
                "osm",
                "osm:node/old-my",
                "malaysia-singapore-brunei",
                "Old Malaysia",
                0.0,
                0.0,
                "{}",
                "old",
            ),
        ],
    )
    main.commit()
    staged = _stage(tmp_path, "r", "osm", [("osm:node/new-uk", "New UK")])

    M.merge_sources(
        main,
        {"osm": staged},
        {"osm"},
        order=("osm",),
        full=False,
    )

    assert main.execute(
        """
        SELECT region, source_ref, name
        FROM source_records
        ORDER BY region, source_ref
        """
    ).fetchall() == [
        ("malaysia-singapore-brunei", "osm:node/old-my", "Old Malaysia"),
        ("united-kingdom", "osm:node/new-uk", "New UK"),
    ]


def test_empty_partial_merge_without_region_fails_without_deleting_rows(tmp_path):
    main = _main_conn()
    main.execute(
        """
        INSERT INTO source_records
            (source, source_ref, region, name, lat, lon, props_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        ("osm", "osm:node/old", "united-kingdom", "Old", 0.0, 0.0, "{}", "old"),
    )
    main.commit()
    staged = _stage(tmp_path, "r", "osm", [])

    try:
        M.merge_sources(
            main,
            {"osm": staged},
            {"osm"},
            order=("osm",),
            full=False,
        )
    except ValueError as exc:
        assert "region is required" in str(exc)
    else:
        raise AssertionError("empty partial merge without region did not fail")

    assert main.execute(
        """
        SELECT region, source, source_ref, name
        FROM source_records
        """
    ).fetchall() == [("united-kingdom", "osm", "osm:node/old", "Old")]


def test_open_staging_recreates_existing_source_database(tmp_path):
    conn = S.open_staging(tmp_path, "r", "wikidata")
    conn.execute(
        """
        INSERT INTO source_records
            (source, source_ref, region, name, lat, lon, props_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        ("wd", "wd:Q1", "united-kingdom", "Old", 0.0, 0.0, "{}", "old"),
    )
    conn.commit()
    conn.close()

    fresh = S.open_staging(tmp_path, "r", "wikidata")

    assert fresh.execute("SELECT COUNT(*) FROM source_records").fetchone()[0] == 0
    fresh.close()


def test_staging_run_id_is_opaque_and_cleaned_inside_staging_root(tmp_path):
    root = tmp_path / "root"
    outside = tmp_path / "outside"
    outside.mkdir()
    marker = outside / "keep.txt"
    marker.write_text("keep")
    run_id = "../outside"

    path = S.staging_path(root, run_id, "wikidata")
    assert path.parent.parent == root.resolve() / "staging"
    assert ".." not in path.parts

    conn = S.open_staging(root, run_id, "wikidata")
    conn.close()
    assert path.exists()
    S.clean_run(root, run_id)

    assert marker.read_text() == "keep"
    assert not path.exists()
