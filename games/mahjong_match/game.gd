extends BaseGame
## Mahjong Match: stacked tile-matching solitaire. Tap two matching free tiles to remove them.
## A tile is free when nothing lies on top of it and its left or right side is open.
## Boards come from layout.gd, which builds them by removing random free pairs, so every board
## is solvable (shuffle re-deals the faces of what is left, again keeping a way out when one exists).
## Level data: shape, layers, tiles, types (tile kinds), hints, shuffles, undos, stars (seconds, lower
## better; hints/shuffles/undos add a time penalty).
##
## Endless mode (is_endless()): boards back to back, bigger and with more tile kinds as
## difficulty(score) rises. Pairs score more on a combo (quick succession); clearing a board pays a
## bonus and refills a shuffle and a hint. The run ends when nothing can be matched, shuffled or undone.

const FX := preload("res://core/fx.gd")
const Layout := preload("res://games/mahjong_match/layout.gd")
const Faces := preload("res://games/mahjong_match/faces.gd")
const INDIGO := Color("#2B2A6B")
const TANGERINE := Color("#FF8A1F")
const LEMON := Color("#FFD23F")
const IVORY := Color("#fff6df")
const IVORY_SEL := Color("#ffe58a")
const SIDE := Color("#1f8a5e")
const SIDE_DARK := Color("#14573d")

const BOTTOM_BAR := 128.0
const HUD_H := 64.0  # endless strip at the top
const MAX_UX := 46.0  # largest half-tile unit in px (tile = 2 x 2.44 units)
const ASPECT := 1.22  # tile height / width
const THICK := 0.22  # tile thickness and per-layer lift, in units
const REMOVE_TIME := 0.3
const SPAWN_TIME := 0.32
const HINT_TIME := 2.4
const WIN_DELAY := 0.75
const BOARD_DELAY := 1.1
const HINT_PENALTY := 8.0  # seconds added to the star time
const SHUFFLE_PENALTY := 12.0
const UNDO_PENALTY := 4.0
const ENDLESS_HINTS := 3
const ENDLESS_SHUFFLES := 2
const ENDLESS_UNDOS := 3
const MAX_HINTS := 5
const MAX_SHUFFLES := 3

var board: Layout.Board
var keys := PackedInt32Array()
var variants := PackedInt32Array()
var alive := PackedByteArray()
var free_now := PackedByteArray()
var solution: Array = []  # pair order the board was built from; stale after the player deviates or shuffles
var selected := -1
var history: Array = []  # {a, b, pts, combo, combo_t}
var rng: RandomNumberGenerator
var hints := 0
var shuffles := 0
var undos := 0
var penalty := 0.0
var elapsed := 0.0
var _locked := false

# Endless run state
var endless := false
var score := 0
var board_no := 0
var combo := 0
var combo_t := 0.0
var board_time := 0.0

# Geometry (px), refreshed when the size or the board changes
var ux := 30.0
var uy := 36.0
var tt := 6.0
var _origin := Vector2.ZERO
var _geo_size := Vector2.ZERO
var _geo_stamp := -1
var _stamp := 0
var _order := PackedInt32Array()  # draw order: layer, then row, then column

# Visual-only animation state
var _out := PackedFloat32Array()  # 0 = in place, 0..1 = sliding out, >=1 gone
var _mate := PackedInt32Array()
var _spawn := PackedFloat32Array()  # <0 waiting to drop in, 0..1 dropping
var _shake := PackedFloat32Array()
var _sel_f := PackedFloat32Array()  # 0..1 lift of a selected tile
var _hint_pair: Array = []
var _hint_t := 0.0
var _time := 0.0
var _banner := ""
var _banner_t := 0.0
var _floats: Array = []  # {text, pos, t}
var _last_sec := -1
var _pulse_shuffle := false

var _hint_btn: Button
var _shuffle_btn: Button
var _undo_btn: Button
var _sb := StyleBoxFlat.new()
var _sb_line := StyleBoxFlat.new()


func _ready() -> void:
	_sb_line.draw_center = false
	resized.connect(func(): queue_redraw())


