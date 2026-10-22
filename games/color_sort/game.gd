extends BaseGame
## Tube Sort: tap a tube, then a target tube, to pour the top colour run.
## A pour is legal onto an empty tube or a tube whose top is the same colour (and has room).
## Level data: "tubes" (bottom -> top colour indices), "capacity", "stars" (moves, lower better).
## Drawn in code with the shared FX kit (core/fx.gd): shadows, glossy balls, bursts, shake.

const PALETTE: Array[Color] = [
	Color("#e63946"), Color("#2a9df4"), Color("#3ddc84"), Color("#ffd23f"),
	Color("#9b5de5"), Color("#ff8a1f"), Color("#00c2b8"), Color("#f15bb5"),
	Color("#8d99ae"), Color("#7cb518"), Color("#a0522d"), Color("#f8f9fa"),
]
const FX := preload("res://core/fx.gd")
const INDIGO := Color("#2B2A6B")
const TANGERINE := Color("#FF8A1F")
const LEMON := Color("#FFD23F")
const BOTTOM_BAR := 128.0
const GAP := 24.0
const MAX_COLS := 7
const LIFT_TIME := 0.12  # seconds to raise/lower the top ball
const FLY_TIME := 0.36  # seconds for one ball to travel between tubes
const FLY_STAGGER := 0.07
const WIN_DELAY := 0.5  # celebrate a moment before the result overlay

var tubes: Array = []
var capacity := 4
var moves := 0
var selected := -1
var history: Array = []  # each entry: [from, to, count]
var _undo_btn: Button
var _reset_btn: Button

# Visual-only animation state; the game logic above is always already up to date.
var _lift: Array[float] = []  # 0..1 per tube: how far its top ball is raised
var _hidden: Array[int] = []  # balls at the top of each tube that are still flying in
var _pulse: Array[float] = []  # 1 -> 0 glow after a tube gets completed
var _flyers: Array = []  # {c, dest, p0, p1, p2, p3, t}; t < 0 means still waiting
var _time := 0.0
var _solved := false

var _sb_glass := StyleBoxFlat.new()
var _sb_glow := StyleBoxFlat.new()
var _sb_lip := StyleBoxFlat.new()
var _sb_streak := StyleBoxFlat.new()


func _on_start() -> void:
	for c in get_children():
		c.queue_free()
	capacity = int(level.get("capacity", 4))
	tubes = []
	for t in level.get("tubes", []):
		var tube: Array = []
		for c in t:
			tube.append(int(c))  # JSON numbers load as floats
		tubes.append(tube)
	moves = 0
	selected = -1
	history = []
	_solved = false
	_reset_anim()
	_build_buttons()
	_report()
	queue_redraw()


func _reset_anim() -> void:
	_flyers.clear()
	_lift.resize(tubes.size())
	_lift.fill(0.0)
	_hidden.resize(tubes.size())
	_hidden.fill(0)
	_pulse.resize(tubes.size())
	_pulse.fill(0.0)


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
	status_changed.emit("Moves %d" % moves)
	report_progress(moves, true)
	if _undo_btn:
		_undo_btn.disabled = history.is_empty() or _done or _solved


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
	var c: int = tubes[a][-1]
	for i in n:
		tubes[a].pop_back()
		tubes[b].append(c)
	return n


func is_solved() -> bool:
	for t in tubes:
		if not t.is_empty() and (t.size() != capacity or top_run(t) != capacity):
			return false
	return true


func _is_complete(i: int) -> bool:
	return tubes[i].size() == capacity and top_run(tubes[i]) == capacity


func undo() -> void:
	if history.is_empty() or _done or _solved:
		return
	_land_all()
	var h: Array = history.pop_back()
	for i in h[2]:
		tubes[h[0]].append(tubes[h[1]].pop_back())
	moves -= 1
	selected = -1
	_lift.fill(0.0)
	Feedback.sfx("tap")
	_report()
	queue_redraw()


func reset() -> void:
	if _done or _solved:
		return
	_on_start()


func _tap(i: int) -> void:
	if _done or _solved:
		return
	if selected == -1:
		if not tubes[i].is_empty():
			selected = i
			Feedback.sfx("select")
	elif selected == i:
		selected = -1
	elif can_pour(selected, i):
		_do_pour(selected, i)
	else:
		# illegal: reselect if the new tube has something, else just deselect
		selected = i if not tubes[i].is_empty() else -1
		Feedback.vibrate(10)
	queue_redraw()


