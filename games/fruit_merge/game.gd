extends BaseGame
## Fruit Fusion (endless): aim with a tap or drag, release to drop the next fruit into the jar.
## Two equal fruits that touch fuse into the next of 11 fruits; two melons (the last) burst for a
## bonus. Fusing tier k scores SCORE[k]. The run ends when a fruit stays above the line for
## DANGER_TIME seconds (or the jar holds MAX_FRUITS). difficulty() (BaseGame, ramping to
## "ramp_score" in games.json) widens the spawn pool toward bigger fruit and shortens the cooldown.
##
## Physics: one RigidBody2D circle per fruit, kept under a plain Node so the bodies live in this
## Control's local coordinates but ignore its transform (the host scales/fades the game; shakes move
## it). Bodies use shape-cast CCD, thick static walls and sleep when still; low friction and angular
## damping let fruit roll, and a spring "jelly" squash on impacts keeps them soft. Nothing is drawn by
## the bodies: _draw() paints each fruit from its body: the skin texture turns with the body, the light
## layers on top do not. Art in art/ is painted by art/gen_art.py (re-run it to retune a fruit).

const FX := preload("res://core/fx.gd")
const INDIGO := Color("#2B2A6B")
const TANGERINE := Color("#FF8A1F")
const LEMON := Color("#FFD23F")

## Radius of each tier in design units (jar is 600 units wide) and its particle colour.
## Original set: berry, strawberry, grape, lime, orange, apple, pear, peach, pineapple, cantaloupe, melon.
const RADII := [19.0, 26.0, 34.0, 41.0, 51.0, 61.0, 71.0, 83.0, 97.0, 113.0, 131.0]
const COLORS := [Color("#D7213C"), Color("#E8323A"), Color("#7B3FA8"), Color("#6CC04A"), Color("#FF8A1F"),
	Color("#C8232E"), Color("#C9D35A"), Color("#F7A35A"), Color("#FFC93C"), Color("#D9C98A"), Color("#3C9A3A")]
const ART := "res://games/fruit_merge/art/"
const ART_HALF := 1.6  # fruit_<n>.png: canvas half-size in fruit radii (the disc is 120 of 192 px)
const SCORE := [1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 66]
const MELON_BONUS := 100  # two of the last tier burst
const LAST := 10
const SPAWN_WEIGHTS := [5.0, 4.0, 3.0, 2.0, 1.4]
const MAX_FRUITS := 72  # body cap for low-end phones
const DANGER_TIME := 2.0  # seconds a settled fruit may stay above the line
const GRACE := 1.0  # a fresh fruit may cross the line while it falls in
const COOLDOWN := [0.55, 0.38]  # seconds between drops at difficulty 0 and 1
const GRAVITY_SCALE := 1.35
const MAX_SPEED := 820.0  # px/s: under one berry radius per physics step, so nothing sinks into a fruit
const JAR_WIDTH := 600.0
const WALL := 18.0  # drawn wall thickness; the physics walls are much thicker
const TOP := 235.0  # y of the jar rim / danger line
const BOTTOM := 112.0  # space under the jar for the stand and the fruit chain strip
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
	var jelly := 0.0  # squash along jelly_dir (spring, + = squashed, - = stretched)
	var jelly_v := 0.0
	var jelly_dir := PI / 2.0
	var vel := Vector2.ZERO  # last velocity, to spot impacts
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
var _skins: Array[Texture2D] = []
var _shade: Texture2D
var _spec: Texture2D
var _backdrop: Texture2D


