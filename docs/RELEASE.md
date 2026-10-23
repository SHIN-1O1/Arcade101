# Releasing Arcade 101 on Google Play (first-time publisher, Windows)

This is the whole road from "works in the editor" to "live on Google Play". Do the parts in order. Anything marked
**you only** needs your accounts, your phone or your money. Ads and the "Remove Ads" purchase are set up in
`docs/MONETIZATION.md`; this guide points there instead of repeating it.

What is already prepared in the repo: app icon (adaptive + themed), splash screen, mobile settings in
`project.godot`, two Android export presets in `export_presets.cfg` (no secrets inside), store texts in
`docs/STORE_LISTING.md`, the privacy policy in `docs/PRIVACY_POLICY.md`, screenshot script
`tools/marketing_shots.sh`, and a pre-launch checker `python tools/check_release.py`.

**Honest status:** nothing here has been built into an Android file in the cloud (the Android SDK cannot be
downloaded there). The presets were checked to load in Godot 4.7.2 and the game runs and renders, but your first
Android export is the first real test. The Troubleshooting table at the end lists the usual first-run problems.

Version facts used below (Godot 4.7.2): Java 17, Android SDK Platform 36, Build-Tools 36.1.0, NDK 29.0.14206865,
target SDK 36 (Google Play requires 36 for new apps and updates from 31 Aug 2026), min SDK 24 (Android 7+).

---

## Part 0. Start accounts early (waiting time)

1. **Google Play developer account**: https://play.google.com/console/signup. One-time **US$25**. You verify your
   identity (government ID, sometimes a video) which can take days. Choose **Personal** unless you have a company.
   Your name and country show on the store page; an organisation account additionally needs a D-U-N-S number.
2. **Important rule for personal accounts created after 13 Nov 2023:** before you may publish to production you must run a
   **closed test with at least 12 testers who stay opted in for 14 days in a row**, then apply for production access.
   Plan for it: ask 12+ friends or family (each needs a Google account and an Android phone) to join your closed test
   link as soon as the app is stable. Start the 14-day clock early. (Check the current rule on the Play Help page
   "Test your app", Google changes it from time to time.)
3. **AdMob account**: see `docs/MONETIZATION.md`, Part 2.
4. A place to host the privacy policy page (see "Privacy policy page" below).

## Part 1. Install the tools (once)

1. **JDK 17**: install Eclipse Temurin 17 from https://adoptium.net (choose JDK, Windows x64, `.msi`; tick
   "Set JAVA_HOME" in the installer). Test in a terminal: `java -version` shows 17.
2. **Android Studio** from https://developer.android.com/studio (it brings the SDK Manager). Open it once, accept
   licences, finish the wizard. Then **More Actions > SDK Manager**:
   - *SDK Platforms* tab: tick **Android 16 (API 36)** (`Android SDK Platform 36`).
   - *SDK Tools* tab: tick **Android SDK Build-Tools 36.1.0** (click "Show Package Details" to pick the version),
     **Android SDK Platform-Tools**, **Android SDK Command-line Tools (latest)**, **NDK (Side by side) 29.0.14206865**.
   - Apply. Note the **Android SDK Location** at the top (normally `C:\Users\<you>\AppData\Local\Android\Sdk`).
3. **Godot 4.7.2** (Standard, not .NET) and **export templates**: Godot > **Editor > Manage Export Templates >
   Download and Install** (version must match exactly).
4. **Editor > Editor Settings > Export > Android**: set *Java SDK Path* (the JDK 17 folder, e.g.
   `C:\Program Files\Eclipse Adoptium\jdk-17...`) and *Android SDK Path* (the SDK Location above).
5. **Debug keystore** (Godot signs debug builds with it). In a terminal, from any folder:
   ```
   keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore debug.keystore -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
   ```
   Keep `debug.keystore` outside the repo (for example `C:\Users\<you>\.android\debug.keystore`). In Editor Settings >
   Export > Android set *Debug Keystore* to it, *Debug Keystore User* `androiddebugkey`, *Debug Keystore Pass* `android`.
6. **Android build template and plugins** (needed for ads and purchases): follow `docs/MONETIZATION.md`, Part 1
   (Project > Install Android Build Template, then the AdMob and Billing plugins, then commit `android/` and `addons/`).
   The presets already have *Use Gradle Build* switched on, which the plugins require.

