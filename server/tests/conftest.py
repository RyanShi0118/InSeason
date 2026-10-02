import copy
import json
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

SERVER = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER))

SAMPLE_PATH = SERVER.parent / "examples" / "2026-10-01_family_dinner.json"
SAMPLE_DATE = "2026-10-01"
SAMPLE_HOUSEHOLD = {"adults": 2, "children": [{"age_years": 4, "allergies": []}]}


def text_message(text, stop_reason="end_turn"):
    return SimpleNamespace(
        stop_reason=stop_reason,
        content=[SimpleNamespace(type="thinking", thinking=""), SimpleNamespace(type="text", text=text)],
    )


class FakeClient:
    """Stands in for anthropic.Anthropic; returns canned replies in order."""

    def __init__(self, replies):
        self.replies = list(replies)
        self.calls = []
        self.beta = SimpleNamespace(messages=SimpleNamespace(stream=self._stream))

    def _stream(self, **kwargs):
        self.calls.append({**kwargs, "messages": list(kwargs["messages"])})
        reply = self.replies.pop(0)

        class _Stream:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def get_final_message(self):
                return reply

        return _Stream()


@pytest.fixture
def sample_plan():
    return json.loads(SAMPLE_PATH.read_text())


@pytest.fixture
def sample_text(sample_plan):
    return json.dumps(sample_plan, ensure_ascii=False)


@pytest.fixture
def broken_plan(sample_plan):
    plan = copy.deepcopy(sample_plan)
    tofu = next(d for d in plan["dishes"] if d["id"] == "golden_sour_tofu_caltrop")
    tofu["steps"][1]["portion"] = "adult_only"
    return plan
