import random

from mt_pipeline.score import composite, rarity, signals, tiers


CFG = type(
    "Cfg",
    (),
    {
        "weights": {
            "article": 1.0,
            "sitelinks": 0.4,
            "heritage": 1.3,
            "plaque": 0.8,
            "image": 0.5,
            "tag_rarity": 1.0,
            "pageviews": 1.0,
            "llm_curiosity": 1.0,
        },
        "boost_weight": 0.2,
        "tiers": {"t1_min": 0.85, "t2_min": 0.65, "t3_min": 0.35},
    },
)()


def _without_fame_or_llm(values):
    return {**values, "pageviews": None, "llm_curiosity": None}


def _signals_from_place(raw, freq):
    tag_rarity = rarity.rarity_score(raw["tags"], freq)
    return _without_fame_or_llm(
        {
            "article": signals.article(raw),
            "sitelinks": signals.sitelinks(raw),
            "heritage": signals.heritage(raw),
            "plaque": signals.plaque(raw),
            "image": signals.image(raw),
            "tag_rarity": tag_rarity,
            "class_penalty": signals.class_penalty(raw),
        }
    )


def test_malaysia_non_llm_floor_discriminates_known_places_from_noise():
    known_raw = [
        {
            "wp": {"extract": "x" * 240},
            "wd": {"sitelinks": 4, "image": "temple.jpg"},
            "hehle": {"grade": "I"},
            "tags": {"historic": "temple", "tourism": "attraction"},
        },
        {
            "wp": {"extract": "x" * 75},
            "wd": {"sitelinks": 1},
            "hehle": {"grade": "II*"},
            "tags": {"historic": "shophouse", "building": "terrace"},
        },
    ]
    noise_raw = [
        {
            "wd": {"sitelinks": 0},
            "tags": {"amenity": "bench"},
        },
        {
            "wd": {"classes": ["Q-noisy"]},
            "tags": {"name": "Unique Unremarkable Node"},
        },
    ]
    corpus_tags = [
        place.get("tags", {})
        for place in [
            *known_raw,
            *noise_raw,
            {"tags": {"amenity": "bench"}},
            {"tags": {"amenity": "bench"}},
        ]
    ]
    freq = rarity.tag_value_frequency_from_tagsets(corpus_tags)
    known_interesting = [_signals_from_place(place, freq) for place in known_raw]
    noise = [_signals_from_place(place, freq) for place in noise_raw]

    known_scores = [composite.score(values, CFG) for values in known_interesting]
    noise_scores = [composite.score(values, CFG) for values in noise]

    assert min(known_scores) > max(noise_scores)


def test_composite_and_tier_are_stable_across_200_signal_order_shuffles():
    values = {
        "article": 0.6,
        "sitelinks": 0.2,
        "heritage": 0.7,
        "plaque": 0.0,
        "image": 1.0,
        "tag_rarity": 0.5,
        "pageviews": None,
        "llm_curiosity": None,
        "class_penalty": 1.0,
    }
    expected = (composite.score(values, CFG), tiers.tier_for(composite.score(values, CFG), CFG))
    items = list(values.items())
    rng = random.Random(20260715)

    for _ in range(200):
        rng.shuffle(items)
        shuffled = dict(items)
        actual_score = composite.score(shuffled, CFG)
        assert (actual_score, tiers.tier_for(actual_score, CFG)) == expected
