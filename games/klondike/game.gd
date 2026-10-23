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
const CardHud := preload("res://core/cards/card_hud.gd")
const CardArt := preload("res://core/cards/card_art.gd")

const DEALS_PATH := "res://games/klondike/deals.json"
const TOP_H := 72.0
const BOTTOM_H := 112.0
const DEAL_ANIM := 0.75

var table: Control
var rules: RefCounted
var draw_mode := 1

var _felt: Control
var _motes: Control
var _top: HBoxContainer
var _pill_streak: Control
var _pill_moves: Control
var _pill_time: Control
var _tap_chip: Button
var _bar: HBoxContainer
var _undo_btn: Button
var _hint_btn: Button
var _auto_btn: Button
var _draw_btn: Button
var _end_btn: Button
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
		_pill_streak.visible = true
		_draw_btn.visible = true
		_end_btn.visible = true
		report_score(0)
		_deal(_endless_deck())
	else:
		draw_mode = int(level.get("draw", 1))
		_undos_left = int(level.get("undos", -1))
		_pill_streak.visible = false
		_draw_btn.visible = false
		_end_btn.visible = false
		_deal(level.deck)
		status_changed.emit("Draw %d   ·   %s" % [draw_mode, "Unlimited undo" if _undos_left < 0 else "%d undos" % _undos_left])
	_update_buttons()


# --- construction -----------------------------------------------------------------

func _build() -> void:
	rules = Rules.new()
	_felt = Felt.new()
	_felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_felt)
	_motes = Motes.new()
	_motes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_motes)
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
	table.moved.connect(_on_moved)
	table.win_animation_finished.connect(_after_win)
	table.auto_complete_finished.connect(_after_auto)

	_top = HBoxContainer.new()
	_top.add_theme_constant_override("separation", 10)
	add_child(_top)
	_pill_streak = _pill("STREAK", FX.TANGERINE)
	_pill_moves = _pill("MOVES", FX.LEMON)
	_pill_time = _pill("TIME", Color("#4fc3f7"))
	_tap_chip = CardHud.ActionButton.new()
	_tap_chip.setup("tap", "Tap", FX.INDIGO.lightened(0.12), _toggle_tap)
	_tap_chip.compact = true
	_tap_chip.show_state = true
	_tap_chip.custom_minimum_size = Vector2(124, 60)
	_tap_chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	_top.add_child(_tap_chip)
	_refresh_tap_chip()

	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 12)
	add_child(_bar)
	_undo_btn = _bar_button("undo", "Undo", FX.INDIGO.lightened(0.18), _on_undo)
	_hint_btn = _bar_button("hint", "Hint", FX.TANGERINE.darkened(0.05), _on_hint)
	_auto_btn = _bar_button("auto", "Auto", Color("#2a9d6f"), _start_auto)
	_draw_btn = _bar_button("draw", "Draw 1", FX.INDIGO.lightened(0.18), _toggle_draw)
	_end_btn = _bar_button("flag", "End run", Color("#c0405a"), func(): _finish_run())
	_banner = PanelContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UI.box(Color(0.06, 0.05, 0.22, 0.95), 30)
	sb.border_color = Color(FX.LEMON, 0.8)
	sb.set_border_width_all(3)
	sb.shadow_size = 18
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	_banner.add_theme_stylebox_override("panel", sb)
	_banner.modulate.a = 0.0
	var l := UI.label("", 34, FX.LEMON)
	l.name = "Text"
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(l)
	add_child(_banner)
	_relayout()


func _pill(title: String, accent: Color) -> Control:
	var p := CardHud.StatPill.new()
	p.title = title
	p.accent = accent
	p.value = "0"
	_top.add_child(p)
	return p


func _bar_button(icon: String, text: String, col: Color, cb: Callable) -> Button:
	var b := CardHud.ActionButton.new()
	b.setup(icon, text, col, cb)
	_bar.add_child(b)
	return b


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and table != null:
		_relayout()


