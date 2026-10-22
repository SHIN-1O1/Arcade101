extends BaseGame
## Merge Tiles (endless): swipe (or arrow keys / WASD) to slide every tile; equal tiles merge into
## their sum and add that sum to the score. There are no levels: the run ends when no move is left
## and only the high score counts. The board is fixed 4x4. As the score rises (difficulty() from
## BaseGame, ramping to "ramp_score" in games.json) more 4s spawn and now and then a stone appears
## that crumbles after a few moves. Undo is a limited resource (UNDOS per run).
## Grid cells: 0 empty, -1 stone, otherwise the tile value. Drawn in code with the FX kit.

const FX := preload("res://core/fx.gd")
const INDIGO := Color("#2B2A6B")
const TANGERINE := Color("#FF8A1F")
const LEMON := Color("#FFD23F")
const BOARD_BG := Color("#1c1b4a")
const CELL_BG := Color("#2d2c78")
const STONE := Color("#5b59b0")
const BLOCKER := -1
const HEADER := 8.0  # the host's Score / Best bar sits above the game area
const BOTTOM_BAR := 128.0
const SLIDE_TIME := 0.12
const POP_TIME := 0.22
const SPAWN_TIME := 0.18
const SWIPE_MIN := 36.0  # pixels of drag before a swipe counts
const FAIL_DELAY := 0.7
const UNDOS := 3
const GRID := 4
const STONE_LIFE := 24  # moves before a stone crumbles
const BIG_MERGE := 64  # merges at least this big get a particle burst
const TILE_COLORS := {
	2: Color("#8E9CFF"), 4: Color("#5CC8FF"), 8: Color("#2EC4B6"), 16: Color("#7ED957"),
	32: Color("#FFD23F"), 64: Color("#FFA21F"), 128: Color("#FF7A3D"), 256: Color("#FF5C8A"),
	512: Color("#E04FD0"), 1024: Color("#9B5DE5"), 2048: Color("#FFC400"),
}
## up, right, down, left
const DX := [0, 1, 0, -1]
const DY := [-1, 0, 1, 0]

var n := GRID
var grid: Array[int] = []
var moves := 0
var score := 0
var undos := UNDOS
var stones: Dictionary = {}  # cell -> moves left before it crumbles
var rng: RandomNumberGenerator
var history: Array = []  # each entry: {grid, moves, score, stones, rng_state}
var _undo_btn: Button
var _finished := false
var _floats: Array = []  # {cell, text, t}: rising "+n" labels

# Visual-only animation state; `grid` is always already up to date.
var _slides: Array = []  # {from, to, v} for every tile that existed before the move
var _slide_t := 1.0  # 0 -> 1 while tiles slide, 1 = idle
var _pending_pops: Array = []  # merged cells (revealed when the slide ends)
var _pending_spawn := -1
var _pops: Dictionary = {}  # cell -> 0..1 progress of the merge pop
var _spawns: Dictionary = {}  # cell -> 0..1 progress of the spawn grow-in
var _time := 0.0
var _press := Vector2.ZERO
var _pressing := false
var _swiped := false


func _on_start() -> void:
	for c in get_children():
		c.queue_free()
	n = GRID
	rng = make_rng()
	grid.clear()
	grid.resize(n * n)
	grid.fill(0)
	stones.clear()
	_spawn()
	_spawn()
	moves = 0
	score = 0
	undos = UNDOS
	history = []
	_slides.clear()
	_pops.clear()
	_spawns.clear()
	_floats.clear()
	_pending_pops.clear()
	_pending_spawn = -1
	_slide_t = 1.0
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
	_undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_undo_btn)
	_undo_btn.disabled = true


func _make_button(text: String, on_press: Callable) -> Button:
	var b := UI.button(text, on_press, INDIGO, 32)
	FX.style_button(b, INDIGO.lightened(0.12))
	return b


func _report() -> void:
	report_score(score)
	if _undo_btn:
		_undo_btn.text = "Undo  ·  %d left" % undos
		_undo_btn.disabled = history.is_empty() or undos <= 0 or _done or _finished


# --- game logic -------------------------------------------------------------

func _random_empty() -> int:
	var empty: Array[int] = []
	for i in grid.size():
		if grid[i] == 0:
			empty.append(i)
	if empty.is_empty():
		return -1
	return empty[rng.randi() % empty.size()]


## Adds a 2 or a 4 to a random empty cell; the share of 4s grows from 10% to 35% with difficulty.
func _spawn() -> int:
	var cell := _random_empty()
	if cell == -1:
		return -1
	grid[cell] = 4 if rng.randf() < 0.10 + 0.25 * difficulty(score) else 2
	return cell


