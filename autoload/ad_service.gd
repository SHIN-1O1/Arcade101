extends Node
## Ad policy + provider glue. Autoloaded as `Ads`. Game code and scenes only use the public API:
##   Ads.on_level_finished(won, level_index)  host calls once per finished level
##   Ads.run_after_interstitial(next)         host wraps "go to next screen" (shows an ad if due)
##   Ads.rewarded_available() / Ads.show_rewarded() -> rewarded_finished(granted)   hints, extra undo
##   Ads.show_banner() / hide_banner()        optional hub banner (AdConfig.BANNER_ENABLED)
## The backend is chosen once in _ready(): the AdMob plugin on Android when addons/admob exists,
## otherwise the mock (desktop, CI, tests). See docs/MONETIZATION.md.

const Cfg := preload("res://core/monetization/ad_config.gd")
const BaseProvider := preload("res://core/monetization/ad_provider.gd")
const MockProvider := preload("res://core/monetization/ad_provider_mock.gd")
const ADMOB_PROVIDER_PATH := "res://core/monetization/ad_provider_admob.gd"
const ADMOB_ADDON_CFG := "res://addons/admob/plugin.cfg"

signal rewarded_finished(granted: bool)

var provider  # ad_provider.gd instance
var provider_name := "mock"

var _wins_since_ad := 0
var _due := false  # an interstitial is owed at the next natural break
var _last_ad_msec := -1000000000  # time of the last full-screen ad
var _busy := false  # a full-screen ad is on screen


func _ready() -> void:
	provider = _make_provider()
	provider.start(self, func(): pass)


func _make_provider():
	var on_android := OS.get_name() == "Android"
	if on_android and FileAccess.file_exists(ADMOB_ADDON_CFG):
		var script: GDScript = load(ADMOB_PROVIDER_PATH)
		if script != null and script.can_instantiate():
			provider_name = "admob"
			return script.new()
		push_warning("[Ads] AdMob provider failed to compile, using mock")
	elif on_android:
		# Release build exported without the plugin: show nothing rather than fake ads.
		push_warning("[Ads] AdMob plugin missing from this Android build: no ads will show")
		provider_name = "none"
		return BaseProvider.new()
	return MockProvider.new()


func ads_enabled() -> bool:
	return not Save.has_no_ads()


func _now_msec() -> int:
	return Time.get_ticks_msec()


# --- Interstitials ----------------------------------------------------------

## Call once when a level ends. Only wins count; fails never trigger an ad. `level_index` is
## 0-based (-1 for endless modes). This only RECORDS that an ad may be owed; the ad itself plays
## at the next natural break via run_after_interstitial().
func on_level_finished(won := true, level_index := -1) -> void:
	if not won or not ads_enabled():
		return
	_wins_since_ad += 1
	if _wins_since_ad >= Cfg.INTERSTITIAL_EVERY and (level_index < 0 or level_index >= Cfg.MIN_LEVEL_INDEX):
		_due = true


## True while a full-screen ad is on screen (Nav ignores Back meanwhile).
func is_showing() -> bool:
	return _busy


func interstitial_due() -> bool:
	return (_due and ads_enabled() and not _busy
		and _now_msec() - _last_ad_msec >= Cfg.INTERSTITIAL_COOLDOWN_SEC * 1000
		and provider.is_interstitial_ready())


## Runs `next` right away, or after an interstitial if one is due. Use it for the Next / Levels
## buttons on the result card, never mid-level. `next` is called exactly once.
func run_after_interstitial(next: Callable) -> void:
	if not interstitial_due():
		next.call()
		return
	_due = false
	_wins_since_ad = 0
	_busy = true
	provider.show_interstitial(func():
		_busy = false
		_last_ad_msec = _now_msec()
		next.call())


# --- Rewarded ---------------------------------------------------------------

func rewarded_available() -> bool:
	return provider.is_rewarded_ready() and not _busy


## Rewarded ads stay available to No Ads buyers (they are opt-in). Emits rewarded_finished(granted);
## granted is false when no ad was ready or the player closed it early.
func show_rewarded() -> void:
	if _busy:
		rewarded_finished.emit(false)
		return
	_busy = true
	provider.show_rewarded(func(granted: bool):
		_busy = false
		if granted:
			_last_ad_msec = _now_msec()  # counts toward the interstitial cooldown
		rewarded_finished.emit(granted))


# --- Banner -----------------------------------------------------------------

func show_banner() -> void:
	if ads_enabled() and Cfg.BANNER_ENABLED:
		provider.show_banner()


func hide_banner() -> void:
	provider.hide_banner()


# --- Privacy ----------------------------------------------------------------

func privacy_options_required() -> bool:
	return provider.privacy_options_required()


func show_privacy_options() -> void:
	provider.show_privacy_options(func(): pass)
