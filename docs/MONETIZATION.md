# Ads and "No Ads" purchase: setup guide

What is built (all in code, works today with no plugin installed):

| Piece | Where | Behaviour |
|---|---|---|
| Ad policy | `autoload/ad_service.gd` (`Ads`) | Interstitial after every 2nd **won** level (one value: `INTERSTITIAL_EVERY` in `ad_config.gd`), at least 60 s apart, never after level 1, never after a fail, never mid-level (plays when the player taps Next or Levels on the result card). Off for No Ads buyers. |
| Ad IDs and switches | `core/monetization/ad_config.gd` | Google **test** ad units only. A marked place for your real IDs. Banner flag, consent and audience flags. |
| Ad backends | `core/monetization/ad_provider_*.gd` | `mock` (desktop, CI, any build without the plugin) and `admob` (Android + AdMob plugin). |
| Purchase | `autoload/iap_service.gd` (`IAP`) | One non-consumable product `remove_ads`. Buy, restore (also silently at every launch), acknowledge. |
| Purchase backends | `core/monetization/iap_provider_*.gd` | `mock` (always succeeds) and `play` (Google Play Billing plugin). |
| UI | hub "No Ads" button, Settings "Restore purchases" and "Privacy settings" | The hub button disappears after a purchase. "Privacy settings" appears only for EU/UK players. |

**What was NOT tested:** real ads and real purchases. They need an Android device and a build installed from Google Play. The code was checked against the plugins' published APIs and compiles against their GDScript layer in Godot 4.7.2, and the mock paths run in the smoke test. Expect to fix small things on the first device run.

Plugins (both free, open source):
- **AdMob**: "AdMob" by Poing Studios (`poingstudios/godot-admob-plugin`, v5.x, needs Godot 4.5+, you use 4.7.2).
- **Billing**: "Godot Google Play Billing" (`godot-sdk-integrations/godot-google-play-billing`, official, Godot 4.2+).

CI runs Godot 4.3 and never loads these plugins, so it stays green without them. The real provider scripts look the plugin classes up by name at runtime, so the editor shows no errors while the plugins are not installed (and none are needed to start installing them).

---

## Part 1. Install the plugins (Windows, Godot 4.7.2)