func _on_start() -> void:
	for c in get_children():
		c.queue_free()
	endless = is_endless()
	rng = make_rng()
	_build_buttons()
	_locked = false
	elapsed = 0.0
	penalty = 0.0
	score = 0
	board_no = 0
	_floats.clear()
	_banner_t = 0.0
	if endless:
		hints = ENDLESS_HINTS
		shuffles = ENDLESS_SHUFFLES
		report_score(0)
		_next_board()
	else:
		hints = int(level.get("hints", 3))
		shuffles = int(level.get("shuffles", 2))
		undos = int(level.get("undos", 5))
		_install(Layout.generate(String(level.get("shape", "rect")), int(level.get("layers", 1)),
			int(level.get("tiles", 24)), int(level.get("types", 8)), rng))
	set_process(true)


## Endless: build the next board; size, layers and tile kinds follow the score.
func _next_board() -> void:
	board_no += 1
	var d := difficulty(score)
	var tiles := 20 + 2 * int(round(d * 50.0))
	var layers := 1 + int(d * 4.0)
	var types := 6 + int(d * 18.0)
	var shape: String = Layout.SHAPES[0] if board_no == 1 else Layout.SHAPES[rng.randi() % Layout.SHAPES.size()]
	undos = ENDLESS_UNDOS
	board_time = 0.0
	_locked = false
	_install(Layout.generate(shape, layers, tiles, types, rng))
	if board_no > 1:
		_show_banner("Board %d" % board_no)


func _install(gen: Dictionary) -> void:
	board = gen.board
	keys = gen.keys
	variants = gen.variants
	solution = gen.solution
	alive = PackedByteArray()
	alive.resize(board.n)
	alive.fill(1)
	free_now = PackedByteArray()
	free_now.resize(board.n)
	_out = PackedFloat32Array()
	_out.resize(board.n)
	_mate = PackedInt32Array()
	_mate.resize(board.n)
	_spawn = PackedFloat32Array()
	_spawn.resize(board.n)
	_shake = PackedFloat32Array()
	_shake.resize(board.n)
	_sel_f = PackedFloat32Array()
	_sel_f.resize(board.n)
	selected = -1
	history.clear()
	_hint_pair = []
	combo = 0
	_pulse_shuffle = false
	_stamp += 1
	var idx: Array = range(board.n)
	idx.sort_custom(func(a, b):
		if board.ls[a] != board.ls[b]:
			return board.ls[a] < board.ls[b]
		if board.ys[a] != board.ys[b]:
			return board.ys[a] < board.ys[b]
		return board.xs[a] < board.xs[b])
	_order = PackedInt32Array(idx)
	for k in _order.size():
		_spawn[_order[k]] = -(board.ls[_order[k]] * 0.12 + float(k) / maxf(1.0, board.n) * 0.3)
	_refresh_free()
	_report()
	queue_redraw()


func _build_buttons() -> void:
	var row := HBoxContainer.new()
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.offset_left = 20
	row.offset_right = -20
	row.offset_top = -BOTTOM_BAR + 14
	row.offset_bottom = -14
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	_hint_btn = _make_button("Hint", hint)
	_shuffle_btn = _make_button("Shuffle", shuffle)
	_undo_btn = _make_button("Undo", undo)
	for b in [_hint_btn, _shuffle_btn, _undo_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)


func _make_button(text: String, on_press: Callable) -> Button:
	var b := UI.button(text, on_press, INDIGO, 28)
	FX.style_button(b, INDIGO.lightened(0.12))
	return b


# --- state ------------------------------------------------------------------

func remaining() -> int:
	var n := 0
	for v in alive:
		n += 1 if v != 0 else 0
	return n


func _refresh_free() -> void:
	for i in board.n:
		free_now[i] = 1 if board.is_free(i, alive) else 0


func _report() -> void:
	var left := remaining()
	var t := int(elapsed + penalty)
	if endless:
		status_changed.emit("")
	elif left == 0:
		status_changed.emit("Cleared in %d:%02d" % [t / 60, t % 60])
		report_progress(elapsed + penalty, true)
	else:
		status_changed.emit("Tiles %d  ·  %d:%02d" % [left, t / 60, t % 60])
		report_progress(elapsed + penalty, true)
	if _hint_btn:
		_hint_btn.text = "Hint  ·  %d" % hints
		_shuffle_btn.text = "Shuffle  ·  %d" % shuffles
		_undo_btn.text = "Undo  ·  %d" % undos
		_hint_btn.disabled = hints <= 0 or _locked
		_shuffle_btn.disabled = shuffles <= 0 or _locked
		_undo_btn.disabled = history.is_empty() or undos <= 0 or _locked


