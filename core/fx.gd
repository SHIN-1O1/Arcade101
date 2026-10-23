extends RefCounted
## Shared visual kit. Load it with `const FX := preload("res://core/fx.gd")` (no class_name, so it
## works on a fresh clone before the editor rebuilds its global class cache).
## Every game gets the same polish with no image assets.
## Draw helpers take the CanvasItem to draw on (call them from its _draw()).
## Node helpers (style_button, pop, burst, shake) work on any Control/Node2D.
## Textures are tiny radial gradients built once and shared.

const INDIGO := Color("#2B2A6B")
const TANGERINE := Color("#FF8A1F")
const LEMON := Color("#FFD23F")
const BG_TOP := Color("#1d1f33")  # same as UI.BG so the host's top bar blends in
const BG_BOTTOM := Color("#141331")

static var _shadow: GradientTexture2D
static var _light: GradientTexture2D
static var _shade: GradientTexture2D
static var _box := StyleBoxFlat.new()
static var _font: Font
static var _theme: Theme


# --- textures ---------------------------------------------------------------

static func _radial(offsets: Array, colors: Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256  # sharp rims on big balls at 1440p; still tiny and built once
	t.height = 256
	return t


## Soft black blob (drop/contact shadows).
static func shadow_tex() -> GradientTexture2D:
	if _shadow == null:
		_shadow = _radial([0.0, 1.0], [Color(0, 0, 0, 0.6), Color(0, 0, 0, 0)])
	return _shadow


## Soft white blob (glows, highlights, particles); tint it with modulate.
static func light_tex() -> GradientTexture2D:
	if _light == null:
		_light = _radial([0.0, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	return _light


## Sphere shading: lit centre, darker rim, transparent outside the circle.
static func shade_tex() -> GradientTexture2D:
	if _shade == null:
		_shade = _radial([0.0, 0.5, 0.9, 0.985, 1.0], [Color(1, 1, 1, 0.12), Color(0, 0, 0, 0),
			Color(0, 0, 0, 0.22), Color(0, 0, 0, 0.38), Color(0, 0, 0, 0)])
	return _shade


# --- draw helpers (call inside _draw) ---------------------------------------

## Vertical gradient (top -> indigo -> bottom) with a soft light in the middle.
static func draw_background(ci: CanvasItem, rect: Rect2) -> void:
	var mid := INDIGO.darkened(0.2)
	var split := rect.position.y + rect.size.y * 0.45
	draw_vgradient(ci, Rect2(rect.position, Vector2(rect.size.x, split - rect.position.y)), BG_TOP, mid)
	draw_vgradient(ci, Rect2(rect.position.x, split, rect.size.x, rect.end.y - split), mid, BG_BOTTOM)
	var w := rect.size.x
	var h := rect.size.y
	draw_glow(ci, Rect2(rect.position + Vector2(-w * 0.25, h * 0.12), Vector2(w * 1.5, h * 0.62)),
		Color(0.55, 0.5, 1.0, 0.16))
	draw_glow(ci, Rect2(rect.position + Vector2(w * 0.1, h * 0.55), Vector2(w * 0.8, h * 0.3)),
		Color(TANGERINE, 0.07))


static func draw_vgradient(ci: CanvasItem, r: Rect2, top: Color, bottom: Color) -> void:
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
		Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bottom, bottom]))


## Rounded rect with a vertical gradient (cards, banners). round_bottom = false keeps
## the bottom corners square, e.g. for a coloured header band across a card's top.
static func draw_round_gradient(ci: CanvasItem, r: Rect2, radius: float, top: Color, bottom: Color,
		round_bottom := true, smooth_edge := true) -> void:
	var pts := round_rect_points(r, radius, round_bottom)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top.lerp(bottom, clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)))
	ci.draw_polygon(pts, cols)
	if not smooth_edge:  # caller draws its own anti-aliased outline (e.g. playing cards)
		return
	# Polygons have no anti-aliasing in the Compatibility renderer: a 1 px smoothed rim in the
	# same colours keeps card edges crisp instead of stair-stepped on high-density screens.
	pts.append(pts[0])
	cols.append(cols[0])
	ci.draw_polyline_colors(pts, cols, 1.0, true)


