extends Control
## Level result card that game_host lays over the finished game: the backdrop dims in,
## a gradient card springs up, stars pop in one by one with sparkles, then the buttons.
## Set the vars, then add it as a full-rect child.

const FX := preload("res://core/fx.gd")

const CARD_W := 600.0

var won := false
var stars := 0
var stat := ""  # e.g. "Score 120", shown in a pill under the stars
var new_best := false
var endless := false  # endless run: game-over card with score and best instead of stars
var score := 0
var high_score := 0
var accent := FX.TANGERINE
var on_next := Callable()  # invalid when there is no next level
var on_retry := Callable()
var on_levels := Callable()

var _dim: Dim
var _card: PanelContainer
var _row: StarRow
var _closing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = Dim.new()
	_dim.accent = accent
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_card = PanelContainer.new()
	var sb := StyleBoxEmpty.new()
	sb.set_content_margin_all(36)
	sb.content_margin_top = 30
	_card.add_theme_stylebox_override("panel", sb)
	_card.draw.connect(_draw_card)
	add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	_card.add_child(box)

	var head_text := "Level Complete!" if won else "Level Failed"
	if endless:
		head_text = "New best!" if new_best else "Game over"
	var head := UI.title(head_text, 60, FX.LEMON if (won or endless) else Color("#ffd9cf"))
	head.name = "Head"
	box.add_child(head)
	if not won and not endless:
		box.add_child(UI.label("So close! Give it another go.", 30, Color(1, 1, 1, 0.8)))
	var info: Array[Control] = []
	if endless:
		var big := UI.title(str(score), 110, FX.LEMON if new_best else Color.WHITE, Color(0, 0, 0, 0.5))
		box.add_child(big)
		info.append(big)
		var pill := _pill("Best  %d" % high_score)
		box.add_child(pill)
		info.append(pill)
	else:
		_row = StarRow.new()
		_row.earned = stars if won else 0
		box.add_child(_row)
	if stat != "" and not endless:
		var pill := _pill(stat + ("   ·   New best!" if new_best else ""))
		box.add_child(pill)
		info.append(pill)

	var buttons: Array = []
	var primary: Button
	var secondary: Array = []
	if endless:
		primary = UI.button("Play again", _press.bind(on_retry), UI.GOOD.darkened(0.08) if new_best else FX.TANGERINE, 46)
		secondary = [["Home", on_levels]]
	elif not won:
		primary = UI.button("Retry", _press.bind(on_retry), FX.TANGERINE, 46)
		secondary = [["Levels", on_levels]]
	elif on_next.is_valid():
		primary = UI.button("Next", _press.bind(on_next), UI.GOOD.darkened(0.08), 46)
		secondary = [["Retry", on_retry], ["Levels", on_levels]]
	else:
		primary = UI.button("Levels", _press.bind(on_levels), UI.GOOD.darkened(0.08), 46)
		secondary = [["Retry", on_retry]]
	primary.custom_minimum_size.y = 116
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	box.add_child(gap)
	box.add_child(primary)
	buttons.append(primary)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	for s in secondary:
		var b := UI.button(s[0], _press.bind(s[1]), UI.VIOLET, 32)
		b.custom_minimum_size.y = 80
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		buttons.append(b)

	resized.connect(_layout)
	_intro(head, info, buttons)


## Card sized to its content and centred; slide is an extra downward offset.
func _layout(slide := 0.0) -> void:
	_card.size = Vector2(minf(CARD_W, size.x - 40.0), 0)
	_card.size = Vector2(_card.size.x, _card.get_combined_minimum_size().y)
	_card.position = (size - _card.size) / 2.0 + Vector2(0, slide)
	_card.pivot_offset = _card.size / 2.0


