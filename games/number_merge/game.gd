extends BaseGame
## Merge Tiles: swipe (or arrow keys / WASD) to slide every tile; equal tiles merge into their sum.
## Reach the target tile to win. Fewer moves = more stars. Some levels have immovable blockers
## and/or a move limit; the level fails when the limit runs out or no move is left.
## Level data: "grid", "target_tile", "blockers", "move_limit" (0 = none), "stars" (moves, lower better).
## Grid cells: 0 empty, -1 blocker, otherwise the tile value. Drawn in code with the FX kit.

const FX := preload("res://core/fx.gd")
const INDIGO := Color("#2B2A6B")
const TANGERINE := Color("#FF8A1F")
const LEMON := Color("#FFD23F")
const BOARD_BG := Color("#1c1b4a")
const CELL_BG := Color("#2d2c78")
const STONE := Color("#5b59b0")
const BLOCKER := -1
const HEADER := 150.0
const BOTTOM_BAR := 128.0
const SLIDE_TIME := 0.12
const POP_TIME := 0.22
const SPAWN_TIME := 0.18
const SWIPE_MIN := 36.0  # pixels of drag before a swipe counts
const WIN_DELAY := 0.8
const FAIL_DELAY := 0.7
const BIG_MERGE := 64  # merges at least this big get a particle burst
const TILE_COLORS := {
	2: Color("#8E9CFF"), 4: Color("#5CC8FF"), 8: Color("#2EC4B6"), 16: Color("#7ED957"),
	32: Color("#FFD23F"), 64: Color("#FFA21F"), 128: Color("#FF7A3D"), 256: Color("#FF5C8A"),
	512: Color("#E04FD0"), 1024: Color("#9B5DE5"), 2048: Color("#FFC400"),
}
## up, right, down, left
const DX := [0, 1, 0, -1]
const DY := [-1, 0, 1, 0]

var n := 4
var target := 256
var move_limit := 0
var grid: Array[int] = []
var moves := 0
var best := 0
var rng: RandomNumberGenerator
var history: Array = []  # each entry: {grid, moves, rng_state}
var _undo_btn: Button
var _reset_btn: Button
var _finished := false

# Visual-only animation state; `grid` is always already up to date.
var _slides: Array = []  # {from, to, v} for every tile that existed before the move
var _slide_t := 1.0  # 0 -> 1 while tiles slide, 1 = idle
var _pending_pops: Array = []  # merged cells (revealed when the slide ends)
var _pending_spawn := -1
var _pops: Dictionary = {}  # cell -> 0..1 progress of the merge pop
var _spawns: Dictionary = {}  # cell -> 0..1 progress of the spawn grow-in
var _glow := 0.0
var _time := 0.0
var _press := Vector2.ZERO
var _pressing := false
var _swiped := false


func _on_start() -> void:
	for c in get_children():
		c.queue_free()
	n = int(level.get("grid", 4))
	target = int(level.get("target_tile", 256))
	move_limit = int(level.get("move_limit", 0))
	rng = make_rng()
	grid.clear()
	grid.resize(n * n)
	grid.fill(0)
	for i in int(level.get("blockers", 0)):
		var cell := _random_empty()
		if cell != -1:
			grid[cell] = BLOCKER
	_spawn()
	_spawn()
	moves = 0
	best = _max_tile()
	history = []
	_slides.clear()
	_pops.clear()
	_spawns.clear()
	_pending_pops.clear()
	_pending_spawn = -1
	_slide_t = 1.0
	_glow = 0.0
	_finished = false
	_pressing = false
	_build_buttons()
	_report()
	queue_redraw()


