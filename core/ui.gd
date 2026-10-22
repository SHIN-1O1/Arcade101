class_name UI
extends RefCounted
## Tiny code-built UI kit so screens need no hand-made themes yet.

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


static func button(text: String, on_press: Callable, color := CARD, font := 34) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 96)
	b.add_theme_font_size_override("font_size", font)
	b.add_theme_stylebox_override("normal", box(color))
	b.add_theme_stylebox_override("hover", box(color.lightened(0.1)))
	b.add_theme_stylebox_override("pressed", box(color.darkened(0.15)))
	b.add_theme_stylebox_override("disabled", box(MUTED))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func():
		Feedback.sfx("tap")
		Feedback.vibrate(15)
		on_press.call())
	return b


static func label(text: String, font := 34, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_color_override("font_color", color)
	return l


static func stars_text(n: int, of := 3) -> String:
	return "★".repeat(n) + "☆".repeat(of - n)


## Full-screen background + safe-area margin + vertical column. Returns the column.
static func screen(root: Control) -> VBoxContainer:
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var safe := safe_margins(root)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 32 + safe.x)
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
