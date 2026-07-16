from mt_pipeline.publish import partition as P


def test_known_lonlat_maps_to_z10_tile():
    assert P.lonlat_to_z10(51.5074, -0.1278) == (511, 340)
    assert P.lonlat_to_z10(3.139, 101.6869) == (801, 503)


def test_extremes_clamp_into_range_not_out():
    for lat, lon in [(90, 180), (-90, -180), (85.06, 179.9), (-85.06, -179.9)]:
        x, y = P.lonlat_to_z10(lat, lon)
        assert 0 <= x <= 1023
        assert 0 <= y <= 1023


def test_partition_groups_deterministically():
    places = [
        {"place_id": "a", "lat": 51.5, "lon": -0.1},
        {"place_id": "b", "lat": 51.5, "lon": -0.1},
        {"place_id": "c", "lat": 3.1, "lon": 101.7},
    ]
    grouped = P.partition_places(places)
    assert len(grouped[P.lonlat_to_z10(51.5, -0.1)]) == 2
    assert len(grouped) == 2