func _build_buttons() -> void:
	var row := HBoxContainer.new()
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.offset_left = 24
	row.offset_right = -24
	row.offset_top = -BOTTOM_BAR + 14
	row.offset_bottom = -14
	row.add_theme_constant_override("separation", 20)
	add_child(row)
	_undo_btn = _make_button("Undo", undo)
	_reset_btn = _make_button("Reset", reset)
	for b in [_undo_btn, _reset_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	_undo_btn.disabled = true


func _make_button(text: String, on_press: Callable) -> Button:
	var b := UI.button(text, on_press, INDIGO, 32)
	FX.style_button(b, INDIGO.lightened(0.12))
	return b


func _report() -> void:
	status_changed.emit("Goal %d  ·  Best %d" % [target, best])
	if _undo_btn:
		_undo_btn.disabled = history.is_empty() or _done or _finished


# --- live star meter data (read by the HUD, and by a shared meter later) -----

## Star thresholds in moves, [one, two, three]; the first is the move limit (or 10000 when none).
func star_thresholds() -> Array:
	return level.get("stars", [10000, 10000, 10000])


## Stars the player would get if they reached the target right now.
func stars_now() -> int:
	return stars_for(moves, true)


# --- game logic -------------------------------------------------------------

func _max_tile() -> int:
	var m := 0
	for v in grid:
		m = maxi(m, v)
	return m


func _random_empty() -> int:
	var empty: Array[int] = []
	for i in grid.size():
		if grid[i] == 0:
			empty.append(i)
	if empty.is_empty():
		return -1
	return empty[rng.randi() % empty.size()]


## Adds a 2 (90%) or 4 (10%) to a random empty cell; returns its index or -1.
func _spawn() -> int:
	var cell := _random_empty()
	if cell == -1:
		return -1
	grid[cell] = 2 if rng.randf() < 0.9 else 4
	return cell


## Slides grid `g` (n x n) one step in direction dir (0 up, 1 right, 2 down, 3 left), in place.
## If `rec` is given it receives {from, to, v, merged} per tile that existed. Returns true if
## anything changed. Pure of any node state so a bot or test can call it directly.
static func step(g: Array, size_n: int, dir: int, rec: Array = []) -> bool:
	var changed := false
	for line in size_n:
		# cells of this line ordered from the wall the tiles slide towards, backwards
		var cells: Array[int] = []
		for k in size_n:
			match dir:
				0: cells.append(k * size_n + line)
				1: cells.append(line * size_n + (size_n - 1 - k))
				2: cells.append((size_n - 1 - k) * size_n + line)
				3: cells.append(line * size_n + k)
		var seg: Array[int] = []
		for k in size_n + 1:
			if k < size_n and g[cells[k]] != BLOCKER:
				seg.append(cells[k])
				continue
			if not seg.is_empty():
				changed = _slide_segment(g, seg, rec) or changed
			seg = []
	return changed


static func _slide_segment(g: Array, seg: Array[int], rec: Array) -> bool:
	var outs: Array = []  # {v, srcs, olds}
	for c in seg:
		var v: int = g[c]
		if v <= 0:
			continue
		if not outs.is_empty() and outs[-1].v == v and outs[-1].srcs.size() == 1:
			outs[-1].v = v * 2
			outs[-1].srcs.append(c)
			outs[-1].olds.append(v)
		else:
			outs.append({"v": v, "srcs": [c], "olds": [v]})
	var changed := false
	for i in seg.size():
		var nv: int = outs[i].v if i < outs.size() else 0
		if g[seg[i]] != nv:
			changed = true
		g[seg[i]] = nv
	for i in outs.size():
		for j in outs[i].srcs.size():
			rec.append({"from": outs[i].srcs[j], "to": seg[i], "v": outs[i].olds[j],
				"merged": outs[i].srcs.size() > 1})
	return changed


static func can_move(g: Array, size_n: int) -> bool:
	for d in 4:
		if step(g.duplicate(), size_n, d):
			return true
	return false


func undo() -> void:
	if history.is_empty() or _done or _finished:
		return
	_settle()
	var h: Dictionary = history.pop_back()
	grid = h.grid
	moves = h.moves
	rng.state = h.rng_state
	_slides.clear()
	_pops.clear()
	_spawns.clear()
	Feedback.sfx("tap")
	_report()
	queue_redraw()


func reset() -> void:
	if _done or _finished:
		return
	_on_start()


func move(dir: int) -> void:
	if _done or _finished:
		return
	_settle()
	var snapshot := {"grid": grid.duplicate(), "moves": moves, "rng_state": rng.state}
	var rec: Array = []
	if not step(grid, n, dir, rec):
		Feedback.vibrate(10)  # nothing moved: no move spent, no spawn
		return
	history.append(snapshot)
	moves += 1
	_slides = rec
	_slide_t = 0.0
	_pending_pops = []
	var biggest := 0
	for r in rec:
		if r.merged and not _pending_pops.has(r.to):
			_pending_pops.append(r.to)
			biggest = maxi(biggest, grid[r.to])
	_pending_spawn = _spawn()
	best = maxi(best, _max_tile())
	Feedback.sfx("merge" if biggest > 0 else "tap")
	if biggest >= BIG_MERGE:
		Feedback.vibrate(25)
	_report()
	if _max_tile() >= target:
		_finished = true
		var tw := create_tween()
		tw.tween_interval(SLIDE_TIME + WIN_DELAY)
		tw.tween_callback(_finish_win)
		get_tree().create_timer(SLIDE_TIME + 0.05).timeout.connect(_celebrate)
	elif move_limit > 0 and moves >= move_limit:
		_lose()
	elif not can_move(grid, n):
		_lose()
	queue_redraw()


func _lose() -> void:
	_finished = true
	var tw := create_tween()
	tw.tween_interval(SLIDE_TIME + FAIL_DELAY)
	tw.tween_callback(fail)
	_report()


func _finish_win() -> void:
	win(stars_for(moves, true))


func _celebrate() -> void:
	_glow = 1.0
	FX.shake(self, 12.0, 0.35)
	var cols: Array = [LEMON, TANGERINE, Color.WHITE]
	FX.burst(self, Vector2(size.x * 0.3, size.y * 0.35), cols, 40, 1.3)
	FX.burst(self, Vector2(size.x * 0.7, size.y * 0.35), cols, 40, 1.3)


## Snap an in-progress slide to its end (before the next move or undo).
func _settle() -> void:
	if _slide_t < 1.0:
		_slide_t = 1.0
		_end_slide()


func _end_slide() -> void:
	_slides.clear()
	var lay := _layout()
	for c in _pending_pops:
		_pops[c] = 0.0
		if grid[c] >= BIG_MERGE:
			var col := _tile_color(grid[c])
			FX.burst(self, _cell_center(lay, c), [col, col.lightened(0.4), LEMON], 14 + mini(grid[c] / 64, 20), 0.8)
	_pending_pops = []
	if _pending_spawn != -1:
		_spawns[_pending_spawn] = 0.0
		_pending_spawn = -1


# --- input ------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	# Touch/mouse emulation delivers one gesture as BOTH a real and an emulated event;
	# emulated copies are skipped so a swipe is not counted twice (see CLAUDE.md).
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		if event is InputEventMouseButton or event is InputEventMouseMotion \
				or event is InputEventScreenTouch or event is InputEventScreenDrag:
			accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_press_changed(mb.pressed, mb.position)
			accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.index == 0:
			_press_changed(st.pressed, st.position)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pressing and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_drag_to(mm.position)
			accept_event()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == 0:
			_drag_to(sd.position)
			accept_event()


func _press_changed(pressed: bool, pos: Vector2) -> void:
	_pressing = pressed
	_press = pos
	_swiped = false


## Fires as soon as the finger has travelled far enough, so the board reacts without lifting.
func _drag_to(pos: Vector2) -> void:
	if not _pressing or _swiped:
		return
	var d := pos - _press
	if d.length() < SWIPE_MIN:
		return
	_swiped = true
	if absf(d.x) > absf(d.y):
		move(1 if d.x > 0.0 else 3)
	else:
		move(2 if d.y > 0.0 else 0)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	match k.keycode:
		KEY_UP, KEY_W: move(0)
		KEY_RIGHT, KEY_D: move(1)
		KEY_DOWN, KEY_S: move(2)
		KEY_LEFT, KEY_A: move(3)
		_:
			return
	get_viewport().set_input_as_handled()


# --- animation --------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var busy := false
	if _slide_t < 1.0:
		_slide_t = minf(1.0, _slide_t + delta / SLIDE_TIME)
		busy = true
		if _slide_t >= 1.0:
			_end_slide()
	for c in _pops.keys():
		_pops[c] += delta / POP_TIME
		busy = true
		if _pops[c] >= 1.0:
			_pops.erase(c)
	for c in _spawns.keys():
		_spawns[c] += delta / SPAWN_TIME
		busy = true
		if _spawns[c] >= 1.0:
			_spawns.erase(c)
	if _glow > 0.0:
		_glow = maxf(0.0, _glow - delta * 0.5)
		busy = true
	if _finished:
		busy = true  # keep the winning tile pulsing
	if busy:
		queue_redraw()


# --- layout -----------------------------------------------------------------

## {origin: Vector2, cell: float, gap: float}. Pure function of size so input and draw agree.
func _layout() -> Dictionary:
	var region_h := size.y - HEADER - BOTTOM_BAR
	var side := minf(size.x - 40.0, region_h)
	var gap := clampf(side * 0.018, 6.0, 14.0)
	var pad := gap * 1.4
	var cell := (side - pad * 2.0 - gap * (n - 1)) / n
	var origin := Vector2((size.x - side) / 2.0, HEADER + (region_h - side) / 2.0)
	return {"origin": origin, "cell": cell, "gap": gap, "pad": pad, "side": side}


func _cell_rect(lay: Dictionary, x: float, y: float) -> Rect2:
	var o: Vector2 = lay.origin
	var step_px: float = lay.cell + lay.gap
	return Rect2(o + Vector2(lay.pad + x * step_px, lay.pad + y * step_px), Vector2(lay.cell, lay.cell))


func _cell_center(lay: Dictionary, i: int) -> Vector2:
	return _cell_rect(lay, i % n, i / n).get_center()


func _tile_color(v: int) -> Color:
	if TILE_COLORS.has(v):
		return TILE_COLORS[v]
	return Color("#FFC400")  # 4096+ all gold


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	FX.draw_background(self, Rect2(Vector2.ZERO, size))
	if grid.is_empty():
		return
	var lay := _layout()
	if lay.cell < 4.0:  # not laid out yet (size is zero on the first frame)
		return
	_draw_header(lay)
	var o: Vector2 = lay.origin
	var side: float = lay.side
	FX.draw_shadow(self, Rect2(o.x - 10.0, o.y + side - 26.0, side + 20.0, 56.0))
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(lay.cell * 0.2))
	sb.bg_color = BOARD_BG
	draw_style_box(sb, Rect2(o, Vector2(side, side)))
	sb.set_corner_radius_all(int(lay.cell * 0.14))
	sb.bg_color = CELL_BG
	for i in grid.size():
		draw_style_box(sb, _cell_rect(lay, i % n, i / n))
	if _slide_t < 1.0:
		var k := FX.ease_smooth(_slide_t)
		for s in _slides:
			var a := Vector2(s.from % n, s.from / n)
			var b := Vector2(s.to % n, s.to / n)
			var p := a.lerp(b, k)
			_draw_tile_at(lay, _cell_rect(lay, p.x, p.y), s.v, 1.0)
	else:
		for i in grid.size():
			var v := grid[i]
			if v == 0:
				continue
			var r := _cell_rect(lay, i % n, i / n)
			if v == BLOCKER:
				_draw_blocker(r)
				continue
			var sc := 1.0
			if _pops.has(i):
				sc = 1.0 + 0.2 * sin(PI * float(_pops[i]))
			elif _spawns.has(i):
				sc = FX.ease_smooth(float(_spawns[i]))
			var winning := _finished and v >= target
			if winning:
				FX.draw_glow(self, r.grow(r.size.x * 0.4), Color(LEMON, 0.5 + 0.3 * sin(_time * 8.0)))
			_draw_tile_at(lay, r, v, sc)
	# blockers never move, so they are drawn during slides too
	if _slide_t < 1.0:
		for i in grid.size():
			if grid[i] == BLOCKER:
				_draw_blocker(_cell_rect(lay, i % n, i / n))
	if level_index == 0 and moves < 4 and not _finished:
		FX.draw_text_centered(self, Vector2(size.x / 2.0, o.y + side + 34.0),
			"Swipe to slide. Equal tiles merge!", 30, Color(1, 1, 1, 0.8), FX.font())


