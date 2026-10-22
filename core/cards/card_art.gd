extends RefCounted
## Vector card faces, backs and suit pips, all drawn in code (no image assets).
## Load with: const CardArt := preload("res://core/cards/card_art.gd")
## Call the static draw_* functions from any CanvasItem's _draw().

const FX := preload("res://core/fx.gd")

const INK_RED := Color("#d62f4b")
const INK_BLACK := Color("#1d1b45")
const FACE_TOP := Color("#ffffff")
const FACE_BOTTOM := Color("#e6e1f4")

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


## Soft drop shadow under a card; `lift` (0..1) makes it bigger and further away (dragged cards).
static func draw_shadow(ci: CanvasItem, r: Rect2, lift := 0.0) -> void:
	var rad := int(r.size.x * 0.12)
	_sb.set_corner_radius_all(rad)
	_sb.draw_center = true
	_sb.bg_color = Color(0, 0, 0, 0)
	_sb.set_border_width_all(0)
	_sb.shadow_color = Color(0, 0, 0, 0.30 + 0.12 * lift)
	_sb.shadow_size = int(5 + 9 * lift)
	_sb.shadow_offset = Vector2(0, 2.0 + 7.0 * lift)
	ci.draw_style_box(_sb, r)


static func _body(ci: CanvasItem, r: Rect2, top: Color, bottom: Color, edge: Color) -> void:
	var rad := r.size.x * 0.12
	FX.draw_round_gradient(ci, r, rad, top, bottom)
	var pts := FX.round_rect_points(r, rad)
	pts.append(pts[0])
	ci.draw_polyline(pts, edge, 1.6, true)


## Card face. `r` is the card rect in the item's space.
static func draw_face(ci: CanvasItem, r: Rect2, suit: int, rank: int, lift := 0.0, shadow := true) -> void:
	if shadow:
		draw_shadow(ci, r, lift)
	_body(ci, r, FACE_TOP, FACE_BOTTOM, Color(0.16, 0.14, 0.42, 0.55))
	var font := FX.font()
	var w := r.size.x
	var h := r.size.y
	var col := ink(suit)
	var txt: String = ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"][rank]
	var fs := int(w * 0.34)
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, r.position + Vector2(w * 0.09, h * 0.115 + fs * 0.42), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_pip(ci, suit, r.position + Vector2(maxf(w * 0.09 + tw + w * 0.14, w * 0.62) + w * 0.06, h * 0.115 + fs * 0.06),
		w * 0.105, col)
	# main art
	var area := Rect2(r.position + Vector2(w * 0.2, h * 0.3), Vector2(w * 0.6, h * 0.58))
	if rank == 1:
		draw_pip(ci, suit, area.get_center() + Vector2(0, -h * 0.01), w * 0.3, col)
	elif rank >= 11:
		_court(ci, r, suit, rank, col)
	else:
		var pr := w * (0.125 if rank >= 6 else 0.14)
		for p in PIPS[rank]:
			var x: float = area.position.x + area.size.x * (float(p[0]) * 0.5)
			var y: float = area.position.y + area.size.y * float(p[1])
			draw_pip(ci, suit, Vector2(x, y), pr, col)


