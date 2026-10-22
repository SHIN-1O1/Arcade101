extends Control
## Hosts any BaseGame: top bar, live star meter, game area, result overlay, saving and ads.

const ResultOverlay := preload("res://scenes/result_overlay.gd")

var _game_def: Dictionary
var _levels: Array
var _game: BaseGame
var _area: Control
var _status: Label
var _meter: UI.StarMeter
var _overlay: Control


func _ready() -> void:
	_game_def = Games.get_game(Nav.game_id)
	_levels = Games.get_levels(Nav.game_id)
	var col := UI.screen(self, UI.ACCENT, false)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	col.add_child(top)
	top.add_child(UI.icon_button("back", func(): Nav.to_level_select(Nav.game_id)))
	var title := UI.title("%s  ·  Level %d" % [_game_def.get("name", ""), Nav.level_index + 1], 36, Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UI.icon_button("restart", _start))

	_status = UI.label("", 28, UI.ACCENT)
	col.add_child(_status)
	_meter = UI.StarMeter.new()
	_meter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_meter.visible = false  # shown once the game reports progress
	col.add_child(_meter)

	_area = Control.new()
	_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_area.clip_contents = true
	col.add_child(_area)
	Ads.hide_banner()
	_start()


func _start() -> void:
	var restart := _game != null
	if _overlay:
		_overlay.close()
		_overlay = null
	if _game:
		_game.queue_free()
	var scene: PackedScene = load(_game_def.scene)
	_game = scene.instantiate()
	_game.set_anchors_preset(Control.PRESET_FULL_RECT)
	_area.add_child(_game)
	_game.finished.connect(_on_finished)
	_game.status_changed.connect(func(t): _status.text = t)
	_game.star_progress.connect(func(v: float, lower: bool):
		_meter.visible = true
		_meter.set_progress(v, _levels[Nav.level_index].get("stars", []), lower))
	_status.text = ""
	_game.start_level(_levels[Nav.level_index], Nav.level_index)
	if restart:  # fresh board fades and grows in instead of snapping
		_game.pivot_offset = _area.size / 2.0
		_game.modulate.a = 0.0
		_game.scale = Vector2(0.96, 0.96)
		var tw := _game.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_game, "modulate:a", 1.0, 0.28)
		tw.tween_property(_game, "scale", Vector2.ONE, 0.32)


func _on_finished(won: bool, stars: int) -> void:
	var best := false
	if won:
		var had := Save.get_stars(Nav.game_id, Nav.level_index)
		best = Save.record_result(Nav.game_id, Nav.level_index, stars) and had > 0
		Feedback.sfx("win")
		Feedback.vibrate(60)
	else:
		Feedback.sfx("fail")
		Feedback.vibrate(120)
	Ads.on_level_finished(won, Nav.level_index)
	_show_result(won, stars, best)


func _show_result(won: bool, stars: int, best: bool) -> void:
	var o := ResultOverlay.new()
	o.won = won
	o.stars = stars
	o.stat = _status.text
	o.new_best = best
	o.accent = Color(_game_def.get("color", "#FF8A1F"))
	if Nav.level_index + 1 < _levels.size():
		o.on_next = func(): Ads.run_after_interstitial(func(): Nav.play(Nav.game_id, Nav.level_index + 1))
	o.on_retry = _start
	o.on_levels = func(): Ads.run_after_interstitial(func(): Nav.to_level_select(Nav.game_id))
	_overlay = o
	add_child(o)