## Occasionally drops a stone on an empty cell once the score is up (never when the board is tight).
func _maybe_stone() -> void:
	var d := difficulty(score)
	if d < 0.2 or stones.size() >= (1 if d < 0.6 else 2):
		return
	var empty := 0
	for v in grid:
		if v == 0:
			empty += 1
	if empty < 5 or rng.randf() > 0.03 + 0.07 * d:
		return
	var cell := _random_empty()
	grid[cell] = BLOCKER
	stones[cell] = STONE_LIFE
	_spawns[cell] = 0.0


## Counts stones down after every move; the one that hits zero crumbles away.
func _tick_stones() -> void:
	for c in stones.keys():
		stones[c] -= 1
		if stones[c] <= 0:
			stones.erase(c)
			grid[c] = 0
			Feedback.sfx("pop")
			FX.burst(self, _cell_center(_layout(), c), [STONE, STONE.lightened(0.4)], 10, 0.5)


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
	if history.is_empty() or undos <= 0 or _done or _finished:
		return
	_settle()
	var h: Dictionary = history.pop_back()
	grid = h.grid
	moves = h.moves
	score = h.score
	stones = h.stones
	rng.state = h.rng_state
	undos -= 1
	_slides.clear()
	_pops.clear()
	_spawns.clear()
	_floats.clear()
	Feedback.sfx("back")
	_report()
	queue_redraw()


func move(dir: int) -> void:
	if _done or _finished:
		return
	_settle()
	var snapshot := {"grid": grid.duplicate(), "moves": moves, "score": score,
		"stones": stones.duplicate(), "rng_state": rng.state}
	var rec: Array = []
	if not step(grid, n, dir, rec):
		Feedback.vibrate(10)  # nothing moved: no move spent, no spawn
		return
	history.append(snapshot)
	if history.size() > UNDOS:
		history.pop_front()
	moves += 1
	_slides = rec
	_slide_t = 0.0
	_pending_pops = []
	var biggest := 0
	for r in rec:
		if r.merged and not _pending_pops.has(r.to):
			_pending_pops.append(r.to)
			biggest = maxi(biggest, grid[r.to])
			score += grid[r.to]
			_floats.append({"cell": r.to, "text": "+%d" % grid[r.to], "t": 0.0})
	_tick_stones()
	_pending_spawn = _spawn()
	_maybe_stone()
	Feedback.sfx("clear" if biggest >= BIG_MERGE else "merge" if biggest > 0 else "tap")
	if biggest >= BIG_MERGE:
		Feedback.vibrate(25)
		FX.shake(self, 5.0, 0.2)
	_report()
	if not can_move(grid, n):
		_lose()
	queue_redraw()


func _lose() -> void:
	_finished = true
	var tw := create_tween()
	tw.tween_interval(SLIDE_TIME + FAIL_DELAY)
	tw.tween_callback(func(): end_run(score))
	_report()


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
	for f in _floats:
		f.t += delta / 0.7
	while not _floats.is_empty() and _floats[0].t >= 1.0:
		_floats.pop_front()
	if not _floats.is_empty():
		busy = true
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
		for i in grid.size():  # stones never move, so they show during slides too
			if grid[i] == BLOCKER:
				_draw_stone(_cell_rect(lay, i % n, i / n), stones.get(i, 0), 1.0)
	else:
		for i in grid.size():
			var v := grid[i]
			if v == 0:
				continue
			var r := _cell_rect(lay, i % n, i / n)
			var sc := 1.0
			if _pops.has(i):
				sc = 1.0 + 0.2 * sin(PI * float(_pops[i]))
			elif _spawns.has(i):
				sc = FX.ease_smooth(float(_spawns[i]))
			if v == BLOCKER:
				_draw_stone(r, stones.get(i, 0), sc)
			else:
				_draw_tile_at(lay, r, v, sc)
	for f in _floats:
		var c := _cell_center(lay, f.cell) + Vector2(0, -lay.cell * (0.3 + 0.6 * float(f.t)))
		FX.draw_text_centered(self, c, f.text, int(lay.cell * 0.3), Color(LEMON, 1.0 - float(f.t) * float(f.t)), FX.font())
	if moves < 4 and not _finished:
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


func _draw_stone(r: Rect2, life: int, sc: float) -> void:
	if sc <= 0.01:
		return
	var rr := Rect2(r.get_center() - r.size * sc / 2.0, r.size * sc).grow(-r.size.x * 0.04)
	FX.draw_tile(self, rr, STONE, int(r.size.x * 0.14))
	FX.draw_text_centered(self, rr.get_center(), str(life), int(r.size.x * 0.34 * sc), Color(1, 1, 1, 0.6), FX.font())
