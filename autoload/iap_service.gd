extends Node
## Placeholder in-app purchase service. Autoloaded as `IAP`.
## Replace _provider_* with the Google Play Billing plugin (Android) and
## StoreKit (iOS) later. Only one product for now: remove_ads.

signal purchase_finished(product_id: String, success: bool)

const REMOVE_ADS := "remove_ads"


func purchase(product_id: String) -> void:
	_provider_purchase(product_id)


func restore_purchases() -> void:
	print("[IAP] restore purchases (stub)")
	# A real provider reports owned products; the stub restores nothing.


func _grant(product_id: String) -> void:
	if product_id == REMOVE_ADS:
		Save.set_no_ads(true)
		Ads.hide_banner()


# --- Provider stubs ---------------------------------------------------------

func _provider_purchase(product_id: String) -> void:
	print("[IAP] purchasing %s (stub, auto-success)" % product_id)
	await get_tree().create_timer(0.3).timeout
	_grant(product_id)
	purchase_finished.emit(product_id, true)
