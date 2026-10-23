extends SceneTree
## godot --headless -s res://games/mahjong_match/selftest.gd   (solvability only; the bot lives in .godot/)
const Check := preload("res://games/mahjong_match/check.gd")

func _initialize() -> void:
	var lv: Array = JSON.parse_string(FileAccess.get_file_as_string("res://games/mahjong_match/levels.json")).levels
	var t := Time.get_ticks_msec()
	var errors := Check.check_levels(lv, true)
	print("mahjong_match solvability: %d problems in %d ms" % [errors, Time.get_ticks_msec() - t])
	quit(errors)
