from mt_contracts.validation import is_valid, validate_instance


def _valid_zone_catalog():
    return {
        "schema_version": 1,
        "min_reader_version": 1,
        "region": "uk",
        "publish_version": "20260718T090000Z",
        "generated_at": "2026-07-18T09:00:00Z",
        "tile_z": 10,
        "zones": [
            {
                "zone_id": "osm_r100",
                "parent": None,
                "admin_level": 2,
                "level_name": "country",
                "name": "United Kingdom",
                "name_translations": {"en": "United Kingdom"},
                "wikidata": "Q145",
                "bbox": [-1.0, 51.0, 1.0, 52.0],
                "cell_set": {
                    "encoding": "ranges",
                    "ranges": [[509, 339, 340], [510, 339, 340]],
                    "cell_count": 4,
                },
                "bytes_without_thumbs": 1024,
                "bytes_with_thumbs": 2048,
                "publish_version": "20260718T090000Z",
                "version": 1,
            }
        ],
    }


def test_zone_catalog_contract_accepts_rle_cell_sets():
    validate_instance("zone-catalog", _valid_zone_catalog())


def test_zone_catalog_rejects_name_derived_or_out_of_bounds_ids():
    inst = _valid_zone_catalog()
    inst["zones"][0]["zone_id"] = "London"
    assert not is_valid("zone-catalog", inst)


def test_zone_catalog_rejects_unbounded_cell_coordinates():
    inst = _valid_zone_catalog()
    inst["zones"][0]["cell_set"]["ranges"] = [[1024, 0, 0]]
    assert not is_valid("zone-catalog", inst)


def test_zone_catalog_rejects_duplicate_zone_ids():
    inst = _valid_zone_catalog()
    inst["zones"].append(dict(inst["zones"][0]))
    assert not is_valid("zone-catalog", inst)


def test_zone_catalog_rejects_missing_parent_reference():
    inst = _valid_zone_catalog()
    inst["zones"].append(
        {
            **dict(inst["zones"][0]),
            "zone_id": "osm_r200",
            "parent": "osm_r999",
        }
    )
    assert not is_valid("zone-catalog", inst)


def test_zone_catalog_rejects_reversed_cell_ranges():
    inst = _valid_zone_catalog()
    inst["zones"][0]["cell_set"]["ranges"] = [[509, 340, 339]]
    assert not is_valid("zone-catalog", inst)


def test_zone_catalog_rejects_wrong_cell_count():
    inst = _valid_zone_catalog()
    inst["zones"][0]["cell_set"]["cell_count"] = 3
    assert not is_valid("zone-catalog", inst)


def test_zone_catalog_rejects_parent_admin_level_inversion():
    inst = _valid_zone_catalog()
    inst["zones"].append(
        {
            **dict(inst["zones"][0]),
            "zone_id": "osm_r200",
            "parent": "osm_r100",
            "admin_level": 2,
        }
    )
    assert not is_valid("zone-catalog", inst)


def test_zone_catalog_rejects_parent_cycles():
    inst = _valid_zone_catalog()
    inst["zones"] = [
        {**dict(inst["zones"][0]), "zone_id": "osm_r100", "parent": "osm_r200", "admin_level": 2},
        {**dict(inst["zones"][0]), "zone_id": "osm_r200", "parent": "osm_r100", "admin_level": 4},
    ]
    assert not is_valid("zone-catalog", inst)
