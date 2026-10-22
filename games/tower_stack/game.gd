extends BaseGame
## Sky Stacker: a block slides side to side, tap to drop it on the tower. Whatever overhangs is
## sliced off and falls away; a near-exact drop is "perfect" (snaps, glows, builds a combo, and
## after a few in a row the block grows back a little). Reach target_height drops to win.
## Level data: target_height, speed (px/s), speed_step (added per drop), block_width, tolerance
## (px counted as perfect), wind (0..1, speed wobble), sway (px, the slide range drifts),
## stars [0, perfects_for_2, perfects_for_3]; 1 star is the win itself.
##
## The HUD star meter is fed by report_progress(perfects) (star metric: perfect drops).
## All x values are measured from the horizontal centre; world y is up-negative from the ground.

const FX := preload("res://core/fx.gd")
const INDIGO := Color("#2B2A6B")
const TANGERINE := Color("#FF8A1F")
const LEMON := Color("#FFD23F")
const BLOCK_H := 52.0
const MARGIN := 24.0
const GROUND_PAD := 150.0  # ground line sits this far above the bottom edge
const MIN_OVERLAP := 6.0  # less than this and the block misses
const GRAVITY := 2600.0
const SPEED_CAP := 1.7  # speed never exceeds this multiple of the level's base speed
const REGROW := 10.0
const REGROW_COMBO := 3  # perfects in a row before the block regrows
const END_DELAY := 0.9  # celebrate / watch it fall before the result overlay
const SKY: Array = [  # [top, bottom] at 0, 1/3, 2/3 and 1 of the climb
	[Color("#2B2A6B"), Color("#FF9A55")],
	[Color("#231f63"), Color("#6a4fc4")],
	[Color("#120f3a"), Color("#2B2A6B")],
	[Color("#05051a"), Color("#151245")],
]
enum { PLAY, WON, LOST }

var tower: Array = []  # {x, w, col}; index 0 is the base slab
var perfects := 0
var combo := 0

var _target := 10
var _start_w := 300.0
var _w := 300.0  # width of the sliding block (= width of the tower top)
var _tol := 10.0
var _speed := 300.0
var _speed_step := 5.0
var _wind := 0.0
var _sway := 0.0
var _x := 0.0
var _dir := 1.0
var _rng := RandomNumberGenerator.new()
var _state := PLAY
var _end_t := 0.0
var _time := 0.0
var _cam := 0.0
var _flash := 0.0  # 1 -> 0 glow on the top block after a perfect
var _land := 0.0  # 1 -> 0 squash on the top block after landing
var _hint := 1.0
var _pieces: Array = []  # falling slices: {x, y, w, col, vx, vy, rot, vr}
var _pops: Array = []  # floating text: {text, x, y, t, col}
var _sky_stars: Array = []  # Vector3(x 0..1, y 0..1, phase)
var _clouds: Array = []  # Vector3(x 0..1, y 0..1, scale)


func _on_start() -> void:
	_rng = make_rng()
	_target = int(level.get("target_height", 10))
	_start_w = float(level.get("block_width", 300))
	_tol = float(level.get("tolerance", 10))
	_speed = float(level.get("speed", 300))
	_speed_step = float(level.get("speed_step", 5))
	_wind = float(level.get("wind", 0))
	_sway = float(level.get("sway", 0))
	_w = _start_w
	perfects = 0
	combo = 0
	_state = PLAY
	_time = 0.0
	_cam = 0.0
	_flash = 0.0
	_land = 0.0
	_hint = 1.0
	_pieces.clear()
	_pops.clear()
	tower = [{"x": 0.0, "w": _start_w, "col": _color(0)}]
	_sky_stars.clear()
	for i in 80:
		_sky_stars.append(Vector3(_rng.randf(), _rng.randf(), _rng.randf() * TAU))
	_clouds.clear()
	for i in 7:
		_clouds.append(Vector3(_rng.randf(), _rng.randf(), _rng.randf_range(0.7, 1.5)))
	_spawn_slider()
	_report()
	queue_redraw()


# --- progress helpers --------------------------------------------------------

func height() -> int:
	return tower.size() - 1


func target() -> int:
	return _target


func progress() -> float:
	return clampf(float(height()) / maxf(1.0, _target), 0.0, 1.0)


func star_thresholds() -> Array:
	return level.get("stars", [0, 0, 0])


## Stars the player would get if the level ended now (0 until the target height is reached).
func current_stars() -> int:
	return stars_for(perfects) if height() >= _target else 0


# --- logic -------------------------------------------------------------------

func _color(i: int) -> Color:
	return Color.from_hsv(fposmod(0.07 + i * 0.047, 1.0), 0.72, 1.0)


func _speed_now() -> float:
	return minf(_speed + _speed_step * height(), _speed * SPEED_CAP)


func _bounds() -> Vector2:
	var half := size.x / 2.0 - MARGIN - _w / 2.0
	var sw := minf(_sway, maxf(0.0, half - 130.0))
	var c := sw * sin(_time * 0.8)
	return Vector2(-(half - sw) + c, (half - sw) + c)


