from mt_pipeline.score import signals as S


def test_article_zero_without_wp_saturates_with_length():
    assert S.article({"wp": None}) == 0.0
    assert 0 < S.article({"wp": {"extract": "x" * 100}}) < 1
    assert S.article({"wp": {"extract": "x" * 100000}}) == 1.0


def test_optional_signals_return_none_when_absent():
    assert S.pageviews({"pageviews": None}) is None
    assert S.llm_curiosity({}) is None
    assert S.image({"wd": {}}) == 0.0


def test_heritage_grade_table_exact():
    assert S.heritage({"hehle": {"grade": "I"}}) == 1.0
    assert S.heritage({"hehle": {"grade": "II*"}}) == 0.7
    assert S.heritage({"hehle": {"grade": "II"}}) == 0.5
    assert S.heritage({"hehle": {"grade": "???"}}) == 0.0
    assert S.heritage({}) == 0.0


def test_hostile_inputs_clamp_not_crash():
    assert S.sitelinks({"wd": {"sitelinks": 10**9}}) == 1.0
    assert S.sitelinks({"wd": {"sitelinks": -5}}) == 0.0
    assert S.pageviews({"pageviews": []}) is None
    assert S.pageviews({"pageviews": ["nan"]}) == 0.0
    assert S.llm_curiosity({"llm_curiosity": "nan"}) == 0.0


def test_class_penalty_defaults_to_no_penalty_and_clamps_config_values():
    assert S.class_penalty({}) == 1.0
    assert S.class_penalty({"wd": {"classes": ["Q-noisy"]}}, {"Q-noisy": 0.3}) == 0.3
    assert S.class_penalty({"wd": {"classes": ["Q-hostile"]}}, {"Q-hostile": -2}) == 0.0
