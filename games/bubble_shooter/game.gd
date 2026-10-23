extends BaseGame
## Bubble Burst: drag to aim, release to shoot. Bubbles stick in a hex grid, 3+ of a colour pop
## and anything left hanging falls. Goals: clear everything, pop N of one colour, or free gems.
## Everything is drawn in _draw(); game logic is instant, the pops and falls are just visuals.

const FX := preload("res://core/fx.gd")

const COLS := 9
const EMPTY := -1
const VOID := -2  # unused cell at the end of an indented row
const SPEED := 1900.0
const COLORS: Array[Color] = [
	Color("#FF8A1F"), Color("#FFD23F"), Color("#FF5C8A"), Color("#2EC4B6"), Color("#5CC8FF"), Color("#9B6BFF"),
]
const COLOR_NAMES: Array[String] = ["orange", "yellow", "pink", "teal", "blue", "violet"]
const GEM := Color("#FFFFFF")
## Bubble sprites are baked once at this size (px, with mipmaps) and tinted per colour, so they stay
## smooth and round at any screen size instead of the jagged edge of a plain draw_circle.
const TEX_SIZE := 256
const TEX_PAD := 3.0

static var _body_tex: ImageTexture  # greyscale lit sphere with a darker rim; modulate gives the colour
static var _spec_tex: ImageTexture  # white gloss: soft highlight, sharp glint, bounce light at the bottom

var rows: Array = []   # Array[PackedInt32Array], COLS entries per row
var gem_rows: Array = []  # Array[PackedByteArray], 1 = bubble holds a gem
var par := 0           # parity shift: flips each time the ceiling adds a row on top
var rng: RandomNumberGenerator
var colors_n := 3
var goal := "clear"
var target_color := 0
var target_n := 0
var popped_target := 0
var gems_total := 0
var gems_freed := 0
var shots_left := 0
var shots_fired := 0
var score := 0
var since_drop := 0
var endless := false
var drop_every := 0
var cur := 0
var nxt := 0
var over := false
var aiming := false
var swap_tap := false
var press_pos := Vector2.ZERO
var aim_dir := Vector2.UP
var flying := false
var fly_pos := Vector2.ZERO
var fly_dir := Vector2.UP
var fly_color := 0
var slide := 0.0
var pops: Array = []    # {pos, color, t}
var falls: Array = []   # {pos, vel, color, gem}
var rings: Array = []   # {pos, t}

var r := 36.0
var row_h := 62.0
var left := 12.0
var top := 70.0
var shooter := Vector2.ZERO
var line_y := 0.0
var max_row := 10


func _on_start() -> void:
	_bake_textures()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rng = make_rng()
	goal = str(level.get("goal", "clear"))
	colors_n = clampi(int(level.get("colors", 3)), 2, COLORS.size())
	endless = is_endless()
	score = 0
	since_drop = 0
	shots_left = 9999 if endless else int(level.get("shots", 30))
	drop_every = int(level.get("drop_every", 0))
	target_color = clampi(int(level.get("target_color", 0)), 0, colors_n - 1)
	target_n = int(level.get("target_n", 0))
	over = false
	flying = false
	aiming = false
	slide = 0.0
	shots_fired = 0
	popped_target = 0
	gems_freed = 0
	pops.clear()
	falls.clear()
	rings.clear()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	_layout()
	_build_grid()
	cur = _pick_color()
	nxt = _pick_color()
	_report()
	queue_redraw()


func _on_resized() -> void:
	_layout()
	queue_redraw()


func _layout() -> void:
	r = (size.x - 24.0) / (2.0 * COLS)
	row_h = r * sqrt(3.0)
	left = (size.x - 2.0 * r * COLS) / 2.0
	top = 74.0
	shooter = Vector2(size.x / 2.0, size.y - 96.0)
	line_y = shooter.y - r * 2.6
	max_row = maxi(6, int((line_y - top - r) / row_h))


# --- grid helpers -------------------------------------------------------------

