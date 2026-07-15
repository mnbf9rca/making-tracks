def test_pipeline_and_contracts_import_with_a1_surface():
    import mt_pipeline
    import mt_contracts

    assert mt_pipeline is not None
    for name in (
        "is_canonical_ref",
        "strip_unsafe_text",
        "load_region_config",
        "available_regions",
    ):
        assert hasattr(mt_contracts, name), f"A0 must export {name}"
