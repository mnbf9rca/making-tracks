import pytest

from mt_pipeline import config


def test_load_known_region_returns_structurally_valid_config():
    cfg = config.load("uk")
    assert cfg.region_id == "uk"
    assert len(cfg.bbox) == 4
    assert cfg.languages
    assert isinstance(cfg.basemap.get("maxzoom"), int)
    assert cfg.raw["region_id"] == "uk"


def test_region_id_is_carried_through_not_hardcoded():
    assert config.load("malaysia").region_id == "malaysia"


def test_unknown_region_raises_naming_available():
    with pytest.raises(config.UnknownRegionError) as exc:
        config.load("atlantis")
    assert "uk" in str(exc.value)


def test_load_delegates_validation_to_contracts(monkeypatch):
    import mt_contracts

    called = {}
    real = mt_contracts.load_region_config

    def spy(region_id):
        called["region"] = region_id
        return real(region_id)

    monkeypatch.setattr(mt_contracts, "load_region_config", spy)
    config.load("malaysia")
    assert called["region"] == "malaysia"


def test_region_config_exposes_dormant_basemap_subregions(monkeypatch):
    import mt_contracts

    monkeypatch.setattr(mt_contracts, "available_regions", lambda: ["malaysia"])
    monkeypatch.setattr(
        mt_contracts,
        "load_region_config",
        lambda _r: {
            "schema_version": 1,
            "region_id": "malaysia",
            "display_name": "Malaysia",
            "bbox": [99.64, 0.85, 119.27, 7.36],
            "languages": ["en"],
            "sources": {"wikidata": True},
            "basemap": {
                "source_pmtiles": "https://build.protomaps.com/20260714.pmtiles",
                "maxzoom": 14,
                "pack_granularity": "subregion",
                "size_budget_bytes": 500000000,
                "measured_archive_bytes": 223155574,
                "subregions": [
                    {
                        "id": "central",
                        "display_name": "Central Malaysia",
                        "bbox": [101.6, 3.0, 101.8, 3.2],
                        "measured_archive_bytes": 12345,
                    }
                ],
            },
        },
    )

    cfg = config.load("malaysia")

    assert len(cfg.subregions) == 1
    assert cfg.subregions[0].id == "central"
    assert cfg.subregions[0].region_id == "malaysia_central"
    assert cfg.subregions[0].display_name == "Central Malaysia"
    assert cfg.subregions[0].bbox == (101.6, 3.0, 101.8, 3.2)
    assert cfg.subregions[0].measured_archive_bytes == 12345


def test_region_config_rejects_subregion_id_that_collides_with_known_region(monkeypatch):
    import mt_contracts

    monkeypatch.setattr(
        mt_contracts,
        "available_regions",
        lambda: ["malaysia", "malaysia_central"],
    )
    monkeypatch.setattr(
        mt_contracts,
        "load_region_config",
        lambda _r: {
            "schema_version": 1,
            "region_id": "malaysia",
            "display_name": "Malaysia",
            "bbox": [99.64, 0.85, 119.27, 7.36],
            "languages": ["en"],
            "sources": {"wikidata": True},
            "basemap": {
                "source_pmtiles": "https://build.protomaps.com/20260714.pmtiles",
                "maxzoom": 14,
                "pack_granularity": "subregion",
                "size_budget_bytes": 500000000,
                "measured_archive_bytes": 223155574,
                "subregions": [{"id": "central", "bbox": [101.6, 3.0, 101.8, 3.2]}],
            },
        },
    )

    with pytest.raises(config.ConfigError, match="collides"):
        config.load("malaysia")


def test_region_config_rejects_invalid_subregion_bbox_before_publish(monkeypatch):
    import mt_contracts

    monkeypatch.setattr(mt_contracts, "available_regions", lambda: ["malaysia"])
    monkeypatch.setattr(
        mt_contracts,
        "load_region_config",
        lambda _r: {
            "schema_version": 1,
            "region_id": "malaysia",
            "display_name": "Malaysia",
            "bbox": [99.64, 0.85, 119.27, 7.36],
            "languages": ["en"],
            "sources": {"wikidata": True},
            "basemap": {
                "source_pmtiles": "https://build.protomaps.com/20260714.pmtiles",
                "maxzoom": 14,
                "pack_granularity": "subregion",
                "size_budget_bytes": 500000000,
                "measured_archive_bytes": 223155574,
                "subregions": [{"id": "central", "bbox": [101.6, 120, 101.8, 121]}],
            },
        },
    )

    with pytest.raises(config.ConfigError, match="latitude"):
        config.load("malaysia")


def test_global_region_id_assert_rejects_top_level_subregion_collision(monkeypatch):
    import mt_contracts

    configs = {
        "malaysia": {
            "schema_version": 1,
            "region_id": "malaysia",
            "display_name": "Malaysia",
            "bbox": [99.64, 0.85, 119.27, 7.36],
            "languages": ["en"],
            "sources": {"wikidata": True},
            "basemap": {
                "source_pmtiles": "https://build.protomaps.com/20260714.pmtiles",
                "maxzoom": 14,
                "pack_granularity": "subregion",
                "size_budget_bytes": 500000000,
                "measured_archive_bytes": 223155574,
                "subregions": [{"id": "central", "bbox": [101.6, 3.0, 101.8, 3.2]}],
            },
        },
        "uk": {
            "schema_version": 1,
            "region_id": "uk",
            "display_name": "United Kingdom",
            "bbox": [-8.65, 49.84, 1.77, 60.86],
            "languages": ["en"],
            "sources": {"wikidata": True},
            "basemap": {
                "source_pmtiles": "https://build.protomaps.com/20260714.pmtiles",
                "maxzoom": 14,
                "pack_granularity": "subregion",
                "size_budget_bytes": 500000000,
                "measured_archive_bytes": 223155574,
                "subregions": [{"id": "central", "bbox": [-1.0, 51.0, 0.0, 52.0]}],
            },
        },
        "malaysia_central": {
            "schema_version": 1,
            "region_id": "malaysia_central",
            "display_name": "Central Malaysia",
            "bbox": [101.6, 3.0, 101.8, 3.2],
            "languages": ["en"],
            "sources": {"wikidata": True},
            "basemap": {
                "source_pmtiles": "https://build.protomaps.com/20260714.pmtiles",
                "maxzoom": 14,
                "pack_granularity": "country",
                "size_budget_bytes": 500000000,
                "measured_archive_bytes": 223155574,
            },
        },
    }
    monkeypatch.setattr(
        mt_contracts,
        "available_regions",
        lambda: ["malaysia", "malaysia_central", "uk"],
    )
    monkeypatch.setattr(mt_contracts, "load_region_config", lambda region: configs[region])

    with pytest.raises(config.ConfigError, match="malaysia_central"):
        config.assert_global_region_ids()


def test_malformed_config_raises_config_error(monkeypatch):
    import mt_contracts

    monkeypatch.setattr(mt_contracts, "available_regions", lambda: ["uk"])
    monkeypatch.setattr(mt_contracts, "load_region_config", lambda _r: {"region_id": "uk"})
    with pytest.raises(config.ConfigError):
        config.load("uk")