static func _court(ci: CanvasItem, r: Rect2, suit: int, rank: int, col: Color) -> void:
	var w := r.size.x
	var h := r.size.y
	var panel := Rect2(r.position + Vector2(w * 0.17, h * 0.3), Vector2(w * 0.66, h * 0.6))
	var tint := col
	tint.a = 0.13
	FX.draw_round_gradient(ci, panel, w * 0.08, tint, Color(tint, 0.04))
	var pts := FX.round_rect_points(panel, w * 0.08)
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(col, 0.55), 1.4, true)
	var c := panel.get_center()
	# crown (K: three points, Q: five small points, J: plume)
	var gold := Color("#f2a900")
	var cw := w * 0.34
	var cy := panel.position.y + h * 0.075
	var crown := PackedVector2Array()
	if rank == 13:
		crown = PackedVector2Array([Vector2(-cw, cy + h * 0.1), Vector2(-cw, cy), Vector2(-cw * 0.45, cy + h * 0.05),
			Vector2(0, cy - h * 0.02), Vector2(cw * 0.45, cy + h * 0.05), Vector2(cw, cy), Vector2(cw, cy + h * 0.1)])
	elif rank == 12:
		crown = PackedVector2Array([Vector2(-cw, cy + h * 0.1), Vector2(-cw, cy + h * 0.015), Vector2(-cw * 0.5, cy + h * 0.06),
			Vector2(-cw * 0.25, cy), Vector2(0, cy + h * 0.06), Vector2(cw * 0.25, cy), Vector2(cw * 0.5, cy + h * 0.06),
			Vector2(cw, cy + h * 0.015), Vector2(cw, cy + h * 0.1)])
	else:
		crown = PackedVector2Array([Vector2(-cw * 0.9, cy + h * 0.1), Vector2(-cw * 0.9, cy + h * 0.045),
			Vector2(cw * 0.1, cy + h * 0.045), Vector2(cw * 0.55, cy - h * 0.03), Vector2(cw * 0.55, cy + h * 0.1)])
	for i in crown.size():
		crown[i] += Vector2(c.x, 0)
	ci.draw_colored_polygon(crown, gold)
	var rim := crown.duplicate()
	rim.append(rim[0])
	ci.draw_polyline(rim, gold.darkened(0.45), 1.3, true)
	var letter: String = ["J", "Q", "K"][rank - 11]
	var fs := int(w * 0.44)
	var lw := FX.font().get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2(c.x - lw / 2.0, c.y + h * 0.01 + fs * 0.34)
	ci.draw_string_outline(FX.font(), base, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(1, 1, 1, 0.85))
	ci.draw_string(FX.font(), base, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_pip(ci, suit, Vector2(c.x, panel.end.y - h * 0.075), w * 0.085, col)


## Card back: indigo with a lattice, tangerine frame and a lemon star.
static func draw_back(ci: CanvasItem, r: Rect2, lift := 0.0, shadow := true) -> void:
	if shadow:
		draw_shadow(ci, r, lift)
	var w := r.size.x
	var h := r.size.y
	_body(ci, r, FX.INDIGO.lightened(0.22), FX.INDIGO.darkened(0.1), Color(0.04, 0.03, 0.2, 0.8))
	var inner := r.grow(-w * 0.075)
	FX.draw_round_gradient(ci, inner, w * 0.07, FX.INDIGO.lightened(0.05), FX.INDIGO.darkened(0.25))
	var frame := FX.round_rect_points(inner, w * 0.07)
	frame.append(frame[0])
	ci.draw_polyline(frame, Color(FX.TANGERINE, 0.9), 1.8, true)
	# lattice of small diamonds, kept inside the inner frame
	var step := w * 0.2
	var cols := int(inner.size.x / step)
	var rows := int(inner.size.y / step)
	var x0 := inner.position.x + (inner.size.x - cols * step) / 2.0 + step / 2.0
	var y0 := inner.position.y + (inner.size.y - rows * step) / 2.0 + step / 2.0
	var d := step * 0.2
	for ix in cols:
		for iy in rows:
			var c := Vector2(x0 + ix * step, y0 + iy * step)
			if (ix + iy) % 2 == 0:
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d),
					c + Vector2(-d, 0)]), Color(FX.TANGERINE, 0.38))
	var mid := r.get_center()
	ci.draw_circle(mid, w * 0.22, FX.INDIGO.darkened(0.2))
	ci.draw_arc(mid, w * 0.22, 0.0, TAU, 32, FX.TANGERINE, 1.8, true)
	FX.draw_star(ci, mid, w * 0.15)


## Suit pip centred at c, radius r (the pip fits a circle of about that size).
static func draw_pip(ci: CanvasItem, suit: int, c: Vector2, r: float, col: Color) -> void:
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
