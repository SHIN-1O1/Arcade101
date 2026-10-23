# Google Play store listing: Arcade 101

Copy-paste text for Play Console > Grow > Store presence > Main store listing. Limits in brackets are
Google's. Keep the game list in the description in step with what is actually in the build
(`status` in `data/games.json`): never advertise a game that is only a placeholder.

## Text

**App name** [30 chars]
```
Arcade 101: Puzzle Games
```

**Short description** [80 chars]
```
Offline puzzle & arcade games: sort, stack, merge and pop. No Wi-Fi needed.
```

**Full description** [4000 chars]
```
Arcade 101 is a pocket arcade of bite-size puzzle, card and arcade games that work completely offline: on the bus, on a plane, or anywhere without Wi-Fi. One app, eight ways to relax, in a bright retro neon look with a synthwave soundtrack. Most games have 30 levels plus an Endless mode for chasing your best score.

GAMES INSIDE
• Tube Sort: pour the coloured balls until every tube holds one colour. A classic sorting puzzle.
• Sky Stacker: tap at the right moment and build the tallest tower you can. Perfect drops keep the blocks wide.
• Block Fit: drag shapes onto the grid and clear full rows and columns. Plan ahead, chase combos.
• Merge Tiles: swipe to slide and merge matching numbers into bigger ones. Easy to learn, hard to stop.
• Bubble Burst: aim, bounce and pop groups of matching bubbles before the ceiling drops.
• Fruit Fusion: drop fruit into the bowl and merge matching ones into bigger fruit. Endless fun.
• Solitaire: the classic card game with winnable deals, hints and an Endless mode.
• Mahjong Match: find free matching tiles and clear the board.

WHY YOU'LL LIKE IT
• 100% offline gameplay, no account and no sign-in needed
• Quick levels (usually a minute or two) and a never-ending Endless mode
• A short how-to card the first time you open each game
• Earn up to 3 stars on every level and unlock the next ones as you go
• Neon arcade visuals, smooth animations, satisfying sound and vibration (both can be switched off)
• Free to play. Remove all ads for good with one small purchase

Whether you like brain teaser puzzles, relaxing casual games, card games or quick arcade challenges, Arcade 101 has a game for the moment. Open it, play a level, close it, come back tomorrow.

Free with ads. A single "Remove Ads" purchase removes them forever. Privacy policy: [PRIVACY POLICY URL]
```
Keywords are woven into the text (puzzle, offline, casual, arcade, card, brain teaser, sort, merge, stack, bubble, relaxing). Do not add a keyword list; Play penalises stuffing. Merge Tiles and Fruit Fusion are Endless-only: keep the "most games have levels" wording.

**What's new** [500 chars] for the first release
```
Welcome to Arcade 101! The first release: eight offline puzzle, card and arcade games, with levels, stars and Endless modes. Tell us which game you want next.
```
Later releases, one line each, e.g. `New: Fruit Fusion. Smoother Block Fit dragging. Small fixes.`

## Settings to pick in the listing

| Field | Value |
|---|---|
| App or game | Game |
| Category | Puzzle (alternative: Casual) |
| Tags (up to 5) | Puzzle, Casual, Offline, Brain teaser, Arcade (pick what Play offers) |
| Contact email | `[YOUR EMAIL]` (public) |
| Website | optional, leave empty |
| Privacy policy | URL of the hosted `docs/PRIVACY_POLICY.md` |
| Default language | English (United States); add translations later |

## Graphics

| Asset | Size | File |
|---|---|---|
| App icon | 512 x 512 PNG, 32-bit, under 1 MB | `store/graphics/play_store_icon_512.png` |
| Feature graphic | 1024 x 500 PNG or JPG | `store/graphics/play_feature_graphic_1024x500.png` |
| Phone screenshots | 2 to 8, 9:16 portrait, 1080 x 1920 | `tools/marketing_shots.sh` |
| 7-inch tablet screenshots | optional, 1200 x 1920 (16:10) or similar | same script with `--resolution` changed |
| 10-inch tablet screenshots | optional, 1600 x 2560 | same script with `--resolution` changed |
| Promo video | optional, YouTube URL | skip for v1 |

Regenerate the icon and feature graphic any time with `python tools/gen_branding.py`
(needs `pip install pillow numpy`).

### Screenshots to capture (phone, in this order)

The first two images matter most: most people never scroll further. `tools/marketing_shots.sh` makes the ones marked (auto), at the opening position of each game; for stronger shots play a few moves on a phone or in the editor and use the screenshot button.

1. Hub with the game cards (neon, shows the variety). (auto) `01_hub`
2. Block Fit with a nearly full row, or Tube Sort mid-pour. By hand.
3. Bubble Burst mid-aim with the bounce guide visible. By hand.
4. Merge Tiles with a tidy 128 / 256 board. By hand.
5. Solitaire mid-game. By hand (or auto: `08_play_klondike`).
6. Mahjong Match mid-game. By hand (or auto).
7. Level select with stars filled in. (auto) `02_levels_color_sort`
8. A result card with three stars. By hand (win a level, screenshot the card).

Automatic screenshots (hub, level select and an opening board for every playable game):
```
GODOT=/path/to/godot tools/marketing_shots.sh        # writes store/screenshots/NN_name.png
```
It runs Godot under xvfb (Linux, WSL or the cloud), uses a throwaway save, and works on Godot 4.3 and 4.7.2.
Boards are at their starting position, so for the by-hand shots run the game on a phone or in the
editor and use the phone's screenshot button (power + volume down), then crop to 9:16 if needed.

## Before you submit the listing
- No misleading claims, no "#1", no price or "free" in the title, no emoji in the title.
- Screenshots show the real app, no fake device frames with other brands.
- Description does not mention any other company's game by name.
