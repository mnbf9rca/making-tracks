import copy

from mt_contracts.validation import is_valid, validate_instance


VALID_INDEX = {
    "schema_version": 1,
    "min_reader_version": 1,
    "z": 10,
    "x": 511,
    "y": 340,
    "places": [
        {
            "place_id": "mt1_00000000000000000000000001",
            "thumb_sha256": "a" * 64,
            "bytes": 12345,
            "width": 320,
            "height": 240,
            "attribution": {
                "creator": "Jane Example",
                "license_code": "CC-BY-SA-4.0",
                "license_name": "Creative Commons Attribution-Share Alike 4.0",
                "license_url": "https://creativecommons.org/licenses/by-sa/4.0/",
                "source_url": "https://commons.wikimedia.org/wiki/File:Fort.jpg",
                "modified": True,
            },
        }
    ],
}


def test_valid_image_index_passes():
    validate_instance("image-index", VALID_INDEX)


def test_image_index_accepts_shipped_crockford_place_id():
    inst = copy.deepcopy(VALID_INDEX)
    inst["places"][0]["place_id"] = "mt1_1Q831BXYQ8GP7ZXKVQZH87G0R5"

    validate_instance("image-index", inst)


def test_image_index_rejects_by_sa_without_creator():
    inst = copy.deepcopy(VALID_INDEX)
    inst["places"][0]["attribution"]["creator"] = None

    assert not is_valid("image-index", inst)


def test_image_index_allows_cc0_without_creator():
    inst = copy.deepcopy(VALID_INDEX)
    attr = inst["places"][0]["attribution"]
    attr["creator"] = None
    attr["license_code"] = "CC0-1.0"
    attr["license_name"] = "Creative Commons Zero 1.0"
    attr["license_url"] = "https://creativecommons.org/publicdomain/zero/1.0/"

    validate_instance("image-index", inst)


def test_image_index_allows_pd_mark_not_stale_commons_public_domain_url():
    inst = copy.deepcopy(VALID_INDEX)
    attr = inst["places"][0]["attribution"]
    attr["creator"] = None
    attr["license_code"] = "PD"
    attr["license_name"] = "Public domain"
    attr["license_url"] = "https://creativecommons.org/publicdomain/mark/1.0/"

    validate_instance("image-index", inst)

    attr["license_url"] = (
        "https://commons.wikimedia.org/wiki/Commons:Copyright_tags/General_public_domain"
    )
    assert not is_valid("image-index", inst)


def test_image_index_allows_exact_older_by_sa_version():
    inst = copy.deepcopy(VALID_INDEX)
    attr = inst["places"][0]["attribution"]
    attr["license_code"] = "CC-BY-SA-3.0"
    attr["license_name"] = "Creative Commons Attribution-Share Alike 3.0"
    attr["license_url"] = "https://creativecommons.org/licenses/by-sa/3.0/"

    validate_instance("image-index", inst)


def test_image_index_allows_ported_sharealike_license_code():
    inst = copy.deepcopy(VALID_INDEX)
    attr = inst["places"][0]["attribution"]
    attr["license_code"] = "CC-BY-SA-3.0-DE"
    attr["license_name"] = "Creative Commons Attribution-Share Alike 3.0 DE"
    attr["license_url"] = "https://creativecommons.org/licenses/by-sa/3.0/de/"

    validate_instance("image-index", inst)


def test_image_index_allows_igo_sharealike_license_code():
    inst = copy.deepcopy(VALID_INDEX)
    attr = inst["places"][0]["attribution"]
    attr["license_code"] = "CC-BY-SA-3.0-IGO"
    attr["license_name"] = "Creative Commons Attribution-Share Alike 3.0 IGO"
    attr["license_url"] = "https://creativecommons.org/licenses/by-sa/3.0/igo/"

    validate_instance("image-index", inst)


def test_image_index_rejects_noncommercial_license_code():
    inst = copy.deepcopy(VALID_INDEX)
    attr = inst["places"][0]["attribution"]
    attr["license_code"] = "CC-BY-NC-SA-4.0"
    attr["license_name"] = "Creative Commons Attribution-NonCommercial-ShareAlike 4.0"
    attr["license_url"] = "https://creativecommons.org/licenses/by-nc-sa/4.0/"

    assert not is_valid("image-index", inst)


def test_image_index_requires_modified_true_and_https_commons_source():
    inst = copy.deepcopy(VALID_INDEX)
    inst["places"][0]["attribution"]["modified"] = False
    assert not is_valid("image-index", inst)

    inst = copy.deepcopy(VALID_INDEX)
    inst["places"][0]["attribution"]["source_url"] = "https://example.com/File:Fort.jpg"
    assert not is_valid("image-index", inst)

    for bad_source_url in [
        "https://commons.wikimedia.org/wiki/File:../Fort.jpg",
        "https://commons.wikimedia.org/wiki/File:Fort.jpg?x=1",
        "https://commons.wikimedia.org/wiki/File:Fort.jpg#fragment",
        "https://commons.wikimedia.org/wiki/File:Folder/Fort.jpg",
    ]:
        inst = copy.deepcopy(VALID_INDEX)
        inst["places"][0]["attribution"]["source_url"] = bad_source_url
        assert not is_valid("image-index", inst)
