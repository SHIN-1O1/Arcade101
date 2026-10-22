extends RefCounted
## Interface every ad backend implements (AdService talks only to this). No class_name on
## purpose, see CLAUDE.md "Look and feel". Callbacks are Callables so providers stay decoupled.

## Initialise the SDK (after consent, if the backend needs it), then call on_done().
func start(_host: Node, on_done: Callable) -> void:
	on_done.call()


func is_interstitial_ready() -> bool:
	return false


## Show the interstitial; on_closed() fires exactly once when it was dismissed or failed.
func show_interstitial(on_closed: Callable) -> void:
	on_closed.call()


func is_rewarded_ready() -> bool:
	return false


## Show a rewarded ad; on_result(granted: bool) fires exactly once.
func show_rewarded(on_result: Callable) -> void:
	on_result.call(false)


func show_banner() -> void:
	pass


func hide_banner() -> void:
	pass


## EU/UK users must be able to reopen the consent choices (UMP "privacy options").
func privacy_options_required() -> bool:
	return false


func show_privacy_options(on_done: Callable) -> void:
	on_done.call()
