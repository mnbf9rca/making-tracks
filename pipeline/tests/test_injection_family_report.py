import importlib.util
import json

from mt_pipeline.llm import bakeoff
from mt_pipeline.llm import cache as llm_cache
from mt_pipeline.llm import curiosity


SCRIPT_PATH = llm_cache.PROJECT_ROOT / "scripts" / "injection_family_report.py"


def _load_report_module():
    spec = importlib.util.spec_from_file_location("injection_family_report", SCRIPT_PATH)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def _put_probe(cache_dir, *, cache_model_id: str, probe: bakeoff.InjectionProbe, curiosity_value: float) -> None:
    cache = llm_cache.LlmCache(
        cache_dir,
        validators={curiosity.CURIOSITY_TASK_ID: lambda blob: curiosity.parse_curiosity(json.dumps(blob))},
    )
    rendered = curiosity.render_prompt(probe.place)
    input_hash = llm_cache.input_hash(
        task_id=curiosity.CURIOSITY_TASK_ID,
        prompt_version=curiosity.CURIOSITY_PROMPT_VERSION,
        rendered_prompt=rendered,
    )
    cache.put(
        llm_cache.cache_key(
            curiosity.CURIOSITY_TASK_ID,
            cache_model_id,
            curiosity.CURIOSITY_PROMPT_VERSION,
            input_hash,
        ),
        {"curiosity": curiosity_value},
    )


def test_injection_family_report_counts_cached_family_resistance(tmp_path):
    report = _load_report_module()
    fixture = (
        bakeoff.InjectionProbe(
            place_id="probe-a",
            origin_place_id="mt1_00000000000000000000000000",
            family="inflation_test",
            direction="inflation",
            field="extract",
            honest=0.0,
            honest_percentile=0.0,
            place={"name": "A", "summary": "a", "tags": ["c"]},
        ),
        bakeoff.InjectionProbe(
            place_id="probe-b",
            origin_place_id="mt1_00000000000000000000000000",
            family="inflation_test",
            direction="inflation",
            field="extract",
            honest=0.0,
            honest_percentile=0.0,
            place={"name": "B", "summary": "b", "tags": ["c"]},
        ),
    )
    _put_probe(tmp_path, cache_model_id="model-a", probe=fixture[0], curiosity_value=0.0)
    _put_probe(tmp_path, cache_model_id="model-a", probe=fixture[1], curiosity_value=1.0)

    rows = report.family_report_rows(
        tmp_path,
        [{"id": "model-a", "provider": "nous", "api_model_id": "provider/model-a"}],
        fixture=fixture,
    )

    assert rows == [
        report.FamilyRow(
            model="model-a",
            family="inflation_test",
            probes=2,
            resisted=1,
            resistance=0.5,
        )
    ]


def test_injection_family_report_reads_legacy_provider_model_cache_keys(tmp_path):
    report = _load_report_module()
    probe = bakeoff.InjectionProbe(
        place_id="probe-a",
        origin_place_id="mt1_00000000000000000000000000",
        family="inflation_test",
        direction="inflation",
        field="extract",
        honest=0.0,
        honest_percentile=0.0,
        place={"name": "A", "summary": "a", "tags": ["c"]},
    )
    _put_probe(tmp_path, cache_model_id="provider/model-a", probe=probe, curiosity_value=0.0)

    rows = report.family_report_rows(
        tmp_path,
        [{"id": "model-a", "provider": "nous", "api_model_id": "provider/model-a"}],
        fixture=(probe,),
    )

    assert rows[0].model == "model-a"
    assert rows[0].probes == 1
    assert rows[0].resisted == 1
