# Arcade 101: guide for AI assistants (read this before exploring code)

Godot 4.3, GDScript, 2D portrait (720x1280 base, `canvas_items` stretch, expand aspect),
Compatibility renderer, Android first. Offline. Free with ads + one-time "remove_ads".
All UI is built in code (core/ui.gd); .tscn files are just a root Control + script.

## Layout
```
project.godot          autoloads, display, renderer
autoload/              singletons (names as used in code)
  save_manager.gd  Save      user://save.json: progress stars, endless high scores, settings, no_ads
  game_registry.gd Games     reads data/games.json + games/<id>/levels.json
  nav.gd           Nav       scene changes (slide transitions, input blocked meanwhile),
                             current game_id/level_index, Android back
  ad_service.gd    Ads       policy + provider glue, see "Ads and purchases"
  iap_service.gd   IAP       remove_ads purchase/restore, see "Ads and purchases"
  feedback.gd      Feedback  sfx(name), play_music(track), vibrate(ms); see "Sound"
core/
  base_game.gd     class BaseGame: the contract every game implements
  stub_game.gd     placeholder game (debug Win/Fail buttons)
  ui.gd            class UI: menu kit: screen(), button(), icon_button(), title(), top_bar(),
                   star_pill(), card_box(), stagger_pop(), widgets Backdrop/IconButton/Switch
  fonts/           LilitaOne-Regular.ttf (OFL, licence in OFL.txt), via FX.font()/FX.theme()
  fx.gd            shared visual kit, preload as FX (see "Look and feel")
  cards/           card kit for solitaire-style games (see "Card kit"): card, deck, pile, card_layout,
                   card_art, card_view, card_hud, card_table, card_rules
  toast.gd         Toast.show_text(root, msg) floating one-liner (preload it)
  monetization/    ad_config.gd (test IDs, pacing, flags), ad_provider*.gd, iap_provider*.gd
scenes/            hub, level_select, game_host, settings (.tscn + .gd);
                   result_overlay.gd = level complete/failed card (preloaded by game_host)
data/games.json    game registry (order = hub order)
games/<id>/        game.tscn (+ scripts/assets) and levels.json (30 levels)
tools/gen_levels.py  regenerates every levels.json (overwrites hand edits!)
tools/klondike_solver.py  finds verified-winnable Klondike deals -> tools/klondike_deals.json (gen_levels.py reads it)
tests/smoke_test.gd  headless check: registry, levels, save logic, scenes load
```

## Flow
hub -> level_select (Nav.game_id) -> game_host (Nav.level_index).
game_host instances `games.json[scene]`, connects `finished`/`status_changed`,
calls `start_level(level_dict, index)`. On `finished(won, stars)` it saves via
`Save.record_result` (keeps best), calls `Ads.on_level_finished()`, shows result
overlay (Next/Retry/Levels). Restart button re-instances the game scene (fades the new board in).
Scenes change via Nav only (never change_scene_* directly) so transitions stay consistent.
Level N unlocks when level N-1 has >= 1 star.

## BaseGame contract (core/base_game.gd)
- Root of game.tscn extends `BaseGame` (a full-rect Control inside the host's area;
  use `size` for layout, the host top bar is outside it).
- Override `_on_start()`; read params from `level` (Dictionary), `level_index`.
- Call `win(stars)` (1..3) or `fail()` exactly once. `stars_for(value, lower_is_better)`
  maps a metric to stars using `level.stars` thresholds `[one, two, three]`.
- `status_changed.emit("Score 120")` updates the HUD line.
- `report_progress(value, lower_is_better)` drives the HUD star meter (UI.StarMeter) so players
  see which star they are heading for. Call it at start and whenever the star metric changes,
  with the same value/direction you pass to `stars_for()`. Every game must do this.
- `make_rng()` gives a RNG seeded from `level.seed` (levels replay identically).
- Use `Feedback.sfx()/vibrate()`; never touch Save/Ads/Nav from a game.