func _intro(head: Control, info: Array[Control], buttons: Array) -> void:
	_dim.modulate.a = 0.0
	_card.modulate.a = 0.0
	for n in info:
		n.modulate.a = 0.0
	for b in buttons:  # hidden and untappable until they pop in (sorting resets scale)
		b.modulate.a = 0.0
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	await get_tree().process_frame  # let the containers size themselves
	_layout(110.0)
	_card.scale = Vector2(0.72, 0.72)
	head.pivot_offset = head.size / 2.0

	var tw := create_tween().set_parallel()
	tw.tween_property(_dim, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "modulate:a", 1.0, 0.18).set_delay(0.06)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.5).set_delay(0.06) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(_layout, 110.0, 0.0, 0.5).set_delay(0.06) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished

	if won:
		FX.burst(self, _card.position + Vector2(_card.size.x / 2.0, 40), [FX.LEMON, FX.TANGERINE, accent, UI.GOOD], 40, 1.1)
		for i in (0 if endless else stars):
			# Each star is flung in big and spinning, slams into its socket, then bursts.
			_row.fly_in(i)
			await get_tree().create_timer(StarRow.LAND).timeout
			var c := _row.global_position - global_position + _row.star_pos(i)
			FX.burst(self, c, [FX.LEMON, Color.WHITE, FX.TANGERINE], 26, 0.75)
			FX.shake(_card, 5.0 + 3.0 * i, 0.18)
			await get_tree().create_timer(0.2).timeout
	else:
		FX.shake(_card, 12.0, 0.35)
		await get_tree().create_timer(0.3).timeout

	if not info.is_empty():  # an empty tween logs "started with no Tweeners"
		var tw2 := create_tween().set_parallel()
		for n in info:
			tw2.tween_property(n, "modulate:a", 1.0, 0.25)
	for b in buttons:
		b.modulate.a = 1.0
		b.mouse_filter = Control.MOUSE_FILTER_STOP
	UI.stagger_pop(buttons, 0.07, 0.0)


func _press(action: Callable) -> void:
	if _closing or not action.is_valid():
		return
	_closing = true
	action.call()


## Fade the whole overlay out, then free it (used by Retry).
func close() -> void:
	_closing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_property(_card, "scale", Vector2(0.9, 0.9), 0.2).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)


func _pill(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UI.box(Color(0.03, 0.02, 0.12, 0.45), 30)
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := UI.label(text, 32, Color.WHITE)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	p.add_child(l)
	return p


func _draw_card() -> void:
	var head: Control = _card.find_child("Head", true, false)
	var band_h := head.position.y + head.size.y + 46.0 if head else 120.0
	FX.draw_neon_card(_card, Rect2(Vector2.ZERO, _card.size), 44,
		FX.neon(accent) if (won or endless) else Color("#ff5a4f"), band_h)


## Dimmed game behind the card, with a soft accent light in the middle.
class Dim extends Control:
	var accent := FX.TANGERINE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.02, 0.1, 0.74))
		FX.draw_glow(self, Rect2(-size.x * 0.3, size.y * 0.15, size.x * 1.6, size.y * 0.7), Color(accent, 0.22))
		FX.draw_vgradient(self, Rect2(0, 0, size.x, size.y * 0.25), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0))
		FX.draw_vgradient(self, Rect2(0, size.y * 0.75, size.x, size.y * 0.25), Color(0, 0, 0, 0), Color(0, 0, 0, 0.35))


