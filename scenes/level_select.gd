extends Control
## 5-column grid of levels with lock state and best stars.

const COLUMNS := 5


func _ready() -> void:
	var id := Nav.game_id
	var game := Games.get_game(id)
	var col := UI.screen(self)

	var top := HBoxContainer.new()
	col.add_child(top)
	var back := UI.button("<", Nav.to_hub)
	back.custom_minimum_size = Vector2(96, 96)
	top.add_child(back)
	var title := UI.label(game.get("name", id), 48, UI.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UI.label("★ %d" % Save.total_stars(id), 34))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)

	var color := Color(game.get("color", "#2b2d42"))
	for i in Games.level_count(id):
		grid.add_child(_level_button(id, i, color))


func _level_button(id: String, i: int, color: Color) -> Button:
	var unlocked := Save.is_unlocked(id, i)
	var text := "%d\n%s" % [i + 1, UI.stars_text(Save.get_stars(id, i))] if unlocked else "🔒\n%d" % (i + 1)
	var b := UI.button(text, func(): Nav.play(id, i), color, 26)
	b.custom_minimum_size = Vector2(0, 120)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = not unlocked
	return b
