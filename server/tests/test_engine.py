import json

import pytest

from conftest import SAMPLE_DATE, SAMPLE_HOUSEHOLD, FakeClient, text_message
from seasonbite_engine.engine import MODEL, MealPlanError, generate_meal_plan, load_system_prompt


def test_valid_first_reply_is_returned(sample_text, sample_plan):
    client = FakeClient([text_message(sample_text)])
    plan = generate_meal_plan(SAMPLE_DATE, SAMPLE_HOUSEHOLD, client)
    assert plan == sample_plan

    call = client.calls[0]
    assert call["model"] == MODEL
    assert call["fallbacks"] == "default"
    assert call["system"][-1]["cache_control"] == {"type": "ephemeral"}
    assert "Plan one family dinner for 2026-10-01" in call["messages"][0]["content"]


def test_fenced_json_is_accepted(sample_text, sample_plan):
    client = FakeClient([text_message(f"```json\n{sample_text}\n```")])
    assert generate_meal_plan(SAMPLE_DATE, SAMPLE_HOUSEHOLD, client) == sample_plan


def test_rule_break_gets_one_repair_round(broken_plan, sample_text, sample_plan):
    first = text_message(json.dumps(broken_plan, ensure_ascii=False))
    client = FakeClient([first, text_message(sample_text)])
    assert generate_meal_plan(SAMPLE_DATE, SAMPLE_HOUSEHOLD, client) == sample_plan

    retry = client.calls[1]["messages"]
    assert retry[1] == {"role": "assistant", "content": first.content}
    assert "adult-only step 2 comes before" in retry[2]["content"]


def test_still_broken_after_repair_raises(broken_plan):
    broken = json.dumps(broken_plan, ensure_ascii=False)
    client = FakeClient([text_message(broken), text_message(broken)])
    with pytest.raises(MealPlanError) as exc:
        generate_meal_plan(SAMPLE_DATE, SAMPLE_HOUSEHOLD, client)
    assert any("adult-only step 2" in e for e in exc.value.errors)


def test_wrong_date_is_sent_back(sample_text, sample_plan):
    client = FakeClient([text_message(sample_text), text_message(sample_text)])
    with pytest.raises(MealPlanError) as exc:
        generate_meal_plan("2026-10-02", SAMPLE_HOUSEHOLD, client)
    assert exc.value.errors == ["date is 2026-10-01, requested 2026-10-02"]


def test_not_json_is_sent_back(sample_text, sample_plan):
    client = FakeClient([text_message("Sorry, here is a recipe in prose."), text_message(sample_text)])
    assert generate_meal_plan(SAMPLE_DATE, SAMPLE_HOUSEHOLD, client) == sample_plan
    assert "not valid JSON" in client.calls[1]["messages"][2]["content"]


@pytest.mark.parametrize("stop_reason", ["refusal", "max_tokens"])
def test_refusal_and_cutoff_raise_without_retry(stop_reason):
    client = FakeClient([text_message("", stop_reason=stop_reason)])
    with pytest.raises(MealPlanError):
        generate_meal_plan(SAMPLE_DATE, SAMPLE_HOUSEHOLD, client)
    assert len(client.calls) == 1


def test_system_prompt_drops_developer_note():
    prompt = load_system_prompt()
    assert prompt.startswith("You are the Executive Pediatric/Adult Dietitian")
    assert "MANDATORY dual-prep rule" in prompt
