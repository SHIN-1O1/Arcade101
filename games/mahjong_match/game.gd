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
const Look := preload("res://games/mahjong_match/look.gd")
const Icons := preload("res://games/mahjong_match/icons.gd")
const INDIGO := Color("#2B2A6B")
const TANGERINE := Color("#FF8A1F")
const LEMON := Color("#FFD23F")
const IVORY := Color("#fff6df")
const IVORY_SEL := Color("#ffe58a")
const SIDE := Color("#2fb383")
const SIDE_DARK := Color("#0f4f3a")

const BOTTOM_BAR := 128.0
const HUD_H := 70.0  # chip strip at the top
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
var _flip := PackedFloat32Array()  # <0 waiting, 0..1 flipping (shuffle)
var _nodes: Array = []  # TileNode per tile
var _active := {}  # tiles whose transform is animating
var _hint_pair: Array = []
var _hint_t := 0.0
var _time := 0.0
var _banner := ""
var _banner_t := 0.0
var _floats: Array = []  # {text, pos, t}
var _rings: Array = []  # {pos, t, col}
var _last_sec := -1
var _pulse_shuffle := false
var _combo_pop := 0.0
var _overlay_dirty := true
var _board_rect := Rect2()

var _backdrop: Look.Backdrop
var _tiles_root: Node2D
var _overlay: Look.Overlay
var _hint_btn: Look.ActionButton
var _shuffle_btn: Look.ActionButton
var _undo_btn: Look.ActionButton
var _sb := StyleBoxFlat.new()
var _sb_line := StyleBoxFlat.new()


func _ready() -> void:
	_sb_line.draw_center = false


func _on_start() -> void:
	for c in get_children():
		c.queue_free()
	_nodes.clear()
	_active.clear()
	endless = is_endless()
	rng = make_rng()
	_backdrop = Look.Backdrop.new()
	add_child(_backdrop)
	add_child(Look.Motes.new())
	_tiles_root = Node2D.new()
	add_child(_tiles_root)
	_overlay = Look.Overlay.new()
	_overlay.g = self
	add_child(_overlay)
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
	_flip = PackedFloat32Array()
	_flip.resize(board.n)
	_flip.fill(-1.0)
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
	for c in _tiles_root.get_children():
		c.queue_free()
	_nodes.clear()
	_nodes.resize(board.n)
	_active.clear()
	for k in _order.size():
		var i := _order[k]
		_spawn[i] = -(board.ls[i] * 0.12 + float(k) / maxf(1.0, board.n) * 0.3)
		var n := Look.TileNode.new()
		n.g = self
		n.idx = i
		n.visible = false
		_tiles_root.add_child(n)  # painter's order: layer, row, column
		_nodes[i] = n
		_active[i] = true
	_refresh_free()
	_report()
	_overlay_dirty = true


func _build_buttons() -> void:
	var row := HBoxContainer.new()
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.offset_left = 20
	row.offset_right = -20
	row.offset_top = -BOTTOM_BAR + 8
	row.offset_bottom = -12
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	_hint_btn = Look.ActionButton.new("hint", Color("#ff9a2e"))
	_shuffle_btn = Look.ActionButton.new("shuffle", Color("#22b3a6"))
	_undo_btn = Look.ActionButton.new("undo", Color("#7a63e0"))
	_hint_btn.pressed.connect(hint)
	_shuffle_btn.pressed.connect(shuffle)
	_undo_btn.pressed.connect(undo)
	for b in [_hint_btn, _shuffle_btn, _undo_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)


# --- state ------------------------------------------------------------------

func remaining() -> int:
	var n := 0
	for v in alive:
		n += 1 if v != 0 else 0
	return n


func _refresh_free() -> void:
	for i in board.n:
		var f := 1 if board.is_free(i, alive) else 0
		if f != free_now[i]:
			free_now[i] = f
			if _nodes[i]:
				_nodes[i].queue_redraw()


