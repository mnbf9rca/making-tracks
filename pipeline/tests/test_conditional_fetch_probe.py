from mt_pipeline import conditional_fetch_probe as probe


def test_classifies_validator_strength():
    assert probe.etag_strength(None) == "missing"
    assert probe.etag_strength("") == "missing"
    assert probe.etag_strength('"abc"') == "strong"
    assert probe.etag_strength('W/"abc"') == "weak"
    assert probe.etag_strength("not-an-http-etag") == "malformed"


def test_builds_conditional_headers_from_observed_validators():
    observed = probe.FetchObservation(
        status=200,
        etag='"abc"',
        last_modified="Tue, 21 Jul 2026 12:00:00 GMT",
        sha256="0" * 64,
        bytes_read=12,
    )

    assert probe.conditional_headers(observed) == {
        "If-None-Match": '"abc"',
        "If-Modified-Since": "Tue, 21 Jul 2026 12:00:00 GMT",
    }


def test_summarizes_304_as_bandwidth_optimization_not_correctness():
    initial = probe.FetchObservation(status=200, etag='"abc"', sha256="a" * 64, bytes_read=12)
    followup = probe.FetchObservation(status=304, etag='"abc"', sha256=None, bytes_read=0)

    result = probe.summarize_pair(initial, followup)

    assert result.outcome == "not_modified"
    assert result.hash_verdict == "not_rechecked_304"


def test_summarizes_200_followup_by_content_hash():
    initial = probe.FetchObservation(status=200, etag='"abc"', sha256="a" * 64, bytes_read=12)

    unchanged = probe.summarize_pair(
        initial,
        probe.FetchObservation(status=200, etag='"abc"', sha256="a" * 64, bytes_read=12),
    )
    changed = probe.summarize_pair(
        initial,
        probe.FetchObservation(status=200, etag='"def"', sha256="b" * 64, bytes_read=12),
    )

    assert unchanged.outcome == "ok"
    assert unchanged.hash_verdict == "unchanged"
    assert changed.outcome == "ok"
    assert changed.hash_verdict == "changed"


def test_default_probe_inventory_covers_required_upstream_classes():
    classes = {item.upstream_class for item in probe.default_probes()}

    assert classes == {
        "commons_api_metadata",
        "commons_image_file",
        "wikipedia_api",
        "wikidata_entity_data",
        "data_gov_sg_api",
        "arcgis_rest",
        "protomaps_build",
        "r2_cdn_catalog",
    }


def test_probe_request_headers_are_bounded_and_descriptive():
    item = probe.ProbeTarget(
        upstream_class="protomaps_build",
        label="configured build prefix",
        url="https://build.protomaps.com/20260714.pmtiles",
        expected_hosts=("build.protomaps.com",),
        accept="application/octet-stream",
        range_header="bytes=0-65535",
    )

    headers = probe.request_headers(item)

    assert headers["User-Agent"].startswith("MakingTracksBot/")
    assert headers["Range"] == "bytes=0-65535"
    assert headers["Accept"] == "application/octet-stream"