func _shift(y: int) -> int:
	return (y + par) & 1


func _valid(y: int, c: int) -> bool:
	return y >= 0 and y < rows.size() and c >= 0 and c < COLS and rows[y][c] != VOID


func _pos(y: int, c: int) -> Vector2:
	return Vector2(left + r + 2.0 * r * c + _shift(y) * r, top + r + y * row_h + slide)


func _new_row(y_shift: int) -> PackedInt32Array:
	var row := PackedInt32Array()
	row.resize(COLS)
	row.fill(EMPTY)
	if y_shift == 1:
		row[COLS - 1] = VOID
	return row


func _ensure_rows(n: int) -> void:
	while rows.size() < n:
		rows.append(_new_row(_shift(rows.size())))
		var g := PackedByteArray()
		g.resize(COLS)
		gem_rows.append(g)


func _neighbors(y: int, c: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var s := _shift(y)
	var cand: Array[Vector2i] = [Vector2i(c - 1, y), Vector2i(c + 1, y)]
	for dy in [-1, 1]:
		cand.append(Vector2i(c - 1 + s, y + dy))
		cand.append(Vector2i(c + s, y + dy))
	for v in cand:
		if _valid(v.y, v.x):
			out.append(v)
	return out


func _present_colors() -> Array[int]:
	var seen := {}
	for row: PackedInt32Array in rows:
		for v in row:
			if v >= 0:
				seen[v] = true
	var out: Array[int] = []
	for k in seen:
		out.append(k)
	out.sort()
	return out


## Endless: number of colours in play grows with score (3 -> 6).
func _cur_colors() -> int:
	if not endless:
		return colors_n
	return clampi(3 + int(difficulty(score) * 3.99), 3, COLORS.size())


func _pick_color() -> int:
	var present := _present_colors()
	if present.is_empty():
		return rng.randi_range(0, _cur_colors() - 1)
	if goal == "color" and present.has(target_color) and rng.randf() < 0.3:
		return target_color
	return present[rng.randi_range(0, present.size() - 1)]


func _build_grid() -> void:
	rows.clear()
	gem_rows.clear()
	par = 0
	var n := 5 if endless else int(level.get("rows", 5))
	var layout := "full" if endless else str(level.get("layout", "full"))
	_ensure_rows(n)
	for y in n:
		for c in COLS:
			if rows[y][c] == VOID:
				continue
			var hole := 0.0
			if y > 0:
				match layout:
					"gaps": hole = 0.16
					"pillars": hole = 0.5 if (c % 3 == 1 and y > 1) else 0.05
					"hang": hole = 0.35 if y > 2 else 0.04
			if rng.randf() < hole:
				continue
			var col := rng.randi_range(0, _cur_colors() - 1)
			if rng.randf() < 0.45:  # clump colours a little so matches are possible
				if c > 0 and rows[y][c - 1] >= 0:
					col = rows[y][c - 1]
				elif y > 0 and _valid(y - 1, c) and rows[y - 1][c] >= 0:
					col = rows[y - 1][c]
			rows[y][c] = col
	_drop_floaters(false)
	gems_total = 0
	if goal == "gems" and not endless:
		var spots: Array[Vector2i] = []
		for y in range(1, rows.size()):
			for c in COLS:
				if rows[y][c] >= 0:
					spots.append(Vector2i(c, y))
		var want := mini(int(level.get("gems", 3)), spots.size())
		for i in want:
			var k := rng.randi_range(0, spots.size() - 1)
			gem_rows[spots[k].y][spots[k].x] = 1
			spots.remove_at(k)
			gems_total += 1
	if goal == "color" and not endless:
		var have := 0
		for row: PackedInt32Array in rows:
			for v in row:
				if v == target_color:
					have += 1
		if have == 0:  # guarantee the target colour exists
			rows[0][0] = target_color
			have = 1
		target_n = mini(target_n, have)


## Removes bubbles not connected to the ceiling row. Returns how many (visual fall if `animate`).
func _drop_floaters(animate: bool) -> int:
	var attached := {}
	var stack: Array[Vector2i] = []
	if rows.size() > 0:
		for c in COLS:
			if rows[0][c] >= 0:
				attached[Vector2i(c, 0)] = true
				stack.append(Vector2i(c, 0))
	while not stack.is_empty():
		var v: Vector2i = stack.pop_back()
		for nb in _neighbors(v.y, v.x):
			if rows[nb.y][nb.x] >= 0 and not attached.has(nb):
				attached[nb] = true
				stack.append(nb)
	var n := 0
	for y in rows.size():
		for c in COLS:
			if rows[y][c] >= 0 and not attached.has(Vector2i(c, y)):
				if animate:
					_count_removed(rows[y][c], gem_rows[y][c] == 1)
					falls.append({"pos": _pos(y, c), "vel": Vector2(rng.randf_range(-120, 120), rng.randf_range(-260, -60)),
						"color": rows[y][c], "gem": gem_rows[y][c] == 1})
				rows[y][c] = EMPTY
				gem_rows[y][c] = 0
				n += 1
	return n


func _count_removed(color: int, gem: bool) -> void:
	if gem:
		gems_freed += 1
	if color == target_color:
		popped_target += 1


func _has_bubbles() -> bool:
	for row: PackedInt32Array in rows:
		for v in row:
			if v >= 0:
				return true
	return false


# --- shooting -------------------------------------------------------------------

## Follows a shot from `from` along `dir` (bouncing off the side walls) until it would stick.
## Returns {"pts": Array[Vector2] of bounce points + end, "end": Vector2, "cell": Vector2i}.
func trace(from: Vector2, dir: Vector2) -> Dictionary:
	var p := from
	var d := dir.normalized()
	var pts: Array[Vector2] = [from]
	var step := r * 0.35
	var xmin := left + r
	var xmax := left + 2.0 * r * COLS - r
	for i in 4000:
		p += d * step
		if p.x < xmin:
			p.x = xmin + (xmin - p.x)
			d.x = absf(d.x)
			pts.append(Vector2(xmin, p.y))
		elif p.x > xmax:
			p.x = xmax - (p.x - xmax)
			d.x = -absf(d.x)
			pts.append(Vector2(xmax, p.y))
		if p.y <= top + r + slide or _hits_bubble(p):
			break
	pts.append(p)
	return {"pts": pts, "end": p, "cell": _snap_cell(p)}


func _hits_bubble(p: Vector2) -> bool:
	var ry := int((p.y - top - r - slide) / row_h)
	for y in range(maxi(0, ry - 1), mini(rows.size(), ry + 3)):
		for c in COLS:
			if rows[y][c] >= 0 and _pos(y, c).distance_squared_to(p) < (r * 1.78) * (r * 1.78):
				return true
	return false


func _snap_cell(p: Vector2) -> Vector2i:
	var ry := int(round((p.y - top - r - slide) / row_h))
	_ensure_rows(ry + 2)
	var best := Vector2i(-1, -1)
	var bd := INF
	for y in range(maxi(0, ry - 1), ry + 2):
		for c in COLS:
			if rows[y][c] == EMPTY:
				var d := _pos(y, c).distance_squared_to(p)
				if d < bd:
					bd = d
					best = Vector2i(c, y)
	return best


func can_shoot() -> bool:
	return not over and not flying and slide == 0.0


## Fires the current bubble along dir (must point upward).
func shoot(dir: Vector2) -> void:
	if not can_shoot():
		return
	flying = true
	fly_pos = shooter
	fly_dir = dir.normalized()
	fly_color = cur
	Feedback.sfx("tap")
	Feedback.vibrate(8)
	queue_redraw()


func swap() -> void:
	if not can_shoot():
		return
	var t := cur
	cur = nxt
	nxt = t
	Feedback.sfx("select")
	queue_redraw()


func _process(delta: float) -> void:
	var dirty := false
	if flying:
		_fly(delta)
		dirty = true
	for i in range(pops.size() - 1, -1, -1):
		pops[i].t += delta * 4.0
		if pops[i].t >= 1.0:
			pops.remove_at(i)
		dirty = true
	for i in range(rings.size() - 1, -1, -1):
		rings[i].t += delta * 3.0
		if rings[i].t >= 1.0:
			rings.remove_at(i)
		dirty = true
	for i in range(falls.size() - 1, -1, -1):
		var f: Dictionary = falls[i]
		f.vel.y += 2400.0 * delta
		f.pos += f.vel * delta
		if f.pos.y > size.y + 80.0:
			falls.remove_at(i)
		dirty = true
	if dirty or aiming:
		queue_redraw()


func _fly(delta: float) -> void:
	var xmin := left + r
	var xmax := left + 2.0 * r * COLS - r
	var left_dist := SPEED * delta
	while left_dist > 0.0 and flying:
		var s := minf(left_dist, r * 0.4)
		left_dist -= s
		fly_pos += fly_dir * s
		if fly_pos.x < xmin:
			fly_pos.x = xmin + (xmin - fly_pos.x)
			fly_dir.x = absf(fly_dir.x)
		elif fly_pos.x > xmax:
			fly_pos.x = xmax - (fly_pos.x - xmax)
			fly_dir.x = -absf(fly_dir.x)
		if fly_pos.y <= top + r + slide or _hits_bubble(fly_pos):
			flying = false
			_land(_snap_cell(fly_pos), fly_color)


func _land(cell: Vector2i, color: int) -> void:
	shots_left -= 1
	shots_fired += 1
	rows[cell.y][cell.x] = color
	gem_rows[cell.y][cell.x] = 0
	var group := _flood(cell, color)
	var total := 0
	since_drop += 1
	if group.size() >= 3:
		for v: Vector2i in group:
			_count_removed(rows[v.y][v.x], gem_rows[v.y][v.x] == 1)
			pops.append({"pos": _pos(v.y, v.x), "color": color, "t": 0.0})
			rows[v.y][v.x] = EMPTY
			gem_rows[v.y][v.x] = 0
		var floaters := _drop_floaters(true)
		total = group.size() + floaters
		score += group.size() * 10 + floaters * 20
		Feedback.sfx("pop")
		if total >= 6:
			Feedback.sfx("clear")
			Feedback.vibrate(30)
		var mid := _pos(cell.y, cell.x)
		FX.burst(self, mid, [COLORS[color], Color.WHITE], 10 + mini(total * 3, 30), 0.8 + total * 0.04)
		if total >= 8:
			FX.shake(self, 6.0 + minf(total, 16.0), 0.35)
	else:
		Feedback.sfx("place")
		rings.append({"pos": _pos(cell.y, cell.x), "t": 0.0})
	cur = nxt
	_trim_rows()
	nxt = _pick_color()
	if endless:
		if not _has_bubbles():  # board cleared: bonus and a fresh start
			score += 200
			for i in 3:
				_add_top_row()
			since_drop = 0
		elif since_drop >= _drop_interval():
			since_drop = 0
			_add_top_row()
	elif drop_every > 0 and shots_fired % drop_every == 0 and not _goal_met():
		_add_top_row()
	_report()
	_check_end()
	queue_redraw()


func _flood(start: Vector2i, color: int) -> Array[Vector2i]:
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	var out: Array[Vector2i] = []
	while not stack.is_empty():
		var v: Vector2i = stack.pop_back()
		out.append(v)
		for nb in _neighbors(v.y, v.x):
			if rows[nb.y][nb.x] == color and not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	return out


## Size of the group the shot would make if it stuck at `cell` (used by aim hints and the test bot).
func match_size(cell: Vector2i, color: int) -> int:
	if cell.x < 0 or rows[cell.y][cell.x] != EMPTY:
		return 0
	rows[cell.y][cell.x] = color
	var n := _flood(cell, color).size()
	rows[cell.y][cell.x] = EMPTY
	return n


func _trim_rows() -> void:
	while rows.size() > 1 and _row_empty(rows.size() - 1):
		rows.pop_back()
		gem_rows.pop_back()


func _row_empty(y: int) -> bool:
	for v in rows[y]:
		if v >= 0:
			return false
	return true


## Endless: shots between ceiling drops shrinks with score (7 -> 3).
func _drop_interval() -> int:
	return int(round(lerpf(7.0, 3.0, difficulty(score))))


func _add_top_row() -> void:
	par ^= 1
	var row := _new_row(_shift(0))
	var present := _present_colors()
	var holes := 0.28 * difficulty(score) if endless else 0.0  # awkward gappy rows later on
	for c in COLS:
		if row[c] != VOID:
			if endless:
				row[c] = EMPTY if rng.randf() < holes else rng.randi_range(0, _cur_colors() - 1)
			else:
				row[c] = present[rng.randi_range(0, present.size() - 1)] if not present.is_empty() else 0
	rows.insert(0, row)
	var g := PackedByteArray()
	g.resize(COLS)
	gem_rows.insert(0, g)
	slide = -row_h
	var tw := create_tween()
	tw.tween_property(self, "slide", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Feedback.sfx("locked")
	FX.shake(self, 5.0, 0.25)


func _goal_met() -> bool:
	if endless:
		return false
	match goal:
		"gems":
			return gems_freed >= gems_total
		"color":
			return popped_target >= target_n
	return not _has_bubbles()


func _lowest_row() -> int:
	for y in range(rows.size() - 1, -1, -1):
		if not _row_empty(y):
			return y
	return -1


func _check_end() -> void:
	if endless:
		_drop_floaters(true)  # a new row can strand nothing, but holes might
		if _lowest_row() > max_row:
			over = true
			Feedback.vibrate(40)
			get_tree().create_timer(0.7).timeout.connect(func() -> void: end_run(score))
		return
	if _goal_met():
		over = true
		var st := maxi(1, stars_for(shots_left))
		get_tree().create_timer(0.7).timeout.connect(func() -> void: win(st))
	elif _lowest_row() > max_row or shots_left <= 0:
		over = true
		Feedback.vibrate(40)
		get_tree().create_timer(0.7).timeout.connect(fail)


func _report() -> void:
	if endless:
		report_score(score)
		return
	var goal_txt := ""
	match goal:
		"gems":
			goal_txt = "Gems %d/%d" % [gems_freed, gems_total]
		"color":
			goal_txt = "%s %d/%d" % [COLOR_NAMES[target_color].capitalize(), popped_target, target_n]
		_:
			goal_txt = "Clear all"
	status_changed.emit("%s  ·  Shots %d" % [goal_txt, shots_left])
	report_progress(shots_left, false)


# --- input ---------------------------------------------------------------------
# Only mouse events are used: a real touch also arrives as an emulated mouse event (and a real
# mouse as an emulated touch), so ignoring touch events means every tap is handled once.

func _gui_input(event: InputEvent) -> void:
	if over:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not can_shoot():
				return
			var preview := Vector2(shooter.x - r * 4.2, shooter.y + r * 0.2)
			press_pos = event.position
			swap_tap = event.position.distance_to(preview) < r * 1.6 or event.position.distance_to(shooter) < r * 1.2
			aiming = not swap_tap or event.position.distance_to(shooter) < r * 1.2
			if aiming:
				_aim_to(event.position)
		elif aiming or swap_tap:
			var moved: float = event.position.distance_to(press_pos)
			aiming = false
			if swap_tap and moved < r * 0.8:
				swap()  # a tap on the shooter or the preview swaps
			elif event.position.distance_to(shooter) > r * 1.3 and aim_dir.y < -0.12:
				shoot(aim_dir)
			swap_tap = false
			queue_redraw()
	elif event is InputEventMouseMotion and aiming:
		_aim_to(event.position)


func _aim_to(p: Vector2) -> void:
	var d := p - shooter
	if d.length() < 4.0:
		return
	d = d.normalized()
	if d.y > -0.12:  # keep it upward-ish so shots never go flat
		d = Vector2((1.0 if d.x >= 0.0 else -1.0) * sqrt(1.0 - 0.0144), -0.12)
	aim_dir = d


# --- drawing -------------------------------------------------------------------

static func _bake_textures() -> void:
	if _body_tex != null:
		return
	var body := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var spec := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var half := TEX_SIZE / 2.0
	var rad := half - TEX_PAD
	var light := Vector3(-0.4, -0.55, 0.73).normalized()
	for py in TEX_SIZE:
		for px in TEX_SIZE:
			var dx := px + 0.5 - half
			var dy := py + 0.5 - half
			var dist := sqrt(dx * dx + dy * dy)
			var cov := clampf(rad - dist + 0.5, 0.0, 1.0)  # analytic anti-aliased edge
			if cov <= 0.0:
				continue
			var u := dx / rad
			var v := dy / rad
			var d := minf(dist / rad, 1.0)
			var n := Vector3(u, v, sqrt(maxf(0.0, 1.0 - d * d)))
			var lit := minf(1.0, 0.6 + 0.48 * maxf(0.0, n.dot(light)))
			lit *= 1.0 - 0.22 * smoothstep(0.76, 1.0, d)
			lit *= 1.0 - 0.32 * smoothstep(0.93, 0.99, d)
			body.set_pixel(px, py, Color(lit, lit, lit, cov))
			var e := pow((u + 0.33) / 0.38, 2.0) + pow((v + 0.4) / 0.26, 2.0)
			var g := 0.8 * (1.0 - smoothstep(0.25, 1.0, e))
			var e2 := pow((u + 0.42) / 0.1, 2.0) + pow((v + 0.44) / 0.08, 2.0)
			g = maxf(g, 1.0 - smoothstep(0.45, 1.0, e2))
			var rim := smoothstep(0.62, 0.9, d) * (1.0 - smoothstep(0.9, 0.985, d))
			g = maxf(g, 0.3 * rim * smoothstep(0.15, 0.75, v * 0.85 + u * 0.35))
			if g > 0.0:
				spec.set_pixel(px, py, Color(1, 1, 1, g * cov))
	body.generate_mipmaps()
	spec.generate_mipmaps()
	_body_tex = ImageTexture.create_from_image(body)
	_spec_tex = ImageTexture.create_from_image(spec)


func _draw_bubble(c: Vector2, color: int, gem := false, scale_ := 1.0) -> void:
	var rad := r * 0.97 * scale_
	var h := rad * (TEX_SIZE / 2.0) / (TEX_SIZE / 2.0 - TEX_PAD)
	var rect := Rect2(c.x - h, c.y - h, h * 2.0, h * 2.0)
	draw_texture_rect(_body_tex, Rect2(rect.position + Vector2(0, rad * 0.1), rect.size), false, Color(0, 0, 0, 0.22))
	draw_texture_rect(_body_tex, rect, false, COLORS[color])
	draw_texture_rect(_spec_tex, rect, false)
	if gem:
		var s := r * 0.42 * scale_
		var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.8, 0), c + Vector2(0, s), c + Vector2(-s * 0.8, 0)])
		draw_colored_polygon(pts, Color(1, 1, 1, 0.92))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0.2, 0.2, 0.4, 0.8), 2.0, true)
		draw_line(c + Vector2(-s * 0.8, 0), c + Vector2(s * 0.8, 0), Color(0.4, 0.5, 0.9, 0.7), 1.5)