## Look and feel (core/fx.gd)
Every game should use the kit so the library looks consistent, no image assets needed.
Load it with `const FX := preload("res://core/fx.gd")` (it has no class_name on purpose:
a fresh pull into an open editor does not know new global classes yet).
- In `_draw()`: `FX.draw_background(self, Rect2(Vector2.ZERO, size))`, `draw_shadow`, `draw_glow`,
  `draw_ball(self, c, r, color, label, airborne)` (glossy sphere), `draw_tile(self, rect, color)`
  (glossy rounded block), `draw_round_gradient` (rounded gradient card), `draw_text_centered`. Palette: `FX.INDIGO/TANGERINE/LEMON`.
- Nodes: `FX.style_button(b)` (3D button + press squash), `pop`, `scale_to`, `ease_smooth`,
  `FX.burst(self, pos, colors)` particles, `FX.shake(self)` for clears and wins.
- Input: handle taps in `_gui_input` and skip `event.device == InputEvent.DEVICE_ID_EMULATION`;
  mouse/touch emulation is on, so every tap also arrives as an emulated twin.
- Example: games/color_sort/game.gd.
- Menus: `UI.screen(root, accent)` sets `FX.theme()` (Lilita One, outlined text) and the
  gradient Backdrop; `FX.draw_star`, `draw_lock`, `draw_icon` draw icons (the font has no ★).
  Screens: scenes/hub.gd (game cards with drawn emblems), level_select.gd (LevelTile states).

## Card kit (core/cards/): for Klondike, Spider, FreeCell and any other card game
Load each script with `const X := preload("res://core/cards/x.gd")` (no class_name, same reason as FX).
Cards are data (`Card`: rank 1..13, suit 0 spades/1 hearts/2 diamonds/3 clubs, `face_up`, unique `uid`, `code()` = suit*13+rank-1).
- `deck.gd` Deck: `codes(decks, suits)` (suits < 4 repeats the first suits, for Spider), `shuffled(codes, seed)` (seeded
  Fisher-Yates, same seed = same deal), `make_cards(codes)`, `permute_suits(codes, perm)`.
- `pile.gd` Pile: `id`, `kind` (free text: "tableau", "foundation", "stock", "waste", "cell"), `cards`, `fan` (NONE / DOWN / RIGHT),
  `origin`, `max_extent` (height a DOWN fan may use; it shrinks to fit), `slot_label`, `recycle`, `show_slot`, `fan_step`.
- `card_layout.gd` CardLayout: `card_size(width, columns, margin, gap)`, `column_x(...)`, `fan_down`, `fan_right`. Everything
  derives from the size the game gives it, so 9:16 to 9:21 portrait all work (no fixed pixels).
- `card_art.gd` / `card_view.gd`: glossy cream faces with vector pips and court cards, indigo/tangerine backs, soft shadows,
  squash flip, hint glow. `CardArt.draw_face(ci, rect, suit, rank)` / `draw_back` can be reused anywhere (hub emblem does).
- `card_hud.gd` CardHud: `StatPill` (title + popping value) and `ActionButton` (glossy tile with a vector icon: undo, hint,
  auto, draw, flag, tap; badge, attention pulse, compact toggle) so card games share one HUD look. Klondike also draws its felt
  table and drifting suits itself (games/klondike/game.gd `Felt`, `Motes`): copy that for a consistent table.
- `card_rules.gd` CardRules: THE interface each game implements (override what you need):
  `can_pick(t, pile, index)`, `can_drop(t, cards, from, to)`, `on_tap(t, pile, index)` (stock draw; index -1 = empty slot),
  `auto_target(t, pile, index)` (double-tap / tap-to-move destination), `after_move(t, from, to, count)` (flip exposed
  card, scoring, Spider run removal via `t.move_cards(..., false)`), `hints(t)`, `auto_step(t)` ({} when done; may return
  `{"action": Callable}`), `is_won(t)`, `get_extra()/set_extra()` (your counters, saved in every undo snapshot).
  A move is `{"from": Pile, "index": int, "to": Pile}` (cards from[index:] move).
