extends RefCounted
## Vector card faces, backs and suit pips, all drawn in code (no image assets).
## Load with: const CardArt := preload("res://core/cards/card_art.gd")
## Call the static draw_* functions from any CanvasItem's _draw(). They leave the item's
## draw transform at identity.

const FX := preload("res://core/fx.gd")

const INK_RED := Color("#d3243f")
const INK_BLACK := Color("#1b1946")
const FACE_TOP := Color("#fffdf7")
const FACE_BOTTOM := Color("#e9e3f6")
const GOLD := Color("#f2a900")
const GOLD_LIGHT := Color("#ffd86b")
const SKIN := Color("#f7d6b4")

static var _sb := StyleBoxFlat.new()

## Pip positions for ranks 2..10 as [column 0..2, row 0..1] in the pip area.
const PIPS := {
	2: [[1, 0.0], [1, 1.0]],
	3: [[1, 0.0], [1, 0.5], [1, 1.0]],
	4: [[0, 0.0], [2, 0.0], [0, 1.0], [2, 1.0]],
	5: [[0, 0.0], [2, 0.0], [1, 0.5], [0, 1.0], [2, 1.0]],
	6: [[0, 0.0], [2, 0.0], [0, 0.5], [2, 0.5], [0, 1.0], [2, 1.0]],
	7: [[0, 0.0], [2, 0.0], [1, 0.25], [0, 0.5], [2, 0.5], [0, 1.0], [2, 1.0]],
	8: [[0, 0.0], [2, 0.0], [1, 0.25], [0, 0.5], [2, 0.5], [1, 0.75], [0, 1.0], [2, 1.0]],
	9: [[0, 0.0], [2, 0.0], [0, 0.333], [2, 0.333], [1, 0.5], [0, 0.667], [2, 0.667], [0, 1.0], [2, 1.0]],
	10: [[0, 0.0], [2, 0.0], [1, 0.167], [0, 0.333], [2, 0.333], [0, 0.667], [2, 0.667], [1, 0.833], [0, 1.0], [2, 1.0]],
}


static func ink(suit: int) -> Color:
	return INK_RED if suit == 1 or suit == 2 else INK_BLACK


static func _reset(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Two-layer drop shadow: a wide soft one and a tight contact one. `lift` (0..1) pushes the card
## "up" (bigger, further, fainter), used while dragging and flying.
static func draw_shadow(ci: CanvasItem, r: Rect2, lift := 0.0) -> void:
	var rad := int(r.size.x * 0.12)
	_sb.set_corner_radius_all(rad)
	_sb.draw_center = true
	_sb.bg_color = Color(0, 0, 0, 0)
	_sb.set_border_width_all(0)
	_sb.shadow_color = Color(0.02, 0.0, 0.12, 0.34 + 0.1 * lift)
	_sb.shadow_size = int(7 + 14 * lift)
	_sb.shadow_offset = Vector2(0, 4.0 + 12.0 * lift)
	ci.draw_style_box(_sb, r)
	_sb.shadow_color = Color(0, 0, 0, 0.42 - 0.2 * lift)
	_sb.shadow_size = 2
	_sb.shadow_offset = Vector2(0, 1.5)
	ci.draw_style_box(_sb, r)


static func _outline(ci: CanvasItem, r: Rect2, rad: float, col: Color, width: float) -> void:
	var pts := FX.round_rect_points(r, rad)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, width, true)


static func _body(ci: CanvasItem, r: Rect2, top: Color, bottom: Color, edge: Color) -> void:
	var rad := r.size.x * 0.12
	FX.draw_round_gradient(ci, r, rad, top, bottom)
	_outline(ci, r, rad, edge, 1.7)
	_outline(ci, r.grow(-2.2), rad * 0.8, Color(1, 1, 1, 0.75), 1.1)


