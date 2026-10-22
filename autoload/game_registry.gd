extends Node
## Reads data/games.json and each game's levels.json. Autoloaded as `Games`.
## Adding a game = add a folder under res://games/ and one entry in games.json.

const REGISTRY_PATH := "res://data/games.json"

var games: Array = []
var _levels_cache: Dictionary = {}


func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		games = parsed.get("games", [])
	else:
		push_error("Invalid %s" % REGISTRY_PATH)


func get_game(id: String) -> Dictionary:
	for g in games:
		if g.id == id:
			return g
	return {}


func get_levels(id: String) -> Array:
	if _levels_cache.has(id):
		return _levels_cache[id]
	var path := "res://games/%s/levels.json" % id
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var levels: Array = parsed.get("levels", []) if typeof(parsed) == TYPE_DICTIONARY else []
	if levels.is_empty():
		push_error("No levels in %s" % path)
	_levels_cache[id] = levels
	return levels


func level_count(id: String) -> int:
	return get_levels(id).size()