## Part 2. Debug build on your phone over USB

1. On the phone: Settings > About phone > tap **Build number** 7 times > back to Settings > **Developer options** >
   switch on **USB debugging**.
2. Plug it in with a data cable, tap **Allow** on the phone's prompt. Windows may need the maker's USB driver
   (Samsung, Xiaomi etc. offer one; Pixels work without). Check with
   `"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" devices`: it must list your phone as `device`.
3. In Godot: **Project > Export**. Two presets exist: **Android Debug (APK)** and **Android Release (AAB)**.
   Click the Android icon in the editor's top-right ("Remote Debug") to build and start the debug preset on the
   phone in one step, or pick **Android Debug (APK)** and **Export Project** to get `build/arcade101-debug.apk`.
4. Play it. Check, in this order: icon and name on the launcher, splash, hub looks right under the notch and above
   the gesture bar, sound, vibration, back gesture returns from a game to the level list, one level of each game.
   Ads are test ads ("Test Ad" label). Logs while the phone is connected: `adb logcat -s godot`.

The first Gradle build takes several minutes and needs internet (it downloads Android libraries). Later ones are quicker.

## Part 3. Create your signing key (upload key), once

Play App Signing is mandatory for new apps: Google keeps the real app signing key, you keep an **upload key**.
Losing the upload key is recoverable (Google can reset it), but it is slow, so back it up anyway.

1. Terminal in a folder **outside the repo** (for example `C:\Users\<you>\keys`):
   ```
   keytool -genkeypair -v -keystore arcade101-upload.keystore -alias arcade101 -keyalg RSA -keysize 2048 -validity 10000
   ```
   It asks for a password (twice), then your name and country, and a key password (press Enter to reuse the same).
2. **Back up** `arcade101-upload.keystore` and write the password and alias `arcade101` in a password manager.
   Copy the file to a USB stick or cloud drive you trust. **Never commit it** (`*.keystore` is git-ignored, and
   `export_presets.cfg` keeps these fields empty).
3. In Godot: Project > Export > **Android Release (AAB)** > scroll to **Keystore**: *Release* = path to the file,
   *Release User* = `arcade101`, *Release Password* = your password. Godot saves these in
   `.godot/export_credentials.cfg`, which is not committed.
   (Command-line export can use the environment variables `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`,
   `GODOT_ANDROID_KEYSTORE_RELEASE_USER`, `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` instead.)

## Part 4. Build the signed AAB

Before the very first release build (and as part of every release), open `core/monetization/ad_config.gd` and
`docs/MONETIZATION.md` Part 4: put your real ad unit IDs in, set `USE_TEST_ADS := false` only for the release
build, set the real AdMob App ID in Project Settings > Admob. Run `python tools/check_release.py` and fix what it flags.

1. Raise **Version Code** (a whole number, +1 every upload, never reused) and **Version Name** (e.g. `0.1.0`) in
   Project > Export > Android Release (AAB) > Version. Also keep `application/config/version` in Project Settings in step.
2. Make sure **Export With Debug** is **off** and **Use Gradle Build** is on, *Export Format* is **Export AAB**, only
   **arm64-v8a** is ticked (covers practically every phone since 2017; if you later want old 32-bit phones tick
   armeabi-v7a too, the file gets bigger).
3. **Export Project** > save as `build/arcade101.aab`. A good file is typically 25 to 60 MB with the plugins.
4. Optional check before uploading: the *Play Console* does a pre-launch scan, or use Google's `bundletool` to
   build an APK set and install it.

## Part 5. Play Console, step by step

Create the app: **Create app** > name **Arcade 101** > default language > **Game** > **Free** > accept the declarations.
Then work through **Dashboard > Set up your app** (Google shows the list; names below match it).

1. **App access**: all functionality available without special access.
2. **Ads**: **Yes, my app contains ads.**
3. **Content rating**: category *Game*, answer the questionnaire truthfully. For this app: no violence, no blood,
   no sexual content, no profanity, no gambling or simulated gambling, no drugs, no user-to-user communication, no
   sharing of location, no digital purchases other than ad removal (the questionnaire asks about in-app purchases:
   say yes, the item is "Remove Ads"). Expected result: **Everyone / PEGI 3 / USK 0**.
