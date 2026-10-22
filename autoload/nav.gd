extends Node
## Scene navigation plus the "currently selected" game/level. Autoloaded as `Nav`.

const HUB := "res://scenes/hub.tscn"
const LEVEL_SELECT := "res://scenes/level_select.tscn"
const GAME_HOST := "res://scenes/game_host.tscn"
const SETTINGS := "res://scenes/settings.tscn"

var game_id := ""
var level_index := 0


func _notification(what: int) -> void:
	# Android back button / gesture.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()


func to_hub() -> void:
	get_tree().change_scene_to_file(HUB)


func to_level_select(id: String) -> void:
	game_id = id
	get_tree().change_scene_to_file(LEVEL_SELECT)


func to_settings() -> void:
	get_tree().change_scene_to_file(SETTINGS)


func play(id: String, level: int) -> void:
	game_id = id
	level_index = level
	get_tree().change_scene_to_file(GAME_HOST)


func back() -> void:
	var current := get_tree().current_scene.scene_file_path
	match current:
		GAME_HOST:
			to_level_select(game_id)
		LEVEL_SELECT, SETTINGS:
			to_hub()
		_:
			get_tree().quit()
