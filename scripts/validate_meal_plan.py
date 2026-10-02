#!/usr/bin/env python3
"""Validate SeasonBite meal plans against the schema and the SeasonBite rules.

Usage: python3 scripts/validate_meal_plan.py [file.json ...]
With no arguments, validates every file in examples/.
"""
import json
import sys
from pathlib import Path

from seasonbite_rules import validate_plan

ROOT = Path(__file__).resolve().parent.parent


def main(argv):
    paths = argv or sorted(str(p) for p in (ROOT / "examples").glob("*.json"))
    failed = False
    for path in paths:
        errors = validate_plan(json.loads(Path(path).read_text()))
        print(f"{'FAIL' if errors else 'ok  '} {path}")
        for e in errors:
            print(f"     {e}")
        failed |= bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