func _report() -> void:
	var left := remaining()
	var t := int(elapsed + penalty)
	if endless:
		status_changed.emit("")
	elif left == 0:
		status_changed.emit("Cleared in %d:%02d" % [t / 60, t % 60])
		report_progress(elapsed + penalty, true)
	else:
		status_changed.emit("")
		report_progress(elapsed + penalty, true)
	if _hint_btn:
		_hint_btn.count = hints
		_shuffle_btn.count = shuffles
		_undo_btn.count = undos
		_hint_btn.disabled = hints <= 0 or _locked
		_shuffle_btn.disabled = shuffles <= 0 or _locked
		_undo_btn.disabled = history.is_empty() or undos <= 0 or _locked
		for b in [_hint_btn, _shuffle_btn, _undo_btn]:
			b.queue_redraw()
	_overlay_dirty = true


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
	var mid := size / 2.0
	FX.burst(self, mid, [FX.LEMON, FX.TANGERINE, Color("#ff5d8f"), Color("#4fc3f7"), Color("#8bd448")], 60, 1.4)
	FX.burst(self, mid + Vector2(-200, -160), [FX.LEMON, Color.WHITE], 24, 1.0)
	FX.burst(self, mid + Vector2(200, -160), [FX.TANGERINE, Color.WHITE], 24, 1.0)
	for k in 3:
		_rings.append({"pos": mid, "t": -k * 0.15, "col": FX.LEMON})
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
	_overlay_dirty = true


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
	_set_hint(pair)
	_hint_t = HINT_TIME
	if not endless:
		_floats.append({"text": "+%ds" % int(HINT_PENALTY), "pos": Vector2(size.x / 2.0, HUD_H + 90.0), "t": 1.0, "col": Color("#ff8f8f")})
	Feedback.sfx("tap")
	_report()


func _set_hint(pair: Array) -> void:
	var old := _hint_pair
	_hint_pair = pair
	for i in old + pair:
		if _nodes[i]:
			_nodes[i].queue_redraw()
			_active[i] = true


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
	_set_selected(-1)
	_set_hint([])
	_pulse_shuffle = false
	var k := 0
	for i in _order:
		if alive[i] != 0:
			_flip[i] = -float(k) * 0.008
			_active[i] = true
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
		_spawn[i] = -0.02
		_active[i] = true
		_nodes[i].queue_redraw()
	undos -= 1
	penalty += UNDO_PENALTY
	score -= int(h.pts)
	combo = int(h.combo)
	combo_t = float(h.combo_t)
	if endless:
		report_score(score)
	_set_selected(-1)
	_set_hint([])
	Feedback.sfx("back")
	_after_change()


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
		_active[i] = true
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
	var old := selected
	selected = i
	for t in [old, i]:
		if t >= 0 and _nodes[t]:
			_nodes[t].queue_redraw()
			_active[t] = true


func _match(a: int, b: int) -> void:
	var pts := 0
	var prev_combo := combo
	var prev_t := combo_t
	if endless:
		combo = combo + 1 if combo_t > 0.0 else 1
		combo_t = _combo_window()
		_combo_pop = 1.0
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
	_active[a] = true
	_active[b] = true
	_set_hint([])
	var mid := (_centre(a) + _centre(b)) / 2.0
	var ca := Faces.key_color(keys[a], variants[a])
	var cb := Faces.key_color(keys[b], variants[b])
	FX.burst(self, _centre(a), [FX.LEMON, ca, Color.WHITE], 9, 0.75)
	FX.burst(self, _centre(b), [FX.LEMON, cb, Color.WHITE], 9, 0.75)
	_rings.append({"pos": mid, "t": 0.0, "col": ca.lerp(FX.LEMON, 0.5)})
	if endless:
		_floats.append({"text": "+%d" % pts + ("  x%d" % combo if combo > 1 else ""), "pos": mid, "t": 1.0, "col": FX.LEMON})
	Feedback.sfx("merge")
	Feedback.vibrate(15)
	_after_change()


func _combo_window() -> float:
	return lerpf(3.6, 2.2, difficulty(score))


# --- geometry ---------------------------------------------------------------

## Recomputes the tile size and origin for the current board and control size. True if it changed.
func _ensure_geometry() -> bool:
	if board == null or size.x < 10.0 or (_geo_size == size and _geo_stamp == _stamp):
		return false
	_geo_size = size
	_geo_stamp = _stamp
	var top := HUD_H
	var avail := Rect2(30.0, top + 18.0, size.x - 60.0, size.y - top - BOTTOM_BAR - 40.0)
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
	var tl := avail.position + (avail.size - total) / 2.0
	_board_rect = Rect2(tl, total)
	return true


## Moves every tile node to its slot and refreshes the mat; run when the geometry changed.
func _relayout() -> void:
	_backdrop.set_mat(_board_rect.grow(22.0))
	for i in board.n:
		_nodes[i].position = _centre(i)
		_nodes[i].queue_redraw()
		_active[i] = true


func _tile_pos(i: int) -> Vector2:
	return _origin + Vector2(board.xs[i] * ux - board.ls[i] * tt, board.ys[i] * uy - board.ls[i] * tt)


