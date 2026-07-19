from mt_pipeline import config


def test_region_config_loads_zone_levels_and_prune_list():
    cfg = config.load("united-kingdom")
    assert cfg.zone_levels == {2: "country", 4: "region", 6: "county"}
    assert cfg.zone_allowlist == ()


def test_region_config_rejects_duplicate_zone_level_names():
    data = {
        "region_id": "test",
        "display_name": "Test",
        "bbox": [0, 0, 1, 1],
        "languages": ["en"],
        "sources": {"osm": True},
        "zone_levels": {"2": "country", "4": "country"},
        "basemap": {
            "source_pmtiles": "https://example.test/base.pmtiles",
            "maxzoom": 14,
            "pack_granularity": "country",
            "size_budget_bytes": 100,
            "measured_archive_bytes": 50,
        },
    }
    try:
        config.RegionConfig.from_dict(data)
    except config.ConfigError as exc:
        assert "duplicate zone level name" in str(exc)
    else:
        raise AssertionError("expected duplicate zone level names to fail")