4. **Target audience and content**: age groups **13-15, 16-17, 18+** (do **not** tick any under-13 group).
   "Does your app appeal to children?": **No**. Reason: ads are configured as not child-directed
   (`CHILD_DIRECTED := false`); choosing under-13 would force the Families policy and different ads. Do not mix these.
5. **News app**: No. **COVID-19 contact tracing**: No. **Government app**: No. **Financial features**: none. **Health**: none.
6. **Data safety** (answers prepared for this app; recheck against the AdMob/Play SDK guidance when you add real ads):

   | Question | Answer |
   |---|---|
   | Does your app collect or share any of the required user data types? | **Yes** (through the ads SDK) |
   | Is all of the user data collected by your app encrypted in transit? | **Yes** |
   | Do you provide a way for users to request that their data be deleted? | **No** (the app holds no account or personal data; ad data is held by Google, see the policy) |
   | **Device or other IDs** (advertising ID) | Collected: Yes. Shared: Yes (Google AdMob). Required, not optional. Purposes: **Advertising or marketing**, **Fraud prevention, security and compliance** |
   | **Approximate location** | Collected and shared via AdMob (derived from IP). Purposes: Advertising or marketing |
   | **App interactions** (ad taps and views) | Collected and shared via AdMob. Purposes: Advertising or marketing, Analytics |
   | **Crash logs / Diagnostics** | Collected and shared via AdMob. Purposes: Analytics, App functionality |
   | **Purchase history** | Handled by Google Play Billing; declare it as in `docs/MONETIZATION.md` (Part 5) to be safe. Purpose: App functionality |
   | Name, email, phone, address, contacts, photos, files, audio, health, financial info, messages | **Not collected** |
   | Is data processed ephemerally / user can choose to turn off sharing | No |

   Google's own AdMob guide for this form ("Play Console Data safety section guidance" in AdMob Help) is the
   authority: if it lists more types than the table, tick those too. The answers must match the policy page.
7. **Privacy policy**: paste the URL of your hosted page.
8. **Advertising ID** declaration (Policy > App content): **Yes**, used for advertising (the ads plugin includes the
   `AD_ID` permission). **Government, financial, health** declarations: No.
9. **Store settings**: category **Game > Puzzle**, contact email, then **Main store listing** with the texts and
   graphics from `docs/STORE_LISTING.md`.
10. **Pricing and distribution** (Production > Countries): choose countries. Free app.
11. **In-app product**: create `remove_ads`, see `docs/MONETIZATION.md` Part 3 step 4. Add licence testers (step 5).

### Testing tracks, then production

1. **Internal testing** (up to 100 people, no review wait, usually live in minutes): Testing > Internal testing >
   **Create new release** > accept Play App Signing > upload `arcade101.aab` > release name `0.1.0 (1)` > notes >
   Save > Review > **Start rollout**. Testers tab: add yourself and your licence testers, copy the opt-in link, open
   it on the phone, install from Play. Test ads, buying "Remove Ads" with a licence-test account, Restore.
   (Walkthrough: `docs/MONETIZATION.md` Part 3 step 6.)
2. **Closed testing**: same upload flow under Testing > Closed testing. Add 12 or more testers as an email list or a
   Google Group. They must **opt in and stay opted in for 14 days** (personal accounts, see Part 0). Ask them to just
   open the app a few times. Fix bugs and upload new builds (higher version code) during the period.
3. **Apply for production access** (Dashboard, after the 14 days): Google asks a few questions about your test
   (how you recruited testers, what feedback you got). Review takes a few days.
4. **Production**: Production > Create new release > pick the build from your closed test (or upload) > release notes
   ("What's new" text from `docs/STORE_LISTING.md`) > Review > **Send for review**. First review can take up to
   several days. Use **Managed publishing** if you want to choose the go-live moment.
5. After it is live: AdMob > App settings > **Link to Google Play** (docs/MONETIZATION.md Part 2 step 6).

## Privacy policy page