## Outline of a rounded rect, clockwise from the top edge (for draw_polygon / draw_polyline).
static func round_rect_points(r: Rect2, radius: float, round_bottom := true) -> PackedVector2Array:
	radius = minf(radius, minf(r.size.x, r.size.y) / 2.0)
	var centres := [Vector2(r.end.x - radius, r.position.y + radius), Vector2(r.end.x - radius, r.end.y - radius),
		Vector2(r.position.x + radius, r.end.y - radius), Vector2(r.position.x + radius, r.position.y + radius)]
	var pts := PackedVector2Array()
	for i in 4:
		if not round_bottom and (i == 1 or i == 2):
			pts.append(Vector2(r.end.x if i == 1 else r.position.x, r.end.y))
			continue
		for s in 9:
			var a := -PI / 2.0 + i * PI / 2.0 + s * PI / 16.0
			pts.append(centres[i] + Vector2(cos(a), sin(a)) * radius)
	return pts


## Soft elliptical shadow filling r (e.g. a flat rect under an object's base).
static func draw_shadow(ci: CanvasItem, r: Rect2, alpha := 0.7) -> void:
	ci.draw_texture_rect(shadow_tex(), r, false, Color(1, 1, 1, alpha))


## Soft additive-looking light filling r, tinted by col (alpha = strength).
static func draw_glow(ci: CanvasItem, r: Rect2, col: Color) -> void:
	ci.draw_texture_rect(light_tex(), r, false, col)


## Glossy ball: shading, specular highlight, crisp anti-aliased rim, optional label.
static func draw_ball(ci: CanvasItem, c: Vector2, rad: float, col: Color, label := "",
		airborne := false) -> void:
	if rad < 1.0:
		return
	if airborne:
		draw_shadow(ci, Rect2(c.x - rad * 0.9, c.y + rad * 0.8, rad * 1.8, rad * 0.6), 0.6)
	ci.draw_circle(c, rad, col)
	ci.draw_texture_rect(shade_tex(), Rect2(c.x - rad, c.y - rad, rad * 2.0, rad * 2.0), false)
	draw_glow(ci, Rect2(c.x - rad * 0.68, c.y - rad * 0.74, rad * 0.8, rad * 0.62), Color(1, 1, 1, 0.75))
	ci.draw_arc(c, rad, 0.0, TAU, 48, col.darkened(0.45), maxf(1.5, rad * 0.06), true)
	if label != "":
		draw_text_centered(ci, c, label, int(rad * 0.9))


## Glossy rounded rect (tiles, cells, blocks): drop shadow, body, top sheen, darker bottom edge.
static func draw_tile(ci: CanvasItem, r: Rect2, col: Color, radius := 12, shadow := true) -> void:
	if r.size.x < 2.0 or r.size.y < 2.0:
		return
	var sb := _box
	sb.set_corner_radius_all(radius)
	sb.draw_center = true
	sb.set_border_width_all(0)
	sb.shadow_size = 0
	if shadow:
		sb.bg_color = Color(0, 0, 0, 0)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = maxi(4, int(r.size.y * 0.12))
		sb.shadow_offset = Vector2(0, r.size.y * 0.06)
		ci.draw_style_box(sb, r)
		sb.shadow_size = 0
	sb.bg_color = col.darkened(0.3)  # bottom edge shows below the face
	ci.draw_style_box(sb, r)
	sb.bg_color = col
	ci.draw_style_box(sb, Rect2(r.position, Vector2(r.size.x, r.size.y * 0.9)))
	sb.bg_color = Color(1, 1, 1, 0.22)
	sb.set_corner_radius_all(maxi(2, radius - 3))
	ci.draw_style_box(sb, Rect2(r.position + r.size * Vector2(0.1, 0.07), r.size * Vector2(0.8, 0.28)))


## White label with a dark outline, centred on c; readable on any colour.
static func draw_text_centered(ci: CanvasItem, c: Vector2, text: String, font_size: int,
		col := Color(1, 1, 1, 0.95), font: Font = null) -> void:
	if font_size <= 0:
		return
	if font == null:
		font = ThemeDB.fallback_font
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var p := c + Vector2(-tw / 2.0, font_size * 0.36)
	ci.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		maxi(3, int(font_size * 0.18)), Color(0, 0, 0, 0.5))
	ci.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


