#!/usr/bin/env python3
"""Validate SeasonBite meal plans against the schema and the dual-prep rule.

Usage: python3 scripts/validate_meal_plan.py [file.json ...]
With no arguments, validates every file in examples/.
"""
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = json.loads((ROOT / "schema" / "meal_plan.schema.json").read_text())


def rule_errors(plan):
    """Checks the schema cannot express."""
    errors = []
    dish_ids = {d["id"] for d in plan["dishes"]}
    for d in plan["dishes"]:
        steps = d["steps"]
        numbers = [s["n"] for s in steps]
        if numbers != list(range(1, len(steps) + 1)):
            errors.append(f"{d['id']}: steps must be numbered 1..{len(steps)}")
        has_heat = any(i["role"] == "adult_heat" for i in d["ingredients"])
        prep = d["dual_prep"]
        if has_heat and not prep["applies"]:
            errors.append(f"{d['id']}: has adult_heat ingredients but dual_prep.applies is false")
        if prep["applies"]:
            split = prep["split_point"]
            by_n = {s["n"]: s for s in steps}
            if split not in by_n or by_n[split]["portion"] != "child_only":
                errors.append(f"{d['id']}: split_point {split} must be a child_only step")
            for s in steps:
                if s["portion"] == "adult_only" and s["n"] <= split:
                    errors.append(f"{d['id']}: adult_only step {s['n']} comes before the child portion is plated")
                if s["portion"] == "shared" and s["n"] > split:
                    errors.append(f"{d['id']}: shared step {s['n']} comes after the split")
    for nutrient, ids in plan["nutrition"]["child_micronutrient_sources"].items():
        for i in ids:
            if i not in dish_ids:
                errors.append(f"child_micronutrient_sources.{nutrient}: unknown dish id {i}")
    gp = plan["golden_plate"]
    total = gp["veg_tuber_pct"] + gp["protein_pct"] + gp["complex_carb_pct"]
    if abs(total - 100) > 1:
        errors.append(f"golden_plate percentages add up to {total}, not 100")
    return errors


def validate(path):
    plan = json.loads(Path(path).read_text())
    validator = Draft202012Validator(SCHEMA, format_checker=Draft202012Validator.FORMAT_CHECKER)
    errors = [f"{'/'.join(map(str, e.absolute_path)) or '<root>'}: {e.message}" for e in validator.iter_errors(plan)]
    if not errors:
        errors = rule_errors(plan)
    return errors


def main(argv):
    paths = argv or sorted(str(p) for p in (ROOT / "examples").glob("*.json"))
    failed = False
    for path in paths:
        errors = validate(path)
        print(f"{'FAIL' if errors else 'ok  '} {path}")
        for e in errors:
            print(f"     {e}")
        failed |= bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
