# QA report

## Final regression pass (2026-10-23, `main` after #19 to #22)
Covers all 8 games in every mode on the new neon UI and art: Fruit Fusion, Tube Sort, Sky Stacker,
Block Fit, Merge Tiles, Solitaire, Bubble Burst and Mahjong Match.

**Runs:** smoke test on Godot 4.7.2 and 4.3; the full driver walk (below) on 4.7.2 with touch at 9:19,
4.7.2 with mouse at 9:16 and 4.3 with mouse at 9:19; then the interrupt, ads, edge-case, hub-scroll and
per-screen cost scripts.

**Passed**
- Every game and mode plays, finishes and returns to the hub with touch and mouse on both versions.
  No script errors, node counts back to the hub baseline, 0 orphan nodes after 5 restart cycles.
- How-to card pops up on first entry only and freezes the game underneath; "i" reopens it.
- Ads: none mid-level or on the result card; the first ad after level 2, then every 2nd win; fails
  never count; endless "Play again" / "Home" are wrapped; No Ads suppresses them; Back during a
  slow (real-SDK-like) ad does not pull the player back into a game.
- Pause on interrupt (Sky Stacker, Fruit Fusion, Solitaire): Paused card on focus-out, Back or
  Resume continues; never over the result card or menus. Fruit Fusion squash stays bounded on
  200 ms frames.
- Hub list scrolls by dragging on a card, a plain tap still opens the mode picker; tap outside
  and Back close the picker.
