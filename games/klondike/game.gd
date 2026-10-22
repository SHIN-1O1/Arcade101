extends BaseGame
## Klondike Solitaire on the shared card kit (core/cards). Campaign levels are pre-verified winnable
## deals (levels.json "deck" = 52 card codes, see tools/klondike_solver.py); Endless deals random
## verified deals from deals.json one after another, with a score and a win streak.

const FX := preload("res://core/fx.gd")
const CardTable := preload("res://core/cards/card_table.gd")
const Deck := preload("res://core/cards/deck.gd")
const Pile := preload("res://core/cards/pile.gd")
const CardLayout := preload("res://core/cards/card_layout.gd")
const Rules := preload("res://games/klondike/klondike_rules.gd")

const DEALS_PATH := "res://games/klondike/deals.json"
const TOP_H := 60.0
const BOTTOM_H := 108.0
const DEAL_ANIM := 0.75

var table: Control
var rules: RefCounted
var draw_mode := 1

var _top: HBoxContainer
var _stats: Label
var _tap_chip: Button
var _bar: HBoxContainer
var _undo_btn: Button
var _auto_btn: Button
var _draw_btn: Button
var _banner: PanelContainer
var _banner_tween: Tween
var _secs := 0.0
var _last_shown_sec := -1
var _running := false
var _ending := false
var _auto_pending := false
var _token := 0           # bumps on every new deal/undo; stale delayed callbacks check it
var _undos_left := -1     # -1 = unlimited
var _banked := 0          # endless: score from cleared deals
var _streak := 0
var _deals_won := 0
var _run_over := false
var _pool: Dictionary = {}


func _on_start() -> void:
	if table == null:
		_build()
	if size.x < 10.0:
		await resized  # the host's layout has not run yet
	_banked = 0
	_streak = 0
	_deals_won = 0
	_run_over = false
	if is_endless():
		var saved = Save.get_setting("klondike_draw")
		draw_mode = 3 if saved == 3 else 1
		_stats.visible = true
		_draw_btn.visible = true
		report_score(0)
		_deal(_endless_deck())
	else:
		draw_mode = int(level.get("draw", 1))
		_undos_left = int(level.get("undos", -1))
		_stats.visible = false
		_draw_btn.visible = false
		_deal(level.deck)
	_update_buttons()


# --- construction -----------------------------------------------------------------

