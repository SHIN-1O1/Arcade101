extends RefCounted
## Interface every purchase backend implements (IAPService talks only to this).

## Connect to the store. Call on_owned(product_id) for every product the player already owns
## (also when it later turns up, e.g. a pending purchase completing).
func start(_host: Node, _on_owned: Callable) -> void:
	pass


func is_available() -> bool:
	return false


## Start the buy flow. on_result(success: bool, message: String) fires exactly once; message is
## "" when nothing needs saying (e.g. the player cancelled).
func purchase(_product_id: String, on_result: Callable) -> void:
	on_result.call(false, "Purchases are not available here")


## Re-check what the store says the player owns. on_result(found: bool, message: String).
func restore(on_result: Callable) -> void:
	on_result.call(false, "Purchases are not available here")
