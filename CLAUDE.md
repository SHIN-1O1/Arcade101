# Pocket Arcade: guide for AI assistants (read this before exploring code)

Godot 4.3, GDScript, 2D portrait (720x1280 base, `canvas_items` stretch, expand aspect),
Compatibility renderer, Android first. Offline. Free with ads + one-time "remove_ads".
All UI is built in code (core/ui.gd); .tscn files are just a root Control + script.

## Layout
```
project.godot          autoloads, display, renderer
autoload/              singletons (names as used in code)
  save_manager.gd  Save      user://save.json: progress stars, settings, no_ads
  game_registry.gd Games     reads data/games.json + games/<id>/levels.json
  nav.gd           Nav       scene changes, current game_id/level_index, Android back
  ad_service.gd    Ads       STUB: interstitial every 3 levels, rewarded, banner
  iap_service.gd   IAP       STUB: purchase("remove_ads") auto-succeeds
  feedback.gd      Feedback  sfx(name) from res://audio/<name>.ogg|wav, vibrate(ms)
core/
  base_game.gd     class BaseGame: the contract every game implements
  stub_game.gd     placeholder game (debug Win/Fail buttons)
  ui.gd            class UI: colors, button(), label(), screen(), stars_text()
  fx.gd            class FX: shared visual kit (see "Look and feel")
scenes/            hub, level_select, game_host, settings (.tscn + .gd)
data/games.json    game registry (order = hub order)
games/<id>/        game.tscn (+ scripts/assets) and levels.json (30 levels)
tools/gen_levels.py  regenerates every levels.json (overwrites hand edits!)
tests/smoke_test.gd  headless check: registry, levels, save logic, scenes load
```

## Flow
hub -> level_select (Nav.game_id) -> game_host (Nav.level_index).
game_host instances `games.json[scene]`, connects `finished`/`status_changed`,
calls `start_level(level_dict, index)`. On `finished(won, stars)` it saves via
`Save.record_result` (keeps best), calls `Ads.on_level_finished()`, shows result
overlay (Next/Retry/Levels). Restart button re-instances the game scene.
Level N unlocks when level N-1 has >= 1 star.

## BaseGame contract (core/base_game.gd)
- Root of game.tscn extends `BaseGame` (a full-rect Control inside the host's area;
  use `size` for layout, the host top bar is outside it).
- Override `_on_start()`; read params from `level` (Dictionary), `level_index`.
- Call `win(stars)` (1..3) or `fail()` exactly once. `stars_for(value, lower_is_better)`
  maps a metric to stars using `level.stars` thresholds `[one, two, three]`.
- `status_changed.emit("Score 120")` updates the HUD line.
- `make_rng()` gives a RNG seeded from `level.seed` (levels replay identically).
- Use `Feedback.sfx()/vibrate()`; never touch Save/Ads/Nav from a game.

## Look and feel (core/fx.gd)
Every game should use `FX` so the library looks consistent, no image assets needed.
- In `_draw()`: `FX.draw_background(self, Rect2(Vector2.ZERO, size))`, `draw_shadow`, `draw_glow`,
  `draw_ball(self, c, r, color, label, airborne)` (glossy sphere), `draw_tile(self, rect, color)`
  (glossy rounded block), `draw_text_centered`. Palette: `FX.INDIGO/TANGERINE/LEMON`.
- Nodes: `FX.style_button(b)` (3D button + press squash), `pop`, `scale_to`, `ease_smooth`,
  `FX.burst(self, pos, colors)` particles, `FX.shake(self)` for clears and wins.
- Input: handle taps in `_gui_input` and skip `event.device == InputEvent.DEVICE_ID_EMULATION`;
  mouse/touch emulation is on, so every tap also arrives as an emulated twin.
- Example: games/color_sort/game.gd.

## Level data
`games/<id>/levels.json` = `{"star_metric": "...", "levels": [ {id, seed, stars, ...game params} x30 ]}`.
Per-game params (defined in tools/gen_levels.py):
| id | name | params | star metric |
|---|---|---|---|
| fruit_merge | Fruit Fusion (Suika-like drop & merge) | target_tier, spawn_max_tier, jar_width | score |
| color_sort | Tube Sort (water/ball sort) | colors, capacity, empty_tubes | moves used, lower better |
| tower_stack | Sky Stacker (one-tap stacker) | target_height, speed, speed_step, block_width | perfect drops |
| block_puzzle | Block Fit (8x8 place pieces, clear lines) | grid, target_lines, prefilled, piece_set | score |
| number_merge | Merge Tiles (2048-like) | grid, target_tile, blockers, move_limit | moves used, lower better |
| bubble_shooter | Bubble Burst | rows, colors, shots | shots left |
All six are placeholders (stub_game.gd). `status` in games.json tracks this.

## Add or implement a game
1. Create `games/<id>/` with `game.gd` (`extends BaseGame`) and `game.tscn` whose
   root Control uses it (copy an existing game.tscn, change the script path).
2. Add a generator function + entry in `GAMES` in tools/gen_levels.py, run
   `python tools/gen_levels.py` (or hand-write levels.json).
3. Add/update the entry in data/games.json (id, name, tagline, color, scene, status).
4. Run the smoke test (below). Nothing else needs changing.

## Commands
- Smoke test: `godot --headless --import` once, then `godot --headless -s res://tests/smoke_test.gd`
- Run: open project in editor, F5.

## Rules
- Original names/art only; copy mechanics, never trademarks or assets.
- Keep games self-contained in their folder; shared helpers go in core/.
- Real ad/IAP SDKs replace only the `_provider_*` functions in the stubs.
- Bump `Save.SAVE_VERSION` and migrate in `load_game()` if the save shape changes.

## Git workflow (full rules: CONTRIBUTING.md)
- `main` is always runnable and is never committed to directly. Releases are tags `vX.Y.Z`.
- Cut every change from fresh main: `feature/<game-or-topic>` (e.g. `feature/color_sort`) or `fix/<topic>`.
- One game per branch/PR; a game PR touches only `games/<id>/` plus its own lines in
  `data/games.json` and `tools/gen_levels.py`. Shared files (autoload/, core/, scenes/,
  project.godot, tests/) change only when the PR title/body says so.
- Small focused commits; run the smoke test before pushing.
- Land via PR into main with squash merge; CI (`.github/workflows/smoke-test.yml`) must pass.
- Rollback: `git revert <squash-commit>` on a fix branch + PR, or check out a tag to inspect.
