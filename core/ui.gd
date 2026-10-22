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


static func box(color: Color, radius := 24) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(16)
	return sb


## Translucent panel with a light rim, for grouping rows on a gradient background.
static func card_box(radius := 32) -> StyleBoxFlat:
	var sb := box(Color(FX.INDIGO.darkened(0.35), 0.82), radius)
	sb.border_color = Color(1, 1, 1, 0.1)
	sb.set_border_width_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, 8)
	sb.set_content_margin_all(28)
	return sb


static func button(text: String, on_press: Callable, color := FX.INDIGO.lightened(0.12), font := 34) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 96)
	b.add_theme_font_size_override("font_size", font)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	FX.style_button(b, color)
	wire(b, on_press)
	return b


## Square button with a drawn icon: "back", "restart" or "settings".
static func icon_button(icon: String, on_press: Callable, color := FX.INDIGO.lightened(0.12)) -> Button:
	var b := IconButton.new()
	b.icon_name = icon
	b.custom_minimum_size = Vector2(88, 88)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	FX.style_button(b, color)
	wire(b, on_press)
	return b


## Tap sound + buzz, then on_press.
static func wire(b: BaseButton, on_press: Callable) -> void:
	b.pressed.connect(func():
		Feedback.sfx("tap")
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
	var sb := box(Color(0.05, 0.04, 0.16, 0.7), 40)
	sb.border_color = Color(FX.LEMON, 0.55)
	sb.set_border_width_all(3)
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

## Menu background: FX gradient, an accent glow at the top, faint rings for depth.
class Backdrop extends Control:
	var accent := FX.TANGERINE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		FX.draw_background(self, Rect2(Vector2.ZERO, size))
		FX.draw_glow(self, Rect2(-w * 0.35, -h * 0.2, w * 1.7, h * 0.5), Color(accent, 0.26))
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for i in 12:
			var c := Vector2(rng.randf() * w, rng.randf() * h)
			var r := rng.randf_range(24.0, 110.0)
			draw_circle(c, r, Color(1, 1, 1, 0.022))
			draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.045), 2.0, true)
		FX.draw_vgradient(self, Rect2(0, h * 0.75, w, h * 0.25), Color(0, 0, 0, 0), Color(0, 0, 0, 0.3))


## Button that draws an FX icon on its raised face.
class IconButton extends Button:
	var icon_name := ""

	func _draw() -> void:
		var down := get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED
		var c := size / 2.0 + Vector2(0, 1.0 if down else -3.0)
		var s := size.y * 0.6
		FX.draw_icon(self, icon_name, c + Vector2(0, 3), s, Color(0, 0, 0, 0.3))
		FX.draw_icon(self, icon_name, c, s)


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
