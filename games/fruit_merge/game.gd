extends BaseGame
## Fruit Fusion (endless): aim with a tap or drag, release to drop the next fruit into the jar.
## Two equal fruits that touch fuse into the next of 11 fruits; two melons (the last) burst for a
## bonus. Fusing tier k scores SCORE[k]. The run ends when a fruit stays above the line for
## DANGER_TIME seconds (or the jar holds MAX_FRUITS). difficulty() (BaseGame, ramping to
## "ramp_score" in games.json) widens the spawn pool toward bigger fruit and shortens the cooldown.
##
## Physics: one RigidBody2D circle per fruit, kept under a plain Node so the bodies live in this
## Control's local coordinates but ignore its transform (the host scales/fades the game; shakes move
## it). Bodies use shape-cast CCD, thick static walls and sleep when still. Nothing is drawn by the
## bodies: _draw() paints every fruit from its body's position/rotation with the FX kit.

const FX := preload("res://core/fx.gd")
const INDIGO := Color("#2B2A6B")
const TANGERINE := Color("#FF8A1F")
const LEMON := Color("#FFD23F")

## Radius of each tier in design units (jar is 600 units wide), colour, and a feature drawn on top.
## Original set: berry, strawbell, grapelet, lime, orange, apple, pear, peach, pineapple, honeydew, melon.
const RADII := [19.0, 26.0, 34.0, 41.0, 51.0, 61.0, 71.0, 83.0, 97.0, 113.0, 131.0]
const COLORS := [Color("#FF3D6E"), Color("#FF5A3C"), Color("#9B5DE5"), Color("#7ED957"), Color("#FF8A1F"),
	Color("#E8364F"), Color("#C9DB4A"), Color("#FFA98F"), Color("#FFC93C"), Color("#9EE6A0"), Color("#2EA44F")]
const SCORE := [1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 66]
const MELON_BONUS := 100  # two of the last tier burst
const LAST := 10
const SPAWN_WEIGHTS := [5.0, 4.0, 3.0, 2.0, 1.4]
const MAX_FRUITS := 72  # body cap for low-end phones
const DANGER_TIME := 2.0  # seconds a settled fruit may stay above the line
const GRACE := 1.0  # a fresh fruit may cross the line while it falls in
const COOLDOWN := [0.55, 0.38]  # seconds between drops at difficulty 0 and 1
const GRAVITY_SCALE := 1.7
const MAX_SPEED := 820.0  # px/s: under one berry radius per physics step, so nothing sinks into a fruit
const JAR_WIDTH := 600.0
const WALL := 18.0  # drawn wall thickness; the physics walls are much thicker
const TOP := 235.0  # y of the jar rim / danger line
const BOTTOM := 78.0  # space under the jar for the fruit chain strip
const BIG_MERGE := 6  # tiers >= this shake the screen


class Fruit:
	var body: RigidBody2D
	var shape: CircleShape2D
	var tier := 0
	var r := 0.0  # full radius
	var grow := 1.0  # 0 -> 1: collision radius grows in after a fusion
	var age := 0.0
	var over := 0.0  # seconds spent settled above the line
	var pop := 1.0  # 0 -> 1: visual pop after a fusion
	var squash := 0.0  # landing squash, decays to 0
	var happy := 0.0  # seconds of closed happy eyes
	var vy := 0.0  # last vertical speed, to spot landings
	var dead := false


var score := 0
var fruits: Array[Fruit] = []
var rng: RandomNumberGenerator
var u := 1.0  # design unit -> pixels
var jar := Rect2()  # inner space of the jar
var drop_y := 0.0
var aim_x := 0.0
var current := 0
var next := 0
var cooldown := 0.0
var best_tier := 0
var _world: Node
var _built := false
var _finished := false
var _pressing := false
var _time := 0.0
var _danger := 0.0  # 0..1 how close the worst fruit is to ending the run
var _floats: Array = []  # {pos, text, t}
var _drops := 0
var _held_pop := 1.0
var _shake_tw: Tween


