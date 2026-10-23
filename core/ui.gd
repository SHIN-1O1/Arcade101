class_name UI
extends RefCounted
## Tiny code-built UI kit so screens need no hand-made themes yet.
## Menus get their look from FX (font, theme, buttons) plus the widgets below.

const FX := preload("res://core/fx.gd")

const BG := Color("#1d1f33")
const CARD := Color("#2b2d42")
const ACCENT := Color("#ffd166")
const GOOD := Color("#06d6a0")
const BAD := Color("#ef476f")
const MUTED := Color("#55586f")
const VIOLET := Color("#7a6cff")  # default neon rim for menu buttons


static func box(color: Color, radius := 24) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(16)
	return sb


## Dark glass panel with a neon rim (the shadow is the glow), for grouping rows on the backdrop.
static func card_box(radius := 32, rim := FX.NEON_CYAN) -> StyleBoxFlat:
	var sb := box(Color(FX.PANEL, 0.9), radius)
	sb.border_color = Color(rim.lerp(Color.WHITE, 0.2), 0.85)
	sb.set_border_width_all(3)
	sb.shadow_color = Color(rim, 0.28)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2.ZERO
	sb.anti_aliasing = true
	sb.set_content_margin_all(28)
	return sb


static func button(text: String, on_press: Callable, color := VIOLET, font := 34) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 96)
	b.add_theme_font_size_override("font_size", font)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	FX.style_button(b, color)
	wire(b, on_press)
	return b


## Square button with a drawn icon: "back", "restart" or "settings".
static func icon_button(icon: String, on_press: Callable, color := VIOLET) -> Button:
	var b := IconButton.new()
	b.icon_name = icon
	b.tint = color
	b.custom_minimum_size = Vector2(88, 88)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	FX.style_button(b, color)
	wire(b, on_press, "back" if icon == "back" else "button")
	return b


## Click sound + buzz, then on_press.
static func wire(b: BaseButton, on_press: Callable, sound := "button") -> void:
	b.pressed.connect(func():
		Feedback.sfx(sound)
		Feedback.vibrate(15)
		on_press.call())


## Squash on press, spring back on release (for custom-drawn buttons).
static func squash(b: Control, amount := 0.92) -> void:
	b.resized.connect(func(): b.pivot_offset = b.size / 2.0)
	if b is BaseButton:
		b.button_down.connect(func(): FX.scale_to(b, amount, 0.08))
		b.button_up.connect(func():
			b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.22) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


## Removes every Button stylebox so a script can draw the whole thing.
static func flat(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())


