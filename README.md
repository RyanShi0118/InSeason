# SeasonBite (知时食)

An iOS meal-planning app for Shanghai households. Each day it plans one family
meal from what is at peak season in Shanghai and the Yangtze River Delta,
cooked so that young children and adults can eat from the same pots.

## Recipe engine

| Path | What it is |
| --- | --- |
| [`prompts/seasonbite_chef_system.md`](prompts/seasonbite_chef_system.md) | System prompt for the dietitian/chef model: seasonality, the Tri-Flavor System, the dual-prep rule, Golden Plate ratio, child and adult nutrition rules, photo prompts |
| [`schema/meal_plan.schema.json`](schema/meal_plan.schema.json) | JSON Schema every generated meal plan must match |
| [`examples/`](examples/) | Hand-written sample plans |
| [`scripts/validate_meal_plan.py`](scripts/validate_meal_plan.py) | Checks a plan against the schema and the dual-prep step order |

```sh
python3 -m pip install jsonschema
python3 scripts/validate_meal_plan.py            # all examples
python3 scripts/validate_meal_plan.py plan.json  # one file
```
