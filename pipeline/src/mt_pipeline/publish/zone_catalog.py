"""Materialise extracted OSM admin boundaries into a versioned zone catalog."""

from __future__ import annotations

from dataclasses import dataclass
import json
import math
from typing import Any, Iterable, Mapping

from mt_contracts import caps
from mt_contracts.validation import validate_instance


@dataclass(frozen=True)
class CellSize:
    bytes_without_thumbs: int
    bytes_with_thumbs: int


def lonlat_to_cell(lon: float, lat: float) -> tuple[int, int]:
    lat_rad = math.radians(max(min(lat, 85.05112878), -85.05112878))
    n = 2**caps.TILE_ZOOM
    x = int((lon + 180.0) / 360.0 * n)
    y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return max(0, min(n - 1, x)), max(0, min(n - 1, y))


def cell_bbox(x: int, y: int) -> tuple[float, float, float, float]:
    n = 2**caps.TILE_ZOOM
    west = x / n * 360.0 - 180.0
    east = (x + 1) / n * 360.0 - 180.0
    north = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n))))
    south = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (y + 1) / n))))
    return west, south, east, north


def cells_for_multipolygon(multipolygon: list) -> set[tuple[int, int]]:
    cells: set[tuple[int, int]] = set()
    for polygon in multipolygon:
        if not polygon:
            continue
        ring = polygon[0]
        if not ring:
            continue
        xs = [float(point[0]) for point in ring]
        ys = [float(point[1]) for point in ring]
        min_x, min_y = lonlat_to_cell(min(xs), max(ys))
        max_x, max_y = lonlat_to_cell(max(xs), min(ys))
        for x in range(min(min_x, max_x), max(min_x, max_x) + 1):
            for y in range(min(min_y, max_y), max(min_y, max_y) + 1):
                if _polygon_intersects_bbox(polygon, cell_bbox(x, y)):
                    cells.add((x, y))
    return cells


def _polygon_intersects_bbox(polygon: list, bbox: tuple[float, float, float, float]) -> bool:
    outer = polygon[0]
    if not _ring_area_intersects_bbox(outer, bbox):
        return False
    for hole in polygon[1:]:
        if _bbox_wholly_inside_ring(bbox, hole):
            return False
    return True


def _ring_area_intersects_bbox(ring: list, bbox: tuple[float, float, float, float]) -> bool:
    west, south, east, north = bbox
    corners = [(west, south), (east, south), (east, north), (west, north)]
    if any(_point_in_bbox(float(px), float(py), bbox) for px, py in ring):
        return True
    if any(_point_in_polygon(corner, ring) for corner in corners):
        return True
    return _ring_boundary_intersects_bbox(ring, bbox)


def _ring_boundary_intersects_bbox(
    ring: list, bbox: tuple[float, float, float, float]
) -> bool:
    west, south, east, north = bbox
    corners = [(west, south), (east, south), (east, north), (west, north)]
    if any(_point_in_bbox(float(px), float(py), bbox) for px, py in ring):
        return True
    edges = list(zip(ring, ring[1:], strict=False))
    bbox_edges = list(zip(corners, [corners[1], corners[2], corners[3], corners[0]], strict=True))
    return any(
        _segments_intersect(
            (float(a[0]), float(a[1])),
            (float(b[0]), float(b[1])),
            c,
            d,
        )
        for a, b in edges
        for c, d in bbox_edges
    )


def _bbox_wholly_inside_ring(
    bbox: tuple[float, float, float, float], ring: list
) -> bool:
    west, south, east, north = bbox
    corners = [(west, south), (east, south), (east, north), (west, north)]
    return all(_point_in_polygon(corner, ring) for corner in corners) and not (
        _ring_boundary_intersects_bbox(ring, bbox)
    )


def _point_in_bbox(x: float, y: float, bbox: tuple[float, float, float, float]) -> bool:
    west, south, east, north = bbox
    return west <= x <= east and south <= y <= north


def _point_in_polygon(point: tuple[float, float], ring: list) -> bool:
    x, y = point
    inside = False
    j = len(ring) - 1
    for i, current in enumerate(ring):
        xi, yi = float(current[0]), float(current[1])
        xj, yj = float(ring[j][0]), float(ring[j][1])
        if ((yi > y) != (yj > y)) and (
            x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-12) + xi
        ):
            inside = not inside
        j = i
    return inside


def _segments_intersect(a, b, c, d) -> bool:
    def orient(p, q, r):
        return (q[1] - p[1]) * (r[0] - q[0]) - (q[0] - p[0]) * (r[1] - q[1])

    def on_segment(p, q, r):
        return (
            min(p[0], r[0]) <= q[0] <= max(p[0], r[0])
            and min(p[1], r[1]) <= q[1] <= max(p[1], r[1])
        )

    o1 = orient(a, b, c)
    o2 = orient(a, b, d)
    o3 = orient(c, d, a)
    o4 = orient(c, d, b)
    if (o1 > 0) != (o2 > 0) and (o3 > 0) != (o4 > 0):
        return True
    return (
        (abs(o1) < 1e-12 and on_segment(a, c, b))
        or (abs(o2) < 1e-12 and on_segment(a, d, b))
        or (abs(o3) < 1e-12 and on_segment(c, a, d))
        or (abs(o4) < 1e-12 and on_segment(c, b, d))
    )


