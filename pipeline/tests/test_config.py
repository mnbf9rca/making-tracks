import pytest

from mt_pipeline import config


def test_load_known_region_returns_structurally_valid_config():
    cfg = config.load("united-kingdom")
    assert cfg.region_id == "united-kingdom"
    assert len(cfg.bbox) == 4
    assert cfg.languages
    assert isinstance(cfg.basemap.get("maxzoom"), int)
    assert cfg.raw["region_id"] == "united-kingdom"


def test_live_region_basemaps_have_retained_controlled_cut_pins():
    for region_id in ("united-kingdom", "malaysia-singapore-brunei"):
        cfg = config.load(region_id)
        basemap = cfg.basemap

        assert basemap["source_pmtiles"] == "https://build.protomaps.com/20260714.pmtiles"
        assert basemap["retained_cut_pmtiles"].startswith(
            f"https://tiles.making-tracks.app/{region_id}/"
        )
        assert basemap["retained_cut_pmtiles"].endswith(f"/{region_id}.pmtiles")
        assert len(basemap["retained_cut_sha256"]) == 64


def test_region_id_is_carried_through_not_hardcoded():
    assert config.load("malaysia-singapore-brunei").region_id == "malaysia-singapore-brunei"


def test_legacy_region_ids_are_unknown():
    for legacy in ("uk", "malaysia"):
        with pytest.raises(config.UnknownRegionError):
            config.load(legacy)


def test_unknown_region_raises_naming_available():
    with pytest.raises(config.UnknownRegionError) as exc:
        config.load("atlantis")
    assert "united-kingdom" in str(exc.value)


def test_load_delegates_validation_to_contracts(monkeypatch):
    import mt_contracts

    called = {}
    real = mt_contracts.load_region_config

    def spy(region_id):
        called["region"] = region_id
        return real(region_id)

    monkeypatch.setattr(mt_contracts, "load_region_config", spy)
    config.load("malaysia-singapore-brunei")
    assert called["region"] == "malaysia-singapore-brunei"


def test_region_config_exposes_dormant_basemap_subregions(monkeypatch):
    import mt_contracts

    monkeypatch.setattr(mt_contracts, "available_regions", lambda: ["malaysia-singapore-brunei"])
    monkeypatch.setattr(
        mt_contracts,
        "load_region_config",
        lambda _r: {
            "schema_version": 1,
            "region_id": "malaysia-singapore-brunei",
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

    cfg = config.load("malaysia-singapore-brunei")

    assert len(cfg.subregions) == 1
    assert cfg.subregions[0].id == "central"
    assert cfg.subregions[0].region_id == "malaysia-singapore-brunei_central"
    assert cfg.subregions[0].display_name == "Central Malaysia"
    assert cfg.subregions[0].bbox == (101.6, 3.0, 101.8, 3.2)
    assert cfg.subregions[0].measured_archive_bytes == 12345


def test_region_config_rejects_subregion_id_that_collides_with_known_region(monkeypatch):
    import mt_contracts

    monkeypatch.setattr(
        mt_contracts,
        "available_regions",
        lambda: ["malaysia-singapore-brunei", "malaysia-singapore-brunei_central"],
    )
    monkeypatch.setattr(
        mt_contracts,
        "load_region_config",
        lambda _r: {
            "schema_version": 1,
            "region_id": "malaysia-singapore-brunei",
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
        config.load("malaysia-singapore-brunei")


def test_region_config_rejects_invalid_subregion_bbox_before_publish(monkeypatch):
    import mt_contracts

    monkeypatch.setattr(mt_contracts, "available_regions", lambda: ["malaysia-singapore-brunei"])
    monkeypatch.setattr(
        mt_contracts,
        "load_region_config",
        lambda _r: {
            "schema_version": 1,
            "region_id": "malaysia-singapore-brunei",
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
        config.load("malaysia-singapore-brunei")


def test_global_region_id_assert_rejects_top_level_subregion_collision(monkeypatch):
    import mt_contracts

    configs = {
        "malaysia-singapore-brunei": {
            "schema_version": 1,
            "region_id": "malaysia-singapore-brunei",
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
        "united-kingdom": {
            "schema_version": 1,
            "region_id": "united-kingdom",
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
        "malaysia-singapore-brunei_central": {
            "schema_version": 1,
            "region_id": "malaysia-singapore-brunei_central",
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
        lambda: ["malaysia-singapore-brunei", "malaysia-singapore-brunei_central", "united-kingdom"],
    )
    monkeypatch.setattr(mt_contracts, "load_region_config", lambda region: configs[region])

    with pytest.raises(config.ConfigError, match="malaysia-singapore-brunei_central"):
        config.assert_global_region_ids()


def test_malformed_config_raises_config_error(monkeypatch):
    import mt_contracts

    monkeypatch.setattr(mt_contracts, "available_regions", lambda: ["united-kingdom"])
    monkeypatch.setattr(
        mt_contracts, "load_region_config", lambda _r: {"region_id": "united-kingdom"}
    )
    with pytest.raises(config.ConfigError):
        config.load("united-kingdom")
