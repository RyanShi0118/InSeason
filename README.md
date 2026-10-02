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
| [`scripts/validate_meal_plan.py`](scripts/validate_meal_plan.py) | Checks a plan against the schema and the SeasonBite rules (`scripts/seasonbite_rules.py`) |

```sh
python3 -m pip install jsonschema pytest
python3 scripts/validate_meal_plan.py            # all examples
python3 scripts/validate_meal_plan.py plan.json  # one file
python3 -m pytest scripts                         # rules tests
```

## iOS app

`SeasonBite/` is the SwiftUI app (iOS 17+), built for personal use. It talks to
two providers directly with your own API keys, which it keeps in the iPhone
Keychain:

- **DeepSeek** (`deepseek-v4-pro` by default) writes the meal plan. The app sends
  the system prompt and schema, asks for JSON, and checks the reply against the
  SeasonBite rules. If a rule is broken, DeepSeek gets the list of problems and
  one more try; otherwise the app shows the error and keeps the old plan.
- **Qwen-Image** (`qwen-image-2.0` by default, Model Studio Beijing) draws a
  square photo for each dish card from `hero_image_prompt`. Step photos
  (`step_image_prompt`) are drawn on request from a dish's page. Photos are
  saved on the phone, since Qwen's links expire after 24 hours.

Tap **Plan today's dinner** to plan for today's date in Shanghai and the
household set in Settings. Until then the app shows the bundled 1 October
sample.

`SeasonBiteKit/` is a Swift package with the meal-plan models, the rules (the
same ones as `scripts/seasonbite_rules.py`), and the DeepSeek and Qwen clients.

```sh
brew install xcodegen
xcodegen generate          # creates SeasonBite.xcodeproj
open SeasonBite.xcodeproj
swift test --package-path SeasonBiteKit   # uses a fake HTTP client, no API calls
```