func _centre(i: int) -> Vector2:
	_ensure_geometry()
	return _tile_pos(i) + Vector2(ux, uy)


## Screen centre of a tile in this control's space (the test bot taps here).
func tile_centre(i: int) -> Vector2:
	return _centre(i)


func tile_size() -> Vector2:
	return Vector2(2.0 * ux, 2.0 * uy)


# --- frame ------------------------------------------------------------------

func _process(delta: float) -> void:
	if board == null:
		return
	_time += delta
	if _ensure_geometry():
		_relayout()
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
		_overlay_dirty = true
	if _hint_t > 0.0:
		_hint_t -= delta
		if _hint_t <= 0.0:
			_set_hint([])
	if _banner_t > 0.0:
		_banner_t = maxf(0.0, _banner_t - delta * 0.7)
		_overlay_dirty = true
	if _combo_pop > 0.0:
		_combo_pop = maxf(0.0, _combo_pop - delta * 4.0)
		_overlay_dirty = true
	for f in _floats:
		f.t -= delta * 1.2
		f.pos.y -= delta * 60.0
		_overlay_dirty = true
	_floats = _floats.filter(func(f): return f.t > 0.0)
	for r in _rings:
		r.t += delta * 2.2
		_overlay_dirty = true
	_rings = _rings.filter(func(r): return r.t < 1.0)
	_tick_tiles(delta)
	if _pulse_shuffle and _shuffle_btn:
		_shuffle_btn.pulse = 0.5 + 0.5 * sin(_time * 7.0)
		_shuffle_btn.queue_redraw()
	elif _shuffle_btn and _shuffle_btn.pulse != 0.0:
		_shuffle_btn.pulse = 0.0
		_shuffle_btn.queue_redraw()
	if _overlay_dirty:
		_overlay_dirty = false
		_overlay.queue_redraw()


## Advances the animation timers of the tiles in _active and applies their transforms.
func _tick_tiles(delta: float) -> void:
	for i in _active.keys():
		var keep := false
		if _out[i] > 0.0 and _out[i] < 1.0:
			_out[i] = minf(1.0, _out[i] + delta / REMOVE_TIME)
			keep = true
		if _spawn[i] < 1.0:
			_spawn[i] = minf(1.0, _spawn[i] + delta / SPAWN_TIME)
			keep = true
		if _shake[i] > 0.0:
			_shake[i] = maxf(0.0, _shake[i] - delta * 3.0)
			_nodes[i].queue_redraw()  # red flash while shaking
			keep = true
		if _flip[i] > -1.0 and _flip[i] < 1.0:
			var before := _flip[i]
			_flip[i] = minf(1.0, _flip[i] + delta / 0.42)
			if before < 0.5 and _flip[i] >= 0.5:
				_nodes[i].queue_redraw()  # new face shows once the tile is edge-on
			if _flip[i] >= 1.0:
				_flip[i] = -1.0
			keep = true
		var want := 1.0 if selected == i else 0.0
		if _sel_f[i] != want:
			_sel_f[i] = move_toward(_sel_f[i], want, delta * 8.0)
			keep = true
		if selected == i or _hint_pair.has(i):
			keep = true
		_apply(i)
		if not keep:
			_active.erase(i)


func _apply(i: int) -> void:
	var node: Node2D = _nodes[i]
	var p := _centre(i)
	var s := 1.0
	var sx := 1.0
	var off := Vector2.ZERO
	var rot := 0.0
	var vis := true
	var mod := Color.WHITE
	var z := 0
	if _out[i] > 0.0:
		z = 2
		if _out[i] >= 1.0:
			vis = false
		else:
			var t := FX.ease_smooth(_out[i])
			s = 1.0 + 0.12 * sin(minf(t * 2.0, 1.0) * PI) - t * 0.95
			var mp := _centre(_mate[i])
			off = (mp - p) * t * 0.5
			rot = signf(mp.x - p.x + 0.01) * 0.2 * t
			mod = Color(1.0 + 0.5 * (1.0 - t), 1.0 + 0.5 * (1.0 - t), 1.0 + 0.2 * (1.0 - t), 1.0 - 0.6 * t)
	elif alive[i] == 0 or _spawn[i] < 0.0:
		vis = false
	else:
		if _spawn[i] < 1.0:
			var t := clampf(_spawn[i], 0.0, 1.0)
			s = 0.55 + 0.45 * (1.0 + 1.6 * pow(t - 1.0, 3.0) + 0.6 * pow(t - 1.0, 2.0)) if t > 0.0 else 0.55
			off.y = -(1.0 - t) * tile_size().y * 0.5
		if _shake[i] > 0.0:
			off.x = sin(_shake[i] * 30.0) * tile_size().x * 0.06 * _shake[i]
		if _flip[i] >= 0.0:
			sx = maxf(0.04, absf(cos(PI * _flip[i])))
			s *= 1.0 + 0.08 * sin(PI * _flip[i])
		s *= 1.0 + 0.06 * _sel_f[i]
		off.y -= tt * 0.9 * _sel_f[i]
		if selected == i:
			s *= 1.0 + 0.012 * sin(_time * 7.0)
			z = 1
		if _hint_pair.has(i):
			mod = Color.WHITE.lerp(Color(1.35, 1.2, 0.8), 0.5 + 0.5 * sin(_time * 9.0))
			s *= 1.0 + 0.025 * sin(_time * 9.0)
			z = 1
	node.visible = vis
	node.position = p + off
	node.scale = Vector2(s * sx, s)
	node.rotation = rot
	node.modulate = mod
	node.z_index = z