func _on_start() -> void:
	for c in get_children():
		c.queue_free()
	if _skins.is_empty():
		for i in RADII.size():
			_skins.append(load(ART + "fruit_%d.png" % i))
		_shade = load(ART + "light_shade.png")
		_spec = load(ART + "light_spec.png")
		_backdrop = load(ART + "backdrop.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # small fruit from big textures
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
	mat.friction = 0.35
	mat.bounce = 0.05
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
	b.linear_damp = 0.05
	b.angular_damp = 0.3
	var mat := PhysicsMaterial.new()
	mat.friction = 0.3
	mat.bounce = 0.14
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
		var sp2 := f.body.linear_velocity.length_squared()
		if sp2 < 900.0 and not f.body.sleeping:  # rolling resistance: free rolling, gentle settling
			f.body.linear_velocity *= 0.97
			f.body.angular_velocity *= 0.94
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
	f.jelly = -0.1  # pops out a little stretched, then wobbles
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
		var v := f.body.linear_velocity
		var hit := f.vel - v  # a sudden change of velocity is an impact
		if hit.length() > 170.0 and f.vel.length() > 160.0:
			f.jelly = maxf(f.jelly, clampf(hit.length() / 2600.0, 0.03, 0.13))
			f.jelly_dir = hit.angle()
		f.vel = v
		# damped spring: squash, overshoot into a small stretch, settle
		f.jelly_v += (-900.0 * f.jelly - 15.0 * f.jelly_v) * delta
		f.jelly += f.jelly_v * delta
		if absf(f.jelly) < 0.002 and absf(f.jelly_v) < 0.05:
			f.jelly = 0.0
			f.jelly_v = 0.0
		f.pop = minf(1.0, f.pop + delta / 0.3)
	for fl in _floats:
		fl.t += delta / 0.8
	while not _floats.is_empty() and _floats[0].t >= 1.0:
		_floats.pop_front()
	queue_redraw()


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	_draw_backdrop()
	if not _built:
		return
	_draw_jar_back()
	if not _finished:
		_draw_guide()
	for f in fruits:
		var s := 1.0
		if f.pop < 1.0:  # grow in with a springy overshoot
			s = 0.6 + 0.4 * f.pop + 0.18 * sin(f.pop * PI)
		draw_fruit(f.body.position, f.r * s, f.tier, f.body.rotation, f.jelly, f.jelly_dir)
	_draw_jar_front()
	if not _finished:
		var hs := 0.5 + 0.5 * FX.ease_smooth(_held_pop)
		var pos := Vector2(aim_x, drop_y + sin(_time * 3.0) * 3.0)
		FX.draw_glow(self, Rect2(pos - Vector2.ONE * radius(current) * 1.6, Vector2.ONE * radius(current) * 3.2),
			Color(LEMON, 0.18 if cooldown <= 0.0 else 0.06))
		draw_fruit(pos, radius(current) * hs, current, 0.0, 0.0, 0.0, 1.0 if cooldown <= 0.0 else 0.6)
	_draw_hud()
	for fl in _floats:
		var t: float = fl.t
		FX.draw_text_centered(self, fl.pos + Vector2(0, -30.0 - 70.0 * t), fl.text, int(30 * u + 10),
			Color(LEMON, 1.0 - t * t), FX.font())
	if _drops == 0 and not _finished:
		var a := 0.65 + 0.25 * sin(_time * 3.0)
		FX.draw_text_centered(self, Vector2(size.x / 2.0, jar.get_center().y), "Tap or drag to aim,", 32,
			Color(1, 1, 1, a), FX.font())
		FX.draw_text_centered(self, Vector2(size.x / 2.0, jar.get_center().y + 42.0), "release to drop!", 32,
			Color(1, 1, 1, a), FX.font())


## Painted orchard (cover-fit, anchored to the bottom) with slow drifting light motes.
func _draw_backdrop() -> void:
	if _backdrop == null:
		FX.draw_background(self, Rect2(Vector2.ZERO, size))
		return
	var ts := _backdrop.get_size()
	var k := maxf(size.x / ts.x, size.y / ts.y)
	var dsz := ts * k
	draw_texture_rect(_backdrop, Rect2(Vector2((size.x - dsz.x) / 2.0, size.y - dsz.y), dsz), false)
	for i in 14:
		var h := float((i * 7919) % 997) / 997.0
		var sp := 14.0 + 22.0 * h
		var y := fposmod(size.y * (1.0 - h) - _time * sp, size.y + 80.0) - 40.0
		var x := fposmod(size.x * float((i * 4271) % 991) / 991.0 + sin(_time * 0.6 + i) * 18.0, size.x)
		var r := 10.0 + 26.0 * fposmod(h * 3.7, 1.0)
		var col := LEMON if i % 3 == 0 else TANGERINE if i % 3 == 1 else Color(0.75, 0.7, 1.0)
		FX.draw_glow(self, Rect2(x - r, y - r, r * 2.0, r * 2.0), Color(col, 0.10 + 0.06 * sin(_time + i)))


func _jar_outline() -> Rect2:
	return Rect2(jar.position.x - WALL, jar.position.y - 12.0, jar.size.x + WALL * 2.0, jar.size.y + 12.0 + WALL)


func _draw_jar_back() -> void:
	var o := _jar_outline()
	FX.draw_shadow(self, Rect2(o.position.x - 30.0, o.end.y - 6.0, o.size.x + 60.0, 70.0), 0.75)
	# wooden stand under the jar
	var stand := Rect2(o.position.x - 14.0, o.end.y - 6.0, o.size.x + 28.0, 34.0)
	FX.draw_tile(self, stand, Color("#B8612A"), 14)
	for i in 4:
		var gx := stand.position.x + stand.size.x * (0.18 + 0.22 * i)
		draw_line(Vector2(gx, stand.position.y + 9.0), Vector2(gx + 26.0, stand.position.y + 9.0), Color(0.35, 0.15, 0.05, 0.35), 2.0)
	# glass body: dark tint, a soft inner glow and fine vertical reflections
	FX.draw_round_gradient(self, o, 34.0, Color(0.09, 0.07, 0.24, 0.78), Color(0.14, 0.10, 0.32, 0.9))
	FX.draw_glow(self, Rect2(jar.position.x, jar.position.y + jar.size.y * 0.3, jar.size.x, jar.size.y * 0.8),
		Color(0.6, 0.5, 1.0, 0.10))


func _draw_jar_front() -> void:
	var o := _jar_outline()
	var pts := FX.round_rect_points(o, 34.0)
	pts.append(pts[0])
	draw_polyline(pts, Color(0.85, 0.85, 1.0, 0.55), 5.0, true)  # glass edge
	draw_polyline(pts, Color(1, 1, 1, 0.12), 14.0, true)  # glass thickness
	# reflections: a tall streak on the left, a short one on the right
	draw_rect(Rect2(jar.position.x + 10.0, jar.position.y + 24.0, 10.0, jar.size.y * 0.55), Color(1, 1, 1, 0.10))
	draw_rect(Rect2(jar.position.x + 26.0, jar.position.y + 40.0, 4.0, jar.size.y * 0.35), Color(1, 1, 1, 0.06))
	draw_rect(Rect2(jar.end.x - 22.0, jar.position.y + jar.size.y * 0.55, 8.0, jar.size.y * 0.3), Color(1, 1, 1, 0.04))
	# rim: two glossy caps on the wall tops
	for x in [o.position.x - 6.0, jar.end.x - 6.0 + 0.0]:
		FX.draw_tile(self, Rect2(x, o.position.y - 10.0, WALL + 12.0, 20.0), TANGERINE, 10, false)
	# danger line: dashed, turns red and pulses while a fruit is stuck above it
	var warn := clampf(_danger * 1.6, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_time * 14.0)
	var lc := Color(1, 1, 1, 0.3).lerp(Color(1.0, 0.25, 0.3, 0.6 + 0.4 * pulse), warn)
	var x := jar.position.x + 8.0
	while x < jar.end.x - 8.0:
		draw_line(Vector2(x, jar.position.y + 2.0), Vector2(minf(x + 16.0, jar.end.x - 8.0), jar.position.y + 2.0), lc, 4.0)
		x += 28.0
	if warn > 0.0:
		draw_rect(Rect2(jar.position.x, jar.position.y - 4.0, jar.size.x, 12.0), Color(1, 0.2, 0.3, 0.18 * warn * pulse))


func _draw_guide() -> void:
	var a := 0.16 if cooldown > 0.0 else 0.36
	var y := drop_y + radius(current) + 10.0
	while y < jar.end.y - 8.0:
		draw_circle(Vector2(aim_x, y), 3.0, Color(1, 1, 1, a * (1.0 - 0.5 * (y - drop_y) / (jar.end.y - drop_y))))
		y += 22.0
	# marker on the rim where the fruit will enter
	var m := Vector2(aim_x, jar.position.y - 2.0)
	draw_colored_polygon(PackedVector2Array([m + Vector2(-9, -12), m + Vector2(9, -12), m]), Color(LEMON, a + 0.3))


## Top cards (best fruit made, next fruit) and the 11-fruit chain under the stand.
func _draw_hud() -> void:
	var font := FX.font()
	var card_w := 170.0
	for side in 2:
		var r := Rect2(24.0 if side == 0 else size.x - 24.0 - card_w, 18.0, card_w, 86.0)
		FX.draw_round_gradient(self, Rect2(r.position + Vector2(0, 5), r.size), 26.0, Color(0, 0, 0, 0.25), Color(0, 0, 0, 0.25))
		FX.draw_round_gradient(self, r, 26.0, Color(0.16, 0.12, 0.40, 0.88), Color(0.07, 0.05, 0.20, 0.88))
		var edge := FX.round_rect_points(r, 26.0)
		edge.append(edge[0])
		draw_polyline(edge, Color(1, 1, 1, 0.14), 2.0, true)
		var fc := Vector2(r.end.x - 44.0, r.get_center().y)
		draw_circle(fc, 32.0, Color(0, 0, 0, 0.25))
		draw_arc(fc, 32.0, 0.0, TAU, 40, Color(LEMON, 0.6), 3.0, true)
		var tier := next if side == 1 else best_tier
		draw_fruit(fc, minf(radius(tier), 24.0), tier, 0.0, 0.0, 0.0)
		FX.draw_text_centered(self, Vector2(r.position.x + 58.0, fc.y - 12.0), "NEXT" if side == 1 else "BEST", 24,
			Color(1, 1, 1, 0.92), font)
		FX.draw_text_centered(self, Vector2(r.position.x + 58.0, fc.y + 18.0), "fruit", 20, Color(1, 1, 1, 0.5), font)
	# chain strip
	var strip := Rect2(jar.position.x - WALL, size.y - 50.0, jar.size.x + WALL * 2.0, 44.0)
	FX.draw_round_gradient(self, strip, 22.0, Color(0.07, 0.05, 0.2, 0.78), Color(0.04, 0.03, 0.14, 0.78))
	var step := strip.size.x / 11.0
	for i in 11:
		var c := Vector2(strip.position.x + step * (i + 0.5), strip.get_center().y)
		var rr := lerpf(9.0, 17.0, float(i) / 10.0) * minf(1.0, step / 52.0)
		if i == best_tier:
			FX.draw_glow(self, Rect2(c - Vector2.ONE * rr * 2.2, Vector2.ONE * rr * 4.4), Color(LEMON, 0.45))
		draw_fruit(c, rr, i, 0.0, 0.0, 0.0, 1.0 if i <= maxi(best_tier, 4) else 0.35)


## A fruit at c with radius r: painted skin turned by rot, fixed light on top. jelly squashes it along
## angle jdir (stretches across it). alpha < 1 dims it (held fruit while cooling down, chain strip).
func draw_fruit(c: Vector2, r: float, tier: int, rot: float, jelly: float, jdir: float, alpha := 1.0) -> void:
	if r < 1.0:
		return
	FX.draw_shadow(self, Rect2(c.x - r * 0.8, c.y + r * 0.66, r * 1.6, r * 0.5), 0.3 * alpha)
	var base := Transform2D(0.0, c)
	if jelly != 0.0:
		base = base * Transform2D(jdir, Vector2.ZERO) * Transform2D(0.0, Vector2(1.0 - jelly, 1.0 + jelly), 0.0,
			Vector2.ZERO) * Transform2D(-jdir, Vector2.ZERO)
	var h := r * ART_HALF
	var rect := Rect2(-h, -h, h * 2.0, h * 2.0)
	var tint := Color(1, 1, 1, 1) if alpha >= 1.0 else Color(alpha, alpha, alpha * 1.1, 1.0)
	draw_set_transform_matrix(base * Transform2D(rot, Vector2.ZERO))
	draw_texture_rect(_skins[tier], rect, false, tint)
	draw_set_transform_matrix(base)
	draw_texture_rect(_shade, rect, false)
	draw_texture_rect(_spec, rect, false, Color(1, 1, 1, alpha))
	draw_set_transform_matrix(Transform2D.IDENTITY)
