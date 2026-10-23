extends "res://core/monetization/ad_provider.gd"
## Desktop / test / CI backend: no SDK, ads "show" instantly. Used whenever the AdMob plugin is
## absent or the build is not Android, so the smoke test needs nothing installed.
## With a display (editor, desktop playtest) the interstitial is a visible stand-in card for
## MOCK_AD_SEC so pacing can be checked by eye; headless runs close it instantly.

const MOCK_AD_SEC := 2.0

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
	if DisplayServer.get_name() == "headless" or _host == null or not _host.is_inside_tree():
		on_closed.call()
		return
	var layer := CanvasLayer.new()
	layer.layer = 128
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # swallows taps like a real full-screen ad
	layer.add_child(bg)
	var l := Label.new()
	l.text = "TEST AD\n(interstitial stand-in)"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 48)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(l)
	_host.get_tree().root.add_child(layer)
	await _host.get_tree().create_timer(MOCK_AD_SEC).timeout
	layer.queue_free()
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