func _can_shuffle() -> bool:
	return shuffles > 0 and board.free_list(alive).size() >= 2


## Called after every change to the board (match, undo, shuffle).
func _after_change() -> void:
	_refresh_free()
	_report()
	if remaining() == 0:
		_board_cleared()
		return
	if not Layout.find_pair(board, alive, keys).is_empty():
		_pulse_shuffle = false
		return
	if _can_shuffle():
		_pulse_shuffle = true
		_show_banner("No moves. Shuffle!")
	elif undos > 0 and not history.is_empty():
		_show_banner("No moves. Try Undo")
	else:
		_locked = true
		_report()
		_show_banner("No moves left")
		create_tween().tween_interval(1.2).finished.connect(func():
			if endless:
				end_run(score)
			else:
				fail())


func _board_cleared() -> void:
	_locked = true
	_report()
	Feedback.sfx("clear")
	Feedback.vibrate(40)
	FX.shake(self, 8.0)
	FX.burst(self, size / 2.0, [FX.LEMON, FX.TANGERINE, Color("#ff5d8f"), Color("#4fc3f7"), Color("#8bd448")], 60, 1.4)
	if endless:
		var bonus := 100 + 4 * board.n + 3 * maxi(0, int(board.n * 1.8 - board_time))
		score += bonus
		report_score(score)
		_show_banner("Board clear! +%d" % bonus)
		shuffles = mini(shuffles + 1, MAX_SHUFFLES)
		hints = mini(hints + 1, MAX_HINTS)
		create_tween().tween_interval(BOARD_DELAY).finished.connect(_next_board)
	else:
		_show_banner("Cleared!")
		create_tween().tween_interval(WIN_DELAY).finished.connect(func(): win(stars_for(elapsed + penalty, true)))


func _show_banner(text: String) -> void:
	_banner = text
	_banner_t = 1.0


# --- actions ----------------------------------------------------------------

func hint() -> void:
	if _locked or hints <= 0 or _done:
		return
	var pair := _best_pair()
	if pair.is_empty():
		_show_banner("No moves. Shuffle!" if shuffles > 0 else "No moves left")
		return
	hints -= 1
	penalty += HINT_PENALTY
	_hint_pair = pair
	_hint_t = HINT_TIME
	Feedback.sfx("tap")
	_report()


## The matching free pair that frees the most other tiles (a sensible suggestion, not a proof).
func _best_pair() -> Array:
	var weight := {}  # how many alive tiles wait on tile i
	for j in board.n:
		if alive[j] == 0:
			continue
		for i in board.above[j]:
			weight[i] = weight.get(i, 0) + 3  # j waits on i
		for i in board.left[j]:
			weight[i] = weight.get(i, 0) + 1
		for i in board.right[j]:
			weight[i] = weight.get(i, 0) + 1
	var groups := {}
	for i in board.free_list(alive):
		if not groups.has(keys[i]):
			groups[keys[i]] = []
		groups[keys[i]].append(i)
	var best: Array = []
	var best_w := -1
	for k in groups:
		var g: Array = groups[k]
		if g.size() < 2:
			continue
		g.sort_custom(func(a, b): return weight.get(a, 0) + board.ls[a] > weight.get(b, 0) + board.ls[b])
		var w: int = weight.get(g[0], 0) + weight.get(g[1], 0) + board.ls[g[0]] + board.ls[g[1]]
		if w > best_w:
			best_w = w
			best = [g[0], g[1]]
	return best


func shuffle() -> void:
	if _locked or _done or shuffles <= 0:
		return
	var order = Layout.reshuffle(board, alive, keys, variants, rng)
	if order == null:
		_show_banner("Can't shuffle")
		return
	shuffles -= 1
	penalty += SHUFFLE_PENALTY
	solution = order
	selected = -1
	_hint_pair = []
	_pulse_shuffle = false
	var k := 0
	for i in _order:
		if alive[i] != 0:
			_spawn[i] = -float(k) * 0.006
			k += 1
	Feedback.sfx("place")
	Feedback.vibrate(20)
	_after_change()


