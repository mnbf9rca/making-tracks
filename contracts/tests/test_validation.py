import json
import tomllib

from mt_contracts import validation


def test_schemas_are_packaged_with_wheel(contracts_root):
    pyproject = tomllib.loads((contracts_root / "pyproject.toml").read_text())
    force_include = pyproject["tool"]["hatch"]["build"]["targets"]["wheel"][
        "force-include"
    ]
    assert force_include["schemas"] == "src/mt_contracts/schemas"


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
