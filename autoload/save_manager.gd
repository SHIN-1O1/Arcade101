extends Node
## Persists progress, settings and purchase flags to user://save.json.
## Autoloaded as `Save`.

signal settings_changed(key: String, value: Variant)
signal no_ads_changed(enabled: bool)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 3  # 2: added "highscores", 3: added "howto_hidden" (both additive, old saves load unchanged)

var data: Dictionary = {}


func _ready() -> void:
	load_game()


func _default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"settings": {"sound": true, "music": true, "vibration": true},
		"no_ads": false,
		"progress": {},  # game_id -> {"stars": [int per level]}
		"highscores": {},  # game_id -> best endless score
		"howto_hidden": {},  # game_id -> true once "Don't show again" was tapped on its how-to-play card
	}


func load_game() -> void:
	data = _default_data()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file unreadable, starting fresh")
		return
	# Merge so new default keys survive old saves.
	for key in parsed:
		if key == "settings" and typeof(parsed[key]) == TYPE_DICTIONARY:
			data.settings.merge(parsed[key], true)
		else:
			data[key] = parsed[key]
	data.version = SAVE_VERSION
	if typeof(data.get("highscores")) != TYPE_DICTIONARY:
		data.highscores = {}
	if typeof(data.get("howto_hidden")) != TYPE_DICTIONARY:
		data.howto_hidden = {}


func save_game() -> void:
	# Write to a temp file then rename, so a crash mid-write never corrupts the save.
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write save: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(tmp, SAVE_PATH)


# --- Progress ---------------------------------------------------------------

func _stars_array(game_id: String) -> Array:
	if not data.progress.has(game_id):
		data.progress[game_id] = {"stars": []}
	return data.progress[game_id].stars


func get_stars(game_id: String, level: int) -> int:
	var arr := _stars_array(game_id)
	return int(arr[level]) if level < arr.size() else 0


func is_unlocked(game_id: String, level: int) -> bool:
	return level == 0 or get_stars(game_id, level - 1) > 0


func total_stars(game_id: String) -> int:
	var total := 0
	for s in _stars_array(game_id):
		total += int(s)
	return total


## Records a finished level. Keeps the best star count. Returns true if improved.
func record_result(game_id: String, level: int, stars: int) -> bool:
	var arr := _stars_array(game_id)
	while arr.size() <= level:
		arr.append(0)
	if stars <= int(arr[level]):
		return false
	arr[level] = clampi(stars, 0, 3)
	save_game()
	return true


# --- Endless high scores ----------------------------------------------------

func get_high_score(game_id: String) -> int:
	return int(data.highscores.get(game_id, 0))


## Records an endless run's final score. Returns true if it beat the previous best.
func record_score(game_id: String, score: int) -> bool:
	if score <= get_high_score(game_id):
		return false
	data.highscores[game_id] = score
	save_game()
	return true


# --- How-to-play card -------------------------------------------------------

## True when the player asked not to see this game's how-to-play card on load (the "i" button still opens it).
func is_howto_hidden(game_id: String) -> bool:
	return bool(data.howto_hidden.get(game_id, false))


func set_howto_hidden(game_id: String, hidden: bool) -> void:
	data.howto_hidden[game_id] = hidden
	save_game()


# --- Settings ---------------------------------------------------------------

func get_setting(key: String) -> Variant:
	return data.settings.get(key)


func set_setting(key: String, value: Variant) -> void:
	data.settings[key] = value
	save_game()
	settings_changed.emit(key, value)


# --- Purchases --------------------------------------------------------------

func has_no_ads() -> bool:
	return bool(data.no_ads)


func set_no_ads(enabled: bool) -> void:
	data.no_ads = enabled
	save_game()
	no_ads_changed.emit(enabled)


func reset_all() -> void:
	var keep_no_ads := has_no_ads()  # purchases survive a progress reset
	data = _default_data()
	data.no_ads = keep_no_ads
	save_game()