func _on_start() -> void:
	for c in get_children():
		c.queue_free()
	rng = make_rng()
	score = 0
	fruits.clear()
	_floats.clear()
	_finished = false
	_built = false
	_drops = 0
	best_tier = 0
	current = _roll()
	next = _roll()
	cooldown = 0.0
	_world = Node.new()
	_world.name = "World"
	add_child(_world)
	report_score(0)
	_try_build()


## The jar needs the real size, which is zero until the host's layout runs.
func _try_build() -> void:
	if _built or _world == null or size.x < 100.0 or size.y < 400.0:
		return
	_built = true
	var jw := minf(size.x - 64.0, JAR_WIDTH)
	u = jw / JAR_WIDTH
	jar = Rect2((size.x - jw) / 2.0, TOP, jw, size.y - BOTTOM - TOP)
	drop_y = TOP - 70.0
	aim_x = size.x / 2.0
	var walls := StaticBody2D.new()
	var mat := PhysicsMaterial.new()
	mat.friction = 0.5
	mat.bounce = 0.0
	walls.physics_material_override = mat
	var t := 400.0  # thick walls: nothing can pass through in one step
	for r in [Rect2(jar.position.x - t, -2000.0, t, jar.end.y + 2000.0 + t),
			Rect2(jar.end.x, -2000.0, t, jar.end.y + 2000.0 + t),
			Rect2(jar.position.x - t, jar.end.y, jar.size.x + t * 2.0, t)]:
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = r.size
		cs.shape = rs
		cs.position = r.get_center()
		walls.add_child(cs)
	_world.add_child(walls)
	queue_redraw()


func radius(tier: int) -> float:
	return RADII[tier] * u


## Next fruit to drop: the pool grows from 3 to 5 kinds as the score rises.
func _roll() -> int:
	var d := difficulty(score)
	var top := 2 if d < 0.25 else 3 if d < 0.6 else 4
	var total := 0.0
	for i in top + 1:
		total += SPAWN_WEIGHTS[i]
	var x := rng.randf() * total
	for i in top + 1:
		x -= SPAWN_WEIGHTS[i]
		if x <= 0.0:
			return i
	return 0


func _cooldown_time() -> float:
	return lerpf(COOLDOWN[0], COOLDOWN[1], difficulty(score))


# --- actions (also used by tests) -------------------------------------------

func can_drop() -> bool:
	return _built and not _finished and not _done and cooldown <= 0.0


## Move the dropper; x is clamped so the held fruit fits inside the jar.
func aim_at(x: float) -> void:
	if not _built:
		return
	var r := radius(current)
	aim_x = clampf(x, jar.position.x + r + 1.0, jar.end.x - r - 1.0)
	queue_redraw()


func drop() -> bool:
	if not can_drop():
		return false
	if fruits.size() >= MAX_FRUITS:
		_lose()
		return false
	aim_at(aim_x)
	var f := _add_fruit(current, Vector2(aim_x, drop_y), Vector2(0, 120))
	f.age = 0.0
	_drops += 1
	Feedback.sfx("place")
	current = next
	next = _roll()
	cooldown = _cooldown_time()
	_held_pop = 0.0
	return true


func fruit_count() -> int:
	return fruits.size()


func _add_fruit(tier: int, pos: Vector2, vel: Vector2, grown := true) -> Fruit:
	var f := Fruit.new()
	f.tier = tier
	f.r = radius(tier)
	f.grow = 1.0 if grown else 0.0
	f.pop = 1.0 if grown else 0.0
	var b := RigidBody2D.new()
	b.position = pos
	b.linear_velocity = vel
	b.mass = 0.6 + pow(RADII[tier] / RADII[0], 2.0) * 0.35
	b.gravity_scale = GRAVITY_SCALE
	b.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	b.can_sleep = true
	b.linear_damp = 0.15
	b.angular_damp = 1.6
	var mat := PhysicsMaterial.new()
	mat.friction = 0.45
	mat.bounce = 0.06
	b.physics_material_override = mat
	var cs := CollisionShape2D.new()
	f.shape = CircleShape2D.new()
	f.shape.radius = f.r * (1.0 if grown else 0.6)
	cs.shape = f.shape
	b.add_child(cs)
	_world.add_child(b)
	f.body = b
	fruits.append(f)
	return f


