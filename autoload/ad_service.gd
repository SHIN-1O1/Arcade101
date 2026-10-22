extends Node
## Placeholder ad service. Autoloaded as `Ads`.
## Swap the bodies of the _provider_* functions for a real SDK plugin
## (e.g. an AdMob Godot plugin) later; game code only calls the public API.

signal rewarded_finished(granted: bool)

## Show an interstitial at most once every N completed levels.
const INTERSTITIAL_EVERY := 3

var _levels_since_ad := 0


func ads_enabled() -> bool:
	return not Save.has_no_ads()


## Call after each level ends. Shows an interstitial when the cap allows.
func on_level_finished() -> void:
	if not ads_enabled():
		return
	_levels_since_ad += 1
	if _levels_since_ad >= INTERSTITIAL_EVERY:
		_levels_since_ad = 0
		_provider_show_interstitial()


## Rewarded ads still work for no-ads buyers (they are opt-in).
## Emits rewarded_finished(granted) when done.
func show_rewarded() -> void:
	_provider_show_rewarded()


func show_banner() -> void:
	if ads_enabled():
		print("[Ads] banner shown (stub)")


func hide_banner() -> void:
	print("[Ads] banner hidden (stub)")


# --- Provider stubs ---------------------------------------------------------

func _provider_show_interstitial() -> void:
	print("[Ads] interstitial shown (stub)")


func _provider_show_rewarded() -> void:
	print("[Ads] rewarded shown (stub), granting reward")
	await get_tree().create_timer(0.3).timeout
	rewarded_finished.emit(true)