## Card face. `r` is the card rect in the item's space. Pass `xform` when drawing under your own
## draw_set_transform (e.g. a fanned hand): the upside-down corner index sets a transform of its
## own and restores `xform` afterwards instead of identity.
static func draw_face(ci: CanvasItem, r: Rect2, suit: int, rank: int, lift := 0.0, shadow := true,
		xform := Transform2D.IDENTITY) -> void:
	if shadow:
		draw_shadow(ci, r, lift)
	_body(ci, r, FACE_TOP, FACE_BOTTOM, Color(0.14, 0.12, 0.4, 0.6))
	var w := r.size.x
	var h := r.size.y
	var col := ink(suit)
	# soft sheen across the upper half
	FX.draw_glow(ci, Rect2(r.position + Vector2(w * 0.04, 2.0), Vector2(w * 0.92, h * 0.5)), Color(1, 1, 1, 0.55))
	_index(ci, r, suit, rank, col)
	# the same index upside down in the opposite corner (visible on the top card of a pile)
	ci.draw_set_transform_matrix(xform * Transform2D(PI, r.position * 2.0 + r.size))
	_index(ci, r, suit, rank, col)
	ci.draw_set_transform_matrix(xform)
	var area := Rect2(r.position + Vector2(w * 0.22, h * 0.3), Vector2(w * 0.56, h * 0.4))
	if rank == 1:
		draw_pip(ci, suit, r.get_center() + Vector2(0, h * 0.02), w * 0.3, col)
	elif rank >= 11:
		_court(ci, r, suit, rank, col)
	else:
		var pr := w * (0.12 if rank >= 6 else 0.135)
		for p in PIPS[rank]:
			var x: float = area.position.x + area.size.x * (float(p[0]) * 0.5)
			var y: float = area.position.y + area.size.y * float(p[1])
			draw_pip(ci, suit, Vector2(x, y), pr, col)


