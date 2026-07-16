import json

import pytest

from mt_pipeline.llm import cache as C
from mt_pipeline.llm.curiosity import parse_curiosity

VALIDATORS = {
    "curiosity": lambda blob: parse_curiosity(json.dumps(blob)),
    "blurb": lambda blob: (_ for _ in ()).throw(ValueError())
    if not isinstance(blob.get("text"), str)
    else blob,
}


def test_task_id_namespaces_the_key_no_silent_collision():
    assert C.cache_key("curiosity", "m", "v1", "hhh") != C.cache_key("blurb", "m", "v1", "hhh")


def test_cache_key_survives_a_slash_bearing_model_id():
    a = C.cache_key("curiosity", "meta-llama/llama-3.1-8b", "v1", "H")
    b = C.cache_key("curiosity", "meta-llama", "llama-3.1-8b/v1", "H")

    assert a != b


def test_cache_key_handles_real_openrouter_style_model_id():
    key = C.cache_key("curiosity", "meta-llama/llama-3.1-8b-instruct", "curiosity-v1", "H")

    assert key == "curiosity/meta-llama%2Fllama-3%2E1-8b-instruct/curiosity-v1/H"


def test_cache_key_encodes_dot_segments_to_prevent_path_traversal():
    key = C.cache_key("curiosity", "..", "v1", "H")

    assert ".." not in key.split("/")


def test_cache_key_rejects_empty_components():
    with pytest.raises(ValueError):
        C.cache_key("curiosity", "", "v1", "H")


def test_input_hash_boundary_is_injective():
    assert C.input_hash(task_id="cur", prompt_version="v1x", rendered_prompt="P") != C.input_hash(
        task_id="curv", prompt_version="1x", rendered_prompt="P"
    )
    assert C.input_hash(task_id="c", prompt_version="v", rendered_prompt="A") != C.input_hash(
        task_id="c", prompt_version="v", rendered_prompt="B"
    )


def test_read_validates_against_the_task_schema_not_just_any_json(tmp_path):
    llm_cache = C.LlmCache(tmp_path, validators=VALIDATORS)
    llm_cache.put(C.cache_key("curiosity", "m", "v1", "hhh"), {"text": "a nice blurb"})

    with pytest.raises(C.LlmCacheCorrupt):
        llm_cache.get("curiosity", "m", "v1", "hhh")


def test_read_rejects_json_bool_as_curiosity(tmp_path):
    llm_cache = C.LlmCache(tmp_path, validators=VALIDATORS)
    llm_cache.put(C.cache_key("curiosity", "m", "v1", "b"), {"curiosity": True})

    with pytest.raises(C.LlmCacheCorrupt):
        llm_cache.get("curiosity", "m", "v1", "b")


def test_unknown_task_id_is_fail_closed(tmp_path):
    llm_cache = C.LlmCache(tmp_path, validators=VALIDATORS)
    llm_cache.put(C.cache_key("mystery", "m", "v1", "x"), {"anything": 1})

    with pytest.raises(C.LlmCacheCorrupt):
        llm_cache.get("mystery", "m", "v1", "x")


def test_cache_miss_returns_none(tmp_path):
    llm_cache = C.LlmCache(tmp_path, validators=VALIDATORS)

    assert llm_cache.get("curiosity", "m", "v1", "missing") is None


def test_put_rejects_raw_traversal_key(tmp_path):
    llm_cache = C.LlmCache(tmp_path, validators=VALIDATORS)

    with pytest.raises(ValueError):
        llm_cache.put("../outside", {"curiosity": 0.5})


def test_task_id_matches_the_frozen_a0_enum():
    schema = json.loads((C.PROJECT_ROOT / "contracts/schemas/manifest.schema.json").read_text())
    enum = schema["properties"]["provenance"]["items"]["properties"]["task_id"]["enum"]

    assert C.CURIOSITY_TASK_ID in enum
