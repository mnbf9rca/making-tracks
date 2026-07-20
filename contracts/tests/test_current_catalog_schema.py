from mt_contracts.validation import is_valid, validate_instance
from mt_contracts.versions import SCHEMA_VERSIONS


def _valid_catalog():
    return {
        "schema_version": SCHEMA_VERSIONS["current_catalog"],
        "publish_versions": {
            "malaysia-singapore-brunei": "20260719T125813Z",
            "united-kingdom": "20260718T120000Z",
        },
    }


def test_current_catalog_schema_version_matches_registry():
    inst = _valid_catalog()
    validate_instance("current-catalog", inst)
    inst["schema_version"] = SCHEMA_VERSIONS["current_catalog"] + 1
    assert not is_valid("current-catalog", inst)


def test_current_catalog_rejects_bad_region_or_publish_version():
    inst = _valid_catalog()
    inst["publish_versions"]["Catalog"] = "20260719T125813Z"
    assert not is_valid("current-catalog", inst)

    inst = _valid_catalog()
    inst["publish_versions"]["united-kingdom"] = "latest"
    assert not is_valid("current-catalog", inst)


def test_current_catalog_rejects_empty_or_extra_fields():
    inst = _valid_catalog()
    inst["publish_versions"] = {}
    assert not is_valid("current-catalog", inst)

    inst = _valid_catalog()
    inst["extra"] = True
    assert not is_valid("current-catalog", inst)