func _remove(f: Fruit) -> void:
	f.dead = true
	fruits.erase(f)
	f.body.queue_free()


# --- physics and rules ------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _built or _finished:
		return
	for f in fruits:
		f.age += delta
		if f.grow < 1.0:
			f.grow = minf(1.0, f.grow + delta / 0.12)
			f.shape.radius = f.r * lerpf(0.6, 1.0, f.grow)
		if f.body.linear_velocity.length_squared() > MAX_SPEED * MAX_SPEED * u * u:
			f.body.linear_velocity = f.body.linear_velocity.limit_length(MAX_SPEED * u)
		var p := f.body.position
		if p.y > jar.end.y + 300.0 or p.x < jar.position.x - 300.0 or p.x > jar.end.x + 300.0:
			push_warning("fruit escaped the jar at %s" % p)  # should never happen; keep the run alive
			f.dead = true
	for f in fruits.duplicate():
		if f.dead:
			_remove(f)
	_merge_pass()
	_check_line(delta)


## Every pair of equal touching fruits fuses (each fruit at most once per step).
func _merge_pass() -> void:
	var n := fruits.size()
	var used := {}
	var pairs: Array = []
	for i in n:
		var a := fruits[i]
		if used.has(a):
			continue
		for j in range(i + 1, n):
			var b := fruits[j]
			if b.tier != a.tier or used.has(b):
				continue
			var reach := a.shape.radius + b.shape.radius + 1.5 * u
			if a.body.position.distance_squared_to(b.body.position) <= reach * reach:
				used[a] = true
				used[b] = true
				pairs.append([a, b])
				break
	for pr in pairs:
		_fuse(pr[0], pr[1])


func _fuse(a: Fruit, b: Fruit) -> void:
	var pos: Vector2 = (a.body.position + b.body.position) / 2.0
	var vel: Vector2 = (a.body.linear_velocity + b.body.linear_velocity) / 2.0
	var tier := a.tier
	_remove(a)
	_remove(b)
	var col: Color = COLORS[tier]
	if tier == LAST:  # two melons: both burst
		_add_score(MELON_BONUS, pos)
		FX.burst(self, pos, [col, LEMON, TANGERINE, Color.WHITE], 48, 1.6)
		_shake(22.0, 0.45)
		Feedback.sfx("clear")
		Feedback.vibrate(80)
		_wake_all()
		return
	var nt := tier + 1
	var nr := radius(nt)
	pos.x = clampf(pos.x, jar.position.x + nr, jar.end.x - nr)
	pos.y = minf(pos.y, jar.end.y - nr)
	var f := _add_fruit(nt, pos, vel * 0.5, false)
	f.happy = 0.6
	best_tier = maxi(best_tier, nt)
	_add_score(SCORE[nt], pos)
	var nc: Color = COLORS[nt]
	FX.burst(self, pos, [col, nc, nc.lightened(0.4), LEMON], 10 + nt * 3, 0.5 + nt * 0.08)
	if nt >= BIG_MERGE:
		_shake(4.0 + (nt - BIG_MERGE) * 3.5, 0.3)
		Feedback.sfx("clear")
		Feedback.vibrate(40 + nt * 4)
	else:
		Feedback.sfx("merge")
		Feedback.vibrate(15)
	_wake_near(pos, nr * 2.5)


## Like FX.shake, but a new shake replaces a running one so overlapping shakes cannot leave the
## board offset (big fusions often chain).
func _shake(strength: float, time: float) -> void:
	if _shake_tw:
		_shake_tw.kill()
	position = Vector2.ZERO
	_shake_tw = create_tween()
	for i in 6:
		var k := 1.0 - i / 6.0
		_shake_tw.tween_property(self, "position", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * k, time / 7.0)
	_shake_tw.tween_property(self, "position", Vector2.ZERO, time / 7.0)


func _add_score(points: int, pos: Vector2) -> void:
	score += points
	_floats.append({"pos": pos, "text": "+%d" % points, "t": 0.0})
	report_score(score)