func undo() -> void:
	if _locked or _done or history.is_empty() or undos <= 0:
		return
	var h: Dictionary = history.pop_back()
	for i in [h.a, h.b]:
		alive[i] = 1
		_out[i] = 0.0
		_spawn[i] = 0.0
		_pop_in(i)
	undos -= 1
	penalty += UNDO_PENALTY
	score -= int(h.pts)
	combo = int(h.combo)
	combo_t = float(h.combo_t)
	if endless:
		report_score(score)
	selected = -1
	_hint_pair = []
	Feedback.sfx("back")
	_after_change()


func _pop_in(i: int) -> void:
	_spawn[i] = -0.02


# --- input ------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		pos = mb.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if not st.pressed or st.index != 0:
			return
		pos = st.position
	else:
		return
	accept_event()
	# One tap arrives as a real event plus an emulated twin (project.godot touch emulation).
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	tap_at(pos)


func tile_at(pos: Vector2) -> int:
	_ensure_geometry()
	for k in range(_order.size() - 1, -1, -1):
		var i := _order[k]
		if alive[i] == 0 or _spawn[i] < 0.0:
			continue
		var r := Rect2(_tile_pos(i), Vector2(2.0 * ux + tt, 2.0 * uy + tt))
		if r.has_point(pos):
			return i
	return -1


func tap_at(pos: Vector2) -> void:
	if _locked or _done or board == null:
		return
	var i := tile_at(pos)
	if i < 0:
		if selected >= 0:
			_set_selected(-1)
		return
	if free_now[i] == 0:
		_shake[i] = 1.0
		Feedback.sfx("locked")
		return
	if selected == i:
		_set_selected(-1)
		Feedback.sfx("tap")
	elif selected < 0 or keys[i] != keys[selected]:
		_set_selected(i)
		Feedback.sfx("select")
	else:
		var a := selected
		_set_selected(-1)
		_match(a, i)


func _set_selected(i: int) -> void:
	selected = i


func _match(a: int, b: int) -> void:
	var pts := 0
	var prev_combo := combo
	var prev_t := combo_t
	if endless:
		combo = combo + 1 if combo_t > 0.0 else 1
		combo_t = _combo_window()
		pts = 20 + 15 * (mini(combo, 10) - 1)
		score += pts
		report_score(score)
	history.append({"a": a, "b": b, "pts": pts, "combo": prev_combo, "combo_t": prev_t})
	alive[a] = 0
	alive[b] = 0
	_out[a] = 0.001
	_out[b] = 0.001
	_mate[a] = b
	_mate[b] = a
	_hint_pair = []
	var mid := (_centre(a) + _centre(b)) / 2.0
	FX.burst(self, _centre(a), [FX.LEMON, FX.TANGERINE, IVORY], 8, 0.7)
	FX.burst(self, _centre(b), [FX.LEMON, FX.TANGERINE, IVORY], 8, 0.7)
	if endless:
		_floats.append({"text": "+%d" % pts + ("  x%d" % combo if combo > 1 else ""), "pos": mid, "t": 1.0})
	Feedback.sfx("merge")
	Feedback.vibrate(15)
	_after_change()


func _combo_window() -> float:
	return lerpf(3.6, 2.2, difficulty(score))


# --- geometry ---------------------------------------------------------------

func _ensure_geometry() -> void:
	if board == null or (_geo_size == size and _geo_stamp == _stamp):
		return
	_geo_size = size
	_geo_stamp = _stamp
	var top := HUD_H if endless else 8.0
	var avail := Rect2(12.0, top + 8.0, size.x - 24.0, size.y - top - BOTTOM_BAR - 16.0)
	var minx := 9999
	var miny := 9999
	var maxx := -9999
	var maxy := -9999
	for i in board.n:
		minx = mini(minx, board.xs[i])
		miny = mini(miny, board.ys[i])
		maxx = maxi(maxx, board.xs[i] + 2)
		maxy = maxi(maxy, board.ys[i] + 2)
	var ml := board.layers - 1
	var wu := float(maxx - minx)
	var hu := float(maxy - miny)
	ux = minf(minf(avail.size.x / (wu + THICK * (ml + 1)), avail.size.y / (ASPECT * hu + THICK * (ml + 1))), MAX_UX)
	uy = ux * ASPECT
	tt = ux * THICK
	var total := Vector2(wu * ux + (ml + 1) * tt, hu * uy + (ml + 1) * tt)
	_origin = avail.position + (avail.size - total) / 2.0 - Vector2(minx * ux, miny * uy) + Vector2(ml * tt, ml * tt)


