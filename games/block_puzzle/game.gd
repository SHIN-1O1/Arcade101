extends BaseGame
## Block Fit: drag one of three shapes onto an 8x8 grid; full rows/columns clear.
## Campaign goal: clear N lines ("lines") or clear every pre-placed block ("clear"). Campaign stars
## count the pieces used to reach the goal (lower is better, so multi-line clears pay off); the
## thresholds come from bot.gd, a greedy player run over every level (see tools/gen_levels.py).
## Endless: no goal, score only; shapes get more awkward and garbage blocks appear as
## difficulty(score) rises. Both end when none of the offered shapes fits.
## Everything is drawn in _draw().

const INDIGO := Color("#2B2A6B")
const TANGERINE := Color("#FF8A1F")
const LEMON := Color("#FFD23F")
const BOARD_BG := Color("#1c1b4a")
const GRID_LINE := Color("#35348a")
const BLOCKER := Color("#7a78c9")
const PIECE_COLORS: Array[Color] = [
	Color("#FF8A1F"), Color("#FFD23F"), Color("#FF5C8A"), Color("#2EC4B6"), Color("#5CC8FF"),
]
const BLOCKER_ID := 6
const SLOTS := 3
const FLASH_TIME := 0.35

const BASIC: Array = [
	["#"], ["##"], ["#", "#"], ["###"], ["#", "#", "#"], ["##", "##"],
	["#.", "##"], ["##", "#."], [".#", "##"], ["##", ".#"],
]
const EXTENDED: Array = [
	["####"], ["#", "#", "#", "#"], ["#####"], ["#", "#", "#", "#", "#"],
	["###", "###"], ["##", "##", "##"], ["###", "#..", "#.."], ["###", "..#", "..#"],
	["#..", "#..", "###"], ["..#", "..#", "###"], ["###", ".#."], [".##", "##."],
	["##.", ".##"],
]

var g := 8
var cells: Array[int] = []
var pre: Array[bool] = []
var score := 0
var lines_done := 0
var placed := 0  # pieces used: the campaign star metric
var goal := "lines"
var target_lines := 5
var blockers_left := 0
var blockers_total := 0
var pieces: Array = []  # each: {"cells": Array[Vector2i], "w": int, "h": int, "color": int} or null
var shapes: Array = []
var shape_weights: Array[float] = []
var endless := false
var rng: RandomNumberGenerator
var drag_slot := -1
var drag_pos := Vector2.ZERO
var flashes: Array = []  # {"cell": Vector2i, "a": float}
var over := false
var cs := 60.0
var origin := Vector2.ZERO
var tray_y := 0.0
var tray_cs := 36.0


func _on_start() -> void:
	g = int(level.get("grid", 8))
	endless = is_endless()
	goal = "endless" if endless else str(level.get("goal", "lines"))
	target_lines = int(level.get("target_lines", 5))
	var use_extended: bool = endless or level.get("piece_set", "basic") == "extended"
	shapes = _parse_shapes(BASIC + (EXTENDED if use_extended else []))
	rng = make_rng()
	cells.clear()
	pre.clear()
	cells.resize(g * g)
	pre.resize(g * g)
	cells.fill(0)
	pre.fill(false)
	score = 0
	lines_done = 0
	placed = 0
	over = false
	drag_slot = -1
	flashes.clear()
	blockers_left = 0
	blockers_total = 0
	_prefill(int(level.get("prefilled", 0)))
	_refill()
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)
	if endless:
		report_score(0)
	_report()
	queue_redraw()


static func _parse_shapes(defs: Array) -> Array:
	var out: Array = []
	for d in defs:
		var cs_: Array[Vector2i] = []
		for y in d.size():
			for x in d[y].length():
				if d[y][x] == "#":
					cs_.append(Vector2i(x, y))
		out.append({"cells": cs_, "w": d[0].length(), "h": d.size()})
	return out


