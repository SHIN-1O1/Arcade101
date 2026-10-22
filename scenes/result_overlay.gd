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
		var b := UI.button(s[0], _press.bind(s[1]), FX.INDIGO.lightened(0.22), 32)
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
			_row.pop_star(i)
			var c := _row.global_position - global_position + _row.star_pos(i)
			FX.burst(self, c, [FX.LEMON, Color.WHITE], 18, 0.6)
			await get_tree().create_timer(0.24).timeout
	else:
		FX.shake(_card, 12.0, 0.35)
		await get_tree().create_timer(0.3).timeout

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
	var r := Rect2(Vector2.ZERO, _card.size)
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0, 0, 0, 0)
	sh.set_corner_radius_all(44)
	sh.shadow_color = Color(0, 0, 0, 0.5)
	sh.shadow_size = 30
	sh.shadow_offset = Vector2(0, 16)
	_card.draw_style_box(sh, r)
	var top := FX.INDIGO.lightened(0.2)
	FX.draw_round_gradient(_card, r, 44, top, FX.INDIGO.darkened(0.35))
	# Coloured header band behind the title, in the game's own colour.
	var head: Control = _card.find_child("Head", true, false)
	var band_h := head.position.y + head.size.y + 46.0 if head else 120.0
	var band := accent if (won or endless) else Color("#c8553d")
	FX.draw_round_gradient(_card, Rect2(0, 0, r.size.x, band_h), 44, band.lightened(0.15), band.darkened(0.2), false)
	_card.draw_rect(Rect2(0, band_h - 4, r.size.x, 4), Color(0, 0, 0, 0.25))
	FX.draw_glow(_card, Rect2(r.size.x * 0.1, -band_h * 0.3, r.size.x * 0.8, band_h), Color(1, 1, 1, 0.22))
	var rim := FX.round_rect_points(r, 44)
	rim.append(rim[0])
	_card.draw_polyline(rim, Color(1, 1, 1, 0.16), 3.0, true)


## Dimmed game behind the card, with a soft accent light in the middle.
class Dim extends Control:
	var accent := FX.TANGERINE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.02, 0.1, 0.74))
		FX.draw_glow(self, Rect2(-size.x * 0.3, size.y * 0.15, size.x * 1.6, size.y * 0.7), Color(accent, 0.22))
		FX.draw_vgradient(self, Rect2(0, 0, size.x, size.y * 0.25), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0))
		FX.draw_vgradient(self, Rect2(0, size.y * 0.75, size.x, size.y * 0.25), Color(0, 0, 0, 0), Color(0, 0, 0, 0.35))


## Three big stars in an arc; earned ones pop in when pop_star() is called.
class StarRow extends Control:
	var earned := 0
	var _k: Array[float] = [0.0, 0.0, 0.0]  # filled-star scale, animated
	var _ring: Array[float] = [0.0, 0.0, 0.0]  # shine ring, 0..1

	func _init() -> void:
		custom_minimum_size = Vector2(0, 170)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func star_pos(i: int) -> Vector2:
		return Vector2(size.x / 2.0 + (i - 1) * 150.0, 92.0 if i != 1 else 78.0)

	func _radius(i: int) -> float:
		return 66.0 if i == 1 else 54.0

	func pop_star(i: int) -> void:
		Feedback.sfx("star")
		Feedback.vibrate(25)
		var tw := create_tween().set_parallel()
		tw.tween_method(func(v: float):
			_k[i] = v
			queue_redraw(), 0.0, 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(v: float):
			_ring[i] = v
			queue_redraw(), 0.0, 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		for i in 3:
			var c := star_pos(i)
			var r := _radius(i)
			FX.draw_star(self, c, r, FX.LEMON, false)
			if _k[i] > 0.0:
				if _ring[i] < 1.0:
					draw_arc(c, r * (0.8 + _ring[i] * 0.9), 0.0, TAU, 48,
						Color(1, 0.95, 0.7, 0.6 * (1.0 - _ring[i])), 6.0 * (1.0 - _ring[i]) + 1.0, true)
				FX.draw_glow(self, Rect2(c - Vector2(r, r) * 1.6, Vector2(r, r) * 3.2), Color(FX.LEMON, 0.35 * _k[i]))
				FX.draw_star(self, c, r * _k[i], FX.LEMON, true)
