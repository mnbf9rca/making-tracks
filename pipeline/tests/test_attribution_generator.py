import json
import pathlib

import jsonschema

from mt_pipeline.publish import credits


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]


def test_generated_sections_preserve_handwritten_text():
    original = "\n".join(
        [
            "# Attribution",
            "",
            "Handwritten opening.",
            "",
            credits.DATA_BEGIN,
            "stale data",
            credits.DATA_END,
            "",
            "Handwritten middle.",
            "",
            credits.OSS_BEGIN,
            "stale oss",
            credits.OSS_END,
            "",
            "Handwritten close.",
            "",
        ]
    )

    replaced = credits.replace_generated_section(
        original,
        credits.DATA_BEGIN,
        credits.DATA_END,
        "fresh data",
    )
    replaced = credits.replace_generated_section(
        replaced,
        credits.OSS_BEGIN,
        credits.OSS_END,
        "fresh oss",
    )

    assert "Handwritten opening." in replaced
    assert "Handwritten middle." in replaced
    assert "Handwritten close." in replaced
    assert "stale data" not in replaced
    assert "stale oss" not in replaced
    assert "fresh data" in replaced
    assert "fresh oss" in replaced


def test_generated_section_rejects_duplicate_missing_or_reversed_markers():
    original = "\n".join(
        [
            credits.DATA_END,
            credits.DATA_BEGIN,
            credits.DATA_BEGIN,
        ]
    )

    try:
        credits.replace_generated_section(
            original,
            credits.DATA_BEGIN,
            credits.DATA_END,
            "fresh",
        )
    except ValueError as exc:
        assert "expected exactly one marker" in str(exc)
    else:
        raise AssertionError("duplicate marker was accepted")

    try:
        credits.replace_generated_section("no markers", "BEGIN", "END", "fresh")
    except ValueError as exc:
        assert "expected exactly one marker" in str(exc)
    else:
        raise AssertionError("missing marker was accepted")

    try:
        credits.replace_generated_section("END\nBEGIN", "BEGIN", "END", "fresh")
    except ValueError as exc:
        assert "begin marker must precede end marker" in str(exc)
    else:
        raise AssertionError("reversed markers were accepted")


def test_data_source_section_uses_publish_attribution_path(monkeypatch):
    calls = []

    def fake_attribution_for(sources, a1d_sources, *, includes_osm_basemap=False):
        calls.append((set(sources), a1d_sources, includes_osm_basemap))
        return [
            {
                "source": "historic_england",
                "license": "OGL-UK-3.0",
                "text": "Historic England credit.",
            }
        ]

    monkeypatch.setattr(
        credits.publish_attribution,
        "attribution_for",
        fake_attribution_for,
    )

    section = credits.render_data_sources_markdown(
        {
            "historic_england": {
                "license": "OGL-UK-3.0",
                "attribution": "real credit",
            },
            "osm": {
                "license": "ODbL-1.0",
                "attribution": "OSM credit",
            },
        }
    )

    assert calls == [
        (
            {"historic_england", "osm"},
            {
                    "historic_england": {
                        "license": "OGL-UK-3.0",
                        "attribution": "real credit",
                    },
                "osm": {
                    "license": "ODbL-1.0",
                    "attribution": "OSM credit",
                },
            },
            True,
        )
    ]
    assert "| historic_england | OGL-UK-3.0 | Historic England credit. |" in section


def test_data_source_section_ignores_a1d_metadata_entries():
    section = credits.render_data_sources_markdown(
        {
            "_header": "human metadata",
            "osm": {
                "license": "ODbL-1.0",
                "attribution": "Map/place data credit.",
            },
        }
    )

    assert "_header" not in section
    assert "| osm | ODbL-1.0 | Map/place data credit. |" in section


def test_app_resource_filters_to_app_visible_credits_and_orders_by_name(tmp_path):
    notices = tmp_path / "contracts/third-party-notices"
    notices.mkdir(parents=True)
    (notices / "zed").write_text("Zed notice", encoding="utf-8")
    (notices / "alpha").write_text("Alpha notice", encoding="utf-8")
    registry = {
        "schema_version": 1,
        "credits": [
            {
                "name": "Zed App Dependency",
                "category": "ios_app",
                "version_or_pin": "2.0",
                "evidence": ["ios/Package.resolved"],
                "license_spdx": "MIT",
                "license_url": "https://example.test/zed",
                "compliance": "Include in app credits.",
                "notice_path": "contracts/third-party-notices/zed",
                "app_resource": True,
            },
            {
                "name": "Alpha Mirrored Asset",
                "category": "mirrored_asset",
                "version_or_pin": "commit abc",
                "evidence": ["https://tiles.example.test/OFL.txt"],
                "license_spdx": "OFL-1.1",
                "license_url": "https://example.test/ofl",
                "compliance": "Include in app credits.",
                "notice_path": "contracts/third-party-notices/alpha",
                "app_resource": True,
            },
        ],
    }

    resource = json.loads(credits.render_app_credits_json(registry, root=tmp_path))

    assert resource["schema_version"] == 1
    assert [credit["name"] for credit in resource["credits"]] == [
        "Alpha Mirrored Asset",
        "Zed App Dependency",
    ]
    assert all("notice_text" in credit for credit in resource["credits"])
    assert all("evidence" not in credit for credit in resource["credits"])
    assert all("compliance" not in credit for credit in resource["credits"])
    assert resource["credits"][0]["notice_text"] == "Alpha notice"
    assert {credit["category"] for credit in resource["credits"]} == {
        "ios_app",
        "mirrored_asset",
    }