func _prefill(count: int) -> void:
	var tries := 0
	var placed := 0
	while placed < count and tries < 500:
		tries += 1
		# Cluster blockers in the bottom rows so the board stays playable.
		var rows := mini(g, count / 5 + 2)
		var i := rng.randi_range(g - rows, g - 1) * g + rng.randi_range(0, g - 1)
		if cells[i] != 0:
			continue
		cells[i] = BLOCKER_ID
		if _line_full(i % g, true) or _line_full(i / g, false):
			cells[i] = 0
			continue
		pre[i] = true
		placed += 1
	blockers_left = placed
	blockers_total = placed


func _line_full(n: int, column: bool) -> bool:
	for k in g:
		if cells[(k * g + n) if column else (n * g + k)] == 0:
			return false
	return true


## Campaign: big pieces (EXTENDED) come up at the level's "ext_weight" relative to the basic ones.
## Endless ramp: small pieces fade out and awkward ones (long bars, zigzags, big Ls) take over.
func _pick_shape() -> Dictionary:
	if not endless:
		var ext := float(level.get("ext_weight", 1.0))
		var n_ext := shapes.size() - BASIC.size()
		var roll_c := rng.randf() * (BASIC.size() + n_ext * ext)
		if roll_c < BASIC.size() or n_ext == 0:
			return shapes[mini(int(roll_c), BASIC.size() - 1)]
		return shapes[BASIC.size() + mini(int((roll_c - BASIC.size()) / ext), n_ext - 1)]
	var d := difficulty(score)
	var total := 0.0
	var weights: Array[float] = []
	for i in shapes.size():
		var n: int = shapes[i].cells.size()
		var w := 1.0
		if i >= BASIC.size():
			w = lerpf(0.3, 2.2, d)
		elif n <= 2:
			w = lerpf(3.0, 0.4, d)
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	for i in shapes.size():
		roll -= weights[i]
		if roll <= 0.0:
			return shapes[i]
	return shapes[shapes.size() - 1]


## Endless: now and then a few garbage blocks land on the board (never completing a line).
func _drop_garbage() -> void:
	var d := difficulty(score)
	if d < 0.25 or rng.randf() > (d - 0.15) * 0.45:
		return
	var want := 2 if d < 0.6 else 3
	var tries := 0
	while want > 0 and tries < 60:
		tries += 1
		var i := rng.randi_range(g * 2, g * g - 1)
		if cells[i] != 0:
			continue
		cells[i] = BLOCKER_ID
		if _line_full(i % g, true) or _line_full(i / g, false):
			cells[i] = 0
			continue
		want -= 1


func _refill() -> void:
	if endless:
		_drop_garbage()
	pieces.clear()
	for attempt in 20:
		pieces.clear()
		for s in SLOTS:
			var sh: Dictionary = _pick_shape()
			pieces.append({"cells": sh.cells, "w": sh.w, "h": sh.h, "color": rng.randi_range(0, PIECE_COLORS.size() - 1)})
		# Campaign trays are fair: for the first tries every piece must fit somewhere on its own.
		if (endless or attempt >= 10) and _any_fits():
			return
		if not endless and attempt < 10 and _all_fit():
			return
	# No fair trio found: guarantee a dot so the board is not an instant loss.
	pieces[0] = {"cells": [Vector2i.ZERO] as Array[Vector2i], "w": 1, "h": 1, "color": 0}


func _fits(p: Dictionary, ox: int, oy: int) -> bool:
	for c: Vector2i in p.cells:
		var x := ox + c.x
		var y := oy + c.y
		if x < 0 or y < 0 or x >= g or y >= g or cells[y * g + x] != 0:
			return false
	return true


func _fits_anywhere(p: Dictionary) -> bool:
	for oy in g - p.h + 1:
		for ox in g - p.w + 1:
			if _fits(p, ox, oy):
				return true
	return false


func _all_fit() -> bool:
	for p in pieces:
		if p != null and not _fits_anywhere(p):
			return false
	return true


func _any_fits() -> bool:
	for p in pieces:
		if p != null and _fits_anywhere(p):
			return true
	return false


