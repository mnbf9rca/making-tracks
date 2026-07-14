import json

from mt_contracts import caps


def test_budget_ceiling_matches_caps_constant(contracts_root):
    budget = json.loads((contracts_root / "basemap-budget.json").read_text())
    assert budget["ceiling_bytes"] == caps.PACK_BUDGET_CEILING_BYTES


def test_every_region_config_stays_under_ceiling(contracts_root):
    budget = json.loads((contracts_root / "basemap-budget.json").read_text())
    for region in ("uk", "malaysia"):
        cfg = json.loads((contracts_root / f"regions/{region}.json").read_text())
        assert cfg["basemap"]["size_budget_bytes"] <= caps.PACK_BUDGET_CEILING_BYTES
        maxzoom = cfg["basemap"]["maxzoom"]
        row = next(
            m
            for m in budget["measurements"]
            if m["region"] == region and m["maxzoom"] == maxzoom
        )
        assert cfg["basemap"]["measured_archive_bytes"] == row["archive_bytes"]
        assert row["exact"] is True
