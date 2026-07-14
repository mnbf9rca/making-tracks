import json
import tomllib
import zipfile

from hatchling.build import build_wheel

from mt_contracts import validation


def test_schemas_are_packaged_with_wheel(contracts_root):
    pyproject = tomllib.loads((contracts_root / "pyproject.toml").read_text())
    force_include = pyproject["tool"]["hatch"]["build"]["targets"]["wheel"][
        "force-include"
    ]
    assert force_include["schemas"] == "src/mt_contracts/schemas"
    assert force_include["regions"] == "src/mt_contracts/regions"
    assert force_include["basemap-budget.json"] == "src/mt_contracts/basemap-budget.json"


def test_schema_loader_accepts_packaged_schema_dir(tmp_path, monkeypatch):
    packaged_schemas = tmp_path / "schemas"
    packaged_schemas.mkdir()
    (packaged_schemas / "example.schema.json").write_text(
        json.dumps(
            {
                "$schema": "https://json-schema.org/draft/2020-12/schema",
                "$id": "https://contracts.making-tracks.app/example/1",
                "type": "object",
            }
        )
    )
    monkeypatch.setattr(validation, "_PACKAGE_SCHEMA_DIR", packaged_schemas)
    monkeypatch.setattr(validation, "_ROOT_SCHEMA_DIR", tmp_path / "missing")
    validation.load_schema.cache_clear()
    validation._registry.cache_clear()
    try:
        assert validation.load_schema("example")["type"] == "object"
    finally:
        validation.load_schema.cache_clear()
        validation._registry.cache_clear()


def test_built_wheel_contains_machine_readable_contract_assets(
    contracts_root, tmp_path, monkeypatch
):
    monkeypatch.chdir(contracts_root)
    wheel_name = build_wheel(str(tmp_path))
    wheel = tmp_path / wheel_name
    with zipfile.ZipFile(wheel) as zf:
        names = set(zf.namelist())
    assert "mt_contracts/versions.json" in names
    assert "mt_contracts/schemas/place.schema.json" in names
    assert "mt_contracts/regions/uk.json" in names
    assert "mt_contracts/regions/malaysia.json" in names
    assert "mt_contracts/basemap-budget.json" in names