## Five-point star: soft drop shadow, dark rim, lighter top half. Empty = dark socket.
static func draw_star(ci: CanvasItem, c: Vector2, r: float, col := LEMON, filled := true) -> void:
	var pts := star_points(c, r)
	var rim := pts.duplicate()
	rim.append(pts[0])
	if not filled:
		ci.draw_colored_polygon(pts, Color(0, 0, 0, 0.32))
		ci.draw_polyline(rim, Color(1, 1, 1, 0.16), maxf(1.0, r * 0.1), true)
		return
	ci.draw_colored_polygon(star_points(c + Vector2(0, r * 0.16), r), Color(0, 0, 0, 0.3))
	ci.draw_colored_polygon(pts, col.darkened(0.12))
	ci.draw_colored_polygon(star_points(c - Vector2(0, r * 0.1), r * 0.62), col.lightened(0.25))
	ci.draw_polyline(rim, col.darkened(0.5), maxf(1.2, r * 0.13), true)


static func star_points(c: Vector2, r: float, inner := 0.48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * inner))
	return pts


## Padlock icon centred on c, about s tall.
static func draw_lock(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var top := c.y - s * 0.08
	ci.draw_arc(Vector2(c.x, top), s * 0.24, PI, TAU, 24, col, s * 0.11, true)
	ci.draw_line(Vector2(c.x - s * 0.24, top), Vector2(c.x - s * 0.24, top + s * 0.1), col, s * 0.11)
	ci.draw_line(Vector2(c.x + s * 0.24, top), Vector2(c.x + s * 0.24, top + s * 0.1), col, s * 0.11)
	var sb := _box
	sb.shadow_size = 0
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(int(s * 0.12))
	sb.bg_color = col
	ci.draw_style_box(sb, Rect2(c.x - s * 0.38, top + s * 0.02, s * 0.76, s * 0.56))
	var hole := Vector2(c.x, top + s * 0.25)
	ci.draw_circle(hole, s * 0.08, col.darkened(0.55))
	ci.draw_line(hole, hole + Vector2(0, s * 0.16), col.darkened(0.55), s * 0.07)


## Simple line icons for round buttons: "back", "restart", "settings".
static func draw_icon(ci: CanvasItem, icon: String, c: Vector2, s: float, col := Color.WHITE) -> void:
	var w := maxf(3.0, s * 0.14)
	match icon:
		"back":
			ci.draw_polyline(PackedVector2Array([c + Vector2(s * 0.14, -s * 0.3), c + Vector2(-s * 0.18, 0),
				c + Vector2(s * 0.14, s * 0.3)]), col, w, true)
			ci.draw_circle(c + Vector2(s * 0.14, -s * 0.3), w / 2.0, col)
			ci.draw_circle(c + Vector2(-s * 0.18, 0), w / 2.0, col)
			ci.draw_circle(c + Vector2(s * 0.14, s * 0.3), w / 2.0, col)
		"restart":
			ci.draw_arc(c, s * 0.3, -PI * 0.35, PI * 1.45, 32, col, w, true)
			var tip := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * s * 0.3
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(-s * 0.2, -s * 0.06),
				tip + Vector2(s * 0.1, -s * 0.18), tip + Vector2(s * 0.06, s * 0.14)]), col)
		"settings":
			var pts := PackedVector2Array()
			for i in 48:
				var a := i * TAU / 48.0
				var tooth := 1.0 if int(i / 3.0) % 2 == 0 else 0.78
				pts.append(c + Vector2(cos(a + PI / 16.0), sin(a + PI / 16.0)) * s * 0.4 * tooth)
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c, s * 0.13, Color(0, 0, 0, 0.45))
		"info":  # lowercase i: dot over a stem with a little foot
			ci.draw_circle(c + Vector2(0, -s * 0.27), w * 0.75, col)
			ci.draw_line(c + Vector2(-s * 0.07, -s * 0.06), c + Vector2(0, -s * 0.06), col, w)
			ci.draw_line(c + Vector2(0, -s * 0.06 - w / 2.0), c + Vector2(0, s * 0.3), col, w)
			ci.draw_line(c + Vector2(-s * 0.12, s * 0.3), c + Vector2(s * 0.12, s * 0.3), col, w)


