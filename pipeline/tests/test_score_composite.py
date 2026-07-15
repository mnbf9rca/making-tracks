import json
import pathlib

from mt_pipeline.score import ADDITIVE_SIGNAL_NAMES, SIGNAL_NAMES
from mt_pipeline.score import composite as C


CFG = type(
    "Cfg",
    (),
    {
        "weights": {
            "article": 1,
            "sitelinks": 1,
            "heritage": 1,
            "plaque": 1,
            "image": 1,
            "tag_rarity": 1,
            "pageviews": 1,
            "llm_curiosity": 1,
        },
        "boost_weight": 0.0,
    },
)()


def test_absent_signal_renormalizes_not_penalizes():
    values = {
        "article": None,
        "sitelinks": None,
        "heritage": 1.0,
        "plaque": None,
        "image": None,
        "tag_rarity": None,
        "pageviews": None,
        "llm_curiosity": None,
    }

    assert C.score(values, CFG) == 1.0


def test_llm_and_pageviews_off_still_scores_from_the_floor_signals():
    values = {
        "article": 0.8,
        "sitelinks": 0.2,
        "heritage": 1.0,
        "plaque": 0.0,
        "image": 1.0,
        "tag_rarity": 0.7,
        "pageviews": None,
        "llm_curiosity": None,
    }

    score = C.score(values, CFG)

    assert 0 < score <= 1


def test_class_penalty_multiplies_and_strictly_lowers():
    cfg = type("Cfg", (), {"weights": {"heritage": 1}, "boost_weight": 0.0})()
    clean = {"heritage": 1.0, "class_penalty": 1.0}
    penalized = {"heritage": 1.0, "class_penalty": 0.3}

    assert C.score(penalized, cfg) == 0.3 * C.score(clean, cfg) < C.score(clean, cfg)


def _cfg(boost_weight):
    return type(
        "Cfg",
        (),
        {
            "weights": {"pageviews": 1, "heritage": 1, "article": 1, "plaque": 1},
            "boost_weight": boost_weight,
        },
    )()


def test_fame_boost_changes_the_order_of_the_pair():
    oddity = {"pageviews": 0.0, "heritage": 0.6, "article": 0.6, "plaque": 0.0}
    generic = {"pageviews": 1.0, "heritage": 0.0, "article": 0.8, "plaque": 0.0}

    assert C.score(generic, _cfg(0.0)) > C.score(oddity, _cfg(0.0))
    assert C.score(oddity, _cfg(0.5)) > C.score(generic, _cfg(0.5))


def test_extreme_boost_clamps_to_one():
    cfg = type(
        "Cfg",
        (),
        {"weights": {"article": 1, "heritage": 1, "pageviews": 1}, "boost_weight": 9.0},
    )()

    assert C.score({"article": 1.0, "heritage": 1.0, "pageviews": 0.0}, cfg) == 1.0


def test_non_finite_inputs_are_clamped_out_of_the_composite():
    cfg = type("Cfg", (), {"weights": {"heritage": 1}, "boost_weight": 0.0})()

    assert C.score({"heritage": "nan"}, cfg) == 0.0
    assert C.score({"heritage": "inf"}, cfg) == 1.0
    assert C.score({"heritage": 1.0, "class_penalty": "nan"}, cfg) == 0.0


def test_scoring_json_shape_matches_signal_contract():
    cfg_path = pathlib.Path(__file__).parents[1] / "config" / "scoring.json"
    cfg = json.loads(cfg_path.read_text())

    assert cfg["version"]
    assert set(cfg["weights"]) == set(ADDITIVE_SIGNAL_NAMES)
    assert "class_penalty" not in cfg["weights"]
    assert set(SIGNAL_NAMES) == set(ADDITIVE_SIGNAL_NAMES) | {"class_penalty"}
    assert cfg["tiers"]["t1_min"] > cfg["tiers"]["t2_min"] > cfg["tiers"]["t3_min"]
    assert cfg["rarity_keys"]


def test_scoring_json_rarity_keys_match_module_default():
    from mt_pipeline.score import rarity

    cfg_path = pathlib.Path(__file__).parents[1] / "config" / "scoring.json"
    cfg = json.loads(cfg_path.read_text())

    assert set(cfg["rarity_keys"]) == set(rarity.RARITY_KEYS)