func _place(slot: int, ox: int, oy: int) -> void:
	var p: Dictionary = pieces[slot]
	for c: Vector2i in p.cells:
		cells[(oy + c.y) * g + ox + c.x] = p.color + 1
	score += p.cells.size()
	placed += 1
	if endless:
		report_score(score)
	pieces[slot] = null
	Feedback.sfx("place")
	_clear_lines()
	if _goal_met():
		_finish(true)
		return
	var any := false
	for q in pieces:
		if q != null:
			any = true
	if not any:
		_refill()
	if not _any_fits():
		_finish(false)
	_report()


func _clear_lines() -> void:
	var kill := {}
	var n := 0
	for r in g:
		if not _line_full(r, false):
			continue
		n += 1
		for x in g:
			kill[r * g + x] = true
	for c in g:
		if not _line_full(c, true):
			continue
		n += 1
		for y in g:
			kill[y * g + c] = true
	if n == 0:
		return
	for i in kill:
		if pre[i]:
			pre[i] = false
			blockers_left -= 1
		cells[i] = 0
		flashes.append({"cell": Vector2i(i % g, i / g), "a": 1.0})
	lines_done += n
	score += 10 * n * n
	if endless:
		report_score(score)
	Feedback.sfx("clear")
	Feedback.vibrate(30)


func _goal_met() -> bool:
	if endless:
		return false
	if goal == "clear":
		return blockers_left <= 0
	return lines_done >= target_lines


func _finish(won: bool) -> void:
	over = true
	drag_slot = -1
	_report()
	queue_redraw()
	await get_tree().create_timer(0.6).timeout
	if endless:
		end_run(score)
	elif won:
		win(maxi(1, stars_for(placed, true)))
	else:
		fail()


func _report() -> void:
	if endless:
		return
	report_progress(placed, true)
	if goal == "clear":
		status_changed.emit("%d / %d left  ·  Pieces %d" % [blockers_left, blockers_total, placed])
	else:
		status_changed.emit("Lines %d/%d  ·  Pieces %d" % [lines_done, target_lines, placed])


# ---------- layout & input ----------

func _layout() -> void:
	cs = floorf(minf((size.x - 40.0) / g, (size.y - 330.0) / g))
	cs = maxf(cs, 20.0)
	origin = Vector2((size.x - cs * g) / 2.0, 70.0)
	tray_y = origin.y + cs * g + 30.0
	tray_cs = minf(cs * 0.6, size.x / SLOTS / 5.4)


func _slot_rect(s: int) -> Rect2:
	var w := size.x / SLOTS
	return Rect2(w * s, tray_y, w, maxf(size.y - tray_y, tray_cs * 5.0))


func _gui_input(event: InputEvent) -> void:
	if over:
		return
	_layout()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			for s in SLOTS:
				if pieces[s] != null and _slot_rect(s).has_point(event.position):
					drag_slot = s
					drag_pos = event.position
					Feedback.vibrate(10)
		elif drag_slot >= 0:
			var cell := _drag_cell()
			var slot := drag_slot
			drag_slot = -1
			if _fits(pieces[slot], cell.x, cell.y):
				_place(slot, cell.x, cell.y)
			queue_redraw()
	elif event is InputEventMouseMotion and drag_slot >= 0:
		drag_pos = event.position
		queue_redraw()


## Grid cell under the dragged piece's top-left. The piece floats above the finger.
func _drag_cell() -> Vector2i:
	var p: Dictionary = pieces[drag_slot]
	var top_left := drag_pos - Vector2(p.w, p.h) * cs / 2.0 - Vector2(0, cs * 2.2) - origin
	return Vector2i(roundi(top_left.x / cs), roundi(top_left.y / cs))


func _process(delta: float) -> void:
	if flashes.is_empty():
		return
	for f in flashes:
		f.a -= delta / FLASH_TIME
	flashes = flashes.filter(func(f): return f.a > 0.0)
	queue_redraw()


# ---------- drawing ----------