static func ease_smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# --- fonts and theme --------------------------------------------------------

## Rounded display font for menus (Lilita One, OFL; see core/fonts/OFL.txt).
## Falls back to the default font for glyphs it lacks (★, arrows).
static func font() -> Font:
	if _font == null:
		var f: FontFile = load("res://core/fonts/LilitaOne-Regular.ttf")
		f.fallbacks = [ThemeDB.fallback_font]
		_font = f
	return _font


## Theme for whole screens: display font, outlined text with a drop shadow.
static func theme() -> Theme:
	if _theme == null:
		var t := Theme.new()
		t.default_font = font()
		t.default_font_size = 34
		for type in ["Label", "Button"]:
			t.set_constant("outline_size", type, 8)
			t.set_color("font_outline_color", type, Color(0.06, 0.05, 0.18, 0.75))
		t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
		t.set_constant("shadow_offset_x", "Label", 0)
		t.set_constant("shadow_offset_y", "Label", 4)
		t.set_constant("shadow_outline_size", "Label", 8)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
				"font_hover_pressed_color"]:
			t.set_color(c, "Button", Color.WHITE)
		t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
		_theme = t
	return _theme


# --- node helpers -----------------------------------------------------------

## Chunky 3D button look (raised face, shadow) plus a squash on press.
static func style_button(b: Button, col: Color) -> void:
	b.add_theme_stylebox_override("normal", button_box(col, false))
	b.add_theme_stylebox_override("hover", button_box(col.lightened(0.08), false))
	b.add_theme_stylebox_override("pressed", button_box(col.darkened(0.1), true))
	b.add_theme_stylebox_override("disabled", button_box(Color(col.darkened(0.35), 0.7), true))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	b.button_down.connect(func(): scale_to(b, 0.94, 0.08))
	b.button_up.connect(func(): scale_to(b, 1.0, 0.12))
	b.resized.connect(func(): b.pivot_offset = b.size / 2.0)


static func button_box(col: Color, flat: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(30)
	sb.border_color = col.darkened(0.4)
	sb.border_width_bottom = 2 if flat else 7
	sb.set_content_margin_all(16)
	sb.content_margin_top = 21.0 if flat else 16.0  # text sinks a little when pressed
	if not flat:
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 5)
	return sb


static func scale_to(node: CanvasItem, s: float, time := 0.1) -> Tween:
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2(s, s), time)
	return tw


## Pop in: scale from `from` back to 1 with a little overshoot. Set pivot_offset first on Controls.
static func pop(node: CanvasItem, from := 1.2, time := 0.25) -> Tween:
	node.scale = Vector2(from, from)
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tw


## One-shot particle burst at pos (in parent's space); frees itself.
static func burst(parent: Node, pos: Vector2, colors: Array, amount := 24, power := 1.0) -> void:
	var p := CPUParticles2D.new()
	p.texture = light_tex()
	p.position = pos
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.9
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 220.0 * power
	p.initial_velocity_max = 520.0 * power
	p.gravity = Vector2(0, 900)
	p.damping_min = 40.0
	p.damping_max = 80.0
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.24
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = fade
	if not colors.is_empty():
		var pick := Gradient.new()
		pick.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		var offs: Array = []
		for i in colors.size():
			offs.append(float(i) / colors.size())
		pick.offsets = PackedFloat32Array(offs)
		pick.colors = PackedColorArray(colors)
		p.color_initial_ramp = pick
	parent.add_child(p)
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime + 0.3)
	tw.tween_callback(p.queue_free)


## Short decaying shake of node.position; returns it to where it was.
static func shake(node: CanvasItem, strength := 10.0, time := 0.3) -> void:
	if not (node is Control or node is Node2D):
		return
	var home: Vector2 = node.get("position")
	var tw := node.create_tween()
	var steps := 6
	for i in steps:
		var k := 1.0 - float(i) / steps
		var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * k
		tw.tween_property(node, "position", home + off, time / steps)
	tw.tween_property(node, "position", home, time / steps)