func _relayout() -> void:
	_felt.position = Vector2.ZERO
	_felt.size = size
	_motes.position = Vector2.ZERO
	_motes.size = size
	_top.position = Vector2(14, 8)
	_top.size = Vector2(size.x - 28, TOP_H - 12)
	table.position = Vector2(0, TOP_H)
	table.size = Vector2(size.x, maxf(100.0, size.y - TOP_H - BOTTOM_H))
	_bar.position = Vector2(14, size.y - BOTTOM_H + 8)
	_bar.size = Vector2(size.x - 28, BOTTOM_H - 18)
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


func _on_moved(_from: String, to: String, _count: int) -> void:
	if to.begins_with("f") and not table.busy:
		table.sparkle(to)
		Feedback.sfx("star")


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
	_pill_streak.set_value(str(_streak))
	_pill_moves.set_value(str(rules.moves))
	_pill_time.set_value(_clock())
	_pill_time.highlight = _running and not _ending


func _update_buttons() -> void:
	var left := _undos_left
	var can: bool = table.can_undo() and left != 0
	_undo_btn.badge = "" if left < 0 else str(left)
	_undo_btn.disabled = not can or _ending
	_undo_btn.queue_redraw()
	_hint_btn.disabled = _ending
	_hint_btn.queue_redraw()
	_draw_btn.label = "Draw %d" % draw_mode
	_draw_btn.queue_redraw()
	var show_auto: bool = rules.all_revealed(table) and not table.busy and not _ending
	_auto_btn.disabled = not show_auto
	_auto_btn.attention = show_auto
	_auto_btn.queue_redraw()


func _check_end() -> void:
	if _ending or table.busy or not table.input_enabled:
		return
	if rules.is_won(table):
		_ending = true
		_running = false
		_update_hud()
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
	_tap_chip.on = table.tap_to_move
	_tap_chip.queue_redraw()


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


