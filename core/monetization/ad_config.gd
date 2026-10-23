extends RefCounted
## Ad and purchase configuration. Load with `const Cfg := preload("res://core/monetization/ad_config.gd")`.
##
## Ships with Google's public TEST ad units only. Test units always fill and never earn money, so
## they are safe to click. Never click your own REAL ads: that gets an AdMob account suspended.

# --- Test units (Google's published sample IDs, Android) --------------------
const TEST_APP_ID := "ca-app-pub-3940256099942544~3347511713"  # set in Project Settings > Admob
const TEST_INTERSTITIAL := "ca-app-pub-3940256099942544/1033173712"
const TEST_REWARDED := "ca-app-pub-3940256099942544/5224354917"
const TEST_BANNER := "ca-app-pub-3940256099942544/6300978111"

# ============================================================================
# YOUR REAL IDS GO HERE (see docs/MONETIZATION.md, "Go live").
# Leave empty until the AdMob account and ad units exist. With USE_TEST_ADS false and an
# empty ID, that ad format simply does not load (it never silently falls back to a test unit).
# ============================================================================
const REAL_INTERSTITIAL := ""  # ca-app-pub-XXXXXXXXXXXXXXXX/NNNNNNNNNN
const REAL_REWARDED := ""
const REAL_BANNER := ""

## Flip to false ONLY for the release build you upload to Play. Debug builds and the editor
## always use test units regardless (see use_test_ads()).
const USE_TEST_ADS := true

# --- Pacing rules -----------------------------------------------------------
const INTERSTITIAL_EVERY := 2        # completed (won) levels between interstitials
const INTERSTITIAL_COOLDOWN_SEC := 30  # minimum gap between any two full-screen ads (short levels: 60 s skipped most)
const MIN_LEVEL_INDEX := 1           # 0-based: no interstitial after level 1 of a game (first ad: after level 2)

## Hub banner. Off by default: banners earn little and crowd the portrait layout.
const BANNER_ENABLED := false

# --- Audience / consent -----------------------------------------------------
## Arcade 101 is a general-audience game, NOT directed at children. If you ever opt into Play's
## "Designed for Families" programme, set CHILD_DIRECTED true (ads become non-personalised)
## and read the COPPA/Families section of docs/MONETIZATION.md first.
const CHILD_DIRECTED := false
const UNDER_AGE_OF_CONSENT := false
## Debug builds only: pretend to be in the EEA to test the consent form. Needs your device's
## hashed ID from logcat ("Use new ConsentDebugSettings.Builder().addTestDeviceHashedId(...)").
const DEBUG_FORCE_EEA := false
const DEBUG_TEST_DEVICE_HASH := ""

# --- Purchases --------------------------------------------------------------
const PRODUCT_REMOVE_ADS := "remove_ads"  # must match the Play Console in-app product ID


static func use_test_ads() -> bool:
	return USE_TEST_ADS or OS.is_debug_build()


static func interstitial_id() -> String:
	return TEST_INTERSTITIAL if use_test_ads() else REAL_INTERSTITIAL


static func rewarded_id() -> String:
	return TEST_REWARDED if use_test_ads() else REAL_REWARDED


static func banner_id() -> String:
	return TEST_BANNER if use_test_ads() else REAL_BANNER
