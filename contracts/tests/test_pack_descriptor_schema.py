from mt_contracts.validation import is_valid, validate_instance


def _valid_pack_descriptor():
    return {
        "schema_version": 1,
        "min_reader_version": 1,
        "region": "united-kingdom",
        "publish_version": "20260718T090000Z",
        "generated_at": "2026-07-18T09:00:00Z",
        "objects": [
            {
                "kind": "description_index",
                "path": "descriptions/10/509/340.json",
                "sha256": "0" * 64,
                "bytes": 512,
                "schema_version": 1,
                "optional": False,
            },
            {
                "kind": "image_thumb",
                "path": "thumbs/aa/" + ("a" * 64) + ".webp",
                "sha256": "a" * 64,
                "bytes": 12345,
                "schema_version": 1,
                "optional": True,
            },
            {
                "kind": "search_index",
                "path": "search/full/ke.json",
                "sha256": "b" * 64,
                "bytes": 2345,
                "schema_version": 1,
                "optional": False,
            },
        ],
    }


def test_pack_descriptor_contract_lists_non_manifest_pack_objects():
    validate_instance("pack-descriptor", _valid_pack_descriptor())


def test_pack_descriptor_rejects_traversal_paths():
    inst = _valid_pack_descriptor()
    inst["objects"][0]["path"] = "../descriptions/10/509/340.json"
    assert not is_valid("pack-descriptor", inst)


def test_pack_descriptor_rejects_unknown_object_kind():
    inst = _valid_pack_descriptor()
    inst["objects"][0]["kind"] = "mystery"
    assert not is_valid("pack-descriptor", inst)


def test_pack_descriptor_rejects_path_that_does_not_match_kind():
    inst = _valid_pack_descriptor()
    inst["objects"][0]["path"] = "thumbs/ab/" + ("a" * 64) + ".webp"
    assert not is_valid("pack-descriptor", inst)


def test_pack_descriptor_rejects_thumb_path_not_matching_sha():
    inst = _valid_pack_descriptor()
    inst["objects"][1]["path"] = "thumbs/ab/" + ("b" * 64) + ".webp"
    assert not is_valid("pack-descriptor", inst)


def test_pack_descriptor_rejects_required_kind_marked_optional():
    inst = _valid_pack_descriptor()
    inst["objects"][0]["optional"] = True
    assert not is_valid("pack-descriptor", inst)
