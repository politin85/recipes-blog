# מתכונים מחושבים — iOS app

Native SwiftUI version of the recipes site. It uses the same backend as the website
(`Recipes/Services/API.swift`), so there is no content in the app itself.

## Run

Open `Recipes.xcodeproj` in Xcode, pick a simulator or your iPhone, and press Run.

## Layout

- `Recipes/Logic` — ports of the site's JavaScript (amount formatting, step-text amounts, filters, fridge helpers)
- `Recipes/Models`, `Recipes/Services` — API models and client, timers, audio, app state
- `Recipes/Views` — Home, Recipe, Fridge and shared components
- `RecipesWidgets` — the timer's Live Activity (Lock Screen and Dynamic Island); `Shared` — types used by both
- `RecipesTests` — unit tests; `RecipesUITests` — end-to-end walkthrough against the live backend

## Tests

```sh
xcodebuild -project Recipes.xcodeproj -scheme Recipes -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project Recipes.xcodeproj -scheme RecipesUITests -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## When the website changes

- If the step-text or amount logic in `recipe.html` changes, port the change to `Recipes/Logic/RecipeText.swift`
  and regenerate the fixture: `node scripts/make_highlight_fixtures.js`. The unit tests then show any mismatch.
- Timer sounds are rendered by `python3 scripts/make_sounds.py`.

A debug build can open straight onto a screen with launch arguments: `-route recipe/23`, `-route fridge`,
`-drawer`, `-favorites`.