func _spawn_slider() -> void:
	var b := _bounds()
	if _rng.randf() < 0.5:
		_x = b.x
		_dir = 1.0
	else:
		_x = b.y
		_dir = -1.0


func _report() -> void:
	status_changed.emit("Height %d / %d   Perfect %d" % [height(), _target, perfects])
	report_progress(perfects)


func _slide(delta: float) -> void:
	var b := _bounds()
	var v := _speed_now() * clampf(1.0 + _wind * sin(_time * 2.1), 0.4, 2.0)
	_x += _dir * v * delta
	if _x > b.y:
		_x = b.y
		_dir = -1.0
	elif _x < b.x:
		_x = b.x
		_dir = 1.0


func drop() -> void:
	if _state != PLAY:
		return
	_hint = 0.0
	var top: Dictionary = tower[-1]
	var n := tower.size()
	var off := _x - float(top.x)
	var col := _color(n)
	var wy := -(n + 0.5) * BLOCK_H
	if absf(off) <= _tol:
		combo += 1
		perfects += 1
		var nw := _w
		if combo >= REGROW_COMBO:
			nw = minf(_start_w, _w + REGROW)
		_w = nw
		tower.append({"x": top.x, "w": nw, "col": col})
		_flash = 1.0
		_land = 1.0
		var label := "Perfect!" if combo < 2 else "Perfect x%d" % combo
		_pops.append({"text": label, "x": top.x, "y": wy - BLOCK_H * 2.2, "t": 0.0, "col": LEMON})
		FX.burst(self, Vector2(size.x / 2.0 + float(top.x), _sy(wy)), [LEMON, TANGERINE, Color.WHITE], 22)
		Feedback.sfx("merge")
		Feedback.vibrate(15)
	else:
		combo = 0
		var l := maxf(_x - _w / 2.0, float(top.x) - float(top.w) / 2.0)
		var r := minf(_x + _w / 2.0, float(top.x) + float(top.w) / 2.0)
		if r - l < MIN_OVERLAP:
			_pieces.append(_piece(_x - _w / 2.0, _x + _w / 2.0, wy, col, signf(off)))
			_state = LOST
			_end_t = END_DELAY
			FX.shake(self, 16.0, 0.4)
			Feedback.sfx("locked")
			Feedback.vibrate(60)
			_report()
			return
		if off > 0.0:
			_pieces.append(_piece(r, _x + _w / 2.0, wy, col, 1.0))
		else:
			_pieces.append(_piece(_x - _w / 2.0, l, wy, col, -1.0))
		_w = r - l
		tower.append({"x": (l + r) / 2.0, "w": _w, "col": col})
		_land = 1.0
		FX.shake(self, 7.0, 0.25)
		Feedback.sfx("place")
		Feedback.sfx("pop")
		Feedback.vibrate(25)
	_report()
	if height() >= _target:
		_state = WON
		_end_t = END_DELAY
		var tp := Vector2(size.x / 2.0 + float(tower[-1].x), _sy(-(n + 1) * BLOCK_H))
		FX.burst(self, tp, [LEMON, TANGERINE, Color.WHITE, col], 40, 1.3)
		FX.burst(self, tp + Vector2(-120, 40), [LEMON, col], 26, 1.1)
		FX.burst(self, tp + Vector2(120, 40), [TANGERINE, col], 26, 1.1)
		FX.shake(self, 10.0, 0.35)
	else:
		_spawn_slider()


func _piece(x0: float, x1: float, wy: float, col: Color, dir: float) -> Dictionary:
	return {"x": (x0 + x1) / 2.0, "y": wy, "w": x1 - x0, "col": col,
		"vx": dir * 150.0, "vy": -260.0, "rot": 0.0, "vr": dir * 2.4}


# --- input -------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
			return
	elif event is InputEventScreenTouch:
		if not event.pressed:
			return
	else:
		return
	accept_event()
	# One tap arrives as a real event plus an emulated twin (see CLAUDE.md); act on the real one.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	drop()


# --- animation ---------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	if _state == PLAY:
		_slide(delta)
	var n := tower.size() + (1 if _state == PLAY else 0)
	var cam_target := maxf(0.0, size.y * 0.32 + n * BLOCK_H - (size.y - GROUND_PAD))
	_cam += (cam_target - _cam) * (1.0 - exp(-delta * 5.0))
	_flash = maxf(0.0, _flash - delta * 2.2)
	_land = maxf(0.0, _land - delta * 7.0)
	for p in _pieces:
		p.vy += GRAVITY * delta
		p.x += p.vx * delta
		p.y += p.vy * delta
		p.rot += p.vr * delta
	_pieces = _pieces.filter(func(p): return _sy(p.y) < size.y + 200.0)
	for q in _pops:
		q.t += delta
	_pops = _pops.filter(func(q): return q.t < 1.1)
	if _state != PLAY:
		_end_t -= delta
		if _end_t <= 0.0:
			if _state == WON:
				win(maxi(1, stars_for(perfects)))
			else:
				fail()
	queue_redraw()


# --- drawing -----------------------------------------------------------------

func _sy(wy: float) -> float:
	return size.y - GROUND_PAD + wy + _cam