## Three big stars in an arc, Angry Birds style: fly_in(i) flings a star in from huge and
## spinning; it slams into its socket with a squash, a shock ring and a rising chime, then sits
## on slowly turning light rays and twinkles.
class StarRow extends Control:
	const LAND := 0.26  # seconds from fly_in() until the star hits its socket
	const SPIN := [-1.1, 0.8, 1.2]  # start rotation per star (radians)

	var earned := 0
	var _k: Array[float] = [0.0, 0.0, 0.0]  # star scale (0 = not shown yet)
	var _a: Array[float] = [0.0, 0.0, 0.0]  # star alpha
	var _rot: Array[float] = [0.0, 0.0, 0.0]
	var _ring: Array[float] = [1.0, 1.0, 1.0]  # shock ring 0..1 (1 = done)
	var _rays: Array[float] = [0.0, 0.0, 0.0]  # rays behind a landed star, 0..1
	var _sparks: Array = []  # [pos, age, size]
	var _t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 170)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func star_pos(i: int) -> Vector2:
		return Vector2(size.x / 2.0 + (i - 1) * 150.0, 92.0 if i != 1 else 78.0)

	func _radius(i: int) -> float:
		return 66.0 if i == 1 else 54.0

	func _process(delta: float) -> void:
		_t += delta
		for sp in _sparks:
			sp[1] += delta
		_sparks = _sparks.filter(func(sp): return sp[1] < 0.55)
		if randf() < delta * 3.0:  # idle twinkle on a landed star
			var lit: Array = []
			for i in 3:
				if _rays[i] > 0.5:
					lit.append(i)
			if not lit.is_empty():
				var i: int = lit.pick_random()
				_sparks.append([star_pos(i) + Vector2.from_angle(randf() * TAU) * randf() * _radius(i) * 0.7, 0.0,
					randf_range(8.0, 16.0)])
		queue_redraw()

	func _anim(arr: Array[float], i: int, from: float, to: float, time: float, delay := 0.0) -> Tweener:
		return create_tween().tween_method(func(v: float):
			arr[i] = v, from, to, time).set_delay(delay)

	func fly_in(i: int) -> void:
		Feedback.sfx("swoosh", 0.9 + i * 0.1)
		_rot[i] = SPIN[i]
		_anim(_a, i, 0.0, 1.0, 0.1)
		_anim(_k, i, 3.4, 1.0, LAND).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_anim(_rot, i, SPIN[i], 0.0, LAND).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var tw := create_tween()
		tw.tween_interval(LAND)
		tw.tween_callback(_land.bind(i))

	func _land(i: int) -> void:
		Feedback.sfx("star", 1.0 + i * 0.12)  # each star rings a step higher
		Feedback.sfx("place", 0.8)
		Feedback.vibrate(30 + i * 10)
		_anim(_k, i, 0.78, 1.0, 0.42).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_anim(_ring, i, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_anim(_rays, i, 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		for n in 5:
			_sparks.append([star_pos(i) + Vector2.from_angle(randf() * TAU) * _radius(i) * randf_range(0.6, 1.3),
				-n * 0.06, randf_range(10.0, 20.0)])

	func _draw() -> void:
		for i in 3:  # rays first so neighbouring stars stay on top
			if _rays[i] <= 0.0:
				continue
			var c := star_pos(i)
			var r := _radius(i)
			FX.draw_glow(self, Rect2(c - Vector2(r, r) * 1.9, Vector2(r, r) * 3.8), Color(FX.LEMON, 0.3 * _rays[i]))
			for k in 10:
				var a := _t * 0.5 * (1.0 if i != 0 else -1.0) + k * TAU / 10.0
				var ray := r * (1.5 + 0.35 * _rays[i])
				draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a - 0.11) * ray,
					c + Vector2.from_angle(a + 0.11) * ray]), Color(1, 0.93, 0.6, 0.1 * _rays[i]))
		for i in 3:
			var c := star_pos(i)
			var r := _radius(i)
			FX.draw_star(self, c, r, FX.LEMON, false)
			if _k[i] <= 0.0:
				continue
			if _ring[i] < 1.0:
				draw_arc(c, r * (0.9 + _ring[i] * 1.1), 0.0, TAU, 48,
					Color(1, 0.95, 0.7, 0.8 * (1.0 - _ring[i])), 10.0 * (1.0 - _ring[i]) + 1.0, true)
			draw_set_transform(c, _rot[i], Vector2.ONE)
			var col := Color(FX.LEMON, _a[i])
			FX.draw_star(self, Vector2.ZERO, r * _k[i], col, true)
			if _k[i] < 1.6:  # glint on the upper arm once it is close
				draw_circle(Vector2(-r * 0.22, -r * 0.3) * _k[i], r * 0.09 * _k[i], Color(1, 1, 1, 0.75 * _a[i]))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for sp in _sparks:  # four-point twinkles
			var age: float = sp[1]
			var k := sin(age / 0.55 * PI)
			if age < 0.0 or sp[2] * k < 0.5:
				continue  # not born yet, or too small to triangulate
			var p: Vector2 = sp[0]
			var sz: float = sp[2] * k
			var w := sz * 0.22
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -sz), p + Vector2(w, 0), p + Vector2(0, sz),
				p + Vector2(-w, 0)]), Color(1, 1, 0.9, 0.95 * k))
			draw_colored_polygon(PackedVector2Array([p + Vector2(-sz, 0), p + Vector2(0, -w), p + Vector2(sz, 0),
				p + Vector2(0, w)]), Color(1, 1, 0.9, 0.95 * k))