static func _index(ci: CanvasItem, r: Rect2, suit: int, rank: int, col: Color) -> void:
	var font := FX.font()
	var w := r.size.x
	var h := r.size.y
	var txt: String = ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"][rank]
	var fs := int(w * 0.34)
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := r.position + Vector2(w * 0.09, h * 0.115 + fs * 0.42)
	ci.draw_string(font, base + Vector2(0.8, 1.2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0.2, 0.18))
	ci.draw_string(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	var px := maxf(w * 0.09 + tw + w * 0.14, w * 0.62) + w * 0.06
	draw_pip(ci, suit, r.position + Vector2(px, h * 0.115 + fs * 0.06), w * 0.1, col)


static func _court(ci: CanvasItem, r: Rect2, suit: int, rank: int, col: Color) -> void:
	var w := r.size.x
	var h := r.size.y
	var panel := Rect2(r.position + Vector2(w * 0.15, h * 0.25), Vector2(w * 0.7, h * 0.53))
	var pr := w * 0.07
	# two-tone panel with a double gold frame
	FX.draw_round_gradient(ci, panel, pr, Color(col, 0.07), Color(GOLD, 0.2))
	ci.draw_colored_polygon(PackedVector2Array([panel.position + Vector2(pr, 0), panel.position + Vector2(panel.size.x * 0.55, 0),
		panel.position + Vector2(0, panel.size.y * 0.7), panel.position + Vector2(0, pr)]), Color(col, 0.07))
	_outline(ci, panel, pr, Color(col, 0.7), 1.5)
	_outline(ci, panel.grow(-3.0), pr * 0.7, Color(GOLD, 0.9), 1.1)
	var c := panel.get_center() + Vector2(0, panel.size.y * 0.03)
	# robe, trimmed in gold, with the suit on the chest
	var robe := Color(col, 0.95).lightened(0.12)
	var bottom := panel.end.y - 5.0
	var top := c.y + panel.size.y * 0.12
	var robe_pts := PackedVector2Array([Vector2(c.x - w * 0.3, bottom), Vector2(c.x - w * 0.17, top + 2.0),
		Vector2(c.x - w * 0.06, top - 2.0), Vector2(c.x + w * 0.06, top - 2.0), Vector2(c.x + w * 0.17, top + 2.0),
		Vector2(c.x + w * 0.3, bottom)])
	ci.draw_colored_polygon(robe_pts, robe)
	var trim := robe_pts.duplicate()
	ci.draw_polyline(trim, GOLD, 1.6, true)
	ci.draw_line(Vector2(c.x - w * 0.06, top - 1.0), Vector2(c.x, top + h * 0.06), GOLD_LIGHT, 1.4, true)
	ci.draw_line(Vector2(c.x + w * 0.06, top - 1.0), Vector2(c.x, top + h * 0.06), GOLD_LIGHT, 1.4, true)
	draw_pip(ci, suit, Vector2(c.x, top + h * 0.095), w * 0.065, Color("#fff4d0"))
	# head and crown
	var head := Vector2(c.x, c.y - panel.size.y * 0.1)
	var hr := w * 0.095
	ci.draw_circle(head + Vector2(0, 1.5), hr, Color(0, 0, 0.2, 0.18))
	ci.draw_circle(head, hr, SKIN)
	ci.draw_arc(head, hr, 0.0, TAU, 20, SKIN.darkened(0.35), 1.1, true)
	var cw := w * 0.145
	var cy := head.y - hr * 0.55
	var crown := PackedVector2Array()
	match rank:
		13:
			crown = PackedVector2Array([Vector2(-cw, 0), Vector2(-cw, -h * 0.055), Vector2(-cw * 0.45, -h * 0.025),
				Vector2(0, -h * 0.075), Vector2(cw * 0.45, -h * 0.025), Vector2(cw, -h * 0.055), Vector2(cw, 0)])
		12:
			crown = PackedVector2Array([Vector2(-cw, 0), Vector2(-cw, -h * 0.04), Vector2(-cw * 0.5, -h * 0.02),
				Vector2(-cw * 0.25, -h * 0.06), Vector2(0, -h * 0.02), Vector2(cw * 0.25, -h * 0.06),
				Vector2(cw * 0.5, -h * 0.02), Vector2(cw, -h * 0.04), Vector2(cw, 0)])
		_:
			crown = PackedVector2Array([Vector2(-cw, 0), Vector2(-cw * 0.9, -h * 0.04), Vector2(cw * 0.2, -h * 0.04),
				Vector2(cw * 0.9, -h * 0.085), Vector2(cw * 0.7, -h * 0.02), Vector2(cw, 0)])
	for i in crown.size():
		crown[i] += Vector2(c.x, cy)
	ci.draw_colored_polygon(crown, col if rank == 11 else GOLD)
	var rim := crown.duplicate()
	rim.append(rim[0])
	ci.draw_polyline(rim, (GOLD if rank == 11 else GOLD.darkened(0.45)), 1.2, true)
	if rank != 11:
		ci.draw_circle(Vector2(c.x, cy - h * 0.075 if rank == 13 else cy - h * 0.04), w * 0.018, Color("#ff5d8f"))


## Card back: indigo guilloche, double tangerine frame, lemon star medallion.
static func draw_back(ci: CanvasItem, r: Rect2, lift := 0.0, shadow := true) -> void:
	if shadow:
		draw_shadow(ci, r, lift)
	var w := r.size.x
	var rad := w * 0.12
	FX.draw_round_gradient(ci, r, rad, FX.INDIGO.lightened(0.3), FX.INDIGO.darkened(0.15))
	_outline(ci, r, rad, Color(0.03, 0.02, 0.18, 0.9), 1.7)
	_outline(ci, r.grow(-2.2), rad * 0.8, Color(1, 1, 1, 0.55), 1.1)
	var inner := r.grow(-w * 0.085)
	FX.draw_round_gradient(ci, inner, w * 0.06, FX.INDIGO.lightened(0.08), FX.INDIGO.darkened(0.3))
	_outline(ci, inner, w * 0.06, Color(FX.TANGERINE, 0.95), 1.9)
	_outline(ci, inner.grow(-3.5), w * 0.04, Color(FX.LEMON, 0.5), 1.0)
	# lattice: diamonds in two sizes, alternating colour
	var step := w * 0.17
	var area := inner.grow(-6.0)
	var cols := int(area.size.x / step)
	var rows := int(area.size.y / step)
	var x0 := area.position.x + (area.size.x - cols * step) / 2.0 + step / 2.0
	var y0 := area.position.y + (area.size.y - rows * step) / 2.0 + step / 2.0
	var mid := r.get_center()
	for ix in cols:
		for iy in rows:
			var c := Vector2(x0 + ix * step, y0 + iy * step)
			if c.distance_to(mid) < w * 0.3:
				continue
			var d := step * (0.27 if (ix + iy) % 2 == 0 else 0.13)
			var tint := Color(FX.TANGERINE, 0.5) if (ix + iy) % 2 == 0 else Color(FX.LEMON, 0.55)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d),
				c + Vector2(-d, 0)]), tint)
	# medallion
	FX.draw_glow(ci, Rect2(mid - Vector2(w * 0.4, w * 0.4), Vector2(w * 0.8, w * 0.8)), Color(FX.TANGERINE, 0.45))
	ci.draw_circle(mid, w * 0.25, FX.INDIGO.darkened(0.35))
	ci.draw_arc(mid, w * 0.25, 0.0, TAU, 40, FX.TANGERINE, 2.0, true)
	ci.draw_arc(mid, w * 0.205, 0.0, TAU, 40, Color(FX.LEMON, 0.6), 1.0, true)
	for i in 12:
		var a := TAU * i / 12.0
		ci.draw_circle(mid + Vector2(cos(a), sin(a)) * w * 0.225, 1.4, FX.LEMON)
	FX.draw_star(ci, mid, w * 0.15)
	# gloss across the top-left
	var g := r.grow(-3.0)
	ci.draw_colored_polygon(PackedVector2Array([g.position + Vector2(rad, 0), g.position + Vector2(g.size.x * 0.75, 0),
		g.position + Vector2(0, g.size.y * 0.5), g.position + Vector2(0, rad)]), Color(1, 1, 1, 0.07))


