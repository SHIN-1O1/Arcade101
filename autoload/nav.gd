extends Node
## Scene navigation plus the "currently selected" game/level. Autoloaded as `Nav`.
## Screens slide like a phone app: going deeper pushes the new screen in from the
## right, going back slides the current one off to the right. Input is blocked
## while a transition runs, and calls made during one are ignored.

const HUB := "res://scenes/hub.tscn"
const LEVEL_SELECT := "res://scenes/level_select.tscn"
const GAME_HOST := "res://scenes/game_host.tscn"
const SETTINGS := "res://scenes/settings.tscn"

const SLIDE_TIME := 0.34
const PARALLAX := 0.3  # how far the screen underneath moves, as a share of the width
const UNDER_TINT := Color(0.55, 0.55, 0.65)  # the screen underneath dims a little

var game_id := ""
var level_index := 0
var mode := "levels"  # "levels" or "endless" for the game being played

var _busy := false
var _blocker: Control


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_blocker = Control.new()
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.visible = false
	layer.add_child(_blocker)


func _notification(what: int) -> void:
	# Android back button / gesture.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()


func is_transitioning() -> bool:
	return _busy


func to_hub() -> void:
	_go(HUB, false)


func to_level_select(id: String) -> void:
	if _busy:
		return  # don't change the selection while a slide still shows the old one
	game_id = id
	_go(LEVEL_SELECT, _current() != GAME_HOST)


func to_settings() -> void:
	_go(SETTINGS, true)


## Hub card tap: endless-only games start straight away, level-only games open the level
## list. Games with both modes are handled by the hub's mode picker (see hub.gd).
func open_game(id: String) -> void:
	if Games.has_levels(id):
		to_level_select(id)
	else:
		play_endless(id)


func play_endless(id: String) -> void:
	if _busy:
		return
	game_id = id
	mode = "endless"
	_go(GAME_HOST, true)


func play(id: String, level: int) -> void:
	if _busy:
		return  # else the host would save this level's result under the new index
	game_id = id
	mode = "levels"
	level_index = level
	_go(GAME_HOST, true)


func back() -> void:
	# During a full-screen ad, leaving would let the ad's close callback (Next / Levels)
	# drag the player back to wherever the card was heading.
	if _busy or Ads.is_showing():
		return
	# A screen with a popup open (hub mode picker) closes that first.
	var scene := get_tree().current_scene
	if scene and scene.has_method("handle_back") and scene.handle_back():
		return
	match _current():
		GAME_HOST:
			if mode == "endless":
				to_hub()
			else:
				to_level_select(game_id)
		LEVEL_SELECT, SETTINGS:
			to_hub()
		_:
			get_tree().quit()


func _current() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path if scene else ""


## Swaps scenes with a slide. Both screens stay alive until the slide ends, so it
## is one smooth tween (no screenshot, no fade to black), cheap on low-end phones.
func _go(path: String, forward: bool) -> void:
	var tree := get_tree()
	var old := tree.current_scene as Control
	if _busy:
		return
	if old == null:
		tree.change_scene_to_file(path)
		return
	_busy = true
	Feedback.play_music("game" if path == GAME_HOST else "menu")
	_blocker.visible = true
	var new := (load(path) as PackedScene).instantiate() as Control
	old.process_mode = Node.PROCESS_MODE_DISABLED
	tree.root.add_child(new)
	tree.current_scene = new
	var w := old.get_viewport_rect().size.x
	# The moving screen is drawn on top; the other sits underneath, shifted and dimmed.
	var top := new if forward else old
	var under := old if forward else new
	tree.root.move_child(top, -1)
	new.position.x = w if forward else -w * PARALLAX
	if not forward:
		new.modulate = UNDER_TINT
	# Let the new screen build its first frame before moving anything, so a slow
	# _ready() costs a frame of waiting instead of a jump in the slide.
	await tree.process_frame
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if forward:
		tw.tween_property(top, "position:x", 0.0, SLIDE_TIME)
		tw.tween_property(under, "position:x", -w * PARALLAX, SLIDE_TIME)
		tw.tween_property(under, "modulate", UNDER_TINT, SLIDE_TIME)
	else:
		tw.tween_property(top, "position:x", w, SLIDE_TIME)
		tw.tween_property(under, "position:x", 0.0, SLIDE_TIME)
		tw.tween_property(under, "modulate", Color.WHITE, SLIDE_TIME)
	await tw.finished
	old.queue_free()
	new.position = Vector2.ZERO
	new.modulate = Color.WHITE
	_blocker.visible = false
	_busy = false