func _cell(rect: Rect2, color: Color) -> void:
	draw_rect(rect, color.darkened(0.25))
	draw_rect(rect.grow(-cs * 0.06 if rect.size.x > tray_cs * 1.5 else -1.5), color)
	draw_rect(Rect2(rect.position + rect.size * 0.18, rect.size * Vector2(0.36, 0.14)), Color(1, 1, 1, 0.28))


func _draw_piece(p: Dictionary, top_left: Vector2, unit: float, alpha := 1.0) -> void:
	var col: Color = PIECE_COLORS[p.color]
	col.a = alpha
	for c: Vector2i in p.cells:
		_cell(Rect2(top_left + Vector2(c) * unit, Vector2(unit, unit)).grow(-1.0), col)


func _text(t: String, pos: Vector2, w: float, fs: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, pos, t, HORIZONTAL_ALIGNMENT_CENTER, w, fs, color)


func _draw() -> void:
	if cells.is_empty():
		return
	_layout()
	var goal_text := "Endless  ·  no limit" if endless else "Clear all %d marked blocks" % blockers_total if goal == "clear" else "Clear %d lines" % target_lines
	_text(goal_text, Vector2(0, 40), size.x, 34, LEMON)
	var board := Rect2(origin, Vector2(cs * g, cs * g))
	draw_rect(board.grow(10), TANGERINE)
	draw_rect(board, BOARD_BG)

	# Ghost preview and the lines it would complete.
	var ghost_ok := false
	var gcell := Vector2i.ZERO
	var would_clear := {}
	if drag_slot >= 0:
		gcell = _drag_cell()
		ghost_ok = _fits(pieces[drag_slot], gcell.x, gcell.y)
		if ghost_ok:
			var sim := cells.duplicate()
			for c: Vector2i in pieces[drag_slot].cells:
				sim[(gcell.y + c.y) * g + gcell.x + c.x] = 1
			for r in g:
				var full := true
				for x in g:
					full = full and sim[r * g + x] != 0
				if full:
					for x in g:
						would_clear[r * g + x] = true
			for cc in g:
				var fullc := true
				for y in g:
					fullc = fullc and sim[y * g + cc] != 0
				if fullc:
					for y in g:
						would_clear[y * g + cc] = true

	for y in g:
		for x in g:
			var r := Rect2(origin + Vector2(x, y) * cs, Vector2(cs, cs))
			draw_rect(r.grow(-1.0), GRID_LINE.darkened(0.3) if (x + y) % 2 == 0 else BOARD_BG.lightened(0.04))
			var v := cells[y * g + x]
			if v == BLOCKER_ID:
				_cell(r.grow(-1.0), BLOCKER)
				if pre[y * g + x] and goal == "clear":
					draw_circle(r.get_center(), cs * 0.14, LEMON)
			elif v != 0:
				_cell(r.grow(-1.0), PIECE_COLORS[v - 1])
			if would_clear.has(y * g + x):
				draw_rect(r.grow(-1.0), Color(LEMON, 0.45))
	for f in flashes:
		var fr := Rect2(origin + Vector2(f.cell) * cs, Vector2(cs, cs))
		draw_rect(fr, Color(1, 1, 1, f.a * 0.8))

	if drag_slot >= 0 and ghost_ok:
		var gp: Dictionary = pieces[drag_slot]
		_draw_piece(gp, origin + Vector2(gcell) * cs, cs, 0.4)

	# Tray
	for s in SLOTS:
		var sr := _slot_rect(s)
		var p = pieces[s]
		if p == null or s == drag_slot:
			continue
		var tl := Vector2(sr.position.x + (sr.size.x - p.w * tray_cs) / 2.0, tray_y + tray_cs * 0.5 + (5 - p.h) * tray_cs / 2.0)
		_draw_piece(p, tl, tray_cs)

	if drag_slot >= 0:
		var dp: Dictionary = pieces[drag_slot]
		_draw_piece(dp, drag_pos - Vector2(dp.w, dp.h) * cs / 2.0 - Vector2(0, cs * 2.2), cs)

	if over:
		draw_rect(Rect2(Vector2.ZERO, size), Color(INDIGO, 0.55))