## A fused fruit appears in a gap; sleeping neighbours must notice it.
func _wake_near(pos: Vector2, dist: float) -> void:
	for f in fruits:
		if f.body.sleeping and f.body.position.distance_to(pos) < dist + f.r:
			f.body.sleeping = false


func _wake_all() -> void:
	for f in fruits:
		f.body.sleeping = false


func _check_line(delta: float) -> void:
	var worst := 0.0
	for f in fruits:
		var above := f.body.position.y - f.r < jar.position.y
		if above and f.age > GRACE and f.body.linear_velocity.length() < 160.0:
			f.over += delta
		else:
			f.over = maxf(0.0, f.over - delta * 2.0)
		worst = maxf(worst, f.over / DANGER_TIME)
	_danger = worst
	if worst >= 1.0:
		_lose()


## Freeze the jar, pop every fruit from the top down, then report the score.
func _lose() -> void:
	if _finished:
		return
	_finished = true
	_pressing = false
	Feedback.sfx("fail")
	Feedback.vibrate(120)
	_shake(12.0, 0.4)
	var order := fruits.duplicate()
	order.sort_custom(func(a: Fruit, b: Fruit): return a.body.position.y < b.body.position.y)
	for f in order:
		f.body.freeze = true
	var tw := create_tween()
	tw.tween_interval(0.6)
	var step := clampf(1.4 / maxf(1.0, order.size()), 0.025, 0.09)
	for i in order.size():
		var f: Fruit = order[i]
		tw.tween_callback(func():
			FX.burst(self, f.body.position, [COLORS[f.tier], Color.WHITE], 8, 0.4)
			if i % 3 == 0:
				Feedback.sfx("pop")
			_remove(f))
		tw.tween_interval(step)
	tw.tween_interval(0.5)
	tw.tween_callback(func(): end_run(score))


# --- input ------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	# Touch/mouse emulation delivers one gesture as BOTH a real and an emulated event;
	# emulated copies are skipped so one release does not drop two fruits (see CLAUDE.md).
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
		aim_at((event as InputEventMouseMotion).position.x)  # desktop: the dropper follows the pointer
		accept_event()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == 0:
			aim_at(sd.position.x)
			accept_event()


func _press_changed(pressed: bool, pos: Vector2) -> void:
	if _finished:
		return
	aim_at(pos.x)
	if pressed:
		_pressing = true
	elif _pressing:
		_pressing = false
		if not drop():
			Feedback.vibrate(8)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	match k.keycode:
		KEY_LEFT, KEY_A: aim_at(aim_x - 24.0 * u)
		KEY_RIGHT, KEY_D: aim_at(aim_x + 24.0 * u)
		KEY_SPACE, KEY_DOWN, KEY_S: drop()
		_:
			return
	get_viewport().set_input_as_handled()


# --- animation --------------------------------------------------------------

func _process(delta: float) -> void:
	if not _built:
		_try_build()
		return
	_time += delta
	if cooldown > 0.0:
		cooldown -= delta
	_held_pop = minf(1.0, _held_pop + delta / 0.25)
	for f in fruits:
		var vy := f.body.linear_velocity.y
		if f.vy > 260.0 and vy < f.vy * 0.4:  # sudden stop: landed on something
			f.squash = clampf((f.vy - vy) / 2600.0, 0.04, 0.16)
		f.vy = vy
		f.squash = move_toward(f.squash, 0.0, delta * 0.7)
		f.pop = minf(1.0, f.pop + delta / 0.35)
		f.happy = maxf(0.0, f.happy - delta)
	for fl in _floats:
		fl.t += delta / 0.8
	while not _floats.is_empty() and _floats[0].t >= 1.0:
		_floats.pop_front()
	queue_redraw()


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	FX.draw_background(self, Rect2(Vector2.ZERO, size))
	if not _built:
		return
	_draw_jar_back()
	if not _finished:
		_draw_guide()
	for f in fruits:
		var s := 1.0
		if f.pop < 1.0:  # grow in with a springy overshoot
			s = 0.6 + 0.4 * f.pop + 0.22 * sin(f.pop * PI) * (1.0 - f.pop * 0.3)
		var k := f.squash
		draw_fruit(f.body.position, f.r * s, f.tier, f.body.rotation, Vector2(1.0 + k, 1.0 - k), f.happy > 0.0)
	_draw_jar_front()
	if not _finished:
		var hs := 0.5 + 0.5 * FX.ease_smooth(_held_pop)
		draw_fruit(Vector2(aim_x, drop_y), radius(current) * hs, current, 0.0, Vector2.ONE, false,
			1.0 if cooldown <= 0.0 else 0.75)
	_draw_next()
	_draw_chain()
	for fl in _floats:
		var t: float = fl.t
		FX.draw_text_centered(self, fl.pos + Vector2(0, -30.0 - 70.0 * t), fl.text, int(30 * u + 8),
			Color(LEMON, 1.0 - t * t), FX.font())
	if _drops == 0 and not _finished:
		FX.draw_text_centered(self, Vector2(size.x / 2.0, jar.get_center().y), "Tap or drag to aim,", 32,
			Color(1, 1, 1, 0.8), FX.font())
		FX.draw_text_centered(self, Vector2(size.x / 2.0, jar.get_center().y + 42.0), "release to drop!", 32,
			Color(1, 1, 1, 0.8), FX.font())


