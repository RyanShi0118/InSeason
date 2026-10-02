import copy
import json
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

SAMPLE_PATH = SCRIPTS.parent / "examples" / "2026-10-01_family_dinner.json"


@pytest.fixture
def sample_plan():
    return json.loads(SAMPLE_PATH.read_text())


@pytest.fixture
def broken_plan(sample_plan):
    plan = copy.deepcopy(sample_plan)
    tofu = next(d for d in plan["dishes"] if d["id"] == "golden_sour_tofu_caltrop")
    tofu["steps"][1]["portion"] = "adult_only"
    return plan