static func label(text: String, font := 34, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_color_override("font_color", color)
	return l


## Big game-style heading: thick dark outline and a deep drop shadow.
## outline defaults to a very dark shade of color.
static func title(text: String, font := 56, color := FX.LEMON, outline := Color(0, 0, 0, 0)) -> Label:
	if outline.a == 0.0:
		outline = color.darkened(0.78)
	var l := label(text, font, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", maxi(8, int(font * 0.24)))
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("shadow_offset_y", maxi(4, int(font * 0.1)))
	l.add_theme_constant_override("shadow_outline_size", maxi(8, int(font * 0.24)))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	return l


## Rounded badge with a gold star in front of the text, e.g. "12 / 90".
static func star_pill(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(Color(FX.NIGHT, 0.82), 40)
	sb.border_color = Color(FX.LEMON, 0.9)
	sb.set_border_width_all(3)
	sb.shadow_color = Color(FX.LEMON, 0.25)
	sb.shadow_size = 10
	sb.content_margin_left = 64
	sb.content_margin_right = 24
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, 32)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	p.add_child(l)
	p.draw.connect(func(): FX.draw_star(p, Vector2(36, p.size.y / 2.0), 21.0))
	return p


## Header with a centred title, back button on the left and an optional widget on the right.
static func top_bar(text: String, on_back: Callable, right: Control = null, color := FX.LEMON,
		outline := Color(0, 0, 0, 0)) -> Control:
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 104)
	var t := title(text, 54, color, outline)
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(t)
	var back := icon_button("back", on_back)
	bar.add_child(back)
	if right:
		bar.add_child(right)
	bar.resized.connect(func():
		back.size = back.get_combined_minimum_size()
		back.position = Vector2(0, (bar.size.y - back.size.y) / 2.0)
		if right:
			right.size = right.get_combined_minimum_size()
			right.position = Vector2(bar.size.x - right.size.x, (bar.size.y - right.size.y) / 2.0))
	return bar


## Scale each node in from zero, one after another.
static func stagger_pop(nodes: Array, step := 0.03, delay := 0.05) -> void:
	for i in nodes.size():
		var n: Control = nodes[i]
		n.pivot_offset = n.size / 2.0
		n.scale = Vector2.ZERO
		var tw := n.create_tween()
		tw.tween_interval(delay + i * step)
		tw.tween_property(n, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func stars_text(n: int, of := 3) -> String:
	return "★".repeat(n) + "☆".repeat(of - n)


## Full-screen background + safe-area margin + vertical column. Returns the column.
## Menus get the gradient backdrop tinted by accent; fancy = false gives a flat colour.
static func screen(root: Control, accent := FX.TANGERINE, fancy := true) -> VBoxContainer:
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = FX.theme()
	var bg: Control
	if fancy:
		bg = Backdrop.new()
		(bg as Backdrop).accent = accent
	else:
		bg = ColorRect.new()
		(bg as ColorRect).color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var safe := safe_margins(root)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 28 + safe.x)
	margin.add_theme_constant_override("margin_bottom", 32 + safe.y)
	root.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	margin.add_child(col)
	return col


## Top/bottom insets (notch, gesture bar) in viewport units.
static func safe_margins(node: Control) -> Vector2i:
	var screen_size := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if screen_size.y <= 0 or safe.size.y <= 0 or not OS.has_feature("mobile"):
		return Vector2i.ZERO
	var scale := node.get_viewport_rect().size.y / float(screen_size.y)
	return Vector2i(int(safe.position.y * scale), int((screen_size.y - safe.end.y) * scale))


# --- widgets ----------------------------------------------------------------

## Menu background: synthwave night sky, striped retro sun on a scrolling neon grid,
## twinkling stars, neon bubbles drifting up, and faint CRT scanlines. Animated unless animate = false.
class Backdrop extends Control:
	const HORIZON := 0.8  # horizon height as a share of the screen

	var accent := FX.TANGERINE
	var animate := true
	var _t := 0.0
	var _bubbles: Array = []  # [x 0..1, y 0..1, radius, rise speed (screens/s), sway phase, colour]
	var _stars: Array[Vector3] = []  # x, y (0..1), twinkle phase

	func _ready() -> void:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # scanline tiling
		resized.connect(queue_redraw)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var cols := [FX.NEON_CYAN, FX.NEON_PINK, FX.LEMON, FX.TANGERINE, accent.lightened(0.2)]
		for i in 16:
			_bubbles.append([rng.randf(), rng.randf(), rng.randf_range(14.0, 82.0), rng.randf_range(0.012, 0.04),
				rng.randf() * TAU, cols[i % cols.size()]])
		for i in 46:
			_stars.append(Vector3(rng.randf(), rng.randf() * HORIZON * 0.9, rng.randf() * TAU))
		set_process(animate)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var hy := h * HORIZON
		FX.draw_vgradient(self, Rect2(0, 0, w, hy * 0.55), FX.NIGHT, Color("#1a1045"))
		FX.draw_vgradient(self, Rect2(0, hy * 0.55, w, hy * 0.45 + 1.0), Color("#1a1045"), Color("#3d1458"))
		FX.draw_vgradient(self, Rect2(0, hy, w, h - hy), Color("#1a0a33"), FX.NIGHT)
		FX.draw_glow(self, Rect2(-w * 0.35, -h * 0.2, w * 1.7, h * 0.5), Color(accent, 0.2))
		for st in _stars:
			var tw := 0.5 + 0.5 * sin(_t * 1.7 + st.z * 3.0)
			draw_circle(Vector2(st.x * w, st.y * h), 1.2 + tw * 1.3, Color(1, 1, 1, 0.15 + 0.5 * tw))
		FX.draw_retro_sun(self, Vector2(w * 0.5, hy - w * 0.12), w * 0.3, 0.5)
		FX.draw_neon_grid(self, Rect2(0, hy, w, h - hy), FX.NEON_PINK, _t * 0.35)
		for b in _bubbles:
			var r: float = b[2]
			var y := fposmod(b[1] - _t * b[3], 1.0) * (h + r * 4.0) - r * 2.0
			var x: float = b[0] * w + sin(_t * 0.5 + b[4]) * 26.0
			var c := Vector2(x, y)
			var col: Color = b[5]
			draw_circle(c, r, Color(col, 0.05))
			FX.draw_neon_circle(self, c, r, Color(col, 0.42), 2.0, 0.6)
			draw_arc(c, r * 0.7, PI * 1.08, PI * 1.42, 12, Color(1, 1, 1, 0.3), maxf(2.0, r * 0.08), true)
		FX.draw_scanlines(self, Rect2(Vector2.ZERO, size), 0.14)
		FX.draw_vgradient(self, Rect2(0, h * 0.86, w, h * 0.14), Color(0, 0, 0, 0), Color(0, 0, 0, 0.35))


## Button that draws an FX icon on its raised face.
class IconButton extends Button:
	var icon_name := ""
	var tint := Color.WHITE  # glow colour around the icon (the button's rim colour)

	func _draw() -> void:
		var down := get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED
		var c := size / 2.0 + Vector2(0, 2.0 if down else 0.0)
		var s := size.y * 0.6
		FX.draw_glow(self, Rect2(c - Vector2(s, s) * 0.8, Vector2(s, s) * 1.6), Color(tint, 0.35))
		FX.draw_icon(self, icon_name, c, s * 1.08, Color(tint.lerp(Color.WHITE, 0.3), 0.45))
		FX.draw_icon(self, icon_name, c, s, Color(1, 1, 1, 0.97))


## Pill-shaped on/off switch with a sliding glossy knob.
class Switch extends Button:
	var _t := 0.0

	func _init() -> void:
		toggle_mode = true
		custom_minimum_size = Vector2(116, 64)
		UI.flat(self)
		toggled.connect(func(on: bool):
			create_tween().tween_method(func(v: float):
				_t = v
				queue_redraw(), _t, 1.0 if on else 0.0, 0.16))

	func set_on(on: bool) -> void:
		set_pressed_no_signal(on)
		_t = 1.0 if on else 0.0
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(0, (size.y - 56.0) / 2.0), Vector2(size.x, 56.0))
		var sb := UI.box(FX.INDIGO.darkened(0.45).lerp(UI.GOOD.darkened(0.1), _t), 28)
		sb.border_color = Color(0, 0, 0, 0.35)
		sb.border_width_top = 4
		draw_style_box(sb, r)
		var rad := r.size.y / 2.0 - 5.0
		var x := lerpf(r.position.x + rad + 5.0, r.end.x - rad - 5.0, _t)
		FX.draw_ball(self, Vector2(x, r.get_center().y), rad, Color("#f4f1ff"), "", true)