Google needs a **public URL**. Fill the `[[...]]` markers in `docs/PRIVACY_POLICY.md` first. Options:
- **GitHub Pages** (free, needs the repository to be public, or a paid plan for private): repository Settings > Pages >
  *Deploy from a branch* > `main` and folder `/docs`. The page appears at
  `https://shin-1o1.github.io/Arcade101/PRIVACY_POLICY` (wait a minute; the URL is case-sensitive). The file already has
  the front matter and `docs/_config.yml` the page needs. This also publishes the other `.md` files in `docs/`, so
  keep nothing private there.
- **No public repo?** Paste the text into a free **Google Sites**, Notion public page, or a WordPress/Blogger page and
  use that URL.
Check the URL opens in a private browser window before you paste it into Play Console and AdMob.

## Pre-launch checklist

Run `python tools/check_release.py` first; it checks the code and file items marked (auto).

- [ ] (auto) No `[[...]]` markers left in `docs/PRIVACY_POLICY.md`, URL works while logged out
- [ ] (auto) `USE_TEST_ADS := false` in the release build only, real ad unit IDs filled, test IDs not in release
- [ ] (auto) `export_presets.cfg` has no keystore path or password; no `*.keystore` or `.jks` in git
- [ ] (auto) Package id `com.shin1o1.arcade101` and arm64-v8a only in both presets
- [ ] Real AdMob App ID set in Project Settings > Admob; app linked in AdMob after launch
- [ ] Version Code higher than the last upload; Version Name matches "What's new"
- [ ] Debug build tested on at least one real phone (ideally also an older, low-end one) for a full session
- [ ] Release AAB installed from internal testing, not just a debug APK: ads show, Remove Ads buys, Restore works
- [ ] EU consent form shows for an EEA test device and **Privacy settings** appears in Settings (`DEBUG_FORCE_EEA`)
- [ ] Every game listed in the store text is playable (`status` in `data/games.json` is not `placeholder`)
- [ ] Back gesture, rotating the phone (stays portrait), killing and reopening the app (progress saved)
- [ ] Store listing: icon, feature graphic, 2+ phone screenshots, short and full description, contact email
- [ ] Content rating, target audience (13+), ads declaration, data safety, advertising ID declarations completed
- [ ] Licence testers and test cards used only on test accounts; never tap real ads on your own phone
- [ ] Keystore and passwords backed up in two places, not in the repo
- [ ] Closed test ran 12 testers x 14 days (personal accounts) and production access granted
- [ ] Git: release PR merged, then tag on `main` in the GitHub web UI (Releases > new tag `v0.1.0`)

## Updating the app later

Raise Version Code (and Name), build the AAB, upload to Internal testing first, check, then promote to Production
(Testing track > Promote release). Never reuse a version code. Keep the same upload keystore forever.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Export says "Android build template not installed" | Project > Install Android Build Template (docs/MONETIZATION.md Part 1) |
| "Invalid Android SDK path" or "Missing 'build-tools'" | Set the SDK path in Editor Settings; install Build-Tools 36.1.0 and Platform-Tools in the SDK Manager |
| "Could not find/install platform android-36" or Gradle licence errors | In a terminal run `sdkmanager --licenses` (in `cmdline-tools\latest\bin`) and accept all; install SDK Platform 36 |
| "Unsupported class file major version" / Gradle crashes at start | Godot is using the wrong Java. Point *Java SDK Path* to JDK 17, not 21 or Android Studio's bundled JBR |
| NDK not found | Install NDK 29.0.14206865 in the SDK Manager (SDK Tools tab) |
| `adb devices` shows nothing or `unauthorized` | Cable is charge-only, USB debugging off, or unlock the phone and tap Allow; try another USB port |
| "App not installed" on the phone | An older build signed with another key is installed: uninstall it first |
| Release export fails on signing | Release keystore path, alias `arcade101` and password in the export dialog; they live in `.godot/export_credentials.cfg` |
| Play rejects the upload: "version code already used" | Raise Version Code |
| Play warns about target API level | Keep Godot's default target SDK (36), do not lower it in the preset |
| Play Console says the app uses AD_ID but no declaration | Policy > App content > Advertising ID: answer Yes |
| Screens too close to the notch or gesture bar | Safe areas are handled in `core/ui.gd` (`UI.screen`); report the phone model, edge-to-edge is on in the preset |
| Black flash on start | Boot splash colour is set in Project Settings > Application > Boot Splash |
