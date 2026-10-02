import copy

from seasonbite_rules import validate_plan


def test_sample_passes(sample_plan):
    assert validate_plan(sample_plan) == []


def test_adult_heat_before_child_portion_is_rejected(broken_plan):
    errors = validate_plan(broken_plan)
    assert any("adult-only step 2 comes before" in e for e in errors), errors


def test_sichuan_hunan_without_dual_prep_is_rejected(sample_plan):
    plan = copy.deepcopy(sample_plan)
    tofu = next(d for d in plan["dishes"] if d["id"] == "golden_sour_tofu_caltrop")
    tofu["dual_prep"] = {"applies": False}
    errors = validate_plan(plan)
    assert errors  # the schema itself requires dual-prep for this pillar


def test_spicy_child_portion_is_rejected(sample_plan):
    plan = copy.deepcopy(sample_plan)
    plan["dishes"][0]["child_safety"]["non_spicy"] = False
    assert validate_plan(plan)


def test_child_sodium_cap_depends_on_age(sample_plan):
    plan = copy.deepcopy(sample_plan)
    plan["household"]["children"] = [{"age_years": 2}]
    errors = validate_plan(plan)
    assert any("exceeds 300" in e for e in errors), errors


def test_unknown_micronutrient_dish_is_rejected(sample_plan):
    plan = copy.deepcopy(sample_plan)
    plan["nutrition"]["child_micronutrient_sources"]["dha"] = ["no_such_dish"]
    errors = validate_plan(plan)
    assert any("unknown dish no_such_dish" in e for e in errors), errors