func _build() -> void:
	rules = Rules.new()
	table = CardTable.new()
	table.rules = rules
	table.layout_callback = _layout_table
	table.tap_to_move = Save.get_setting("klondike_tap") == true
	add_child(table)
	table.add_pile("stock", "stock").recycle = true
	table.add_pile("waste", "waste", Pile.Fan.RIGHT)
	for i in 4:
		table.add_pile("f%d" % i, "foundation").slot_label = "A"
	for i in 7:
		table.add_pile("t%d" % i, "tableau", Pile.Fan.DOWN).slot_label = "K"
	table.changed.connect(_on_changed)
	table.win_animation_finished.connect(_after_win)
	table.auto_complete_finished.connect(_after_auto)

	_top = HBoxContainer.new()
	_top.add_theme_constant_override("separation", 12)
	add_child(_top)
	_stats = UI.label("", 28, FX.LEMON)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats.autowrap_mode = TextServer.AUTOWRAP_OFF
	_top.add_child(_stats)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top.add_child(spacer)
	_tap_chip = UI.button("", _toggle_tap, FX.INDIGO.lightened(0.05), 22)
	_tap_chip.custom_minimum_size = Vector2(230, 48)
	_top.add_child(_tap_chip)
	_refresh_tap_chip()

	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 12)
	add_child(_bar)
	_undo_btn = _bar_button("Undo", _on_undo, FX.INDIGO.lightened(0.12))
	_bar_button("Hint", _on_hint, FX.TANGERINE.darkened(0.1))
	_auto_btn = _bar_button("Auto", _start_auto, Color("#2a9d6f"))
	_auto_btn.visible = false
	_draw_btn = _bar_button("Draw 1", _toggle_draw, FX.INDIGO.lightened(0.12))
	_draw_btn.visible = false
	var end_btn := _bar_button("End run", func(): _finish_run(), Color("#a23a4f"))
	end_btn.visible = false
	end_btn.set_meta("endless_only", true)
	_banner = PanelContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.04, 0.16, 0.92), 28))
	_banner.modulate.a = 0.0
	var l := UI.label("", 32, Color.WHITE)
	l.name = "Text"
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_constant_override("outline_size", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(l)
	add_child(_banner)
	_relayout()


func _bar_button(text: String, cb: Callable, col: Color) -> Button:
	var b := UI.button(text, cb, col, 30)
	b.custom_minimum_size = Vector2(0, 88)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.add_child(b)
	return b


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and table != null:
		_relayout()


func _relayout() -> void:
	_top.position = Vector2(12, 6)
	_top.size = Vector2(size.x - 24, TOP_H - 10)
	table.position = Vector2(0, TOP_H)
	table.size = Vector2(size.x, maxf(100.0, size.y - TOP_H - BOTTOM_H))
	_bar.position = Vector2(12, size.y - BOTTOM_H + 8)
	_bar.size = Vector2(size.x - 24, BOTTOM_H - 16)
	table.layout(false)


## Card size and pile origins for the current table size (called by the card table on every resize).
func _layout_table(t) -> void:
	var m := 14.0
	var gap := clampf(t.size.x * 0.011, 6.0, 12.0)
	var cs := CardLayout.card_size(t.size.x, 7, m, gap)
	t.card_size = cs
	var y1 := 8.0
	var row_gap := maxf(22.0, cs.x * 0.3)
	var y2 := y1 + cs.y + row_gap
	t.pile("stock").origin = Vector2(CardLayout.column_x(t.size.x, 7, cs, gap, 0), y1)
	var waste = t.pile("waste")
	waste.origin = Vector2(CardLayout.column_x(t.size.x, 7, cs, gap, 1), y1)
	waste.max_extent = cs.x * 2.0 + gap
	waste.right_visible = 3 if draw_mode == 3 else 1
	waste.fan_step = 0.42
	for i in 4:
		t.pile("f%d" % i).origin = Vector2(CardLayout.column_x(t.size.x, 7, cs, gap, 3 + i), y1)
	for i in 7:
		var p = t.pile("t%d" % i)
		p.origin = Vector2(CardLayout.column_x(t.size.x, 7, cs, gap, i), y2)
		p.max_extent = t.size.y - y2 - 6.0


# --- dealing -------------------------------------------------------------------

func _endless_deck() -> Array:
	if _pool.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DEALS_PATH))
		_pool = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var list: Array = _pool.get("draw3" if draw_mode == 3 else "draw1", [])
	var rng := make_rng()
	rng.randomize()
	var perm := [0, 1, 2, 3]
	for i in range(3, 0, -1):
		var j := rng.randi_range(0, i)
		var t = perm[i]
		perm[i] = perm[j]
		perm[j] = t
	return Deck.permute_suits(list[rng.randi_range(0, list.size() - 1)], perm)


func _deal(codes: Array) -> void:
	_token += 1
	_ending = false
	_auto_pending = false
	_running = false
	_secs = 0.0
	_last_shown_sec = -1
	_hide_banner()
	rules.draw_count = draw_mode
	rules.moves = 0
	rules.points = 0
	rules.counting = true
	rules.reset_auto()
	table.clear_cards()
	table.layout(false)
	var cards := Deck.make_cards(codes)
	var order: Array = []
	var idx := 0
	for r in 7:
		for p in range(r, 7):
			table.add_cards([cards[idx]], "t%d" % p)
			order.append(cards[idx])
			idx += 1
	table.add_cards(cards.slice(idx), "stock")
	var home: Vector2 = table.pile("stock").origin
	for v in table.views.values():
		v.position = home
	table.input_enabled = false
	table.refresh(true, order)
	var token := _token
	var tw := create_tween()
	tw.tween_interval(DEAL_ANIM)
	tw.tween_callback(func():
		if token != _token:
			return
		for p in table.piles_of("tableau"):
			p.top().face_up = true
		table.refresh(true)
		table.input_enabled = true)
	_report()
	_update_hud()
	_update_buttons()


# --- state changes ------------------------------------------------------------------

func _on_changed() -> void:
	if rules.moves > 0 and not _running and not _ending:
		_running = true
	_hide_banner()
	_report()
	_update_hud()
	_update_buttons()
	_check_end()


func _process(delta: float) -> void:
	if not _running or _ending:
		return
	_secs += delta
	if int(_secs) != _last_shown_sec:
		_last_shown_sec = int(_secs)
		_update_hud()
		_report()


func _effort() -> float:
	return maxf(float(rules.moves), _secs * float(level.get("time_k", 0.5)))


func _score() -> int:
	return _banked + rules.points


func _report() -> void:
	if is_endless():
		report_score(_score())
	else:
		report_progress(_effort(), true)