- The Solitaire bottom bar no longer looks cramped at 9:16 (new layout in #22). Solitaire now
  costs about 600 draw calls a frame (was 3,200) thanks to the card atlas.

**Fixed in this PR**
1. **Mahjong Match: big boards cost up to about 4,200 draw calls a frame** (level 30; level 15
   about 2,400), the heaviest screen in the app and likely to drop frames on low-end phones. Resting
   tiles now come from a pre-rendered atlas (`games/mahjong_match/tile_cache.gd`, same idea as the
   Solitaire card atlas): level 30 drops to about 650 calls and primitives from 285k to 19k.
   Selected, hinted and shaking tiles still draw as vectors; pixel diffs against the vector tiles
   differ only by sub-pixel edges. Headless runs keep the vector path.
2. **Result card logged "Invalid polygon data, triangulation failed"** when a star twinkle was
   born at size zero. Zero-size twinkles are skipped.
3. **Result card logged "Tween started with no Tweeners"** after a level that ends with no status
   line (fixed in #18's last commit, rechecked here).

**Findings, not fixed here**
- **Hub:** about 1,600 draw calls a frame (animated neon backdrop about 430, game cards about 1,200).
  It is a menu, so a dropped frame matters less than in play, but caching each card into a texture
  would bring it down if low-end phones stutter on the hub.
- **Block Fit balance:** a greedy bot still wins only 11 of 30 campaign levels. It plays
  worse than people, so this needs the human playtest to judge.
- Frame times under xvfb are software-rendered (all screens 30 to 100 ms), so only the relative
  costs above mean anything; real-device frame times still need the playtest.

---

## First pass (2026-10-23, #18)
Run on `main` at #15 (Klondike) plus the fixes in this PR. Covers Fruit Fusion,
Tube Sort, Sky Stacker, Block Fit, Merge Tiles, Klondike and Bubble Burst in every mode.
Mahjong Match (#16) was not mergeable with main at the time, so it is not covered yet.

## How it was tested
- Godot 4.7.2 and 4.3: headless smoke test, plus xvfb runs of a scripted driver that sends real
  input events (`Input.parse_input_event`) and saves screenshots.
- Driver walk for every game and every mode: hub card, mode picker, level select, play with
  random taps and drags, result card, Retry / Next / Play again / Home, Android Back, back to hub.
  Also rapid taps during slides, triple Back, settings toggles and restart cycles (node and
  orphan counts).
- Input as mouse clicks and as touches (what a phone sends).
- Screen shapes: 720x1280 (9:16), 720x1560 (9:19.5), 720x1680 (9:21), 1080x1440 (3:4 tablet),
  540x960.
- Interrupts: focus-out and app-pause notifications in Sky Stacker, Fruit Fusion and Klondike,
  on the result card, and on menus.
- Slow frames: Fruit Fusion stepped with 200 ms frames.
- Saves: missing file, old v1 save, no version, garbage, empty file, and keys of the wrong type.
- Ads with the mock backend: cadence, cooldown, fails, endless runs, No Ads, and a slow mock that
  stays open like a real SDK.
- Levels: BFS solver over the 30 Tube Sort levels; greedy bot over the 30 Block Fit levels.
- Cost per screen: draw calls and primitives per frame, idle and while playing.

## Passed
- Every game and mode loads, plays, finishes and returns to the hub on both Godot versions, with
  mouse and touch. No script errors. Node counts return to the hub baseline, 0 orphan nodes.
- Layouts hold on all five screen shapes: nothing off screen, result card, HUD and star meter
  don't overlap.
- Slides never got stuck; taps during a slide are blocked; triple Back is safe.
- Ads never show mid-level or on the result card itself, only after a card button; fails never
  count; cooldown and first-ad rules hold; No Ads suppresses interstitials.
- Old v1 saves migrate. Tube Sort: all 30 levels solvable with 3 stars reachable.
- The "ObjectDB instances leaked / resources still in use" lines at exit are the menu music
  stream still playing when a test quits, not a leak in game code.

## Fixed in this PR
1. **Hub list could not be scrolled by dragging on a card.** Cards stopped every drag, so on a
   9:16 phone the list only moved from the thin gaps and Bubble Burst was hard to reach. Drags now
   reach the scroll list, and a drag cancels the tap so scrolling never opens a game.
2. **No pause on interrupts.** A call, the home button or the notification shade left timers and
   falling pieces running. The game now pauses behind a Paused card; Resume or Back continues.
   Not shown over the result card, an ad or a slide.
3. **Fruit Fusion: a fruit could turn into a screen-wide coloured band** after one slow frame (seen
   on both Godot versions). The squash spring diverged; it is now stepped at 1/60 s and clamped.
4. **Hub: stray card suits around the Solitaire card.** The card art reset the drawing transform,
   so the fanned emblem drew its centre pips at the wrong place.
5. **Mode picker could not be closed by tapping outside on a phone** (it only accepted mouse
   clicks), and **Android Back with it open quit the app**.
6. **Back during a real (async) interstitial pulled the player back into a game** once the ad
   closed. Back now waits while `Ads.is_showing()`.
7. **Nav changed the selected level while a slide was running**, so a result could be saved under
   the wrong level. Calls during a slide are ignored before they touch state.
8. **A damaged save crashed later lookups.** Wrong-type keys fall back to defaults, bad star
   values are cleaned, and an unreadable file is kept as `save.json.bad`.
9. **Bubble Burst could overwrite a bubble** when every cell near the landing point was full.
10. **Smoke test gaps:** it passed when a scene's script failed to parse, and it left No Ads on in
    the developer's save (local F5 runs never showed ads). Both fixed.

## Polish in this PR
- Brighter, distinct card colours for six games (the old muted defaults read as unfinished);
  Klondike's colour is left to the rename work.
- Gradient cards get an anti-aliased rim (Compatibility polygons have no AA), and the glossy
  highlight textures are 256 px, so edges and ball rims stay crisp on 1080p+ phones.
- Hub hides "BEST 0" until a game has a score, and the tag widens for long scores.

## Findings routed, not fixed here
- **Klondike cost:** about 3,200 draw calls a frame (other screens 40 to 480). Fine on mid-range
  phones; on low-end ones it may drop frames. Caching card faces to textures would cut it sharply.
- **Klondike bottom bar** (Undo / Hint / Auto) looks cramped at 9:16.
- **Block Fit balance:** campaign 3-star scores look out of reach from about level 10, since a
  level ends as soon as the line goal is met. Clear-goal levels 15, 18, 24, 27, 30 start with very
  few legal placements.

## Not covered
- Real phone, real AdMob and Play Billing, real GPU frame times (xvfb renders in software).