## The table: green-teal felt with a woven lattice, a faint suit emblem, gold trim and vignette.
class Felt extends Control:
	static var _grain: ImageTexture

	func _init() -> void:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	## Tileable felt fibres: short random strokes in a small alpha texture, made once.
	static func grain() -> ImageTexture:
		if _grain == null:
			var n := 128
			var img := Image.create(n, n, false, Image.FORMAT_LA8)
			img.fill(Color(1, 1, 1, 0))
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			for k in 2600:
				var x := rng.randi_range(0, n - 1)
				var y := rng.randi_range(0, n - 1)
				var v := 1.0 if rng.randf() < 0.5 else 0.0
				var a := rng.randf_range(0.05, 0.16)
				var dx := rng.randi_range(-1, 1)
				for s in rng.randi_range(1, 3):
					img.set_pixel(posmod(x + dx * s, n), (y + s) % n, Color(v, v, v, a))
			_grain = ImageTexture.create_from_image(img)
		return _grain

	func _draw() -> void:
		var outer := Rect2(Vector2(4, 2), size - Vector2(8, 6))
		var rad := 40.0
		# lacquered walnut rail with a gold inlay
		FX.draw_shadow(self, Rect2(outer.position + Vector2(-10, 14), outer.size + Vector2(20, 16)), 0.6)
		FX.draw_round_gradient(self, outer, rad, Color("#5a3420"), Color("#24130b"))
		var rail := FX.round_rect_points(outer.grow(-2.0), rad - 2.0)
		rail.append(rail[0])
		draw_polyline(rail, Color(1, 0.85, 0.6, 0.25), 1.5, true)
		var r := outer.grow(-11.0)
		var frad := rad - 10.0
		var gold := FX.round_rect_points(r.grow(3.0), frad + 3.0)
		gold.append(gold[0])
		draw_polyline(gold, Color("#8a6212"), 4.0, true)
		draw_polyline(gold, Color("#f2c14e"), 2.0, true)
		# felt with a lamp-lit centre
		FX.draw_round_gradient(self, r, frad, Color("#21876a"), Color("#0b3d3a"))
		FX.draw_glow(self, Rect2(r.position + Vector2(-r.size.x * 0.2, -r.size.y * 0.05), Vector2(r.size.x * 1.4, r.size.y * 0.85)),
			Color(0.7, 1.0, 0.82, 0.22))
		# felt fibres, clipped to the rounded felt by drawing them as a textured polygon
		var pts := FX.round_rect_points(r, frad)
		var uvs := PackedVector2Array()
		for q in pts:
			uvs.append(q / 128.0)
		draw_polygon(pts, PackedColorArray([Color(1, 1, 1, 1)]), uvs, grain())
		# emblem: rosette ring with the four suits in the lower half
		var mid := Vector2(r.get_center().x, r.position.y + r.size.y * 0.66)
		var er := minf(r.size.x * 0.34, 190.0)
		var ring := PackedVector2Array()
		for k in 181:
			var a := TAU * k / 180.0
			ring.append(mid + Vector2(cos(a), sin(a)) * er * (0.93 + 0.04 * cos(a * 16.0)))
		draw_polyline(ring, Color(FX.LEMON, 0.08), 2.0, true)
		draw_arc(mid, er, 0.0, TAU, 96, Color(FX.LEMON, 0.09), 2.5, true)
		draw_arc(mid, er * 0.78, 0.0, TAU, 96, Color(FX.LEMON, 0.06), 1.5, true)
		for i in 4:
			var ang := -PI / 2.0 + i * PI / 2.0
			CardArt.draw_pip(self, i, mid + Vector2(cos(ang), sin(ang)) * er * 0.5, er * 0.17, Color(1, 1, 1, 0.07))
		for i in 4:
			var ang := -PI / 4.0 + i * PI / 2.0
			var c := mid + Vector2(cos(ang), sin(ang)) * er
			var d := 6.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]),
				Color(FX.LEMON, 0.14))
		FX.draw_star(self, mid, er * 0.17, Color(FX.LEMON, 0.1))
		# inner shade under the rail and a vignette at the bottom
		FX.draw_vgradient(self, Rect2(r.position + Vector2(frad * 0.5, 0), Vector2(r.size.x - frad, 40)),
			Color(0, 0.02, 0.06, 0.45), Color(0, 0.02, 0.06, 0.0))
		FX.draw_vgradient(self, Rect2(r.position.x + frad * 0.5, r.end.y - 140, r.size.x - frad, 140),
			Color(0, 0.02, 0.06, 0.0), Color(0, 0.02, 0.06, 0.45))
		for corner in [r.position + Vector2(16, 16), Vector2(r.end.x - 16, r.position.y + 16),
				Vector2(r.position.x + 16, r.end.y - 16), r.end - Vector2(16, 16)]:
			draw_circle(corner, 4.5, Color("#8a6212"))
			draw_circle(corner, 3.4, Color("#f2c14e"))
			draw_circle(corner + Vector2(-1, -1), 1.3, Color(1, 1, 1, 0.75))


## Slow drifting suit shapes and sparkles over the felt.
class Motes extends Control:
	var _m: Array = []
	var _t := 0.0

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for i in 22:
			_m.append({"x": rng.randf(), "y": rng.randf(), "v": rng.randf_range(0.01, 0.03), "ph": rng.randf() * TAU,
				"s": rng.randf_range(5.0, 15.0), "suit": i % 4 if i < 12 else -1})

	func _process(d: float) -> void:
		_t += d
		for m in _m:
			m.y -= m.v * d
			if m.y < -0.05:
				m.y = 1.05
				m.x = randf()
		queue_redraw()

	func _draw() -> void:
		for m in _m:
			var p := Vector2((m.x + sin(_t * 0.4 + m.ph) * 0.02) * size.x, m.y * size.y)
			if m.suit >= 0:
				CardArt.draw_pip(self, m.suit, p, m.s * 1.4, Color(1, 1, 1, 0.07))
			else:
				var a := 0.25 + 0.2 * sin(_t * 1.6 + m.ph)
				FX.draw_glow(self, Rect2(p - Vector2(m.s, m.s), Vector2(m.s, m.s) * 2.0), Color(FX.LEMON, a))