func _sky_col(t: float, which: int) -> Color:
	var f := clampf(t, 0.0, 1.0) * (SKY.size() - 1)
	var i := mini(int(f), SKY.size() - 2)
	return (SKY[i][which] as Color).lerp(SKY[i + 1][which], f - i)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var cx := size.x / 2.0
	var climb := _cam / maxf(1.0, _target * BLOCK_H * 0.8)
	_draw_sky(r, climb)
	var g := _sy(0.0)
	if g < size.y + 20.0:
		FX.draw_vgradient(self, Rect2(-10.0, g, size.x + 20.0, size.y - g + 20.0),
			INDIGO.lightened(0.08), INDIGO.darkened(0.55))
		draw_rect(Rect2(-10.0, g, size.x + 20.0, 8.0), TANGERINE.darkened(0.15))
	var top: Dictionary = tower[-1]
	for i in tower.size():
		var b: Dictionary = tower[i]
		var rect := Rect2(cx + float(b.x) - float(b.w) / 2.0, _sy(-(i + 1) * BLOCK_H), b.w, BLOCK_H)
		if rect.end.y < -10.0 or rect.position.y > size.y:
			continue
		if i == tower.size() - 1:
			if _flash > 0.0:
				FX.draw_glow(self, rect.grow_individual(50, 40, 50, 30), Color(LEMON, _flash * 0.9))
			var sq := 0.14 * _land
			rect = Rect2(rect.position.x - rect.size.x * sq * 0.25, rect.position.y + BLOCK_H * sq,
				rect.size.x * (1.0 + sq * 0.5), BLOCK_H * (1.0 - sq))
		FX.draw_tile(self, rect, b.col, 10)
	if _state == PLAY:
		var n := tower.size()
		var sy := _sy(-(n + 1) * BLOCK_H)
		# faint guide lines from the tower top edges up through the slider
		var gl := Color(1, 1, 1, 0.16)
		var ty := _sy(-n * BLOCK_H)
		draw_line(Vector2(cx + float(top.x) - float(top.w) / 2.0, ty), Vector2(cx + float(top.x) - float(top.w) / 2.0, sy - 40.0), gl, 2.0)
		draw_line(Vector2(cx + float(top.x) + float(top.w) / 2.0, ty), Vector2(cx + float(top.x) + float(top.w) / 2.0, sy - 40.0), gl, 2.0)
		FX.draw_tile(self, Rect2(cx + _x - _w / 2.0, sy, _w, BLOCK_H), _color(n), 10)
	for p in _pieces:
		draw_set_transform(Vector2(cx + p.x, _sy(p.y)), p.rot)
		FX.draw_tile(self, Rect2(-p.w / 2.0, -BLOCK_H / 2.0, p.w, BLOCK_H), p.col, 10, false)
	draw_set_transform(Vector2.ZERO, 0.0)
	for q in _pops:
		var k: float = q.t / 1.1
		var c: Color = q.col
		FX.draw_text_centered(self, Vector2(cx + float(q.x), _sy(q.y) - k * 70.0), q.text,
			int(46 + 10 * (1.0 - k)), Color(c, 1.0 - k * k))
	if _hint > 0.0 and _state == PLAY:
		FX.draw_text_centered(self, Vector2(cx, size.y * 0.5), "Tap to drop", 52,
			Color(1, 1, 1, 0.55 + 0.35 * sin(_time * 4.0)))
	_draw_meter(cx)


func _draw_sky(r: Rect2, t: float) -> void:
	FX.draw_vgradient(self, r, _sky_col(t, 0), _sky_col(t, 1))
	var sun := clampf(1.0 - t * 2.5, 0.0, 1.0)
	if sun > 0.0:
		FX.draw_glow(self, Rect2(-size.x * 0.3, _sy(0.0) - size.y * 0.5, size.x * 1.6, size.y * 0.7),
			Color(TANGERINE, 0.55 * sun))
	var night := smoothstep(0.1, 0.6, t)
	if night > 0.0:
		for s in _sky_stars:
			var y := fposmod(s.y * size.y + _cam * 0.2, size.y)
			var a := night * (0.35 + 0.65 * (0.5 + 0.5 * sin(_time * 1.7 + s.z)))
			draw_circle(Vector2(s.x * size.x, y), 1.5 + 1.2 * s.y, Color(1, 1, 0.9, a))
	var cloud := 1.0 - smoothstep(0.1, 0.55, t)
	if cloud > 0.0:
		for c in _clouds:
			var x := fposmod(c.x * (size.x + 400.0) + _time * 14.0 * c.z, size.x + 400.0) - 200.0
			var y := fposmod(c.y * size.y * 1.3 + _cam * 0.55, size.y * 1.3) - size.y * 0.15
			FX.draw_glow(self, Rect2(x - 130.0 * c.z, y - 34.0 * c.z, 260.0 * c.z, 68.0 * c.z),
				Color(1, 1, 1, 0.3 * cloud))


## Height counter; the stars live in the host's shared star meter (fed by report_progress).
func _draw_meter(cx: float) -> void:
	FX.draw_text_centered(self, Vector2(cx, 44.0), "%d / %d" % [height(), _target], 62)
