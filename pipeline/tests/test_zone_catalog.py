import json
import math
import random

from mt_contracts.validation import validate_instance
from mt_pipeline import config, store
from mt_pipeline.publish import publish_stage, zone_catalog


def _cfg():
    return config.RegionConfig.from_dict(
        {
            "schema_version": 1,
            "region_id": "united-kingdom",
            "display_name": "United Kingdom",
            "bbox": [-1.0, -1.0, 1.0, 1.0],
            "languages": ["en"],
            "sources": {"osm": True},
            "zone_levels": {"2": "country", "6": "county"},
            "zone_allowlist": ["osm_r2"],
            "basemap": {
                "source_pmtiles": "https://example.test/base.pmtiles",
                "maxzoom": 14,
                "pack_granularity": "country",
                "size_budget_bytes": 100000,
                "measured_archive_bytes": 50000,
            },
        }
    )


def _cfg_with_regions():
    return config.RegionConfig.from_dict(
        {
            "schema_version": 1,
            "region_id": "united-kingdom",
            "display_name": "United Kingdom",
            "bbox": [-1.0, -1.0, 3.0, 3.0],
            "languages": ["en"],
            "sources": {"osm": True},
            "zone_levels": {"2": "country", "4": "region", "6": "county"},
            "zone_allowlist": ["osm_r3"],
            "basemap": {
                "source_pmtiles": "https://example.test/base.pmtiles",
                "maxzoom": 14,
                "pack_granularity": "country",
                "size_budget_bytes": 100000,
                "measured_archive_bytes": 50000,
            },
        }
    )