func _draw_tile_at(lay: Dictionary, r: Rect2, v: int, sc: float) -> void:
	if sc <= 0.01:
		return
	var c := r.get_center()
	var rr := Rect2(c - r.size * sc / 2.0, r.size * sc)
	FX.draw_tile(self, rr, _tile_color(v), int(lay.cell * 0.14))
	var digits := str(v).length()
	var fs: float = float(lay.cell) * (0.5 if digits <= 2 else 0.42 if digits == 3 else 0.34 if digits == 4 else 0.28)
	FX.draw_text_centered(self, c + Vector2(0, -rr.size.y * 0.02), str(v), int(fs * sc), Color(1, 1, 1, 0.97), FX.font())


func _draw_blocker(r: Rect2) -> void:
	FX.draw_tile(self, r.grow(-r.size.x * 0.04), STONE, int(r.size.x * 0.14))
	FX.draw_lock(self, r.get_center(), r.size.x * 0.34, Color(1, 1, 1, 0.55))


func _draw_header(lay: Dictionary) -> void:
	var font := FX.font()
	# goal tile (left)
	var goal := Rect2(28.0, 44.0, 84.0, 84.0)
	FX.draw_text_centered(self, Vector2(goal.get_center().x, 26.0), "GOAL", 24, Color(1, 1, 1, 0.7), font)
	var gl := Rect2(goal.position + Vector2(8, 8), goal.size - Vector2(16, 16))
	FX.draw_tile(self, gl, _tile_color(target), 14)
	var gd := str(target).length()
	FX.draw_text_centered(self, gl.get_center(), str(target), 40 if gd <= 3 else 32, Color(1, 1, 1, 0.97), font)
	# moves (centre)
	var cx := size.x * 0.43
	FX.draw_text_centered(self, Vector2(cx, 26.0), "MOVES", 24, Color(1, 1, 1, 0.7), font)
	var txt := str(moves) if move_limit == 0 else "%d / %d" % [moves, move_limit]
	var warn := move_limit > 0 and move_limit - moves <= 5
	FX.draw_text_centered(self, Vector2(cx, 84.0), txt, 56 if move_limit == 0 else 46,
		TANGERINE if warn else Color.WHITE, font)
	# star meter (right): a star stays lit while its move budget has not been spent
	var th := star_thresholds()
	for i in 3:
		var t: int = th[i] if i < th.size() else 10000
		var lit := moves <= t
		var c := Vector2(size.x - 40.0 - (2 - i) * 78.0 - 32.0, 62.0)
		FX.draw_star(self, c, 26.0, LEMON, lit)
		var label := "win" if t >= 10000 else str(t)
		FX.draw_text_centered(self, c + Vector2(0, 46.0), label, 24,
			Color(1, 1, 1, 0.9 if lit else 0.35), font)
