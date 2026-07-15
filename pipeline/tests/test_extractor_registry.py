from mt_pipeline import extractors


def test_enabled_for_returns_only_true_sources_in_registration_order():
    reg = extractors.Registry()
    reg.register("wikidata", object())
    reg.register("wikipedia", object())
    reg.register("osm", object())
    sources = {
        "wikidata": True,
        "wikipedia": True,
        "osm": False,
        "national_register": None,
    }
    assert [name for name, _ in reg.enabled_for(sources)] == ["wikidata", "wikipedia"]


def test_enabled_for_ignores_non_bool_and_unregistered():
    reg = extractors.Registry()
    reg.register("wikidata", object())
    sources = {
        "wikidata": True,
        "national_register": {"id": "x", "enabled": False},
        "osm": True,
    }
    assert [name for name, _ in reg.enabled_for(sources)] == ["wikidata"]
