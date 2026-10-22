extends "res://core/monetization/iap_provider.gd"
## Desktop / test / CI backend: purchases succeed after a short delay, nothing is really bought.

var owned: Array[String] = []  # what restore() will "find"; tests can set this
var succeed := true
var _host: Node
var _on_owned: Callable


func start(host: Node, on_owned: Callable) -> void:
	_host = host
	_on_owned = on_owned


func is_available() -> bool:
	return true


func purchase(product_id: String, on_result: Callable) -> void:
	print("[IAP/mock] purchasing %s" % product_id)
	if _host != null and _host.is_inside_tree():
		await _host.get_tree().create_timer(0.3).timeout
	if succeed:
		owned.append(product_id)
		_on_owned.call(product_id)
	on_result.call(succeed, "" if succeed else "Purchase failed (mock)")


func restore(on_result: Callable) -> void:
	for id in owned:
		_on_owned.call(id)
	on_result.call(not owned.is_empty(), "")