func _draw() -> void:
	if rows.is_empty():
		return
	FX.draw_background(self, Rect2(Vector2.ZERO, size))
	var goal_text := "Clear every bubble"
	if endless:
		goal_text = "Hold the line!"
	match goal:
		"gems" when not endless:
			goal_text = "Free %d gems (%d left)" % [gems_total, gems_total - gems_freed]
		"color" when not endless:
			goal_text = "Pop %d %s bubbles" % [target_n, COLOR_NAMES[target_color]]
	FX.draw_text_centered(self, Vector2(size.x / 2.0, 30), goal_text, 34, FX.LEMON, FX.font())
	# play field with a danger line
	var field := Rect2(left - 4.0, top - 6.0, 2.0 * r * COLS + 8.0, line_y - top + 12.0)
	FX.draw_round_gradient(self, field, 18.0, Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.02))
	var warn := _lowest_row() >= max_row - 1
	var lc := Color(1.0, 0.35, 0.35, 0.9 if warn else 0.45)
	var x := left
	while x < left + 2.0 * r * COLS:
		draw_line(Vector2(x, line_y), Vector2(minf(x + 14.0, left + 2.0 * r * COLS), line_y), lc, 3.0)
		x += 26.0
	# bubbles
	for y in rows.size():
		for c in COLS:
			var v: int = rows[y][c]
			if v >= 0:
				_draw_bubble(_pos(y, c), v, gem_rows[y][c] == 1)
	for p in pops:
		var k: float = p.t
		_draw_bubble(p.pos, p.color, false, 1.0 + k * 0.5)
		draw_arc(p.pos, r * (1.0 + k * 1.6), 0.0, TAU, 32, Color(1, 1, 1, 1.0 - k), 4.0 * (1.0 - k) + 1.0, true)
	for f in falls:
		_draw_bubble(f.pos, f.color, f.gem)
	for g in rings:
		draw_arc(g.pos, r * (0.9 + g.t * 0.7), 0.0, TAU, 32, Color(1, 1, 1, 0.6 * (1.0 - g.t)), 3.0, true)
	# aim guide
	if aiming and can_shoot():
		var t := trace(shooter, aim_dir)
		var pts: Array[Vector2] = t.pts
		var carry := 0.0
		var alpha_n := 0.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var seg := a.distance_to(b)
			var dpos := carry
			while dpos < seg:
				var pp := a.lerp(b, dpos / seg)
				var fade := clampf(1.0 - (alpha_n + dpos) / 1500.0, 0.2, 1.0)
				draw_texture_rect(_body_tex, Rect2(pp - Vector2(5.5, 5.5), Vector2(11, 11)), false,
						Color(1, 1, 1, 0.8 * fade))
				dpos += 30.0
			carry = dpos - seg
			alpha_n += seg
		var cell: Vector2i = t.cell
		if cell.x >= 0:
			var gp := _pos(cell.y, cell.x)
			draw_texture_rect(_body_tex, Rect2(gp - Vector2.ONE * r, Vector2.ONE * r * 2.0), false,
					Color(COLORS[cur], 0.28))
	# shooter, current and next bubble
	FX.draw_shadow(self, Rect2(shooter.x - r * 1.6, shooter.y + r * 0.5, r * 3.2, r * 1.1), 0.5)
	FX.draw_round_gradient(self, Rect2(shooter.x - r * 1.5, shooter.y - r * 0.2, r * 3.0, r * 1.5), r * 0.6,
			FX.TANGERINE, FX.TANGERINE.darkened(0.45))
	if not flying:
		_draw_bubble(shooter, cur)
	var np := Vector2(shooter.x - r * 4.2, shooter.y + r * 0.2)
	draw_texture_rect(_body_tex, Rect2(np - Vector2.ONE * r * 1.07, Vector2.ONE * r * 2.14), false, Color(0, 0, 0, 0.25))
	_draw_bubble(np, nxt, false, 0.72)
	FX.draw_text_centered(self, np + Vector2(0, r * 1.45), "NEXT", 18, Color(1, 1, 1, 0.6), FX.font())
	if flying:
		_draw_bubble(fly_pos, fly_color)
