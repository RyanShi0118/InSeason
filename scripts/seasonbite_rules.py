"""Checks a meal plan against the JSON Schema and the SeasonBite rules.

The same rules live in Swift in SeasonBiteKit/Sources/SeasonBiteKit/MealPlanRules.swift.
Keep the two in step.
"""
import json
from functools import lru_cache
from pathlib import Path

from jsonschema import Draft202012Validator

REPO_ROOT = Path(__file__).resolve().parents[1]
SCHEMA_PATH = REPO_ROOT / "schema" / "meal_plan.schema.json"

GOLDEN_PLATE_TARGET = {"veg_tuber_pct": 50, "protein_pct": 25, "complex_carb_pct": 25}
GOLDEN_PLATE_TOLERANCE = 5


@lru_cache(maxsize=1)
def _validator():
    schema = json.loads(SCHEMA_PATH.read_text())
    return Draft202012Validator(schema, format_checker=Draft202012Validator.FORMAT_CHECKER)


def child_sodium_cap_mg(age_years):
    """Sodium cap for the whole meal, by child age. None above age 8."""
    if age_years < 4:
        return 300
    if age_years < 9:
        return 500
    return None


def schema_errors(plan):
    return [
        f"{'/'.join(map(str, e.absolute_path)) or '<root>'}: {e.message}"
        for e in _validator().iter_errors(plan)
    ]


def dish_rule_errors(dish):
    errors = []
    dish_id = dish["id"]
    steps = dish["steps"]

    if [s["n"] for s in steps] != list(range(1, len(steps) + 1)):
        errors.append(f"{dish_id}: steps must be numbered 1 to {len(steps)}")

    prep = dish["dual_prep"]
    has_heat = any(i["role"] == "adult_heat" for i in dish["ingredients"])
    if dish["flavor_pillar"] == "mild_sichuan_hunan" and not prep["applies"]:
        errors.append(f"{dish_id}: mild Sichuan-Hunan dishes must use dual-prep")
    if has_heat and not prep["applies"]:
        errors.append(f"{dish_id}: has adult-only heat but dual-prep is off")
    if not prep["applies"]:
        return errors

    split = prep.get("split_point")
    by_n = {s["n"]: s for s in steps}
    if split not in by_n or by_n[split]["portion"] != "child_only":
        errors.append(f"{dish_id}: split point {split} must be a child-only step")
        return errors
    for s in steps:
        if s["portion"] == "adult_only" and s["n"] <= split:
            errors.append(f"{dish_id}: adult-only step {s['n']} comes before the child portion is plated")
        if s["portion"] == "shared" and s["n"] > split:
            errors.append(f"{dish_id}: shared step {s['n']} comes after the child portion is plated")
    return errors


def rule_errors(plan):
    """Checks the schema cannot express. Assumes the plan already matches the schema."""
    errors = []

    plate = plan["golden_plate"]
    for key, goal in GOLDEN_PLATE_TARGET.items():
        if abs(plate[key] - goal) > GOLDEN_PLATE_TOLERANCE:
            errors.append(f"golden_plate.{key} is {plate[key]}, target {goal} ± {GOLDEN_PLATE_TOLERANCE}")
    total = sum(plate.values())
    if abs(total - 100) > 1:
        errors.append(f"golden_plate adds up to {total}, not 100")

    for dish in plan["dishes"]:
        errors += dish_rule_errors(dish)

    child_sodium = sum(d["child_safety"]["sodium_mg_per_child_serving"] for d in plan["dishes"])
    for child in plan["household"]["children"]:
        cap = child_sodium_cap_mg(child["age_years"])
        if cap is not None and child_sodium > cap:
            errors.append(f"child sodium {child_sodium} mg exceeds {cap} mg for age {child['age_years']}")

    dish_ids = {d["id"] for d in plan["dishes"]}
    for nutrient, ids in plan["nutrition"]["child_micronutrient_sources"].items():
        for i in ids:
            if i not in dish_ids:
                errors.append(f"child_micronutrient_sources.{nutrient} names unknown dish {i}")
    return errors


def validate_plan(plan):
    """All problems with a plan, schema first. Empty list means it is good to show."""
    errors = schema_errors(plan)
    if errors:
        return errors
    return rule_errors(plan)
