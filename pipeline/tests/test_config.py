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


def test_malformed_config_raises_config_error(monkeypatch):
    import mt_contracts

    monkeypatch.setattr(mt_contracts, "available_regions", lambda: ["uk"])
    monkeypatch.setattr(mt_contracts, "load_region_config", lambda _r: {"region_id": "uk"})
    with pytest.raises(config.ConfigError):
        config.load("uk")
