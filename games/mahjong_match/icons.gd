extends RefCounted
## Small drawn icons and the HUD chip for Mahjong Match.

const FX := preload("res://core/fx.gd")
const LEMON := Color("#FFD23F")

static func draw_action_icon(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(3.0, s * 0.12)
	match kind:
		"hint":  # light bulb
			ci.draw_circle(c + Vector2(0, -s * 0.1), s * 0.3, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.15, s * 0.16), Vector2(s * 0.3, s * 0.1)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.1, s * 0.3), Vector2(s * 0.2, s * 0.07)), col)
			for k in 5:
				var a := -PI * 0.5 + (k - 2) * 0.55
				ci.draw_line(c + Vector2(0, -s * 0.1) + Vector2(cos(a), sin(a)) * s * 0.4,
					c + Vector2(0, -s * 0.1) + Vector2(cos(a), sin(a)) * s * 0.55, col, w * 0.8, true)
		"shuffle":  # two crossing arrows
			for k in 2:
				var sg := -1.0 if k == 0 else 1.0
				var pts := PackedVector2Array([c + Vector2(-s * 0.45, sg * s * 0.2), c + Vector2(-s * 0.12, sg * s * 0.2),
					c + Vector2(s * 0.12, -sg * s * 0.2), c + Vector2(s * 0.34, -sg * s * 0.2)])
				ci.draw_polyline(pts, col, w, true)
				var tip := pts[3]
				ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(s * 0.14, 0), tip + Vector2(-s * 0.02, -s * 0.13),
					tip + Vector2(-s * 0.02, s * 0.13)]), col)
		_:  # undo: a restart arrow mirrored
			ci.draw_set_transform(c, 0.0, Vector2(-1, 1))
			FX.draw_icon(ci, "restart", Vector2.ZERO, s * 1.3, col)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Dark pill with a gold rim, a round icon on the left and a value; used by the HUD.
static func draw_chip(ci: CanvasItem, r: Rect2, icon: String, text: String, font: Font, accent: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(r.size.y / 2.0))
	sb.bg_color = Color(0.03, 0.05, 0.16, 0.72)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	ci.draw_style_box(sb, r)
	sb.draw_center = false
	sb.shadow_size = 0
	sb.set_border_width_all(2)
	sb.border_color = Color(LEMON, 0.45)
	ci.draw_style_box(sb, r)
	var ic := Vector2(r.position.x + r.size.y / 2.0, r.get_center().y)
	ci.draw_circle(ic, r.size.y * 0.4, accent)
	ci.draw_arc(ic, r.size.y * 0.4, 0.0, TAU, 32, accent.darkened(0.4), 2.0, true)
	var s := r.size.y * 0.5
	match icon:
		"tiles":
			var tr := Rect2(ic - Vector2(s * 0.3, s * 0.4), Vector2(s * 0.6, s * 0.8))
			ci.draw_rect(Rect2(tr.position + Vector2(2, 2), tr.size), Color(0, 0, 0, 0.3))
			ci.draw_rect(tr, Color("#fff6df"))
			ci.draw_circle(tr.get_center(), s * 0.14, accent.darkened(0.3))
		"clock":
			ci.draw_arc(ic, s * 0.38, 0.0, TAU, 24, Color.WHITE, 2.5, true)
			ci.draw_line(ic, ic + Vector2(0, -s * 0.28), Color.WHITE, 2.5, true)
			ci.draw_line(ic, ic + Vector2(s * 0.2, s * 0.06), Color.WHITE, 2.5, true)
		"board":
			for k in 3:
				ci.draw_rect(Rect2(ic + Vector2(-s * 0.36 + k * 2.0, -s * 0.3 + k * s * 0.24 - 2.0), Vector2(s * 0.72 - k * 4.0, s * 0.18)),
					Color.WHITE)
		"flame":
			ci.draw_colored_polygon(PackedVector2Array([ic + Vector2(0, -s * 0.45), ic + Vector2(s * 0.3, s * 0.05),
				ic + Vector2(s * 0.16, s * 0.4), ic + Vector2(-s * 0.16, s * 0.4), ic + Vector2(-s * 0.3, s * 0.05)]), Color.WHITE)
		"plus":
			ci.draw_line(ic + Vector2(-s * 0.3, 0), ic + Vector2(s * 0.3, 0), Color.WHITE, 3.0, true)
			ci.draw_line(ic + Vector2(0, -s * 0.3), ic + Vector2(0, s * 0.3), Color.WHITE, 3.0, true)
	FX.draw_text_centered(ci, Vector2((ic.x + r.size.y * 0.4 + r.end.x) / 2.0, r.get_center().y), text, int(r.size.y * 0.56),
		Color.WHITE, font)
