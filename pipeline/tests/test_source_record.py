import inspect

import pytest

from mt_pipeline import source_record as sr
from mt_pipeline import store


def _ok(**over):
    kwargs = dict(
        region="uk",
        source="wd",
        source_ref="wd:Q42",
        name="Big Ben",
        lat=51.5,
        lon=-0.12,
        props={"k": "v"},
    )
    kwargs.update(over)
    return sr.parse(**kwargs)


def test_parse_accepts_valid_record():
    record = _ok()
    assert record.source_ref == "wd:Q42"
    assert record.name == "Big Ben"


def test_parse_defers_ref_grammar_to_contracts(monkeypatch):
    import mt_contracts

    monkeypatch.setattr(mt_contracts, "is_canonical_ref", lambda _s: False)
    with pytest.raises(sr.SourceRecordError):
        _ok(source_ref="wd:Q42")


def test_parse_source_prefix_must_match():
    with pytest.raises(sr.SourceRecordError):
        _ok(source="osm", source_ref="wd:Q42")


def test_parse_source_ref_length_capped():
    with pytest.raises(sr.SourceRecordError):
        _ok(source_ref="wd:Q" + "9" * sr.SOURCE_REF_MAX)


@pytest.mark.parametrize("lat,lon", [(91, 0), (-91, 0), (0, 181), (0, -181)])
def test_parse_bounds_coordinates_all_directions(lat, lon):
    with pytest.raises(sr.SourceRecordError):
        _ok(lat=lat, lon=lon)


def test_parse_accepts_boundary_coordinates():
    assert _ok(lat=90, lon=180)
    assert _ok(lat=-90, lon=-180)


def test_parse_rejects_nonfinite_coordinates():
    with pytest.raises(sr.SourceRecordError):
        _ok(lat=float("nan"))


def test_parse_delegates_text_cleaning_to_contracts(monkeypatch):
    import mt_contracts

    monkeypatch.setattr(mt_contracts, "strip_unsafe_text", lambda s: s.replace("Z", ""))
    assert _ok(name="BigZ Ben").name == "Big Ben"


def test_parse_caps_name_length():
    assert len(_ok(name="x" * 5000).name) <= sr.NAME_MAX


def test_parse_rejects_oversize_raw_name():
    with pytest.raises(sr.SourceRecordError):
        _ok(name="x" * (sr.RAW_TEXT_MAX + 1))


def test_parse_rejects_empty_or_whitespace_name():
    for bad in ["   ", "\t\n"]:
        with pytest.raises(sr.SourceRecordError):
            _ok(name=bad)


def test_props_must_be_dict():
    with pytest.raises(sr.SourceRecordError):
        _ok(props=["not", "a", "dict"])


def test_props_bounds_depth_and_count():
    deep = cur = {}
    for _ in range(sr.PROPS_MAX_DEPTH + 2):
        cur["x"] = {}
        cur = cur["x"]
    with pytest.raises(sr.SourceRecordError):
        _ok(props=deep)
    with pytest.raises(sr.SourceRecordError):
        _ok(props={f"k{i}": 1 for i in range(sr.PROPS_MAX_ITEMS + 1)})


def test_props_rejects_nonstring_keys_and_nonfinite_and_bad_types():
    with pytest.raises(sr.SourceRecordError):
        _ok(props={1: "v"})
    with pytest.raises(sr.SourceRecordError):
        _ok(props={"x": float("inf")})
    with pytest.raises(sr.SourceRecordError):
        _ok(props={"x": b"bytes"})


def test_props_allows_supported_scalar_types():
    props = {
        "none": None,
        "bool": True,
        "int": 123,
        "float": 1.5,
        "nested": [None, False, 0, 2.5, {"ok": True}],
    }

    assert _ok(props=props).props == props


def test_props_string_values_are_cleaned(monkeypatch):
    import mt_contracts

    monkeypatch.setattr(mt_contracts, "strip_unsafe_text", lambda s: s.replace("Z", ""))
    record = _ok(props={"desc": "aZb", "nested": {"t": "cZd"}})
    assert record.props["desc"] == "ab"
    assert record.props["nested"]["t"] == "cd"


def test_props_keys_and_list_strings_are_cleaned(monkeypatch):
    import mt_contracts

    monkeypatch.setattr(mt_contracts, "strip_unsafe_text", lambda s: s.replace("Z", ""))
    record = _ok(props={"keZy": ["aZb"]})
    assert record.props == {"key": ["ab"]}


def test_props_rejects_empty_or_duplicate_cleaned_keys(monkeypatch):
    import mt_contracts

    monkeypatch.setattr(mt_contracts, "strip_unsafe_text", lambda s: s.replace("Z", ""))
    with pytest.raises(sr.SourceRecordError, match="empty"):
        _ok(props={"ZZ": "v"})
    with pytest.raises(sr.SourceRecordError, match="duplicate"):
        _ok(props={"aZ": 1, "a": 2})


def test_props_serialized_size_is_capped(monkeypatch):
    monkeypatch.setattr(sr, "PROPS_JSON_MAX", 24)
    with pytest.raises(sr.SourceRecordError, match="too large"):
        _ok(props={"desc": "x" * 40})


def test_props_total_node_budget_is_capped(monkeypatch):
    monkeypatch.setattr(sr, "PROPS_MAX_ITEMS", 4)
    props = {f"k{i}": [1, 2, 3] for i in range(4)}
    with pytest.raises(sr.SourceRecordError, match="too large"):
        _ok(props=props)


def test_record_owns_props_not_caller_alias():
    source_props = {"k": "v"}
    record = _ok(props=source_props)
    source_props["k"] = "MUTATED"
    assert record.props["k"] == "v"


def test_run_id_is_not_a_parse_parameter_and_not_a_field():
    assert "run_id" not in inspect.signature(sr.parse).parameters
    assert "run_id" not in sr.SourceRecord.__dataclass_fields__


def test_injection_hostile_name_through_production_persist(tmp_path):
    conn = store.connect(tmp_path / "w.db")
    store.init_schema(conn)
    record = sr.parse(
        region="uk",
        source="wd",
        source_ref="wd:Q42",
        name="Robert'); DROP TABLE source_records;--",
        lat=51.5,
        lon=-0.1,
        props={},
    )
    sr.persist(conn, record, run_id="r1")
    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert store.SOURCE_RECORDS_TABLE in tables
    row = conn.execute(f"SELECT name FROM {store.SOURCE_RECORDS_TABLE}").fetchone()
    assert row[0].startswith("Robert')")
