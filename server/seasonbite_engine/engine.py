"""Asks Claude for a meal plan and only returns one that passes every rule."""
import json

import anthropic

from .validation import REPO_ROOT, SCHEMA_PATH, validate_plan

MODEL = "claude-opus-5-5"
MAX_TOKENS = 64000
PROMPT_PATH = REPO_ROOT / "prompts" / "seasonbite_chef_system.md"


class MealPlanError(Exception):
    """The model could not produce a plan that passes the rules."""

    def __init__(self, message, errors=()):
        super().__init__(message)
        self.errors = list(errors)


def load_system_prompt():
    """The prompt file has a short note for developers above the first `---`."""
    text = PROMPT_PATH.read_text()
    _, sep, body = text.partition("\n---\n")
    return (body if sep else text).strip()


def system_blocks():
    # Both blocks are identical on every request, so they are cached together.
    return [
        {"type": "text", "text": load_system_prompt()},
        {
            "type": "text",
            "text": "The JSON Schema your reply must validate against:\n\n" + SCHEMA_PATH.read_text(),
            "cache_control": {"type": "ephemeral"},
        },
    ]


def user_request(date, household):
    return (
        f"Plan one family dinner for {date}.\n"
        f"Household: {json.dumps(household, ensure_ascii=False)}\n"
        "Copy the date and household into the plan exactly as given. "
        "Reply with the JSON object only."
    )


def extract_json(text):
    """Parse the reply, tolerating a ```json fence or stray text around the object."""
    start, end = text.find("{"), text.rfind("}")
    if start == -1 or end < start:
        raise ValueError("no JSON object in the reply")
    return json.loads(text[start : end + 1])


def request_mismatch_errors(plan, date, household):
    errors = []
    if plan.get("date") != date:
        errors.append(f"date is {plan.get('date')}, requested {date}")
    got = plan.get("household", {})
    if got.get("adults") != household["adults"]:
        errors.append(f"household.adults is {got.get('adults')}, requested {household['adults']}")
    got_ages = sorted(c.get("age_years") for c in got.get("children", []))
    want_ages = sorted(c["age_years"] for c in household["children"])
    if got_ages != want_ages:
        errors.append(f"children's ages are {got_ages}, requested {want_ages}")
    return errors


def _ask(client, messages):
    with client.beta.messages.stream(
        model=MODEL,
        max_tokens=MAX_TOKENS,
        system=system_blocks(),
        messages=messages,
        output_config={"effort": "high"},
        # If a safety classifier declines, the API retries on its recommended fallback model.
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
    ) as stream:
        return stream.get_final_message()


def generate_meal_plan(date, household, client=None, max_attempts=2):
    """Returns a plan dict that passes the schema and every SeasonBite rule.

    date: ISO date string, e.g. "2026-10-02".
    household: {"adults": int, "children": [{"age_years": float, "allergies": [str]}]}
    If the first reply breaks a rule, the model gets the list of problems and one
    chance to fix them. Raises MealPlanError if it still fails.
    """
    client = client or anthropic.Anthropic()
    messages = [{"role": "user", "content": user_request(date, household)}]
    errors = []

    for _ in range(max_attempts):
        message = _ask(client, messages)
        if message.stop_reason == "refusal":
            raise MealPlanError("The model declined to write this meal plan.")
        if message.stop_reason == "max_tokens":
            raise MealPlanError("The meal plan was cut off before it finished.")

        text = "".join(block.text for block in message.content if block.type == "text")
        try:
            plan = extract_json(text)
        except ValueError as e:
            errors = [f"reply is not valid JSON: {e}"]
        else:
            errors = validate_plan(plan) or request_mismatch_errors(plan, date, household)
            if not errors:
                return plan

        messages += [
            # Echo the whole reply (thinking blocks included) so the model keeps its reasoning.
            {"role": "assistant", "content": message.content},
            {
                "role": "user",
                "content": "That plan breaks these rules:\n"
                + "\n".join(f"- {e}" for e in errors)
                + "\nFix every one and reply with the complete corrected JSON object only.",
            },
        ]

    raise MealPlanError("The model did not produce a valid meal plan.", errors)