func _draw_jar_back() -> void:
	FX.draw_shadow(self, Rect2(jar.position.x - 30.0, jar.end.y - 10.0, jar.size.x + 60.0, 60.0), 0.6)
	FX.draw_round_gradient(self, Rect2(jar.position.x - WALL, jar.position.y - 10.0, jar.size.x + WALL * 2.0,
		jar.size.y + 10.0 + WALL), 30.0, Color(1, 1, 1, 0.04), Color(0.55, 0.5, 1.0, 0.16))


func _draw_jar_front() -> void:
	var wc := INDIGO.lightened(0.32)
	var y0 := jar.position.y - 10.0
	FX.draw_tile(self, Rect2(jar.position.x - WALL, y0, WALL, jar.end.y - y0 + WALL), wc, 9, false)
	FX.draw_tile(self, Rect2(jar.end.x, y0, WALL, jar.end.y - y0 + WALL), wc, 9, false)
	FX.draw_tile(self, Rect2(jar.position.x - WALL, jar.end.y, jar.size.x + WALL * 2.0, WALL), wc, 9, false)
	# glass sheen on the left wall
	draw_rect(Rect2(jar.position.x + 6.0, jar.position.y + 20.0, 6.0, jar.size.y * 0.5), Color(1, 1, 1, 0.07))
	# danger line: dashed, turns red and pulses while a fruit is stuck above it
	var warn := clampf(_danger * 1.6, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_time * 14.0)
	var lc := Color(1, 1, 1, 0.28).lerp(Color(1.0, 0.25, 0.3, 0.6 + 0.4 * pulse), warn)
	var x := jar.position.x + 4.0
	while x < jar.end.x - 4.0:
		draw_line(Vector2(x, jar.position.y), Vector2(minf(x + 16.0, jar.end.x - 4.0), jar.position.y), lc, 4.0)
		x += 28.0
	if warn > 0.0:
		draw_rect(Rect2(jar.position.x, jar.position.y - 4.0, jar.size.x, 8.0), Color(1, 0.2, 0.3, 0.15 * warn * pulse))


func _draw_guide() -> void:
	var c := Color(1, 1, 1, 0.16 if cooldown > 0.0 else 0.32)
	var y := drop_y + radius(current) + 6.0
	while y < jar.end.y - 6.0:
		draw_line(Vector2(aim_x, y), Vector2(aim_x, minf(y + 14.0, jar.end.y - 6.0)), c, 3.0)
		y += 26.0


func _draw_next() -> void:
	var c := Vector2(size.x - 64.0, 66.0)
	draw_circle(c + Vector2(0, 4), 44.0, Color(0, 0, 0, 0.25))
	draw_circle(c, 44.0, Color(0.03, 0.02, 0.12, 0.55))
	draw_arc(c, 44.0, 0.0, TAU, 48, Color(1, 1, 1, 0.18), 3.0, true)
	FX.draw_text_centered(self, c + Vector2(-92.0, 0.0), "NEXT", 26, Color(1, 1, 1, 0.7), FX.font())
	draw_fruit(c, minf(radius(next), 32.0), next, 0.0, Vector2.ONE, false)