# --- drawing ----------------------------------------------------------------

## One tile in its own local space (centred on the origin). Called by Look.TileNode.
func draw_tile_node(ci: CanvasItem, i: int) -> void:
	var ts := tile_size()
	if ts.x < 4.0:
		return
	var radius := int(ts.x * 0.15)
	var r := Rect2(-ts / 2.0, ts)
	var sel := selected == i
	var free := free_now[i] != 0
	var lay := board.ls[i]
	if sel:
		FX.draw_glow(ci, r.grow(ts.x * 0.4), Color(LEMON, 0.6))
	elif _hint_pair.has(i):
		FX.draw_glow(ci, r.grow(ts.x * 0.4), Color(TANGERINE, 0.7))
	FX.draw_shadow(ci, Rect2(r.position + Vector2(tt * 0.5, tt * (1.0 + 0.25 * lay)), ts * Vector2(1.1, 1.08)),
		0.55 if lay == 0 else 0.45)
	_sb.draw_center = true
	_sb.set_corner_radius_all(radius)
	for k in range(4, 0, -1):  # the jade slab under the ivory face, in four steps
		var d := tt * k / 4.0
		_sb.bg_color = SIDE.lerp(SIDE_DARK, float(k) / 4.0)
		ci.draw_style_box(_sb, Rect2(r.position + Vector2(d, d), ts))
	var top_c := Color("#fffaf0")
	var bot_c := Color("#f1dfb4")
	if sel:
		top_c = Color("#fff3a8")
		bot_c = Color("#ffd35a")
	elif not free:
		top_c = Color("#e6dfd0")
		bot_c = Color("#c9bb98")
	FX.draw_round_gradient(ci, r, float(radius), top_c, bot_c)
	_sb_line.set_border_width_all(2)
	_sb_line.set_corner_radius_all(maxi(2, radius - 3))
	_sb_line.border_color = Color(0.62, 0.46, 0.2, 0.32)
	ci.draw_style_box(_sb_line, r.grow(-ts.x * 0.055))
	FX.draw_glow(ci, Rect2(r.position + ts * Vector2(-0.05, -0.05), ts * Vector2(0.95, 0.55)), Color(1, 1, 1, 0.45 if free else 0.22))
	ci.draw_line(r.position + Vector2(radius, 1.5), Vector2(r.end.x - radius, r.position.y + 1.5), Color(1, 1, 1, 0.85), 2.0, true)
	ci.draw_line(Vector2(r.position.x + radius, r.end.y - 2.5), Vector2(r.end.x - radius, r.end.y - 2.5), Color(0.5, 0.35, 0.1, 0.18), 2.0, true)
	Faces.draw_face(ci, Rect2(r.position + ts * Vector2(0.1, 0.1), ts * Vector2(0.8, 0.78)), keys[i], variants[i], FX.font())
	if not free:
		_sb.set_corner_radius_all(radius)
		_sb.bg_color = Color(0.2, 0.18, 0.46, 0.3)
		ci.draw_style_box(_sb, r)
	if _shake[i] > 0.0:
		_sb.set_corner_radius_all(radius)
		_sb.bg_color = Color(1.0, 0.25, 0.25, 0.4 * _shake[i])
		ci.draw_style_box(_sb, r)
	if sel:
		_sb_line.set_border_width_all(int(maxf(3.0, tt * 0.8)))
		_sb_line.set_corner_radius_all(radius)
		_sb_line.border_color = LEMON
		ci.draw_style_box(_sb_line, r.grow(1.0))
	elif _hint_pair.has(i):
		_sb_line.set_border_width_all(int(maxf(3.0, tt * 0.7)))
		_sb_line.set_corner_radius_all(radius)
		_sb_line.border_color = TANGERINE
		ci.draw_style_box(_sb_line, r.grow(1.0))


