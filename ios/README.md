# מתכונים מחושבים — iOS app

Two native SwiftUI apps for the recipes site, both using the website's backend (`Core/API.swift`):

- **Recipes** ("מתכונים") — the reader app.
- **RecipesAdmin** ("ניהול מתכונים") — the password-protected admin app. Kept separate so the
  reader app contains no admin code.

## Run

Open `Recipes.xcodeproj` in Xcode, choose the `Recipes` or `RecipesAdmin` scheme, pick a simulator
or your iPhone, and press Run.

## Layout

- `Core` — shared by both apps: models, theme, public API client, fonts, and `Core/Logic`, the ports
  of the site's JavaScript (amount formatting, step-text amounts, filters, fridge helpers)
- `Recipes` — the reader app: timers, audio, app state and the Home, Recipe and Fridge screens
- `RecipesAdmin` — the admin app: login and lock, admin API client, recipe editor, tools
- `RecipesWidgets` — the timer's Live Activity (Lock Screen and Dynamic Island); `Shared` — types used by both
- `RecipesTests`, `RecipesAdminTests` — unit tests; `RecipesUITests` — end-to-end walkthroughs against the live backend

## Tests

```sh
xcodebuild -project Recipes.xcodeproj -scheme Recipes -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project Recipes.xcodeproj -scheme RecipesAdmin -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project Recipes.xcodeproj -scheme RecipesUITests -destination 'platform=iOS Simulator,name=iPhone 17' test
```

The admin UI tests are skipped unless the admin app is installed on the simulator and
`TEST_RUNNER_ADMIN_PW` is set; they create and delete one hidden recipe on the live backend.

## When the website changes

- If the step-text or amount logic in `recipe.html` changes, port the change to `Core/Logic/RecipeText.swift`
  and regenerate the fixture: `node scripts/make_highlight_fixtures.js`. The unit tests then show any mismatch.
- Timer sounds are rendered by `python3 scripts/make_sounds.py`.

A debug build can open straight onto a screen with launch arguments: `-route recipe/23`, `-route fridge`,
`-drawer`, `-favorites`.
