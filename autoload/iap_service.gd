extends Node
## In-app purchases. Autoloaded as `IAP`. One product: the non-consumable "remove_ads".
##   IAP.purchase()            buy it (hub No Ads button)
##   IAP.restore_purchases()   re-check the store (Settings button; also done silently at launch)
## Both end with a signal; `message` is player-facing text ("" = nothing to show).
## Backend: GodotGooglePlayBilling on Android when addons/GodotGooglePlayBilling exists, otherwise a
## mock that always succeeds (desktop, CI). See docs/MONETIZATION.md.

const Cfg := preload("res://core/monetization/ad_config.gd")
const BaseProvider := preload("res://core/monetization/iap_provider.gd")
const MockProvider := preload("res://core/monetization/iap_provider_mock.gd")
const PLAY_PROVIDER_PATH := "res://core/monetization/iap_provider_play.gd"
const PLAY_ADDON_CFG := "res://addons/GodotGooglePlayBilling/plugin.cfg"

const REMOVE_ADS := Cfg.PRODUCT_REMOVE_ADS

signal purchase_finished(product_id: String, success: bool)
signal purchase_message(message: String)
signal restore_finished(found: bool, message: String)
signal busy_changed(busy: bool)

var provider  # iap_provider.gd instance
var provider_name := "mock"
var busy := false


func _ready() -> void:
	provider = _make_provider()
	provider.start(self, _grant)


func _make_provider():
	if OS.get_name() == "Android":
		if FileAccess.file_exists(PLAY_ADDON_CFG):
			var script: GDScript = load(PLAY_PROVIDER_PATH)
			if script != null and script.can_instantiate():
				provider_name = "play"
				return script.new()
			push_warning("[IAP] Play Billing provider failed to compile, purchases disabled")
		else:
			push_warning("[IAP] GodotGooglePlayBilling plugin missing from this Android build")
		provider_name = "none"
		return BaseProvider.new()
	return MockProvider.new()


func purchase(product_id := REMOVE_ADS) -> void:
	if busy:
		return
	_set_busy(true)
	provider.purchase(product_id, func(success: bool, message: String):
		_set_busy(false)
		if message != "":
			purchase_message.emit(message)
		purchase_finished.emit(product_id, success))


func restore_purchases() -> void:
	if busy:
		return
	_set_busy(true)
	provider.restore(func(found: bool, message: String):
		_set_busy(false)
		restore_finished.emit(found, message))


func _set_busy(on: bool) -> void:
	busy = on
	busy_changed.emit(on)


## Idempotent: called for every owned product, at launch, on purchase and on restore.
func _grant(product_id: String) -> void:
	if product_id == REMOVE_ADS and not Save.has_no_ads():
		Save.set_no_ads(true)
		Ads.hide_banner()