## HUD chips, shock rings, score pops and the banner; drawn above the tiles by Look.Overlay.
func draw_overlay(ci: CanvasItem) -> void:
	if board == null:
		return
	var font := FX.font()
	var left := remaining()
	var h := 50.0
	var y := 10.0
	var t := int(elapsed + penalty)
	if endless:
		Icons.draw_chip(ci, Rect2(16, y, 190, h), "board", "Board %d" % board_no, font, Color("#3aa76d"))
		Icons.draw_chip(ci, Rect2(size.x - 206, y, 190, h), "tiles", "%d left" % left, font, Color("#6a5fd1"))
		if combo > 1 and combo_t > 0.0:
			var pop := 1.0 + 0.2 * _combo_pop
			var c := Vector2(size.x / 2.0, y + h / 2.0 - 2)
			FX.draw_text_centered(ci, c, "x%d" % combo, int(36 * pop), FX.LEMON, font)
			var w := 80.0 * combo_t / _combo_window()
			ci.draw_style_box(UI.box(Color(1, 1, 1, 0.2), 4), Rect2(c.x - 40, y + h - 4, 80, 7))
			ci.draw_style_box(UI.box(TANGERINE, 4), Rect2(c.x - 40, y + h - 4, maxf(w, 6.0), 7))
	else:
		Icons.draw_chip(ci, Rect2(16, y, 190, h), "tiles", "%d tiles" % left, font, Color("#3aa76d"))
		Icons.draw_chip(ci, Rect2(size.x - 206, y, 190, h), "clock", "%d:%02d" % [t / 60, t % 60], font, Color("#6a5fd1"))
		if penalty > 0.0:
			Icons.draw_chip(ci, Rect2(size.x / 2.0 - 55, y, 110, h), "plus", "%ds" % int(penalty), font, Color("#e5484d"))
	for r in _rings:
		if r.t < 0.0:
			continue
		var k: float = r.t
		var col: Color = r.col
		ci.draw_arc(r.pos, lerpf(14.0, 130.0, FX.ease_smooth(k)), 0.0, TAU, 48, Color(col.r, col.g, col.b, 1.0 - k),
			lerpf(9.0, 1.5, k), true)
	for f in _floats:
		if String(f.text) == "":
			continue
		var a := clampf(f.t, 0.0, 1.0)
		var fc: Color = f.get("col", FX.LEMON)
		FX.draw_text_centered(ci, f.pos, f.text, 40, Color(fc.r, fc.g, fc.b, a), font)
	if _banner_t > 0.0:
		var age := 1.0 - _banner_t
		var a := clampf(_banner_t * 2.5, 0.0, 1.0)
		var pop := 1.0 + 0.25 * pow(1.0 - clampf(age * 6.0, 0.0, 1.0), 2.0)
		var c := Vector2(size.x / 2.0, size.y * 0.5)
		var w := (maxf(320.0, font.get_string_size(_banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 50).x + 110.0)) * pop
		var pr := Rect2(c - Vector2(w, 104.0 * pop) / 2.0, Vector2(w, 104.0 * pop))
		FX.draw_shadow(ci, pr.grow(26.0), 0.7 * a)
		FX.draw_round_gradient(ci, pr, 48.0, Color(0.2, 0.18, 0.5, 0.95 * a), Color(0.07, 0.06, 0.25, 0.95 * a))
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.set_corner_radius_all(48)
		sb.set_border_width_all(4)
		sb.border_color = Color(LEMON.r, LEMON.g, LEMON.b, a)
		ci.draw_style_box(sb, pr)
		FX.draw_star(ci, pr.position + Vector2(36, pr.size.y / 2.0), 15.0 * pop, Color(LEMON.r, LEMON.g, LEMON.b, a))
		FX.draw_star(ci, pr.end - Vector2(36, pr.size.y / 2.0), 15.0 * pop, Color(LEMON.r, LEMON.g, LEMON.b, a))
		FX.draw_text_centered(ci, c, _banner, int(50 * pop), Color(1, 1, 1, a), font)