func _do_pour(a: int, b: int) -> void:
	_land_all()
	var lay := _layout()
	var rects: Array = lay.rects
	var ball: float = lay.ball
	var from_size: int = tubes[a].size()
	var c: int = tubes[a][-1]
	var n := pour(a, b)
	history.append([a, b, n])
	moves += 1
	selected = -1
	# Animate: each ball arcs from its slot in `a` to above `b`, then drops into its slot.
	for k in n:
		var p0 := _slot(rects[a], ball, from_size - 1 - k)
		if k == 0:
			p0 = p0.lerp(_raised(rects[a], ball), FX.ease_smooth(_lift[a]))
		var p3 := _slot(rects[b], ball, tubes[b].size() - n + k)
		var p2 := _raised(rects[b], ball)
		var p1 := Vector2((p0.x + p2.x) / 2.0, minf(p0.y, p2.y) - ball * 1.3)
		_flyers.append({"c": c, "dest": b, "p0": p0, "p1": p1, "p2": p2, "p3": p3,
			"t": -k * FLY_STAGGER / FLY_TIME})
	_hidden[b] += n
	_lift[a] = 0.0
	Feedback.sfx("pour")
	Feedback.vibrate(20)
	if is_solved():
		_solved = true
		var tw := create_tween()
		tw.tween_interval(FLY_TIME + n * FLY_STAGGER + WIN_DELAY)
		tw.tween_callback(_finish_win)
	_report()


func _finish_win() -> void:
	win(stars_for(moves, true))
	_report()


func _celebrate() -> void:
	FX.shake(self, 12.0, 0.35)
	var colors: Array = []
	for t in tubes:
		if not t.is_empty():
			colors.append(PALETTE[posmod(int(t[0]), PALETTE.size())])
	FX.burst(self, Vector2(size.x * 0.3, size.y * 0.3), colors, 40, 1.3)
	FX.burst(self, Vector2(size.x * 0.7, size.y * 0.3), colors, 40, 1.3)


## Snap every in-flight ball into place (before a new move or undo).
func _land_all() -> void:
	_flyers.clear()
	_hidden.fill(0)


func _on_landed(t: int) -> void:
	if _is_complete(t):
		_pulse[t] = 1.0
		Feedback.vibrate(15)
		var r: Rect2 = _layout().rects[t]
		var col: Color = PALETTE[posmod(int(tubes[t][0]), PALETTE.size())]
		FX.burst(self, Vector2(r.get_center().x, r.position.y), [col, col.lightened(0.4), LEMON], 22)
	if _solved and _flyers.is_empty():
		_celebrate()


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
	# Touch/mouse emulation (emulate_touch_from_mouse in project.godot, emulate_mouse_from_touch
	# on phones) delivers one tap as BOTH a real and an emulated event. Handling both selected and
	# immediately deselected the tube, so taps looked dead. Emulated copies are skipped.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var lay := _layout()
	var rects: Array = lay.rects
	var ball: float = lay.ball
	for i in rects.size():
		var r: Rect2 = rects[i]
		# generous hit area: the whole column, including the space for the raised ball
		var hit := Rect2(r.position.x - GAP / 2.0, r.position.y - ball * 1.3,
			r.size.x + GAP, r.size.y + ball * 1.3 + 24.0)
		if hit.has_point(pos):
			_tap(i)
			return


# --- animation --------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var busy := selected != -1 or not _flyers.is_empty()
	for i in _lift.size():
		var target := 1.0 if i == selected else 0.0
		if _lift[i] != target:
			_lift[i] = move_toward(_lift[i], target, delta / LIFT_TIME)
			busy = true
		if _pulse[i] > 0.0:
			_pulse[i] = maxf(0.0, _pulse[i] - delta * 1.5)
			busy = true
	for f in _flyers:
		f["t"] = float(f["t"]) + delta / FLY_TIME
	# flyers land in the order they were launched
	while not _flyers.is_empty() and float(_flyers[0]["t"]) >= 1.0:
		var f: Dictionary = _flyers.pop_front()
		var d: int = f["dest"]
		_hidden[d] = maxi(0, _hidden[d] - 1)
		if _hidden[d] == 0:
			_on_landed(d)
	if busy:
		queue_redraw()


func _flyer_pos(f: Dictionary) -> Vector2:
	var k := clampf(float(f["t"]), 0.0, 1.0)
	var p0: Vector2 = f["p0"]
	var p1: Vector2 = f["p1"]
	var p2: Vector2 = f["p2"]
	var p3: Vector2 = f["p3"]
	if k < 0.7:
		var u: float = FX.ease_smooth(k / 0.7)
		return p0 * (1.0 - u) * (1.0 - u) + p1 * 2.0 * (1.0 - u) * u + p2 * u * u
	var v := (k - 0.7) / 0.3
	return p2.lerp(p3, v * v)


# --- layout -----------------------------------------------------------------

## Returns {rects: Array[Rect2], ball: float}. Pure function of size so input and draw agree.
func _layout() -> Dictionary:
	var n := tubes.size()
	var rows := maxi(1, ceili(n / float(MAX_COLS)))
	var cols := maxi(1, ceili(n / float(rows)))
	var area_w := size.x - 48.0
	var area_h := size.y - BOTTOM_BAR - 16.0
	var row_h := area_h / rows
	var tube_w := minf(104.0, (area_w - GAP * (cols - 1)) / cols)
	# per row: headroom for the raised ball (1.3 balls) + the tube (capacity + 0.44 balls)
	var ball := minf(tube_w * 0.8, (row_h - 24.0) / (capacity + 0.44 + 1.3))
	tube_w = minf(tube_w, ball * 1.25)
	var tube_h := ball * (capacity + 0.44)
	var head := ball * 1.3
	var rects: Array[Rect2] = []
	for i in n:
		var r := floori(float(i) / cols)
		var c := i - r * cols
		var in_row := mini(cols, n - r * cols)
		var row_w := in_row * tube_w + (in_row - 1) * GAP
		var x := (size.x - row_w) / 2.0 + c * (tube_w + GAP)
		var y := 8.0 + r * row_h + (row_h - head - tube_h) / 2.0 + head
		rects.append(Rect2(x, y, tube_w, tube_h))
	return {"rects": rects, "ball": ball}


