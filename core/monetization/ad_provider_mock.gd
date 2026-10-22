extends "res://core/monetization/ad_provider.gd"
## Desktop / test / CI backend: no SDK, ads "show" instantly. Used whenever the AdMob plugin is
## absent or the build is not Android, so the smoke test needs nothing installed.

var shown_interstitials := 0
var shown_rewarded := 0
var grant_rewarded := true
var banner_visible := false
var _host: Node


func start(host: Node, on_done: Callable) -> void:
	_host = host
	on_done.call()


func is_interstitial_ready() -> bool:
	return true


func show_interstitial(on_closed: Callable) -> void:
	shown_interstitials += 1
	print("[Ads/mock] interstitial shown")
	on_closed.call()


func is_rewarded_ready() -> bool:
	return true


func show_rewarded(on_result: Callable) -> void:
	shown_rewarded += 1
	print("[Ads/mock] rewarded shown, granted=%s" % grant_rewarded)
	if _host != null and _host.is_inside_tree():
		await _host.get_tree().create_timer(0.3).timeout
	on_result.call(grant_rewarded)


func show_banner() -> void:
	banner_visible = true
	print("[Ads/mock] banner shown")


func hide_banner() -> void:
	banner_visible = false