def materialize_catalogs(
    conn,
    region_config,
    *,
    publish_version: str,
    generated_at: str,
    cell_sizes: Mapping[tuple[int, int], CellSize],
) -> tuple[dict[str, Any], dict[str, Any]]:
    zones = _zone_entries(conn, region_config, publish_version, cell_sizes)
    full = _catalog(region_config.region_id, publish_version, generated_at, zones)
    allow = set(region_config.zone_allowlist)
    pruned_zones = _pruned_with_parents(zones, allow)
    pruned = _catalog(region_config.region_id, publish_version, generated_at, pruned_zones)
    validate_instance("zone-catalog", full)
    validate_instance("zone-catalog", pruned)
    return full, pruned


def _catalog(region: str, publish_version: str, generated_at: str, zones: list[dict]) -> dict:
    return {
        "schema_version": 1,
        "min_reader_version": 1,
        "region": region,
        "publish_version": publish_version,
        "generated_at": generated_at,
        "tile_z": caps.TILE_ZOOM,
        "zones": zones,
    }


def _zone_entries(conn, region_config, publish_version: str, cell_sizes) -> list[dict]:
    rows = conn.execute(
        """
        SELECT zone_id, admin_level, level_name, name, name_translations_json,
               wikidata, bbox_json, geometry_json
        FROM zone_boundaries
        WHERE region = ?
        ORDER BY admin_level, zone_id
        """,
        (region_config.region_id,),
    ).fetchall()
    raw = []
    for row in rows:
        geometry = json.loads(row[7])
        cells = cells_for_multipolygon(geometry["coordinates"])
        raw.append(
            {
                "zone_id": row[0],
                "admin_level": int(row[1]),
                "level_name": row[2],
                "name": row[3],
                "name_translations": json.loads(row[4]),
                "wikidata": row[5],
                "bbox": json.loads(row[6]),
                "geometry": geometry["coordinates"],
                "cells": cells,
            }
        )
    parents = _parents(raw)
    entries = []
    for item in raw:
        bytes_without = sum(
            int(cell_sizes.get(cell, CellSize(0, 0)).bytes_without_thumbs)
            for cell in item["cells"]
        )
        bytes_with = sum(
            int(cell_sizes.get(cell, CellSize(0, 0)).bytes_with_thumbs)
            for cell in item["cells"]
        )
        entries.append(
            {
                "zone_id": item["zone_id"],
                "parent": parents.get(item["zone_id"]),
                "admin_level": item["admin_level"],
                "level_name": item["level_name"],
                "name": item["name"],
                "name_translations": item["name_translations"],
                "wikidata": item["wikidata"],
                "bbox": item["bbox"],
                "cell_set": _encode_cells(item["cells"]),
                "bytes_without_thumbs": bytes_without,
                "bytes_with_thumbs": bytes_with,
                "publish_version": publish_version,
                "version": 1,
            }
        )
    return entries


def _parents(items: list[dict]) -> dict[str, str]:
    out: dict[str, str] = {}
    for child in items:
        candidates = []
        for parent in items:
            if parent["admin_level"] >= child["admin_level"]:
                continue
            containment = _multipolygon_containment_ratio(
                child["geometry"], parent["geometry"]
            )
            if containment >= 0.5:
                candidates.append((parent, containment))
        if candidates:
            candidates.sort(
                key=lambda item: (
                    -item[1],
                    -item[0]["admin_level"],
                    item[0]["zone_id"],
                )
            )
            out[child["zone_id"]] = candidates[0][0]["zone_id"]
    return out


def _multipolygon_containment_ratio(child: list, parent: list) -> float:
    samples = []
    for polygon in child:
        if not polygon or not polygon[0]:
            continue
        ring = polygon[0]
        samples.extend((float(point[0]), float(point[1])) for point in ring[:-1])
        xs = [float(point[0]) for point in ring]
        ys = [float(point[1]) for point in ring]
        samples.append(((min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0))
    if not samples:
        return 0.0
    contained = sum(1 for point in samples if _point_in_multipolygon(point, parent))
    return contained / len(samples)


def _point_in_multipolygon(point: tuple[float, float], multipolygon: list) -> bool:
    for polygon in multipolygon:
        if not polygon or not polygon[0]:
            continue
        if _point_in_polygon(point, polygon[0]) and not any(
            _point_in_polygon(point, hole) for hole in polygon[1:]
        ):
            return True
    return False


def _pruned_with_parents(zones: list[dict], allow: set[str]) -> list[dict]:
    by_id = {str(zone["zone_id"]): zone for zone in zones}
    keep: set[str] = set()
    pending = list(sorted(allow))
    while pending:
        zone_id = pending.pop()
        zone = by_id.get(zone_id)
        if zone is None or zone_id in keep:
            continue
        keep.add(zone_id)
        parent = zone.get("parent")
        if parent is not None:
            pending.append(str(parent))
    return [zone for zone in zones if zone["zone_id"] in keep]


def _encode_cells(cells: Iterable[tuple[int, int]]) -> dict:
    by_x: dict[int, list[int]] = {}
    for x, y in sorted(cells):
        by_x.setdefault(x, []).append(y)
    ranges = []
    for x, ys in by_x.items():
        start = prev = ys[0]
        for y in ys[1:]:
            if y == prev + 1:
                prev = y
                continue
            ranges.append([x, start, prev])
            start = prev = y
        ranges.append([x, start, prev])
    return {"encoding": "ranges", "ranges": ranges, "cell_count": sum(len(ys) for ys in by_x.values())}