- `card_table.gd` CardTable (Control): add piles (`add_pile(id, kind, fan)`), set `rules` and `layout_callback`
  (`func(t)`: set `t.card_size` and every pile's `origin`/`max_extent`; called on every resize), then `add_cards(cards, pile_id)`
  and `refresh(true, moving_cards)`. It handles drag and drop with snap-back (drop target = best overlap that `can_drop`
  accepts), double-tap auto-move, optional `tap_to_move`, `move_cards()/move_list()` (tweened, one undo snapshot each),
  `undo()` (whole-table snapshots: piles, face-up flags, rules extra), `show_hint()` (cycles `rules.hints`),
  `sparkle(pile_id)`, `auto_complete(step)`, `play_win()` (foundation cascade with trails, tap skips) and signals `moved`, `changed`,
  `win_animation_finished`, `auto_complete_finished`. Input skips emulated duplicate events. Kit plays select/place/locked/tap sfx
  (`sfx = false` to mute). `busy` is true during auto-complete and the win cascade.
- Game side: `BaseGame` subclass that owns a CardTable plus its own buttons/HUD. Example: games/klondike/game.gd (rules in
  klondike_rules.gd). Spider = 10 tableau piles, stock deals a card to each, `after_move` removes a K..A same-suit run to a
  foundation; FreeCell = "cell" piles + a `can_drop` that checks the free-cell move limit.
- Deals that must be winnable: store verified deck orders in levels.json (Klondike: `tools/klondike_solver.py`) instead of
  relying on the shuffle; permuting suits keeps a Klondike deal winnable.

## Sound (autoload/feedback.gd, audio/)
All audio is synthesised by `python tools/gen_audio.py` (numpy + ffmpeg) into `audio/sfx/*.ogg` and
`audio/music/*.ogg`; original, CC0, listed in `audio/CREDITS.md`. Edit a recipe and rerun to retune.
`Feedback.sfx(name)` honours the sound toggle, uses an 8-voice pool and jitters pitch slightly.
Names: `tap` (generic tap), `select` (pick a piece/tube/tile/level), `place` (drop a piece), `pour`,
`pop`, `merge`, `clear` (line/set cleared), `star` (star earned), `win`, `fail`, `button` (menu
button), `back`, `locked`, `unlock`. Unknown names warn once. `UI.wire`/`icon_button` already play
`button`/`back`; the host plays `win`/`fail`/`star`, so games add only their own move sounds.
Music: `Feedback.play_music("menu"|"game")` loops with a crossfade and follows the music toggle;
Nav switches it (menu on hub/levels/settings, game in game_host), games never call it.
New sound: add a recipe in gen_audio.py `SFX`, an entry in `Feedback.SFX`, and list it here.

## Ads and purchases (autoload/ad_service.gd, iap_service.gd, core/monetization/, docs/MONETIZATION.md)
Games never touch ads: the host does. `Ads.on_level_finished(won, level_index)` records a finished level;
the interstitial plays only via `Ads.run_after_interstitial(next)` wrapped around the result card's
Next/Levels buttons (every 2nd win (`INTERSTITIAL_EVERY` in ad_config.gd), 60 s cooldown, not after level 1, never on fail, off with No Ads).
Endless modes: call `on_level_finished(won)` with level_index -1 and wrap their "play again/home" the same way.
Rewarded hook for hints/undo: `Ads.rewarded_available()`, `Ads.show_rewarded()`, signal `rewarded_finished(granted)`.
Backends are chosen at startup: AdMob / Play Billing plugins on Android when `addons/admob` /
`addons/GodotGooglePlayBilling` exist, else a mock (desktop, CI). The real provider scripts look plugin
classes up by name at runtime (`_c("MobileAds")`, untyped) so the editor shows no errors without the plugins;
never write a plugin class name or type directly in them, and never preload them.
`core/monetization/ad_config.gd` holds Google TEST ad IDs and a marked place for real ones; keep it test-only in git
until release. `IAP.purchase()`, `IAP.restore_purchases()`, signals `purchase_finished`, `restore_finished`.

## Endless mode (high-score games, no levels)
A game offers `"modes": ["levels"]` (default), `["endless"]` or both in data/games.json. An optional
`"endless": {...}` block holds its endless params (always `ramp_score`); there is no levels.json for an
endless-only game and `tools/gen_levels.py` skips it. Hub card tap (`Nav.open_game`): levels-only opens
level select, endless-only starts the run, both shows a Campaign / Endless picker.
- The host builds the level dict with `Games.endless_level(id)` (the endless block + `endless: true`,
  `id: 0`, fresh random `seed`) and calls `start_level(dict, 0)`; `is_endless()` tells a game which mode it is in.
  `Nav.mode` is "levels" or "endless"; the host shows a shared Score / Best bar instead of the star meter.
- Game side: `report_score(score)` at start (0) and whenever it changes; `end_run(score)` exactly once
  when the run is over (never `win`/`fail` in endless). Never call `report_progress` in endless mode.
- Host side (already done): `Save.record_score(id, score)` keeps the best in `Save.data.highscores`
  (`Save.get_high_score(id)`); the result card shows the endless variant (score, "New best!", Play
  again / Home); the hub card shows BEST instead of the star bar (a small tag when a game has both).
- Difficulty by score: `difficulty(score)` returns 0..1 (score / `ramp_score`). Map it to the game's own
  knobs, e.g. Merge Tiles: share of 4s 10% -> 35%, and from 0.2 up occasional stones that crumble.
  Tune `ramp_score` in games.json, not in code.
- Adding endless to a levels game (e.g. Block Fit): set `"modes": ["levels", "endless"]`, add the
  `endless` block, and branch on `is_endless()` in `_on_start()`; keep the level code path as is.

## Level data
`games/<id>/levels.json` = `{"star_metric": "...", "levels": [ {id, seed, stars, ...game params} x30 ]}`.
Per-game params (defined in tools/gen_levels.py):
| id | name | params | star metric |
|---|---|---|---|
| fruit_merge | Fruit Fusion (drop & merge physics) | none: endless only (games.json `endless` block: ramp_score) | high score |
| color_sort | Tube Sort (water/ball sort) | colors, capacity, empty_tubes | moves used, lower better |
| tower_stack | Sky Stacker (one-tap stacker) | target_height, speed, speed_step, block_width | perfect drops |
| block_puzzle | Block Fit (8x8 drag pieces, clear lines) | grid, goal (lines/clear), target_lines, prefilled, piece_set | score |
| number_merge | Merge Tiles (2048-like swipe) | none: endless only (games.json `endless` block: ramp_score) | high score |
| bubble_shooter | Bubble Burst (aim-and-pop) | goal (clear/color/gems), layout, rows, colors, shots, drop_every, target_color, target_n, gems; also has an endless mode | shots left (endless: score) |
| klondike | Klondike Solitaire | deck (52 card codes, verified winnable), draw 1/3, undos (-1 = unlimited), time_k | effort = max(moves, seconds * time_k), lower better |
| mahjong_match | Mahjong Match (stacked tile pairs) | shape, layers, tiles, types, hints, shuffles, undos | seconds + penalties, lower better |
Tube Sort, Block Fit, Sky Stacker, Klondike, Mahjong Match, Bubble Burst and Merge Tiles (endless only) are playable; Fruit Fusion is a placeholder (stub_game.gd). `status` in games.json tracks this.

## Mahjong Match (games/mahjong_match/)
`layout.gd` is the logic with no drawing (shapes, stacking, free rule, solvable pair order, shuffle); `faces.gd` draws the
27 tile faces; `look.gd` + `icons.gd` hold the table backdrop, per-tile nodes, icon buttons and HUD chips; `game.gd` is the scene
(each tile is a Node2D so only changed tiles redraw). Boards are built by removing random free pairs until empty, then giving each pair one
match key, so every board is solvable. Levels store params only (the board is regenerated from `seed`); `tools/gen_levels.py`
mirrors the shape/size maths so `tiles` is what the board really holds. Campaign stars use time plus penalties (hint 8 s,
shuffle 12 s, undo 4 s); endless scores pairs with a combo and refills a shuffle and hint per cleared board.
`check.gd` (`check_levels`) proves all 30 layouts solvable with an independent free-rule and search; the smoke test runs it for
any game that ships a `check.gd`.

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
- Ad/IAP SDK code lives only in `core/monetization/*_provider_*.gd`; policy stays in `Ads`/`IAP`.
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