## Suit pip centred at c, radius r (the pip fits a circle of about that size), with a soft drop shadow.
static func draw_pip(ci: CanvasItem, suit: int, c: Vector2, r: float, col: Color) -> void:
	if col.a > 0.9 and r > 6.0:
		_pip_shape(ci, suit, c + Vector2(0.6, 1.4), r, Color(0, 0, 0.2, 0.16))
	_pip_shape(ci, suit, c, r, col)
	if r > 9.0 and col.a > 0.9 and col.v > 0.15:
		# tiny specular dot
		ci.draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.1, Color(1, 1, 1, 0.35))


static func _pip_shape(ci: CanvasItem, suit: int, c: Vector2, r: float, col: Color) -> void:
	match suit:
		0:  # spade: upside-down heart plus a stem
			ci.draw_colored_polygon(_heart(c + Vector2(0, -r * 0.05), r * 0.98, true), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, r * 0.35), c + Vector2(r * 0.34, r * 1.0),
				c + Vector2(-r * 0.34, r * 1.0)]), col)
		1:
			ci.draw_colored_polygon(_heart(c + Vector2(0, r * 0.05), r * 1.0, false), col)
		2:
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.05), c + Vector2(r * 0.74, 0),
				c + Vector2(0, r * 1.05), c + Vector2(-r * 0.74, 0)]), col)
		_:  # club: three lobes plus a stem
			var lr := r * 0.43
			ci.draw_circle(c + Vector2(0, -r * 0.5), lr, col)
			ci.draw_circle(c + Vector2(-r * 0.5, r * 0.2), lr, col)
			ci.draw_circle(c + Vector2(r * 0.5, r * 0.2), lr, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.2), c + Vector2(r * 0.3, r * 1.0),
				c + Vector2(-r * 0.3, r * 1.0)]), col)
			ci.draw_circle(c + Vector2(0, r * 0.1), lr * 0.9, col)


static func _heart(c: Vector2, r: float, flip: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 32
	for i in n:
		var t := TAU * i / n
		var x := 16.0 * pow(sin(t), 3.0)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		var p := Vector2(x, y) / 16.5 * r
		if flip:
			p.y = -p.y
		pts.append(c + p + Vector2(0, -r * 0.05 if not flip else r * 0.05))
	return pts
