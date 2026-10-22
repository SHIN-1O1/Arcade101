extends "res://core/monetization/iap_provider.gd"
## Google Play Billing backend using the official GodotGooglePlayBilling plugin (Godot 4.2+,
## addons/GodotGooglePlayBilling, class BillingClient). Loaded by IAPService only on Android when
## that addon exists. BillingClient is looked up BY NAME at runtime (_bc) and nothing is typed, so
## this file parses cleanly in an editor without the plugin. Never write `BillingClient` directly.
## Not testable in the cloud: needs a Play-signed build installed from a Play testing track.

const Cfg := preload("res://core/monetization/ad_config.gd")
const PRODUCTS: Array[String] = [Cfg.PRODUCT_REMOVE_ADS]
const RECONNECT_DELAY := 5.0

var _host: Node
var _billing
var _on_owned: Callable
var _connected := false
var _details_ready := false
var _purchase_cb := Callable()
var _purchase_id := ""
var _restore_cb := Callable()
static var _billing_script = null


## The plugin's BillingClient script (class_name), found by name so no plugin type is referenced.
static func _bc():
	if _billing_script == null:
		for entry in ProjectSettings.get_global_class_list():
			if entry["class"] == "BillingClient":
				_billing_script = load(entry["path"])
				break
	return _billing_script


func start(host: Node, on_owned: Callable) -> void:
	_host = host
	_on_owned = on_owned
	_billing = _bc().new()
	_billing.connected.connect(_on_connected)
	_billing.disconnected.connect(_on_disconnected)
	_billing.connect_error.connect(func(_code: int, msg: String): _on_disconnected(msg))
	_billing.query_product_details_response.connect(_on_details)
	_billing.query_purchases_response.connect(_on_purchases)
	_billing.on_purchase_updated.connect(_on_purchase_updated)
	_billing.acknowledge_purchase_response.connect(_on_acknowledged)
	host.add_child(_billing)
	_billing.start_connection()


func is_available() -> bool:
	return _connected and _details_ready


# --- Connection -------------------------------------------------------------

func _on_connected() -> void:
	_connected = true
	_billing.query_product_details(PRODUCTS, _bc().ProductType.INAPP)
	_billing.query_purchases(_bc().ProductType.INAPP)  # silent restore on every launch


func _on_disconnected(_msg := "") -> void:
	_connected = false
	_details_ready = false
	if _host != null and _host.is_inside_tree():
		_host.get_tree().create_timer(RECONNECT_DELAY).timeout.connect(func():
			if _billing != null and not _connected:
				_billing.start_connection())


func _on_details(result: Dictionary) -> void:
	_details_ready = result.get("response_code", -1) == _bc().BillingResponseCode.OK
	if not _details_ready:
		push_warning("[IAP] product details failed: %s" % result.get("debug_message", ""))


# --- Purchase ---------------------------------------------------------------

func purchase(product_id: String, on_result: Callable) -> void:
	if not is_available():
		if _connected:  # connected but details missing (e.g. product not active in Play Console yet)
			_billing.query_product_details(PRODUCTS, _bc().ProductType.INAPP)
		on_result.call(false, "Store not ready yet. Check your connection and try again.")
		return
	if _purchase_cb.is_valid():
		on_result.call(false, "")  # one purchase at a time
		return
	_purchase_cb = on_result
	_purchase_id = product_id
	var r: Dictionary = _billing.purchase(product_id)
	if r.get("response_code", -1) != _bc().BillingResponseCode.OK:
		_finish_purchase(false, "Could not open the store.")


func _on_purchase_updated(result: Dictionary) -> void:
	var code: int = result.get("response_code", -1)
	var codes = _bc().BillingResponseCode
	if code == codes.OK:
		var owned_now := false
		var pending := false
		for p in result.get("purchases", []):
			if _purchase_id in p.product_ids or Cfg.PRODUCT_REMOVE_ADS in p.product_ids:
				if p.purchase_state == _bc().PurchaseState.PURCHASED:
					_award(p)
					owned_now = true
				elif p.purchase_state == _bc().PurchaseState.PENDING:
					pending = true
		if owned_now:
			_finish_purchase(true, "")
		elif pending:
			_finish_purchase(false, "Payment pending. Ads will be removed once it completes.")
		else:
			_finish_purchase(false, "")
	elif code == codes.ITEM_ALREADY_OWNED:
		_billing.query_purchases(_bc().ProductType.INAPP)
		_finish_purchase(true, "")  # the query above re-grants and acknowledges it
	elif code == codes.USER_CANCELED:
		_finish_purchase(false, "")
	else:
		_finish_purchase(false, "Purchase failed. You were not charged.")


func _finish_purchase(success: bool, message: String) -> void:
	var cb := _purchase_cb
	_purchase_cb = Callable()
	_purchase_id = ""
	if cb.is_valid():
		cb.call(success, message)


## Grants the product and acknowledges it. Google refunds unacknowledged purchases after 3 days.
func _award(p: Dictionary) -> void:
	for id in p.product_ids:
		_on_owned.call(id)
	if not p.get("is_acknowledged", false):
		_billing.acknowledge_purchase(p.purchase_token)


func _on_acknowledged(result: Dictionary) -> void:
	if result.get("response_code", -1) != _bc().BillingResponseCode.OK:
		push_warning("[IAP] acknowledge failed: %s (retried on next launch)" % result.get("debug_message", ""))


# --- Restore ----------------------------------------------------------------

func restore(on_result: Callable) -> void:
	if not _connected:
		on_result.call(false, "Store not reachable. Check your connection and try again.")
		return
	_restore_cb = on_result
	_billing.query_purchases(_bc().ProductType.INAPP)


func _on_purchases(result: Dictionary) -> void:
	var found := false
	var ok: bool = result.get("response_code", -1) == _bc().BillingResponseCode.OK
	if ok:
		for p in result.get("purchases", []):
			if p.purchase_state == _bc().PurchaseState.PURCHASED:
				_award(p)
				found = true
	var cb := _restore_cb
	_restore_cb = Callable()
	if cb.is_valid():
		cb.call(found, "" if ok else "Could not reach the store. Try again later.")
