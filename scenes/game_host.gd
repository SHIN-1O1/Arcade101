extends Control
## Hosts any BaseGame: top bar, game area, result overlay, saving and ads.

var _game_def: Dictionary
var _levels: Array
var _game: BaseGame
var _area: Control
var _status: Label
var _overlay: Control


func _ready() -> void:
	_game_def = Games.get_game(Nav.game_id)
	_levels = Games.get_levels(Nav.game_id)
	var col := UI.screen(self)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	col.add_child(top)
	var back := UI.button("<", func(): Nav.to_level_select(Nav.game_id))
	back.custom_minimum_size = Vector2(96, 96)
	top.add_child(back)
	var title := UI.label("%s  ·  Level %d" % [_game_def.get("name", ""), Nav.level_index + 1], 32)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var restart := UI.button("↻", _start)
	restart.custom_minimum_size = Vector2(96, 96)
	top.add_child(restart)

	_status = UI.label("", 28, UI.ACCENT)
	col.add_child(_status)

	_area = Control.new()
	_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_area.clip_contents = true
	col.add_child(_area)
	Ads.hide_banner()
	_start()


func _start() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null
	if _game:
		_game.queue_free()
	var scene: PackedScene = load(_game_def.scene)
	_game = scene.instantiate()
	_game.set_anchors_preset(Control.PRESET_FULL_RECT)
	_area.add_child(_game)
	_game.finished.connect(_on_finished)
	_game.status_changed.connect(func(t): _status.text = t)
	_status.text = ""
	_game.start_level(_levels[Nav.level_index], Nav.level_index)


func _on_finished(won: bool, stars: int) -> void:
	if won:
		Save.record_result(Nav.game_id, Nav.level_index, stars)
		Feedback.sfx("win")
		Feedback.vibrate(60)
	else:
		Feedback.sfx("lose")
		Feedback.vibrate(120)
	Ads.on_level_finished()
	_show_result(won, stars)


func _show_result(won: bool, stars: int) -> void:
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0, 0, 0, 0.7)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(UI.CARD, 32))
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)

	box.add_child(UI.label("Level complete!" if won else "Try again", 48, UI.GOOD if won else UI.BAD))
	if won:
		box.add_child(UI.label(UI.stars_text(stars), 72, UI.ACCENT))
	var has_next := Nav.level_index + 1 < _levels.size()
	if won and has_next:
		box.add_child(UI.button("Next", func(): Nav.play(Nav.game_id, Nav.level_index + 1), UI.GOOD))
	box.add_child(UI.button("Retry", _start))
	box.add_child(UI.button("Levels", func(): Nav.to_level_select(Nav.game_id)))