1. **Android build template**: Godot > `Project > Install Android Build Template`. This creates `android/` (commit it).
2. **AdMob plugin**: AssetLib tab > search `AdMob` > publisher **Poing Studios** > Download > Install (leave "Ignore asset root" unticked). Then `Project > Project Settings > Plugins` > tick **AdMob**. The Android library downloads itself. If it does not: `Project > Tools > AdMob Manager > Android > Download & Install`.
3. **Billing plugin**: AssetLib > search `Godot Google Play Billing` > Download > Install (leave "Ignore asset root" unticked, so it lands in `addons/GodotGooglePlayBilling/`). Plugins > tick **GodotGooglePlayBilling**.
4. Project Settings (turn on **Advanced Settings** top right) > General > **Admob** > General > under **Android** tick **Enabled** and paste the AdMob **App ID** (looks like `ca-app-pub-1234567890123456~1234567890`, contains a `~`). While testing use Google's sample App ID: `ca-app-pub-3940256099942544~3347511713`.
5. `Project > Export > Add > Android`. Tick **Use Gradle Build**. Set *Unique Name* (package, e.g. `com.shin1o1.arcade101`), keep it forever. Set *Min SDK* 24 or higher. Sign with your release keystore (see README, "Android export").
6. Commit `addons/` and `android/`. The big native libraries are in `.gitignore` and are re-downloaded by the plugin on each machine.
7. If CI starts failing after adding addons (they target newer Godot than CI's 4.3), change `GODOT_VERSION` in `.github/workflows/smoke-test.yml` to `4.7.2`.

Check: run on a phone with USB debugging. In the logs (`adb logcat -s poing-godot-admob godot`) you should see the ads initialise, and an interstitial after finishing two levels (after levels 2, 4, 6..., never after level 1, and never twice within 60 s). Test ads are labelled "Test Ad".

## Part 2. AdMob account, app and ad units

1. Go to https://admob.google.com and sign in with a Google account. Accept the terms, pick country and time zone, currency. **These cannot be changed later.**
2. **Apps > Add app** > Android > "No, the app is not published yet" (you can link it to Play later) > name it "Arcade 101". Copy the **App ID** (`...~...`).
3. Open the app > **Ad units > Add ad unit**. Create:
   - **Interstitial** named `interstitial_between_levels`
   - **Rewarded** named `rewarded_hint` (only needed once a game uses hints or extra undo)
   - **Banner** named `banner_hub` (optional, banner is off by default)
   Copy each **Ad unit ID** (contains a `/`).
4. **Payments**: add your payment info and verify your address (Google mails a PIN for some countries). Not needed to test, needed to get paid.
5. **Privacy & messaging** (left menu) > **European regulations** > create a message (Consent, the standard one) and apply it to the app. This is the consent form EU/UK players see. Also set up **US states regulations** if offered.
6. Later, when the app is on Play: **Apps > Arcade 101 > App settings > Link to Google Play** so AdMob can verify the app. New apps can show limited ads until reviewed. This is normal.

## Part 3. Play Console app and the No Ads product

1. https://play.google.com/console, create a developer account (one-time US$25, identity verification takes days, start early).
2. **Create app**: name "Arcade 101", default language, App (not game category yet), **Free**, accept declarations.
3. Complete the **Dashboard set-up tasks**: app access (all features available), **Ads: Yes, contains ads**, content rating questionnaire, target audience (see COPPA section: choose **18+ / 13+ general audience**, not children), data safety form, privacy policy URL (Part 5).
4. **Monetise with Play > Products > In-app products > Create product**:
   - Product ID: `remove_ads` (exactly, matches `PRODUCT_REMOVE_ADS` in `ad_config.gd`; cannot be changed later)
   - Name: "Remove Ads", description: "Remove all ads for good. One-time purchase."
   - Price: for example US$2.99 (you can set other countries after).
   - Save and **Activate**. (Console menus move around; look for "In-app products", **not** Subscriptions.)
   Billing only works once the app has an uploaded build and the product is active.
5. **Licence testers** (so you can buy without paying): Play Console home (not inside an app) > **Settings > License testing** > add the Gmail addresses of your test phones > set licence response `RESPOND_NORMALLY`. Those accounts can "buy" for free (test cards) on builds installed from Play.
6. **Upload to internal testing**:
   1. In Godot export an **Android App Bundle**: Export dialog > *Gradle Build* ticked > **Export Format: Export AAB**, release keystore set, *Export With Debug* **off**. Raise **Version Code** every upload.
   2. Play Console > your app > **Testing > Internal testing > Create new release** > upload the `.aab`. Accept **Play App Signing**.
   3. **Testers** tab > create an email list, add yourself and your licence testers > save > copy the **opt-in link**, open it on the phone with that Google account, install from Play.
   4. Test: levels 1-3 then an ad appears, tap **No Ads**, buy (test card), ads stop and the button disappears. Uninstall, reinstall from Play, open Settings > **Restore purchases**: No Ads comes back.

## Part 4. Go live (only after Part 3 works)

1. Open `core/monetization/ad_config.gd`:
   - Paste your three real ad unit IDs into `REAL_INTERSTITIAL`, `REAL_REWARDED`, `REAL_BANNER`.
   - Set `USE_TEST_ADS := false` **only for the release build**. Debug builds and the editor always use test ads, whatever this says (safety net: clicking your own real ads gets AdMob accounts banned).
   - Project Settings > Admob > Android > App ID = your real App ID.
2. Never tap real ads on your own phone. Use test builds for all testing.
3. Optional banner on the hub: `BANNER_ENABLED := true` (and keep the banner ad unit). Off is fine.
4. Rewarded ads: call `Ads.rewarded_available()` to decide whether to show a "Watch ad for a hint" button, then `Ads.show_rewarded()` and listen to `Ads.rewarded_finished(granted)`. Games must keep this opt-in. Rewarded ads still work for No Ads buyers.

## Part 5. Privacy, consent, children

- Privacy policy: fill the `[[...]]` markers in `docs/PRIVACY_POLICY.md`, host it on a public page (docs/RELEASE.md, "Privacy policy page") and paste the URL into Play Console and AdMob.
- **EU/UK consent (GDPR/UMP)** is built in: at each launch the plugin asks Google's User Messaging Platform whether this player needs a consent form, shows it if so (message created in Part 2 step 5), and only starts ads when consent is not outstanding. EU/UK players can reopen their choices from Settings > **Privacy settings**. Test it by setting `DEBUG_FORCE_EEA := true` and your phone's hashed ID in `ad_config.gd` (the ID is printed in `adb logcat` the first time), debug build only.
- **COPPA / Families:** Arcade 101 is a general-audience game, not aimed at children, so `CHILD_DIRECTED` is false and Play target audience should exclude under-13s. If you ever target children or join "Designed for Families": set `CHILD_DIRECTED := true`, use only Google-certified ad networks (AdMob qualifies when configured as child-directed), no personalised ads, review the Families Policy, and expect stricter review. Do not mix: do not tick "children" in Play without setting this flag. Misusing the child-directed flag can get an AdMob account terminated.
- Data safety form (Play Console): declare that the app uses **Advertising ID**, **device or other IDs**, **app interactions / diagnostics** shared with Google (AdMob), and **purchase history** (Play Billing). Nothing else is collected; progress stays on the phone.
- Ads default to a maximum content rating of PG.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| No ads at all on device | AdMob **Enabled** + App ID not set in Project Settings; plugin not enabled; EEA consent form dismissed without a choice (by design no ads then). |
| Log says "AdMob plugin missing from this Android build" | `addons/admob` not committed, or Gradle build off. |
| "Store not ready yet" when buying | Build was not installed from Play, product not Active, or account not a licence tester/internal tester. |
| Purchase works but ads return after reinstall | Use Settings > Restore purchases (same Google account). |
| Ad shown twice in a row | Should not happen: 60 s cooldown. Check `ad_config.gd` has not been edited. |
| New AdMob units show nothing | New units take up to an hour to start serving. |

Refunded purchases are not revoked automatically (keeps the player from losing access when offline). Rare, acceptable.