func _tile_pos(i: int) -> Vector2:
	return _origin + Vector2(board.xs[i] * ux - board.ls[i] * tt, board.ys[i] * uy - board.ls[i] * tt)


func _centre(i: int) -> Vector2:
	_ensure_geometry()
	return _tile_pos(i) + Vector2(ux, uy)


## Screen centre of a tile in this control's space (the test bot taps here).
func tile_centre(i: int) -> Vector2:
	return _centre(i)


# --- frame ------------------------------------------------------------------

func _process(delta: float) -> void:
	if board == null:
		return
	_time += delta
	var busy := _pulse_shuffle or _banner_t > 0.0 or _hint_t > 0.0 or selected >= 0 or not _floats.is_empty()
	if not _done and not _locked and remaining() > 0:
		elapsed += delta
		board_time += delta
		var sec := int(elapsed + penalty)
		if sec != _last_sec:
			_last_sec = sec
			_report()
	if endless and combo_t > 0.0:
		combo_t = maxf(0.0, combo_t - delta)
		if combo_t == 0.0:
			combo = 0
		busy = true
	if _hint_t > 0.0:
		_hint_t -= delta
		if _hint_t <= 0.0:
			_hint_pair = []
	if _banner_t > 0.0:
		_banner_t = maxf(0.0, _banner_t - delta * 0.7)
	for f in _floats:
		f.t -= delta * 1.2
		f.pos.y -= delta * 60.0
	_floats = _floats.filter(func(f): return f.t > 0.0)
	for i in board.n:
		if _out[i] > 0.0 and _out[i] < 1.0:
			_out[i] = minf(1.0, _out[i] + delta / REMOVE_TIME)
			busy = true
		if _spawn[i] < 1.0:
			_spawn[i] = minf(1.0, _spawn[i] + delta / SPAWN_TIME)
			busy = true
		if _shake[i] > 0.0:
			_shake[i] = maxf(0.0, _shake[i] - delta * 3.0)
			busy = true
		var want := 1.0 if selected == i else 0.0
		if _sel_f[i] != want:
			_sel_f[i] = move_toward(_sel_f[i], want, delta * 8.0)
			busy = true
	if _pulse_shuffle and _shuffle_btn:
		_shuffle_btn.modulate = Color.WHITE.lerp(Color(1.4, 1.25, 0.7), 0.5 + 0.5 * sin(_time * 7.0))
	elif _shuffle_btn and _shuffle_btn.modulate != Color.WHITE:
		_shuffle_btn.modulate = Color.WHITE
	if busy:
		queue_redraw()


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	FX.draw_background(self, Rect2(Vector2.ZERO, size))
	if board == null:
		return
	_ensure_geometry()
	var font := FX.font()
	var ts := Vector2(2.0 * ux, 2.0 * uy)
	var radius := int(ts.x * 0.14)
	for i in _order:
		if alive[i] == 0 and (_out[i] <= 0.0 or _out[i] >= 1.0):
			continue
		if _spawn[i] < 0.0 and _out[i] == 0.0:
			continue  # still waiting to drop in
		_draw_tile(i, ts, radius, font)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not _hint_pair.is_empty():
		var pulse := 0.5 + 0.5 * sin(_time * 9.0)
		for i in _hint_pair:
			if alive[i] != 0:
				_sb_line.set_border_width_all(int(maxf(3.0, tt * 0.7)))
				_sb_line.set_corner_radius_all(radius)
				_sb_line.border_color = TANGERINE.lerp(Color.WHITE, pulse * 0.6)
				draw_style_box(_sb_line, Rect2(_tile_pos(i) - Vector2(2, 2), ts + Vector2(4, 4)))
	if endless:
		_draw_hud(font)
	for f in _floats:
		var a := clampf(f.t, 0.0, 1.0)
		FX.draw_text_centered(self, f.pos, f.text, 40, Color(LEMON.r, LEMON.g, LEMON.b, a), font)
	if _banner_t > 0.0:
		var a := clampf(_banner_t * 2.5, 0.0, 1.0)
		var c := Vector2(size.x / 2.0, size.y * 0.5)
		var w := maxf(300.0, font.get_string_size(_banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 48).x + 70.0)
		var pr := Rect2(c - Vector2(w, 90.0) / 2.0, Vector2(w, 90.0))
		draw_style_box(UI.box(Color(0.04, 0.03, 0.16, 0.82 * a), 40), pr)
		FX.draw_text_centered(self, c, _banner, 48, Color(1, 1, 1, a), font)


