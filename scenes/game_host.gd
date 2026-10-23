extends Control
## Hosts any BaseGame: top bar, live star meter, game area, result overlay, saving and ads.

const ResultOverlay := preload("res://scenes/result_overlay.gd")
const HowToPlay := preload("res://scenes/how_to_play.gd")
const PauseOverlay := preload("res://scenes/pause_overlay.gd")
const FX := preload("res://core/fx.gd")

var _game_def: Dictionary
var _levels: Array
var _game: BaseGame
var _area: Control
var _status: Label
var _meter: UI.StarMeter
var _score_bar: ScoreBar
var _overlay: Control
var _how_to: Control
var _endless := false
var _pause_card: Control  # shown while the app is in the background / unfocused


func _ready() -> void:
	_game_def = Games.get_game(Nav.game_id)
	_endless = Nav.mode == "endless"
	_levels = [] if _endless else Games.get_levels(Nav.game_id)
	var col := UI.screen(self, UI.ACCENT, false)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	col.add_child(top)
	top.add_child(UI.icon_button("back", func(): Nav.back()))
	var title_text: String = _game_def.get("name", "") if _endless \
		else "%s  ·  Level %d" % [_game_def.get("name", ""), Nav.level_index + 1]
	var title := UI.title(title_text, 36 if title_text.length() <= 20 else 30, Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # never push the buttons off a narrow screen
	top.add_child(title)
	if not Games.how_to_play(Nav.game_id).get("steps", []).is_empty():
		top.add_child(UI.icon_button("info", _show_how_to))
	top.add_child(UI.icon_button("restart", _start))

	_status = UI.label("", 28, UI.ACCENT)
	_status.visible = not _endless
	col.add_child(_status)
	if _endless:
		_score_bar = ScoreBar.new()
		_score_bar.best = Save.get_high_score(Nav.game_id)
		col.add_child(_score_bar)
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
	if not Save.is_howto_seen(Nav.game_id):  # first time in this game only, not every level
		_show_how_to()
		Save.set_howto_seen(Nav.game_id)


## Interrupts (call, home button, notification shade): freeze the run so timers and falling
## pieces don't keep going, and so the frame-time spike on return lands while paused.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_pause.call_deferred()  # sent while the tree propagates it, so no add_child right now
	elif what == NOTIFICATION_EXIT_TREE and _pause_card:
		get_tree().paused = false


func _pause() -> void:
	if _pause_card or _overlay or _how_to or Ads.is_showing() or Nav.is_transitioning() \
			or get_tree().current_scene != self:
		return  # nothing running to protect (result card, how-to card, ad, or a slide)
	_pause_card = PauseOverlay.new()
	_pause_card.on_resume = _resume
	add_child(_pause_card)
	get_tree().paused = true


func _resume() -> void:
	if _pause_card:
		_pause_card.queue_free()
		_pause_card = null
	get_tree().paused = false


## Android Back while paused resumes instead of leaving (Nav is paused too). Called by Nav.back().
func handle_back() -> bool:
	if _pause_card:
		_resume()
		return true
	return false


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
	_game.run_ended.connect(_on_run_ended)
	_game.score_changed.connect(func(s: int):
		if _score_bar:
			_score_bar.set_score(s))
	_game.star_progress.connect(func(v: float, lower: bool):
		if _endless:
			return  # endless runs have no stars
		_meter.visible = true
		_meter.set_progress(v, _levels[Nav.level_index].get("stars", []), lower))
	_status.text = ""
	if _endless:
		_score_bar.reset(Save.get_high_score(Nav.game_id))
		_game.start_level(Games.endless_level(Nav.game_id), 0)
	else:
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


## How-to-play card over the game, which is paused (no timers, physics or input) until it closes.
func _show_how_to() -> void:
	var info := Games.how_to_play(Nav.game_id)
	if _how_to or _overlay or info.get("steps", []).is_empty():
		return
	var o := HowToPlay.new()
	o.game_name = _game_def.get("name", "")
	o.steps = info.steps
	o.extra = str(info.get("endless", "")) if _endless else ""
	o.accent = Color(_game_def.get("color", "#FF8A1F"))
	o.on_close = func():
		_how_to = null
		if _game:
			_game.process_mode = Node.PROCESS_MODE_INHERIT
	_how_to = o
	if _game:
		_game.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(o)


## Endless run over: keep the best score, then show the game-over card.
func _on_run_ended(score: int) -> void:
	var best := Save.record_score(Nav.game_id, score) and score > 0
	Feedback.sfx("win" if best else "fail")
	Feedback.vibrate(60 if best else 120)
	Ads.on_level_finished(true, -1)  # a finished run counts like a completed level
	var o := ResultOverlay.new()
	o.endless = true
	o.won = best
	o.score = score
	o.high_score = Save.get_high_score(Nav.game_id)
	o.new_best = best
	o.accent = Color(_game_def.get("color", "#FF8A1F"))
	o.on_retry = func(): Ads.run_after_interstitial(_start)
	o.on_levels = func(): Ads.run_after_interstitial(Nav.to_hub)
	_overlay = o
	add_child(o)


func _show_result(won: bool, stars: int, best: bool) -> void:
	var o := ResultOverlay.new()
	o.won = won
	o.stars = stars
	o.stat = _status.text
	o.new_best = best
	o.accent = Color(_game_def.get("color", "#FF8A1F"))
	if Nav.level_index + 1 < _levels.size():
		o.on_next = func(): Ads.run_after_interstitial(func(): Nav.play(Nav.game_id, Nav.level_index + 1))
	o.on_retry = func(): Ads.run_after_interstitial(_start)  # a no-op after a fail (fails never make an ad due)
	o.on_levels = func(): Ads.run_after_interstitial(func(): Nav.to_level_select(Nav.game_id))
	_overlay = o
	add_child(o)


## Endless HUD: two pills, Score and Best. Best follows the score live once it is beaten.
class ScoreBar extends Control:
	var best := 0
	var _score := 0
	var _pop := 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 92)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func reset(best_score: int) -> void:
		best = best_score
		_score = 0
		queue_redraw()

	func set_score(s: int) -> void:
		if s > _score:
			_pop = 1.18
			create_tween().tween_property(self, "_pop", 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_score = s
		queue_redraw()

	func _process(_d: float) -> void:
		if _pop != 1.0:
			queue_redraw()

	func _draw() -> void:
		var font := FX.font()
		var w := (size.x - 20.0) / 2.0
		var shown_best := maxi(best, _score)
		for i in 2:
			var r := Rect2(i * (w + 20.0), 4.0, w, size.y - 8.0)
			draw_style_box(UI.box(Color(0.03, 0.02, 0.12, 0.55), 28), r)
			var c := r.get_center()
			FX.draw_text_centered(self, Vector2(c.x, r.position.y + 22.0), "SCORE" if i == 0 else "BEST", 22,
				Color(1, 1, 1, 0.65), font)
			var v := _score if i == 0 else shown_best
			var col := FX.LEMON if (i == 0 and _score > 0 and _score >= best) else Color.WHITE
			FX.draw_text_centered(self, Vector2(c.x, r.position.y + 56.0), str(v),
				int(44 * (_pop if i == 0 else 1.0)), col, font)