def test_registry_schema_rejects_pipeline_build_entries():
    schema = json.loads(
        (REPO_ROOT / "contracts/schemas/oss-credits.schema.json").read_text()
    )
    bad_registry = {
        "schema_version": 1,
        "credits": [
            {
                "name": "Pipeline Tool",
                "category": "pipeline_build",
                "version_or_pin": "1.0",
                "evidence": ["pipeline/pyproject.toml"],
                "license_spdx": "MIT",
                "license_url": "https://example.test/license",
                "compliance": "Credit in root attribution.",
                "app_resource": False,
            }
        ],
    }

    validator = jsonschema.Draft202012Validator(schema)
    errors = list(validator.iter_errors(bad_registry))

    assert errors


def test_registry_schema_requires_every_credit_in_app_resource():
    schema = json.loads(
        (REPO_ROOT / "contracts/schemas/oss-credits.schema.json").read_text()
    )
    bad_registry = {
        "schema_version": 1,
        "credits": [
            {
                "name": "App Tool",
                "category": "ios_app",
                "version_or_pin": "1.0",
                "evidence": ["ios/Package.resolved"],
                "license_spdx": "MIT",
                "license_url": "https://example.test/license",
                "compliance": "Credit in app.",
                "notice_path": "contracts/third-party-notices/AppTool-LICENSE",
                "app_resource": False,
            }
        ],
    }

    validator = jsonschema.Draft202012Validator(schema)
    errors = list(validator.iter_errors(bad_registry))

    assert errors


def test_registry_schema_requires_valid_https_license_urls_for_app_credits():
    schema = json.loads(
        (REPO_ROOT / "contracts/schemas/oss-credits.schema.json").read_text()
    )
    validator = jsonschema.Draft202012Validator(
        schema,
        format_checker=jsonschema.Draft202012Validator.FORMAT_CHECKER,
    )

    for bad_url in ("http://example.test/license", "https://not a url", "https://"):
        bad_registry = {
            "schema_version": 1,
            "credits": [
                {
                    "name": "App Tool",
                    "category": "ios_app",
                    "version_or_pin": "1.0",
                    "evidence": ["ios/Package.resolved"],
                    "license_spdx": "MIT",
                    "license_url": bad_url,
                    "compliance": "Credit in app.",
                    "notice_path": "contracts/third-party-notices/AppTool-LICENSE",
                    "app_resource": True,
                }
            ],
        }

        errors = list(validator.iter_errors(bad_registry))

        assert errors


def test_stale_outputs_detects_missing_then_clean_then_mutated_outputs(tmp_path):
    _write_minimal_generation_inputs(tmp_path)

    stale = [path.relative_to(tmp_path) for path in credits.stale_outputs(tmp_path)]

    assert stale == [
        pathlib.Path("attribution.md"),
        pathlib.Path("ios/App/Sources/OSSCredits.json"),
    ]

    credits.write_outputs(tmp_path)
    assert credits.stale_outputs(tmp_path) == []

    (tmp_path / "ios/App/Sources/OSSCredits.json").write_text(
        "{}\n",
        encoding="utf-8",
    )
    stale = [path.relative_to(tmp_path) for path in credits.stale_outputs(tmp_path)]

    assert stale == [pathlib.Path("ios/App/Sources/OSSCredits.json")]


def _write_minimal_generation_inputs(root: pathlib.Path) -> None:
    (root / "pipeline/config").mkdir(parents=True)
    (root / "contracts/schemas").mkdir(parents=True)
    (root / "contracts/third-party-notices").mkdir(parents=True)
    (root / "attribution.md").write_text(
        "\n".join(
            [
                "# Attribution",
                "",
                credits.DATA_BEGIN,
                "stale",
                credits.DATA_END,
                "",
                credits.OSS_BEGIN,
                "stale",
                credits.OSS_END,
                "",
            ]
        ),
        encoding="utf-8",
    )
    (root / "pipeline/config/a1d_sources.json").write_text(
        json.dumps(
            {
                "osm": {
                    "license": "ODbL-1.0",
                    "attribution": "OSM credit.",
                }
            }
        ),
        encoding="utf-8",
    )
    (root / "contracts/schemas/oss-credits.schema.json").write_text(
        (REPO_ROOT / "contracts/schemas/oss-credits.schema.json").read_text(
            encoding="utf-8"
        ),
        encoding="utf-8",
    )
    (root / "contracts/third-party-notices/AppTool-LICENSE").write_text(
        "App Tool notice",
        encoding="utf-8",
    )
    (root / "contracts/oss-credits.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "credits": [
                    {
                        "name": "App Tool",
                        "category": "ios_app",
                        "version_or_pin": "1.0",
                        "evidence": ["ios/Package.resolved"],
                        "license_spdx": "MIT",
                        "license_url": "https://example.test/license",
                        "compliance": "Credit in app.",
                        "notice_path": "contracts/third-party-notices/AppTool-LICENSE",
                        "app_resource": True,
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
