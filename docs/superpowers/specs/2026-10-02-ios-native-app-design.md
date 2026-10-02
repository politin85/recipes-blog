# Native iOS app for מתכונים מחושבים — design

Date: 2026-10-02

## Goal

A native iOS app that looks like the website and has the same reader-facing features,
talking to the same Railway backend so recipes live in one place. The website is unchanged.

## Decisions

- **SwiftUI, no third-party dependencies.** Project in `ios/`, targets iOS 26.1+ (needed for system timers), iPhone-first (runs on iPad).
- **Same backend.** Only the public endpoints are used: `/api/settings`, `/api/recipes`,
  `/api/recipes/:id`, `/api/recipes/:id/nutrition`, `/api/recipes/:id/notes`, `/api/ingredients`,
  `/api/recipes/by-ingredients`. The paid Google `/tts` proxy is not used.
- **No admin in this app.** No admin screens, link, endpoints or password handling. Admin is planned
  as a separate app target (see "Not included").
- **Hebrew, right-to-left, light mode only**, like the site. Same palette and the same fonts
  (Secular One, Rubik) bundled in the app.
- **Bundle ID** `com.nirpoliti.recipes`, display name "מתכונים", icon from `AppIconEnhanced.png`.

## Screens

| Web page | App screen | Notes |
|---|---|---|
| `index.html` | `HomeView` | Cover, search (200 ms debounce), filter/sort sheet, grid/list toggle, favorites view, filter button with badge |
| `recipe.html` | `RecipeView` | Hero, story, servings scaling, ingredients checklist, steps accordion, cook mode, timers, narration, notes, nutrition, related |
| `fridge.html` | `FridgeView` | Autocomplete, chips, "show all" sheet by category, pantry toggle, match-% results |
| drawer | `DrawerView` | Navigation plus voice and timer-sound settings |

## Logic ported from the site

`Logic/` holds pure ports of the site's JavaScript: quantity formatting, the step-text
"(amount unit)" injection, the `#pos=` image crop fragment, home filtering/sorting and the fridge
helpers. The step-text port is checked against the site's own code: `scripts/make_highlight_fixtures.js`
lifts the functions out of `recipe.html`, runs them over every live recipe, and the unit tests
compare the Swift output to that fixture.

## Where the app differs from the browser

- Timers are system timers: they keep running when the app is closed and show on the Lock Screen
  and in the Dynamic Island. With alarm access (AlarmKit) they ring like a Clock timer and can be
  paused from the Live Activity; without it, a plain Live Activity plus a notification is used.
  The Live Activity UI lives in the `RecipesWidgets` extension; `Shared/` is compiled into both.
- Narration uses the Hebrew voices installed on the device (AVSpeechSynthesizer), not the server.
  The voice setting lists those voices.
- Cook mode keeps the screen awake.
- Favorites, view mode, voice and sound are stored on the device (same keys as localStorage).
- Images are requested from Cloudinary as resized JPEGs instead of the original PNGs.
- A back button sits next to the menu button (the site relies on the browser's).
- Fridge suggestions reopen on typing rather than on a second tap of the field.

## Not included

- Admin (recipe editor, ingredient aliases, batch tools) — separate app target, to be designed.
- Offline mode, App Store / TestFlight submission.

## Testing

- `RecipesTests` (unit): port fidelity against the website fixture, decoding, filtering, fridge logic.
- `RecipesUITests` (own scheme, needs network): walks home → filters → drawer → favorites,
  the fridge flow, and a recipe with scaling, cook mode and a timer run to completion.