## The 11-fruit chain under the jar; fruits not yet made this run are dimmed.
func _draw_chain() -> void:
	var y := size.y - BOTTOM / 2.0 + 8.0
	var w := jar.size.x + WALL * 2.0
	var step := w / 11.0
	for i in 11:
		var c := Vector2(jar.position.x - WALL + step * (i + 0.5), y)
		var rr := lerpf(9.0, 20.0, float(i) / 10.0) * minf(1.0, step / 54.0)
		draw_fruit(c, rr, i, 0.0, Vector2.ONE, false, 1.0 if i <= maxi(best_tier, 4) else 0.3)


## A glossy fruit with a face. rot turns the face and stem with the body; sq squashes the whole
## fruit in screen space (x, y). alpha < 1 dims it (preview while cooling down, chain strip).
func draw_fruit(c: Vector2, r: float, tier: int, rot: float, sq: Vector2, happy: bool, alpha := 1.0) -> void:
	if r < 1.0:
		return
	var col: Color = COLORS[tier]
	if alpha < 1.0:
		col = col.lerp(INDIGO, 1.0 - alpha)
	draw_set_transform(Vector2.ZERO)
	FX.draw_shadow(self, Rect2(c.x - r * 0.85, c.y + r * 0.62, r * 1.7, r * 0.55), 0.35 * alpha)
	draw_set_transform(c, 0.0, sq)
	FX.draw_ball(self, Vector2.ZERO, r, col)
	draw_set_transform_matrix(Transform2D(0.0, sq, 0.0, c) * Transform2D(rot, Vector2.ZERO))
	_draw_skin(tier, r, col)
	if r >= 8.0:
		_draw_face(r, happy, alpha)
	draw_set_transform(Vector2.ZERO)


## Per-fruit details in local space (up = -y).
func _draw_skin(tier: int, r: float, col: Color) -> void:
	var leaf := Color("#3FBF5A")
	var stem := Color("#6B4226")
	match tier:
		0:  # berry: long curly stem
			draw_line(Vector2(0, -r * 0.85), Vector2(r * 0.35, -r * 1.55), stem, maxf(2.0, r * 0.14), true)
			_leaf(Vector2(r * 0.35, -r * 1.5), r * 0.5, 0.5, leaf)
		1:  # strawbell: seeds and a leafy cap
			for p in [Vector2(-0.45, 0.1), Vector2(0.45, 0.1), Vector2(-0.2, 0.55), Vector2(0.25, 0.5), Vector2(0, 0.25)]:
				draw_circle(p * r, maxf(1.2, r * 0.06), Color(LEMON, 0.85))
			for a in [-0.9, -0.3, 0.3, 0.9]:
				_leaf(Vector2(0, -r * 0.82), r * 0.48, a, leaf)
		2:  # grapelet: tiny stem
			draw_line(Vector2(0, -r * 0.9), Vector2(0, -r * 1.25), stem, maxf(2.0, r * 0.1), true)
			_leaf(Vector2(0, -r * 1.15), r * 0.42, 0.9, leaf)
		3:  # lime: light rind ring
			draw_arc(Vector2.ZERO, r * 0.82, 0.0, TAU, 32, Color(1, 1, 1, 0.14), maxf(1.5, r * 0.06), true)
		4:  # orange: pores and a navel leaf
			for p in [Vector2(-0.5, 0.35), Vector2(0.55, 0.3), Vector2(-0.15, 0.62), Vector2(0.3, 0.6), Vector2(-0.6, -0.2)]:
				draw_circle(p * r, maxf(1.0, r * 0.035), col.darkened(0.2))
			_leaf(Vector2(0, -r * 0.9), r * 0.4, 0.6, leaf)
		5:  # apple
			draw_line(Vector2(0, -r * 0.8), Vector2(-r * 0.08, -r * 1.18), stem, maxf(2.0, r * 0.08), true)
			_leaf(Vector2(-r * 0.05, -r * 1.05), r * 0.4, 0.7, leaf)
		6:  # pear: speckles and stem
			for p in [Vector2(-0.4, 0.3), Vector2(0.45, 0.35), Vector2(0.1, 0.62), Vector2(-0.55, -0.25), Vector2(0.6, -0.15)]:
				draw_circle(p * r, maxf(1.0, r * 0.035), col.darkened(0.3))
			draw_line(Vector2(0, -r * 0.85), Vector2(r * 0.1, -r * 1.15), stem, maxf(2.0, r * 0.07), true)
		7:  # peach: soft crease and leaf
			draw_arc(Vector2(r * 0.55, 0), r * 0.75, PI * 0.72, PI * 1.25, 16, col.darkened(0.15), maxf(1.5, r * 0.04), true)
			_leaf(Vector2(0, -r * 0.92), r * 0.38, 0.8, leaf)
		8:  # pineapple: diamond pattern and a crown
			var lc := Color(col.darkened(0.28), 0.5)
			for k in range(-2, 3):
				_chord(r * 0.9, Vector2(k * r * 0.4, 0), Vector2(1, 1).normalized(), lc, maxf(1.0, r * 0.03))
				_chord(r * 0.9, Vector2(k * r * 0.4, 0), Vector2(-1, 1).normalized(), lc, maxf(1.0, r * 0.03))
			for a in [-0.7, -0.25, 0.25, 0.7]:
				_leaf(Vector2(a * r * 0.3, -r * 0.88), r * 0.42, a, leaf.darkened(0.1))
		9:  # honeydew: pale net
			for k in range(-2, 3):
				_meridian(r, k * 0.38, Color(1, 1, 1, 0.22), maxf(1.0, r * 0.025))
		10:  # melon: dark stripes
			for k in range(-3, 4):
				_meridian(r, k * 0.27, col.darkened(0.45), maxf(2.0, r * 0.07))


