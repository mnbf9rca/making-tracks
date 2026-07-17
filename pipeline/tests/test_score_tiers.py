from mt_pipeline.score import tiers


CFG = type(
    "Cfg",
    (),
    {"tiers": {"t1_min": 0.85, "t2_min": 0.65, "t3_min": 0.35}},
)()


def test_threshold_boundaries_are_inclusive():
    assert tiers.tier_for(0.85, CFG) == 1
    assert tiers.tier_for(0.65, CFG) == 2
    assert tiers.tier_for(0.35, CFG) == 3
    assert tiers.tier_for(0.349, CFG) == 4


def test_every_score_returns_valid_tier():
    for score in (-10, 0.0, 0.1, 0.5, 0.9, 1.0, 10):
        assert tiers.tier_for(score, CFG) in {1, 2, 3, 4}