func _clock() -> String:
	return "%d:%02d" % [int(_secs) / 60, int(_secs) % 60]


func _update_hud() -> void:
	if is_endless():
		_stats.text = "Streak %d   ·   Moves %d   ·   %s" % [_streak, rules.moves, _clock()]
	else:
		status_changed.emit("Moves %d   ·   %s" % [rules.moves, _clock()])


func _update_buttons() -> void:
	var left := _undos_left
	var can: bool = table.can_undo() and left != 0
	_undo_btn.text = "Undo" if left < 0 else "Undo %d" % left
	_undo_btn.disabled = not can or _ending
	_draw_btn.text = "Draw %d" % draw_mode
	var show_auto: bool = rules.all_revealed(table) and not table.busy and not _ending
	_auto_btn.visible = show_auto
	for b in _bar.get_children():
		if b.has_meta("endless_only"):
			b.visible = is_endless()


func _check_end() -> void:
	if _ending or table.busy or not table.input_enabled:
		return
	if rules.is_won(table):
		_ending = true
		_running = false
		_update_buttons()
		table.play_win()
		return
	if rules.all_revealed(table) and table.pile("stock").cards.is_empty() and table.pile("waste").cards.is_empty():
		if not _auto_pending:
			_auto_pending = true
			var token := _token
			var tw := create_tween()
			tw.tween_interval(0.45)
			tw.tween_callback(func():
				if token == _token:
					_start_auto())
		return
	if rules.is_stuck(table):
		_stuck()


func _stuck() -> void:
	var token := _token
	if is_endless():
		_show_banner("No more moves!")
		var tw := create_tween()
		tw.tween_interval(2.6)
		tw.tween_callback(func():
			if token == _token and rules.is_stuck(table) and not _ending:
				_finish_run())
	else:
		_show_banner("No more moves. Undo or restart")


func _start_auto() -> void:
	_auto_pending = false
	if _ending or table.busy:
		return
	rules.counting = false
	rules.reset_auto()
	_update_buttons()
	table.auto_complete(0.08)


func _after_auto(_won: bool) -> void:
	rules.counting = true
	_update_buttons()
	_check_end()


func _after_win() -> void:
	if is_endless():
		var base := 800 if draw_mode == 3 else 500
		var bonus := base + maxi(0, 300 - int(_secs)) + 150 * _streak
		_banked += rules.points + bonus
		_streak += 1
		_deals_won += 1
		report_score(_banked)
		_show_banner("Deal cleared!  +%d" % bonus, 1.6)
		Feedback.sfx("win")
		var token := _token
		var tw := create_tween()
		tw.tween_interval(1.5)
		tw.tween_callback(func():
			if token == _token:
				_deal(_endless_deck()))
	else:
		status_changed.emit("Moves %d   ·   %s" % [rules.moves, _clock()])
		win(stars_for(_effort(), true))


func _finish_run() -> void:
	if _run_over:
		return
	_run_over = true
	_ending = true
	_running = false
	end_run(_score())


# --- buttons ---------------------------------------------------------------------

func _on_undo() -> void:
	if _undos_left == 0 or _ending:
		return
	if table.undo():
		_token += 1  # cancels a pending "no more moves" end
		if _undos_left > 0:
			_undos_left -= 1
		_auto_pending = false
		_hide_banner()
		_update_buttons()


func _on_hint() -> void:
	if _ending:
		return
	if not table.show_hint():
		_show_banner("No moves left")


func _toggle_tap() -> void:
	table.tap_to_move = not table.tap_to_move
	Save.set_setting("klondike_tap", table.tap_to_move)
	_refresh_tap_chip()


func _refresh_tap_chip() -> void:
	_tap_chip.text = "Tap to move: %s" % ("on" if table.tap_to_move else "off")


func _toggle_draw() -> void:
	draw_mode = 1 if draw_mode == 3 else 3
	Save.set_setting("klondike_draw", draw_mode)
	if rules.moves == 0:
		_deal(_endless_deck())
	else:
		_show_banner("Draw %d from the next deal" % draw_mode)
		_update_buttons()


# --- banner ----------------------------------------------------------------------

func _show_banner(text: String, hold := 2.2) -> void:
	var l: Label = _banner.get_node("Text")
	l.text = text
	_banner.reset_size()
	_banner.position = Vector2((size.x - _banner.size.x) / 2.0, TOP_H + table.size.y * 0.42)
	if _banner_tween:
		_banner_tween.kill()
	_banner.move_to_front()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.15)
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.35)


func _hide_banner() -> void:
	if _banner == null:
		return
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 0.0
