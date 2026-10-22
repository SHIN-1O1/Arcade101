extends RefCounted
## HUD widgets shared by card games: stat pills and glossy icon action buttons, drawn in code.
## Load with: const CardHud := preload("res://core/cards/card_hud.gd")
##   var pill := CardHud.StatPill.new(); pill.title = "MOVES"; pill.set_value("12")
##   var b := CardHud.ActionButton.new(); b.setup("undo", "Undo", color, callback)

const FX := preload("res://core/fx.gd")


## Rounded dark pill: small caps title over a big value. set_value() pops it when it changes.
class StatPill extends Control:
	var title := ""
	var value := ""
	var accent := FX.LEMON
	var highlight := false
	var _pop := 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(120, 56)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func set_value(v: String, pop := true) -> void:
		if v == value:
			return
		value = v
		if pop and is_inside_tree():
			_pop = 1.18
			create_tween().tween_property(self, "_pop", 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		queue_redraw()

	func _process(_d: float) -> void:
		if _pop != 1.0:
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		FX.draw_round_gradient(self, r, size.y * 0.5, Color(0.1, 0.09, 0.3, 0.92), Color(0.03, 0.02, 0.14, 0.92))
		var pts := FX.round_rect_points(r.grow(-0.8), size.y * 0.5)
		pts.append(pts[0])
		draw_polyline(pts, Color(accent, 0.45 if highlight else 0.22), 1.6, true)
		FX.draw_glow(self, Rect2(r.position + Vector2(size.x * 0.1, 1), Vector2(size.x * 0.8, size.y * 0.5)), Color(1, 1, 1, 0.16))
		var font := FX.font()
		FX.draw_text_centered(self, Vector2(size.x / 2.0, size.y * 0.27), title, 15, Color(1, 1, 1, 0.55), font)
		FX.draw_text_centered(self, Vector2(size.x / 2.0, size.y * 0.67), value, int(28 * _pop),
			accent if highlight else Color.WHITE, font)


## Glossy tile button with a vector icon and a label; optional corner badge and attention pulse.
class ActionButton extends Button:
	var icon_name := ""
	var label := ""
	var badge := ""
	var color := FX.INDIGO.lightened(0.15)
	var compact := false      ## icon and label side by side (for small toggles)
	var attention := false:   ## soft pulsing glow (e.g. Auto is available)
		set(v):
			attention = v
			set_process(v)
			queue_redraw()
	var on := false           ## toggle state, shown as a lit lemon dot
	var show_state := false
	var _t := 0.0

	func setup(icon: String, text: String, col: Color, on_press: Callable) -> void:
		icon_name = icon
		label = text
		color = col
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(0, 92)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		UI.squash(self)
		UI.wire(self, on_press)
		set_process(false)

	func _process(d: float) -> void:
		_t += d
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 10))
		var col := color
		if disabled:
			col = col.darkened(0.45)
			col.s *= 0.5
		FX.draw_tile(self, r, col, int(size.y * 0.24), not disabled)
		if attention:
			var a := 0.35 + 0.3 * sin(_t * 5.0)
			FX.draw_glow(self, r.grow(size.y * 0.35), Color(FX.LEMON, a))
		var fg := Color(1, 1, 1, 0.45 if disabled else 1.0)
		var font := FX.font()
		if compact:
			_icon(icon_name, Vector2(r.position.x + r.size.y * 0.55, r.get_center().y - 2.0), r.size.y * 0.3, fg)
			FX.draw_text_centered(self, Vector2(r.position.x + r.size.y * 1.0 + (r.size.x - r.size.y) * 0.5, r.get_center().y - 2.0),
				label, 22, fg, font)
		else:
			_icon(icon_name, Vector2(r.get_center().x, r.position.y + r.size.y * 0.4), r.size.y * 0.25, fg)
			FX.draw_text_centered(self, Vector2(r.get_center().x, r.position.y + r.size.y * 0.8), label, 21, fg, font)
		if badge != "":
			var b := Vector2(r.end.x - 16.0, r.position.y + 6.0)
			draw_circle(b, 17.0, Color("#ef476f"))
			draw_arc(b, 17.0, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 2.0, true)
			FX.draw_text_centered(self, b, badge, 20, Color.WHITE, font)
		if show_state:
			var d := Vector2(r.end.x - 14.0, r.end.y - 14.0)
			draw_circle(d, 6.0, FX.LEMON if on else Color(0, 0, 0, 0.4))
			draw_arc(d, 6.0, 0.0, TAU, 16, Color(1, 1, 1, 0.7), 1.5, true)

	func _icon(name: String, c: Vector2, s: float, col: Color) -> void:
		var dark := Color(0, 0, 0, 0.28)
		for pass_i in 2:
			var o := Vector2(0, 2.0) if pass_i == 0 else Vector2.ZERO
			var k := dark if pass_i == 0 else col
			var p := c + o
			match name:
				"undo":
					draw_arc(p + Vector2(0, s * 0.1), s * 0.8, -PI * 0.9, PI * 0.55, 24, k, s * 0.28, true)
					var tip := p + Vector2(-s * 0.78, -s * 0.1)
					draw_colored_polygon(PackedVector2Array([tip + Vector2(-s * 0.4, s * 0.15), tip + Vector2(s * 0.5, -s * 0.15),
						tip + Vector2(s * 0.15, s * 0.75)]), k)
				"hint":
					draw_circle(p + Vector2(0, -s * 0.2), s * 0.62, k)
					draw_rect(Rect2(p + Vector2(-s * 0.3, s * 0.35), Vector2(s * 0.6, s * 0.3)), k)
					for a in [-0.9, -0.45, 0.0, 0.45, 0.9]:
						var dir := Vector2(sin(a), -cos(a))
						draw_line(p + Vector2(0, -s * 0.2) + dir * s * 0.82, p + Vector2(0, -s * 0.2) + dir * s * 1.08, k, s * 0.14, true)
				"auto":
					for sp in [[Vector2.ZERO, 1.0], [Vector2(s * 0.8, -s * 0.6), 0.5], [Vector2(-s * 0.75, s * 0.55), 0.42]]:
						var q: Vector2 = p + sp[0]
						var z: float = s * 0.7 * sp[1]
						draw_colored_polygon(PackedVector2Array([q + Vector2(0, -z), q + Vector2(z * 0.28, -z * 0.28), q + Vector2(z, 0),
							q + Vector2(z * 0.28, z * 0.28), q + Vector2(0, z), q + Vector2(-z * 0.28, z * 0.28), q + Vector2(-z, 0),
							q + Vector2(-z * 0.28, -z * 0.28)]), k)
				"draw":
					for i in 3:
						var rr := Rect2(p + Vector2(-s * 0.55 + i * s * 0.28, -s * 0.8 + i * s * 0.1), Vector2(s * 0.85, s * 1.2))
						draw_style_box(UI.box(k if i == 2 else Color(k, 0.55), 4), rr)
				"flag":
					draw_line(p + Vector2(-s * 0.5, s * 0.9), p + Vector2(-s * 0.5, -s * 0.9), k, s * 0.2, true)
					draw_colored_polygon(PackedVector2Array([p + Vector2(-s * 0.45, -s * 0.85), p + Vector2(s * 0.8, -s * 0.4),
						p + Vector2(-s * 0.45, s * 0.1)]), k)
				"tap":
					draw_circle(p + Vector2(0, -s * 0.15), s * 0.28, k)
					draw_arc(p + Vector2(0, -s * 0.15), s * 0.6, 0.0, TAU, 24, k, s * 0.12, true)
					draw_arc(p + Vector2(0, -s * 0.15), s * 0.92, 0.0, TAU, 24, Color(k, 0.5), s * 0.1, true)
