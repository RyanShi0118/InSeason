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
python3 -m pip install -r server/requirements-dev.txt
python3 scripts/validate_meal_plan.py            # all examples
python3 scripts/validate_meal_plan.py plan.json  # one file
```

### Recipe engine server

`server/` is a small FastAPI service the app will call. It sends the system
prompt and schema to Claude (`claude-opus-5-5`), parses the reply, and checks
it with the same rules. If the reply breaks a rule, the model gets the list of
problems and one chance to fix them; otherwise the request fails with a 502
and the errors. The Anthropic API key lives only on this server.

```sh
export ANTHROPIC_API_KEY=...            # never ship this in the app
export SEASONBITE_APP_TOKEN=...         # optional: require this bearer token from the app
uvicorn seasonbite_engine.api:app --app-dir server
curl -X POST localhost:8000/v1/meal-plans -H 'Content-Type: application/json' \
  -d '{"date": "2026-10-02", "household": {"adults": 2, "children": [{"age_years": 4}]}}'
python3 -m pytest server                # tests use a fake model client, no API calls
```

## iOS app

`SeasonBite/` is the SwiftUI app (iOS 17+). It shows today's meal: the season
note, the Golden Plate split, a card per dish, and a detail page with in-season
ingredients, steps marked for everyone, child or adults, and the child-safety
notes. For now it loads the bundled sample plan and refuses any plan that
breaks the rules.

`SeasonBiteKit/` is a Swift package with the meal-plan models and the same
rules as the recipe engine server, so the app can check model output itself.

```sh
brew install xcodegen
xcodegen generate          # creates SeasonBite.xcodeproj
open SeasonBite.xcodeproj
swift test --package-path SeasonBiteKit
```