## The part of the line through p (direction d) that lies inside the circle of radius rr.
func _chord(rr: float, p: Vector2, d: Vector2, col: Color, w: float) -> void:
	var b := p.dot(d)
	var disc := b * b - (p.length_squared() - rr * rr)
	if disc <= 0.0:
		return
	var q := sqrt(disc)
	draw_line(p + d * (-b - q), p + d * (-b + q), col, w, true)


func _leaf(base: Vector2, s: float, tilt: float, col: Color) -> void:
	var dir := Vector2(sin(tilt), -cos(tilt))
	var side := Vector2(-dir.y, dir.x)
	var tip := base + dir * s
	var mid := base + dir * s * 0.5
	draw_colored_polygon(PackedVector2Array([base, mid + side * s * 0.28, tip, mid - side * s * 0.28]), col)
	draw_line(base, tip, col.darkened(0.25), maxf(1.0, s * 0.06), true)


## A curved stripe from pole to pole; offset is -1..1 across the fruit.
func _meridian(r: float, offset: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var y := -1.0 + i / 6.0
		var x := offset * sqrt(maxf(0.0, 1.0 - y * y))
		pts.append(Vector2(x, y) * r * 0.92)
	draw_polyline(pts, col, w, true)


func _draw_face(r: float, happy: bool, alpha: float) -> void:
	var s := minf(r, 46.0)  # big fruit keep a small, centred face
	var ink := Color(0.13, 0.08, 0.16, alpha)
	var ex := s * 0.34
	var ey := -s * 0.02
	var er := maxf(1.5, s * 0.12)
	for side in [-1.0, 1.0]:
		var e := Vector2(side * ex, ey)
		if happy:
			draw_arc(e + Vector2(0, er * 0.4), er, PI * 1.1, PI * 1.9, 8, ink, maxf(1.5, er * 0.45), true)
		else:
			draw_circle(e, er, ink)
			draw_circle(e + Vector2(-er * 0.3, -er * 0.35), er * 0.38, Color(1, 1, 1, 0.9 * alpha))
		draw_circle(Vector2(side * s * 0.56, s * 0.2), s * 0.13, Color(1.0, 0.45, 0.55, 0.45 * alpha))
	draw_arc(Vector2(0, s * 0.14), s * 0.16, PI * 0.15, PI * 0.85, 10, ink, maxf(1.5, s * 0.07), true)