def _insert_boundary(conn, *, relation_id, admin_level, level_name, name, ring):
    xs = [point[0] for point in ring]
    ys = [point[1] for point in ring]
    conn.execute(
        """
        INSERT INTO zone_boundaries
            (region, zone_id, osm_relation_id, admin_level, level_name, name,
             name_translations_json, wikidata, bbox_json, geometry_json, run_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            "united-kingdom",
            f"osm_r{relation_id}",
            relation_id,
            admin_level,
            level_name,
            name,
            "{}",
            None,
            json.dumps([min(xs), min(ys), max(xs), max(ys)]),
            json.dumps({"type": "MultiPolygon", "coordinates": [[ring]]}),
            "r1",
        ),
    )
    conn.commit()


def test_cells_for_polygon_uses_intersects_rule_for_boundary_cells():
    x, y = zone_catalog.lonlat_to_cell(0.0, 0.0)
    west, south, east, north = zone_catalog.cell_bbox(x, y)
    strip = [
        [west - 0.0005, south + 0.001],
        [west + 0.0005, south + 0.001],
        [west + 0.0005, north - 0.001],
        [west - 0.0005, north - 0.001],
        [west - 0.0005, south + 0.001],
    ]

    assert (x, y) in zone_catalog.cells_for_multipolygon([[strip]])


def test_cells_for_polygon_excludes_cells_wholly_inside_hole():
    x, y = zone_catalog.lonlat_to_cell(0.0, 0.0)
    west, south, east, north = zone_catalog.cell_bbox(x, y)
    outer = [
        [west - 1.0, south - 1.0],
        [east + 1.0, south - 1.0],
        [east + 1.0, north + 1.0],
        [west - 1.0, north + 1.0],
        [west - 1.0, south - 1.0],
    ]
    hole = [
        [west - 0.1, south - 0.1],
        [east + 0.1, south - 0.1],
        [east + 0.1, north + 0.1],
        [west - 0.1, north + 0.1],
        [west - 0.1, south - 0.1],
    ]

    assert (x, y) not in zone_catalog.cells_for_multipolygon([[outer, hole]])


def test_cells_for_multipolygon_matches_bruteforce_scan_on_irregular_holey_fixture():
    x, y = zone_catalog.lonlat_to_cell(0.0, 0.0)
    west, _, _, north = zone_catalog.cell_bbox(x - 2, y - 2)
    _, _, east, _ = zone_catalog.cell_bbox(x + 2, y - 2)
    _, south, _, _ = zone_catalog.cell_bbox(x - 2, y + 2)
    _, center_south, _, center_north = zone_catalog.cell_bbox(x, y)
    _, upper_south, _, upper_north = zone_catalog.cell_bbox(x, y - 1)
    center_lat = (center_south + center_north) / 2.0
    upper_center_lat = (upper_south + upper_north) / 2.0
    right_mid = zone_catalog.cell_bbox(x + 1, y)[2]
    right_far = east
    left_mid = zone_catalog.cell_bbox(x - 1, y)[0]
    left_far = west
    lower_center_lat = (
        zone_catalog.cell_bbox(x, y + 1)[1] + zone_catalog.cell_bbox(x, y + 1)[3]
    ) / 2.0
    center_west, center_south, center_east, center_north = zone_catalog.cell_bbox(x, y)
    outer = [
        [left_far, upper_center_lat],
        [left_mid, north],
        [right_far, upper_center_lat],
        [right_mid, center_lat],
        [right_far, lower_center_lat],
        [left_far, south],
        [left_mid, center_lat],
        [left_far, upper_center_lat],
    ]
    hole = [
        [center_west - 0.001, center_south + 0.001],
        [center_east + 0.001, center_south - 0.001],
        [center_east - 0.001, center_north + 0.001],
        [center_west + 0.001, center_north - 0.001],
        [center_west - 0.001, center_south + 0.001],
    ]
    multipolygon = [[outer, hole]]

    assert zone_catalog.cells_for_multipolygon(multipolygon) == _bruteforce_cells(
        multipolygon
    )


def test_cells_for_multipolygon_matches_bruteforce_scan_for_seeded_polygons():
    rng = random.Random(8675309)
    x, y = zone_catalog.lonlat_to_cell(0.0, 0.0)
    west, _, east, _ = zone_catalog.cell_bbox(x, y)
    _, south, _, north = zone_catalog.cell_bbox(x, y)
    span_lon = east - west
    span_lat = north - south

    for _ in range(50):
        center_lon = rng.uniform(west - span_lon * 1.5, east + span_lon * 1.5)
        center_lat = rng.uniform(south - span_lat * 1.5, north + span_lat * 1.5)
        points = []
        for index in range(rng.randint(5, 9)):
            angle = (index / 8.0) * 6.283185307179586 + rng.uniform(-0.18, 0.18)
            radius_lon = rng.uniform(span_lon * 0.35, span_lon * 1.35)
            radius_lat = rng.uniform(span_lat * 0.35, span_lat * 1.35)
            points.append(
                [
                    center_lon + math.cos(angle) * radius_lon,
                    center_lat + math.sin(angle) * radius_lat,
                ]
            )
        points.sort(key=lambda point: math.atan2(point[1] - center_lat, point[0] - center_lon))
        points.append(points[0])
        multipolygon = [[points]]

        assert zone_catalog.cells_for_multipolygon(multipolygon) == _bruteforce_cells(
            multipolygon
        )


def test_point_in_multipolygon_treats_boundary_points_as_inside():
    polygon = [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0], [0.0, 0.0]]

    assert zone_catalog._point_in_multipolygon((1.0, 0.5), [[polygon]])
    assert zone_catalog._point_in_multipolygon((0.5, 1.0), [[polygon]])


def test_scanline_intersections_treat_unclosed_ring_as_closed():
    ring = [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]

    assert zone_catalog._ring_scanline_intersections(ring, 0.5) == [0.0, 1.0]


def test_ring_interior_falls_back_to_point_checks_for_odd_intersections(monkeypatch):
    x, y = zone_catalog.lonlat_to_cell(0.0, 0.0)
    monkeypatch.setattr(zone_catalog, "_ring_scanline_intersections", lambda _ring, _lat: [0.0])
    monkeypatch.setattr(zone_catalog, "_point_in_polygon", lambda _point, _ring: True)

    cells = zone_catalog._cells_for_ring_interior([], x, x, y, y)

    assert cells == {(x, y)}


def test_zone_cell_sizes_include_referenced_thumbnail_bytes():
    thumb_sha = "a" * 64
    image_payload = json.dumps(
        {
            "schema_version": 1,
            "min_reader_version": 1,
            "z": 10,
            "x": 1,
            "y": 2,
            "places": [{"thumb_sha256": thumb_sha, "bytes": 9}],
        },
        sort_keys=True,
    ).encode()

    class Art:
        x = 1
        y = 2
        json_bytes = image_payload
        byte_len = len(image_payload)

    sizes = publish_stage._zone_cell_sizes((), (), [Art()])

    assert sizes[(1, 2)].bytes_without_thumbs == 0
    assert sizes[(1, 2)].bytes_with_thumbs == len(image_payload) + 9


def test_zone_cell_sizes_dedupe_repeated_thumbnail_sha_in_cell():
    thumb_sha = "a" * 64
    image_payload = json.dumps(
        {
            "schema_version": 1,
            "min_reader_version": 1,
            "z": 10,
            "x": 1,
            "y": 2,
            "places": [
                {"thumb_sha256": thumb_sha, "bytes": 9},
                {"thumb_sha256": thumb_sha, "bytes": 9},
            ],
        },
        sort_keys=True,
    ).encode()

    class Art:
        x = 1
        y = 2
        json_bytes = image_payload
        byte_len = len(image_payload)

    sizes = publish_stage._zone_cell_sizes((), (), [Art()])

    assert sizes[(1, 2)].bytes_with_thumbs == len(image_payload) + 9


def test_materialize_catalog_does_not_parent_disjoint_polygons_sharing_cell(tmp_path):
    conn = store.connect(tmp_path / "work.db")
    store.init_schema(conn)
    x, y = zone_catalog.lonlat_to_cell(0.0, 0.0)
    west, south, east, north = zone_catalog.cell_bbox(x, y)
    parent_ring = [
        [west + 0.001, south + 0.001],
        [west + 0.01, south + 0.001],
        [west + 0.01, south + 0.01],
        [west + 0.001, south + 0.01],
        [west + 0.001, south + 0.001],
    ]
    child_ring = [
        [east - 0.01, north - 0.01],
        [east - 0.001, north - 0.01],
        [east - 0.001, north - 0.001],
        [east - 0.01, north - 0.001],
        [east - 0.01, north - 0.01],
    ]
    _insert_boundary(
        conn,
        relation_id=1,
        admin_level=2,
        level_name="country",
        name="Parent",
        ring=parent_ring,
    )
    _insert_boundary(
        conn,
        relation_id=2,
        admin_level=6,
        level_name="county",
        name="Child",
        ring=child_ring,
    )

    full, _pruned = zone_catalog.materialize_catalogs(
        conn,
        _cfg(),
        publish_version="20260718T090000Z",
        generated_at="2026-07-18T09:00:00Z",
        cell_sizes={},
    )

    zones = {zone["zone_id"]: zone for zone in full["zones"]}
    assert zones["osm_r2"]["parent"] is None


def test_materialize_catalog_skips_containment_for_bbox_disjoint_candidates(
    monkeypatch,
    tmp_path,
):
    conn = store.connect(tmp_path / "work.db")
    store.init_schema(conn)
    _insert_boundary(
        conn,
        relation_id=1,
        admin_level=2,
        level_name="country",
        name="Distant Parent",
        ring=[[-1.0, -1.0], [-0.5, -1.0], [-0.5, -0.5], [-1.0, -0.5], [-1.0, -1.0]],
    )
    _insert_boundary(
        conn,
        relation_id=2,
        admin_level=6,
        level_name="county",
        name="Distant Child",
        ring=[[0.5, 0.5], [1.0, 0.5], [1.0, 1.0], [0.5, 1.0], [0.5, 0.5]],
    )

    def fail_cell_ratio(_child_cells, _parent_cells):
        raise AssertionError("bbox-disjoint zones should not reach cell ratio")

    monkeypatch.setattr(
        zone_catalog,
        "_cell_containment_ratio",
        fail_cell_ratio,
    )

    full, _pruned = zone_catalog.materialize_catalogs(
        conn,
        _cfg(),
        publish_version="20260718T090000Z",
        generated_at="2026-07-18T09:00:00Z",
        cell_sizes={},
    )

    zones = {zone["zone_id"]: zone for zone in full["zones"]}
    assert zones["osm_r2"]["parent"] is None


def test_parent_selection_reuses_precomputed_child_samples(monkeypatch):
    items = [
        {
            "zone_id": "osm_r1",
            "admin_level": 2,
            "bbox": [-1.0, -1.0, 1.0, 1.0],
            "geometry": [[[]]],
            "cells": {(1, 1)},
            "samples": [(0.0, 0.0)],
        },
        {
            "zone_id": "osm_r2",
            "admin_level": 6,
            "bbox": [-0.1, -0.1, 0.1, 0.1],
            "geometry": [[[]]],
            "cells": {(1, 1)},
            "samples": [(0.0, 0.0)],
        },
    ]

    def fail_sample(_multipolygon):
        raise AssertionError("precomputed samples should be reused")

    monkeypatch.setattr(zone_catalog, "_multipolygon_samples", fail_sample)
    monkeypatch.setattr(zone_catalog, "_point_in_multipolygon", lambda _point, _parent: True)
    monkeypatch.setattr(
        zone_catalog,
        "_point_strictly_in_multipolygon",
        lambda _point, _parent: True,
    )

    assert zone_catalog._parents(items) == {"osm_r2": "osm_r1"}


def test_parent_selection_uses_cell_ratio_before_exact_sample_ratio(monkeypatch):
    items = [
        {
            "zone_id": "osm_r1",
            "admin_level": 2,
            "bbox": [-1.0, -1.0, 1.0, 1.0],
            "geometry": [[[]]],
            "cells": {(1, 1), (1, 2), (2, 1), (2, 2)},
            "samples": [(0.0, 0.0)],
        },
        {
            "zone_id": "osm_r2",
            "admin_level": 6,
            "bbox": [-0.1, -0.1, 0.1, 0.1],
            "geometry": [[[]]],
            "cells": {(1, 1), (1, 2)},
            "samples": [(0.0, 0.0)],
        },
    ]

    def fail_exact_ratio(_samples, _parent):
        raise AssertionError("cell overlap should provide the candidate ratio")

    monkeypatch.setattr(zone_catalog, "_containment_ratio_for_samples", fail_exact_ratio)
    monkeypatch.setattr(
        zone_catalog,
        "_point_strictly_in_multipolygon",
        lambda _point, _parent: True,
    )

    assert zone_catalog._parents(items) == {"osm_r2": "osm_r1"}


def test_parent_selection_uses_bbox_interior_overlap_before_exact_strict_sample(
    monkeypatch,
):
    items = [
        {
            "zone_id": "osm_r1",
            "admin_level": 2,
            "bbox": [-1.0, -1.0, 1.0, 1.0],
            "geometry": [[[]]],
            "cells": {(1, 1), (1, 2), (2, 1), (2, 2)},
            "samples": [(0.0, 0.0)],
        },
        {
            "zone_id": "osm_r2",
            "admin_level": 6,
            "bbox": [-0.1, -0.1, 0.1, 0.1],
            "geometry": [[[]]],
            "cells": {(1, 1), (1, 2)},
            "samples": [(0.0, 0.0)],
        },
    ]

    def fail_strict(_samples, _parent):
        raise AssertionError("bbox interior overlap should avoid exact strict sampling")

    monkeypatch.setattr(zone_catalog, "_has_strict_containment_sample", fail_strict)

    assert zone_catalog._parents(items) == {"osm_r2": "osm_r1"}


def test_materialize_catalog_prefers_deepest_containing_parent_on_shared_boundary(tmp_path):
    conn = store.connect(tmp_path / "work.db")
    store.init_schema(conn)
    country = [[0.0, 0.0], [3.0, 0.0], [3.0, 3.0], [0.0, 3.0], [0.0, 0.0]]
    region = [[0.0, 0.0], [1.0, 0.0], [1.0, 3.0], [0.0, 3.0], [0.0, 0.0]]
    child = [
        [0.0, 0.0],
        [1.0, 0.0],
        [1.2, 0.8],
        [1.2, 1.2],
        [0.0, 1.2],
        [0.0, 0.0],
    ]
    _insert_boundary(
        conn,
        relation_id=1,
        admin_level=2,
        level_name="country",
        name="Country",
        ring=country,
    )
    _insert_boundary(
        conn,
        relation_id=2,
        admin_level=4,
        level_name="region",
        name="Region",
        ring=region,
    )
    _insert_boundary(
        conn,
        relation_id=3,
        admin_level=6,
        level_name="county",
        name="Coastal Child",
        ring=child,
    )

    full, _pruned = zone_catalog.materialize_catalogs(
        conn,
        _cfg_with_regions(),
        publish_version="20260718T090000Z",
        generated_at="2026-07-18T09:00:00Z",
        cell_sizes={},
    )

    zones = {zone["zone_id"]: zone for zone in full["zones"]}
    assert zones["osm_r3"]["parent"] == "osm_r2"


def test_materialize_catalog_rejects_adjacent_parent_with_only_shared_boundary(
    tmp_path,
):
    conn = store.connect(tmp_path / "work.db")
    store.init_schema(conn)
    country = [[0.0, 0.0], [3.0, 0.0], [3.0, 3.0], [0.0, 3.0], [0.0, 0.0]]
    adjacent_region = [[0.0, 0.0], [1.0, 0.0], [1.0, 3.0], [0.0, 3.0], [0.0, 0.0]]
    child = [[1.0, 0.0]]
    child.extend([[1.0, index / 100.0] for index in range(1, 101)])
    child.extend([[1.4, 1.0], [1.4, 0.0], [1.0, 0.0]])
    _insert_boundary(
        conn,
        relation_id=1,
        admin_level=2,
        level_name="country",
        name="Country",
        ring=country,
    )
    _insert_boundary(
        conn,
        relation_id=2,
        admin_level=4,
        level_name="region",
        name="Adjacent Region",
        ring=adjacent_region,
    )
    _insert_boundary(
        conn,
        relation_id=3,
        admin_level=6,
        level_name="county",
        name="Border County",
        ring=child,
    )

    full, _pruned = zone_catalog.materialize_catalogs(
        conn,
        _cfg_with_regions(),
        publish_version="20260718T090000Z",
        generated_at="2026-07-18T09:00:00Z",
        cell_sizes={},
    )

    zones = {zone["zone_id"]: zone for zone in full["zones"]}
    assert zones["osm_r3"]["parent"] == "osm_r1"


def test_materialize_catalog_fails_when_configured_level_produces_no_zones(tmp_path):
    conn = store.connect(tmp_path / "work.db")
    store.init_schema(conn)
    _insert_boundary(
        conn,
        relation_id=2,
        admin_level=6,
        level_name="county",
        name="County",
        ring=[[0.0, 0.0], [0.5, 0.0], [0.5, 0.5], [0.0, 0.5], [0.0, 0.0]],
    )

    try:
        zone_catalog.materialize_catalogs(
            conn,
            _cfg(),
            publish_version="20260718T090000Z",
            generated_at="2026-07-18T09:00:00Z",
            cell_sizes={},
        )
    except zone_catalog.ZoneCatalogError as exc:
        assert "configured zone level 2" in str(exc)
    else:
        raise AssertionError("missing configured zone level should fail")


def test_materialize_catalog_fails_when_allowlist_zone_is_missing(tmp_path):
    conn = store.connect(tmp_path / "work.db")
    store.init_schema(conn)
    _insert_boundary(
        conn,
        relation_id=1,
        admin_level=2,
        level_name="country",
        name="Country",
        ring=[[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0], [-1.0, -1.0]],
    )
    _insert_boundary(
        conn,
        relation_id=2,
        admin_level=6,
        level_name="county",
        name="County",
        ring=[[0.0, 0.0], [0.2, 0.0], [0.2, 0.2], [0.0, 0.2], [0.0, 0.0]],
    )
    cfg = config.RegionConfig.from_dict(
        {
            "schema_version": 1,
            "region_id": "united-kingdom",
            "display_name": "United Kingdom",
            "bbox": [-1.0, -1.0, 1.0, 1.0],
            "languages": ["en"],
            "sources": {"osm": True},
            "zone_levels": {"2": "country", "6": "county"},
            "zone_allowlist": ["osm_r999"],
            "basemap": {
                "source_pmtiles": "https://example.test/base.pmtiles",
                "maxzoom": 14,
                "pack_granularity": "country",
                "size_budget_bytes": 100000,
                "measured_archive_bytes": 50000,
            },
        }
    )

    try:
        zone_catalog.materialize_catalogs(
            conn,
            cfg,
            publish_version="20260718T090000Z",
            generated_at="2026-07-18T09:00:00Z",
            cell_sizes={},
        )
    except zone_catalog.ZoneCatalogError as exc:
        assert "zone_allowlist entries not present" in str(exc)
    else:
        raise AssertionError("missing allowlist zone should fail")


def test_materialize_catalog_assigns_parent_and_sizes_from_actual_cells(tmp_path):
    conn = store.connect(tmp_path / "work.db")
    store.init_schema(conn)
    parent_ring = [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0], [-1.0, -1.0]]
    child_ring = [[0.0, 0.0], [0.2, 0.0], [0.2, 0.2], [0.0, 0.2], [0.0, 0.0]]
    _insert_boundary(
        conn,
        relation_id=1,
        admin_level=2,
        level_name="country",
        name="Parent",
        ring=parent_ring,
    )
    _insert_boundary(
        conn,
        relation_id=2,
        admin_level=6,
        level_name="county",
        name="Child",
        ring=child_ring,
    )
    child_cells = zone_catalog.cells_for_multipolygon([[child_ring]])
    cell_sizes = {
        cell: zone_catalog.CellSize(bytes_without_thumbs=100, bytes_with_thumbs=130)
        for cell in child_cells
    }

    full, pruned = zone_catalog.materialize_catalogs(
        conn,
        _cfg(),
        publish_version="20260718T090000Z",
        generated_at="2026-07-18T09:00:00Z",
        cell_sizes=cell_sizes,
    )

    validate_instance("zone-catalog", full)
    validate_instance("zone-catalog", pruned)
    zones = {zone["zone_id"]: zone for zone in full["zones"]}
    assert zones["osm_r1"]["parent"] is None
    assert zones["osm_r2"]["parent"] == "osm_r1"
    assert zones["osm_r2"]["bytes_without_thumbs"] == 100 * len(child_cells)
    assert zones["osm_r2"]["bytes_with_thumbs"] == 130 * len(child_cells)
    assert [zone["zone_id"] for zone in pruned["zones"]] == ["osm_r1", "osm_r2"]


def _bruteforce_cells(multipolygon):
    cells = set()
    for polygon in multipolygon:
        ring = polygon[0]
        xs = [float(point[0]) for point in ring]
        ys = [float(point[1]) for point in ring]
        min_x, min_y = zone_catalog.lonlat_to_cell(min(xs), max(ys))
        max_x, max_y = zone_catalog.lonlat_to_cell(max(xs), min(ys))
        for cell_x in range(min(min_x, max_x), max(min_x, max_x) + 1):
            for cell_y in range(min(min_y, max_y), max(min_y, max_y) + 1):
                if zone_catalog._polygon_intersects_bbox(
                    polygon,
                    zone_catalog.cell_bbox(cell_x, cell_y),
                ):
                    cells.add((cell_x, cell_y))
    return cells