## Centre of ball slot j (0 = bottom) in tube rect r.
func _slot(r: Rect2, ball: float, j: int) -> Vector2:
	return Vector2(r.position.x + r.size.x / 2.0, r.end.y - ball * 0.14 - ball * (j + 0.5))


## Where a selected tube's top ball hovers, just above the mouth.
func _raised(r: Rect2, ball: float) -> Vector2:
	return Vector2(r.position.x + r.size.x / 2.0, r.position.y - ball * 0.62)


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	FX.draw_background(self, Rect2(Vector2.ZERO, size))
	if tubes.is_empty():
		return
	var lay := _layout()
	var rects: Array = lay.rects
	var ball: float = lay.ball
	if ball < 4.0:  # not laid out yet (size is zero on the first frame)
		return
	for r: Rect2 in rects:  # contact shadows first so no tube covers another's
		FX.draw_shadow(self, Rect2(r.position.x - r.size.x * 0.25, r.end.y - 14.0, r.size.x * 1.5, 30.0))
	for i in tubes.size():
		_draw_tube(i, rects[i], ball)
	for f in _flyers:
		_draw_ball(_flyer_pos(f), ball * 0.46, f["c"], true)


func _draw_tube(i: int, r: Rect2, ball: float) -> void:
	var sel := i == selected
	var complete := _is_complete(i) and _hidden[i] == 0
	var bottom_radius := int(r.size.x / 2.0)

	# glow: pulsing tangerine when selected, a lemon flash when completed
	var glow := _pulse[i]
	var glow_col: Color = LEMON
	if sel:
		glow = maxf(glow, 0.6 + 0.2 * sin(_time * 6.0))
		glow_col = TANGERINE
	elif _solved and complete:
		glow = maxf(glow, 0.45)
	if glow > 0.0:
		_sb_glow.draw_center = false
		_sb_glow.bg_color = Color(0, 0, 0, 0)
		_sb_glow.shadow_color = Color(glow_col, 0.55 * glow)
		_sb_glow.shadow_size = 20
		_set_tube_corners(_sb_glow, bottom_radius)
		draw_style_box(_sb_glow, r)

	# glass body
	_sb_glass.bg_color = Color(0.04, 0.03, 0.14, 0.5)
	_sb_glass.border_color = TANGERINE if sel else Color(1, 1, 1, 0.38)
	_sb_glass.set_border_width_all(4 if sel else 3)
	_set_tube_corners(_sb_glass, bottom_radius)
	draw_style_box(_sb_glass, r)

	# balls (the raised top ball is drawn last, in front of the rim)
	var rad := ball * 0.46
	var shown: int = tubes[i].size() - _hidden[i]
	var raised := -1
	if shown > 0 and _lift[i] > 0.0 and _hidden[i] == 0:
		raised = shown - 1
	for j in shown:
		if j != raised:
			_draw_ball(_slot(r, ball, j), rad, tubes[i][j], false)

	# glass reflections over the balls
	_sb_streak.set_corner_radius_all(int(r.size.x * 0.1))
	_sb_streak.bg_color = Color(1, 1, 1, 0.16)
	draw_style_box(_sb_streak, Rect2(r.position.x + r.size.x * 0.13, r.position.y + 14.0,
		r.size.x * 0.11, r.size.y - r.size.x * 0.55 - 14.0))
	_sb_streak.bg_color = Color(1, 1, 1, 0.07)
	draw_style_box(_sb_streak, Rect2(r.position.x + r.size.x * 0.76, r.position.y + 18.0,
		r.size.x * 0.06, r.size.y * 0.5))

	# rim
	_sb_lip.set_corner_radius_all(7)
	_sb_lip.bg_color = TANGERINE if sel else (LEMON if complete else Color(1, 1, 1, 0.5))
	draw_style_box(_sb_lip, Rect2(r.position.x - 6.0, r.position.y - 5.0, r.size.x + 12.0, 12.0))

	if raised != -1:
		var p := _slot(r, ball, raised).lerp(_raised(r, ball), FX.ease_smooth(_lift[i]))
		_draw_ball(p, rad, tubes[i][raised], true)


func _set_tube_corners(sb: StyleBoxFlat, bottom_radius: int) -> void:
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = bottom_radius
	sb.corner_radius_bottom_right = bottom_radius


func _draw_ball(c: Vector2, rad: float, idx: int, airborne: bool) -> void:
	FX.draw_ball(self, c, rad, PALETTE[posmod(idx, PALETTE.size())], str(idx + 1), airborne)