## Live star meter for the in-game HUD. set_progress(value, thresholds, lower_is_better)
## with thresholds = level "stars" [one, two, three]. Higher-is-better metrics fill the
## bar towards the 3-star mark; lower-is-better ones (moves) start full and drain, and
## the stars drop off as their limit is passed. Stars pop when gained or lost.
class StarMeter extends Control:
	const TRACK_H := 22.0
	const STAR_R := 19.0

	var _fill := 0.0  # shown fill, eased towards _target
	var _target := 0.0
	var _marks: Array[float] = [0.0, 0.0, 0.0]  # where each star sits along the bar, 0..1
	var _labels: Array[String] = ["", "", ""]
	var _lit := -1  # stars currently earned; -1 until the first update
	var _pop: Array[float] = [1.0, 1.0, 1.0]
	var _tw: Tween

	func _init() -> void:
		custom_minimum_size = Vector2(440, 68)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func set_progress(value: float, t: Array, lower_is_better := false) -> void:
		if t.size() < 3:
			return
		var lit := 0
		for i in 3:
			if (value <= t[i]) if lower_is_better else (value >= t[i]):
				lit = i + 1
			if lower_is_better:
				var limit := maxf(float(t[0]), 1.0)
				_marks[i] = 1.0 - float(t[i]) / limit
			else:
				_marks[i] = float(t[i]) / maxf(float(t[2]), 1.0)
			_labels[i] = str(int(t[i])) if (lower_is_better or float(t[i]) > 0.0) else ""
		if lower_is_better:
			_target = clampf(1.0 - value / maxf(float(t[0]), 1.0), 0.0, 1.0)
		else:
			_target = clampf(value / maxf(float(t[2]), 1.0), 0.0, 1.0)
		if _lit < 0:
			_fill = _target
		elif lit != _lit:
			var star := (lit if lit > _lit else _lit) - 1  # the star that changed
			_pop_star(star, lit > _lit)
		_lit = lit
		if _tw:
			_tw.kill()
		_tw = create_tween()
		_tw.tween_method(func(v: float):
			_fill = v
			queue_redraw(), _fill, _target, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		queue_redraw()

	func _pop_star(i: int, gained: bool) -> void:
		var tw := create_tween()
		tw.tween_method(func(v: float):
			_pop[i] = v
			queue_redraw(), 1.7 if gained else 0.4, 1.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if gained:
			Feedback.sfx("star")
			FX.burst(self, _star_pos(i), [FX.LEMON, Color.WHITE], 12, 0.45)

	func _track() -> Rect2:
		var pad := STAR_R + 4.0
		return Rect2(pad, 8.0 + STAR_R - TRACK_H / 2.0, size.x - pad * 2.0, TRACK_H)

	func _star_pos(i: int) -> Vector2:
		var tr := _track()
		return Vector2(tr.position.x + tr.size.x * _marks[i], tr.get_center().y)

	func _draw() -> void:
		var tr := _track()
		var sb := UI.box(Color(0.03, 0.02, 0.12, 0.65), int(TRACK_H / 2.0))
		sb.border_color = Color(1, 1, 1, 0.12)
		sb.set_border_width_all(2)
		draw_style_box(sb, tr.grow(3.0))
		if _fill > 0.0:
			var fr := Rect2(tr.position, Vector2(maxf(TRACK_H, tr.size.x * _fill), TRACK_H))
			FX.draw_round_gradient(self, fr, TRACK_H / 2.0, FX.LEMON.lightened(0.2), FX.TANGERINE)
			FX.draw_round_gradient(self, Rect2(fr.position + Vector2(6, 3), Vector2(fr.size.x - 12, 6)),
				3.0, Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.1))
		var f := FX.font()
		for i in 3:
			var c := _star_pos(i)
			var on := i < _lit
			FX.draw_star(self, c, STAR_R * (_pop[i] if on else 1.0) * (1.0 if on else 0.8), FX.LEMON, on)
			if not on and _pop[i] < 1.0:  # just lost: a shrinking ghost of the star
				FX.draw_star(self, c, STAR_R * _pop[i], Color(FX.LEMON, 0.5), true)
			if _labels[i] != "":
				var w := f.get_string_size(_labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
				draw_string_outline(f, Vector2(c.x - w / 2.0, size.y - 2.0), _labels[i],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0, 0, 0, 0.6))
				draw_string(f, Vector2(c.x - w / 2.0, size.y - 2.0), _labels[i],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.85 if on else 0.5))
