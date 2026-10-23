# Arcade 101

Offline mini-games collection for Android (iOS later), built with Godot 4.3.
Six games x 30 levels, a hub, level select with stars, settings, and ads + a one-time "No Ads" purchase (mock on desktop; real AdMob/Play Billing setup in docs/MONETIZATION.md).
Architecture and conventions: see CLAUDE.md.

## Run on Windows
1. Download **Godot 4.3 stable (Standard, not .NET)** from https://godotengine.org/download/windows and unzip it anywhere.
2. Start Godot, click **Import**, pick this folder's `project.godot`, then **Import & Edit**.
3. Press **F5** to run. The window opens at phone size (405x720); click = tap.
4. Optional smoke test from a terminal in this folder:
   `Godot_v4.3-stable_win64_console.exe --headless -s res://tests/smoke_test.gd`

## Android export and Google Play (Windows)
Step by step, from tools to Play Console: **docs/RELEASE.md**. Ads and the No Ads purchase: docs/MONETIZATION.md.
Store texts: docs/STORE_LISTING.md. Privacy policy: docs/PRIVACY_POLICY.md. Check readiness: `python tools/check_release.py`.

## What is real vs stub
- Real: hub, level select, locking and stars, save file (`user://save.json`), settings, Android back button.
- Stub: all six games (debug Win/Fail buttons), `Ads` and `IAP` services (print to console;
  remove-ads purchase auto-succeeds). Replace the `_provider_*` functions when adding SDKs.
- Levels: `python tools/gen_levels.py` regenerates all `games/*/levels.json`.