func _draw_tile(i: int, ts: Vector2, radius: int, font: Font) -> void:
	var p := _tile_pos(i) + ts / 2.0
	var s := 1.0
	var off := Vector2.ZERO
	if _out[i] > 0.0:
		var t := FX.ease_smooth(_out[i])
		s = 1.0 + 0.1 * sin(minf(t * 2.0, 1.0) * PI) - t * 0.95
		var mate_p := _tile_pos(_mate[i]) + ts / 2.0
		off = (mate_p - p) * t * 0.5
	else:
		if _spawn[i] < 1.0:
			var t := clampf(_spawn[i], 0.0, 1.0)
			s = 0.55 + 0.45 * (1.0 + 1.6 * pow(t - 1.0, 3.0) + 0.6 * pow(t - 1.0, 2.0)) if t > 0.0 else 0.55
			off.y = -(1.0 - t) * ts.y * 0.5
		if _shake[i] > 0.0:
			off.x = sin(_shake[i] * 30.0) * ts.x * 0.06 * _shake[i]
		s *= 1.0 + 0.05 * _sel_f[i]
		off.y -= tt * 0.6 * _sel_f[i]
	draw_set_transform(p + off, 0.0, Vector2(s, s))
	var r := Rect2(-ts / 2.0, ts)
	var layer_lift := board.ls[i]
	FX.draw_shadow(self, Rect2(r.position + Vector2(tt * 0.3, tt * 1.0), ts * Vector2(1.08, 1.04)), 0.55 if layer_lift == 0 else 0.4)
	_sb.set_corner_radius_all(radius)
	_sb.bg_color = SIDE_DARK
	draw_style_box(_sb, Rect2(r.position + Vector2(tt, tt), ts))
	_sb.bg_color = SIDE
	draw_style_box(_sb, Rect2(r.position + Vector2(tt, tt) * 0.5, ts))
	var face := IVORY.lerp(IVORY_SEL, _sel_f[i])
	_sb.bg_color = face.darkened(0.08)
	draw_style_box(_sb, r)
	_sb.bg_color = face
	draw_style_box(_sb, Rect2(r.position, ts * Vector2(1.0, 0.94)))
	_sb.bg_color = Color(1, 1, 1, 0.5)
	_sb.set_corner_radius_all(maxi(2, radius - 3))
	draw_style_box(_sb, Rect2(r.position + ts * Vector2(0.09, 0.05), ts * Vector2(0.82, 0.16)))
	Faces.draw_face(self, Rect2(r.position + ts * Vector2(0.1, 0.1), ts * Vector2(0.8, 0.78)), keys[i], variants[i], font)
	if free_now[i] == 0 and _out[i] == 0.0:
		_sb.set_corner_radius_all(radius)
		_sb.bg_color = Color(0.16, 0.18, 0.42, 0.36)
		draw_style_box(_sb, r)
	if selected == i:
		_sb_line.set_border_width_all(int(maxf(3.0, tt * 0.8)))
		_sb_line.set_corner_radius_all(radius)
		_sb_line.border_color = LEMON
		draw_style_box(_sb_line, r.grow(1.0))


func _draw_hud(font: Font) -> void:
	var left := remaining()
	FX.draw_text_centered(self, Vector2(90, 30), "BOARD %d" % board_no, 26, Color(1, 1, 1, 0.8), font)
	FX.draw_text_centered(self, Vector2(size.x - 90, 30), "%d LEFT" % left, 26, Color(1, 1, 1, 0.8), font)
	if combo > 1 and combo_t > 0.0:
		var c := Vector2(size.x / 2.0, 28)
		FX.draw_text_centered(self, c, "COMBO x%d" % combo, 30, LEMON, font)
		var w := 200.0 * combo_t / _combo_window()
		draw_style_box(UI.box(Color(1, 1, 1, 0.18), 5), Rect2(c.x - 100, 50, 200, 8))
		draw_style_box(UI.box(TANGERINE, 5), Rect2(c.x - 100, 50, maxf(w, 6.0), 8))
