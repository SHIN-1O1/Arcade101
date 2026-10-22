extends BaseGame
## Tube Sort: tap a tube, then a target tube, to pour the top colour run.
## A pour is legal onto an empty tube or a tube whose top is the same colour (and has room).
## Level data: "tubes" (bottom -> top colour indices), "capacity", "stars" (moves, lower better).

const PALETTE: Array[Color] = [
	Color("#e63946"), Color("#2a9df4"), Color("#3ddc84"), Color("#ffd23f"),
	Color("#9b5de5"), Color("#ff8a1f"), Color("#00c2b8"), Color("#f15bb5"),
	Color("#8d99ae"), Color("#7cb518"), Color("#a0522d"), Color("#f8f9fa"),
]
const INDIGO := Color("#2B2A6B")
const TANGERINE := Color("#FF8A1F")
const LEMON := Color("#FFD23F")
const BOTTOM_BAR := 120.0
const LIFT := 26.0

var tubes: Array = []
var capacity := 4
var moves := 0
var selected := -1
var history: Array = []  # each entry: [from, to, count]
var _undo_btn: Button
var _reset_btn: Button


func _on_start() -> void:
	for c in get_children():
		c.queue_free()
	capacity = int(level.get("capacity", 4))
	tubes = []
	for t in level.get("tubes", []):
		tubes.append(Array(t))
	moves = 0
	selected = -1
	history = []
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
	row.offset_top = -BOTTOM_BAR + 12
	row.offset_bottom = -12
	row.add_theme_constant_override("separation", 20)
	add_child(row)
	_undo_btn = UI.button("Undo", undo, INDIGO, 32)
	_reset_btn = UI.button("Reset", reset, INDIGO, 32)
	for b in [_undo_btn, _reset_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	_undo_btn.disabled = true


func _report() -> void:
	status_changed.emit("Moves %d" % moves)
	if _undo_btn:
		_undo_btn.disabled = history.is_empty() or _done


# --- game logic -------------------------------------------------------------

func top_run(t: Array) -> int:
	if t.is_empty():
		return 0
	var n := 0
	while n < t.size() and t[t.size() - 1 - n] == t[t.size() - 1]:
		n += 1
	return n


func can_pour(a: int, b: int) -> bool:
	if a == b or tubes[a].is_empty() or tubes[b].size() >= capacity:
		return false
	return tubes[b].is_empty() or tubes[b][-1] == tubes[a][-1]


func pour(a: int, b: int) -> int:
	var n := mini(top_run(tubes[a]), capacity - tubes[b].size())
	var c = tubes[a][-1]
	for i in n:
		tubes[a].pop_back()
		tubes[b].append(c)
	return n


func is_solved() -> bool:
	for t in tubes:
		if not t.is_empty() and (t.size() != capacity or top_run(t) != capacity):
			return false
	return true


func undo() -> void:
	if history.is_empty() or _done:
		return
	var h: Array = history.pop_back()
	for i in h[2]:
		tubes[h[0]].append(tubes[h[1]].pop_back())
	moves -= 1
	selected = -1
	Feedback.sfx("tap")
	_report()
	queue_redraw()


func reset() -> void:
	if _done:
		return
	_on_start()


func _tap(i: int) -> void:
	if _done:
		return
	if selected == -1:
		if not tubes[i].is_empty():
			selected = i
			Feedback.sfx("tap")
	elif selected == i:
		selected = -1
	elif can_pour(selected, i):
		var n := pour(selected, i)
		history.append([selected, i, n])
		moves += 1
		selected = -1
		Feedback.sfx("pour")
		Feedback.vibrate(20)
		_report()
		if is_solved():
			queue_redraw()
			Feedback.sfx("win")
			win(stars_for(moves, true))
			return
	else:
		# illegal: reselect if the new tube has something, else just deselect
		selected = i if not tubes[i].is_empty() else -1
		Feedback.vibrate(10)
	queue_redraw()


# --- layout & drawing -------------------------------------------------------

## Returns {rects: Array[Rect2], ball: float}. Pure function of size so input and draw agree.
func _layout() -> Dictionary:
	var n := tubes.size()
	var rows := 1 if n <= 6 else 2 if n <= 12 else 3
	var cols := ceili(n / float(rows))
	var area := Vector2(size.x - 48.0, size.y - BOTTOM_BAR - 24.0 - LIFT)
	var gap := 18.0
	var row_h := area.y / rows
	var tube_w := minf(120.0, (area.x - gap * (cols - 1)) / cols)
	var ball := minf(tube_w * 0.78, (row_h - 40.0) / (capacity + 0.5))
	var tube_h := ball * capacity + ball * 0.5 + 12.0
	var rects: Array[Rect2] = []
	for i in n:
		var r := i / cols
		var c := i % cols
		var in_row := mini(cols, n - r * cols)
		var row_w := in_row * tube_w + (in_row - 1) * gap
		var x := (size.x - row_w) / 2.0 + c * (tube_w + gap)
		var y := 12.0 + LIFT + r * row_h + (row_h - tube_h) / 2.0
		rects.append(Rect2(x, y, tube_w, tube_h))
	return {"rects": rects, "ball": ball}


func _draw() -> void:
	if tubes.is_empty():
		return
	var lay := _layout()
	var rects: Array = lay.rects
	var ball: float = lay.ball
	var font := ThemeDB.fallback_font
	for i in tubes.size():
		var r: Rect2 = rects[i]
		if i == selected:
			r.position.y -= LIFT
		var is_sel := i == selected
		var body := StyleBoxFlat.new()
		body.bg_color = Color(INDIGO, 0.55)
		body.border_color = TANGERINE if is_sel else LEMON.darkened(0.35)
		body.set_border_width_all(5 if is_sel else 3)
		body.set_corner_radius_all(int(r.size.x * 0.4))
		body.corner_radius_top_left = 8
		body.corner_radius_top_right = 8
		draw_style_box(body, r)
		for j in tubes[i].size():
			var col: Color = PALETTE[tubes[i][j] % PALETTE.size()]
			var center := Vector2(r.position.x + r.size.x / 2.0, r.end.y - 8.0 - ball * (j + 0.5))
			draw_circle(center, ball / 2.0, col)
			draw_arc(center, ball / 2.0, 0, TAU, 24, col.darkened(0.35), 2.5)
			var label := str(tubes[i][j] + 1)
			var fs := int(ball * 0.4)
			var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, center + Vector2(-tw / 2.0, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(0, 0, 0, 0.45) if col.get_luminance() > 0.5 else Color(1, 1, 1, 0.6))


func _gui_input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
	else:
		return
	var rects: Array = _layout().rects
	for i in rects.size():
		var r: Rect2 = rects[i].grow(9)
		r.position.y -= LIFT * 0.5 if i == selected else 0.0
		if r.has_point(pos):
			_tap(i)
			return
