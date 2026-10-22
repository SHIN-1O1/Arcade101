# Arcade 101

Offline mini-games collection for Android (iOS later), built with Godot 4.3.
Six games x 30 levels, a hub, level select with stars, settings, and stubbed ads/purchases.
Architecture and conventions: see CLAUDE.md.

## Run on Windows
1. Download **Godot 4.3 stable (Standard, not .NET)** from https://godotengine.org/download/windows and unzip it anywhere.
2. Start Godot, click **Import**, pick this folder's `project.godot`, then **Import & Edit**.
3. Press **F5** to run. The window opens at phone size (405x720); click = tap.
4. Optional smoke test from a terminal in this folder:
   `Godot_v4.3-stable_win64_console.exe --headless -s res://tests/smoke_test.gd`

## Android export (Windows)
One-time setup:
1. Install **OpenJDK 17** (e.g. Adoptium Temurin 17) and **Android Studio** (or just the command-line tools).
   In the SDK Manager install: Platform-Tools, Build-Tools 34, Android SDK Platform 34.
2. Godot: **Editor > Editor Settings > Export > Android**: set *Java SDK Path* (the JDK 17 folder)
   and *Android SDK Path* (usually `C:\Users\<you>\AppData\Local\Android\Sdk`).
3. **Editor > Manage Export Templates > Download and Install**.
4. Create a release keystore (keep it safe and backed up, never commit it):
   `keytool -genkeypair -v -keystore release.keystore -alias arcade101 -keyalg RSA -keysize 2048 -validity 10000`

Export:
1. **Project > Export > Add... > Android**.
2. Set *Package > Unique Name* (e.g. `com.shin1o1.arcade101`), *Version Code/Name*, and
   *Screen orientation* is already portrait from project settings.
3. Under *Keystore > Release* fill the keystore path, alias and password.
4. Quick test: enable USB debugging on your phone, plug it in, and press the Android icon in the
   editor's top-right (one-click deploy). Or **Export Project** with *Export With Debug* to get an `.apk`.
5. Play Store: turn on *Gradle Build > Use Gradle Build* (Project > Install Android Build Template first)
   and export as **.aab** with *Export With Debug* off.

## What is real vs stub
- Real: hub, level select, locking and stars, save file (`user://save.json`), settings, Android back button.
- Stub: all six games (debug Win/Fail buttons), `Ads` and `IAP` services (print to console;
  remove-ads purchase auto-succeeds). Replace the `_provider_*` functions when adding SDKs.
- Levels: `python tools/gen_levels.py` regenerates all `games/*/levels.json`.
