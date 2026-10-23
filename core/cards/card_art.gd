extends RefCounted
## Vector card faces, backs and suit pips, all drawn in code (no image assets).
## Load with: const CardArt := preload("res://core/cards/card_art.gd")
## Call the static draw_* functions from any CanvasItem's _draw(). draw_face restores `xform`
## (identity by default) as the item's draw transform. CardView normally shows these through
## CardCache (one atlas texture rendered once), so the extra detail costs nothing per frame.
## Every filled shape gets an anti-aliased rim (Godot polygons have hard edges), so faces stay
## crisp at any size.

const FX := preload("res://core/fx.gd")

const INK_RED := Color("#c3102f")
const INK_BLACK := Color("#16152e")
const FACE_TOP := Color("#fffdf6")
const FACE_BOTTOM := Color("#f1ebdc")
const EDGE := Color("#2c2840")
const GOLD := Color("#c8961e")
const GOLD_LIGHT := Color("#f4d27a")
const GOLD_DARK := Color("#8a6212")
const SKIN := Color("#f4d3b1")
const ERMINE := Color("#fbf7ee")
const BACK_TOP := Color("#34328a")
const BACK_BOTTOM := Color("#191849")
const RANKS := ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

## When true (set by CardCache while it renders the atlas) faces get paper grain and finer patterns.
static var detail := false
static var _sb := StyleBoxFlat.new()
static var _rank_font: Font

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


## High-contrast serif (Playfair Display, OFL) used for indices and court letters.
static func rank_font() -> Font:
	if _rank_font == null:
		var fv := FontVariation.new()
		fv.base_font = load("res://core/cards/fonts/PlayfairDisplay.ttf")
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): 900}
		fv.opentype_features = {ts.name_to_tag("lnum"): 1}  # lining figures (the default ones descend)
		_rank_font = fv
	return _rank_font


static func corner_radius(w: float) -> float:
	return w * 0.085


## Filled polygon with an anti-aliased rim. `cols` (optional) gives per-point colours.
static func fill(ci: CanvasItem, pts: PackedVector2Array, col: Color, cols := PackedColorArray()) -> void:
	if pts.size() < 3:
		return
	var loop := pts.duplicate()
	loop.append(pts[0])
	if cols.is_empty():
		ci.draw_colored_polygon(pts, col)
		ci.draw_polyline(loop, col, 1.0, true)
	else:
		ci.draw_polygon(pts, cols)
		var lc := cols.duplicate()
		lc.append(cols[0])
		ci.draw_polyline_colors(loop, lc, 1.0, true)


## The same polygon shaded top (light) to bottom (col) across the band y0..y1.
static func fill_shaded(ci: CanvasItem, pts: PackedVector2Array, col: Color, y0: float, y1: float, light := 0.22) -> void:
	var top := col.lightened(light)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top.lerp(col, clampf((p.y - y0) / maxf(1.0, y1 - y0), 0.0, 1.0)))
	fill(ci, pts, col, cols)


static func circle_pts(c: Vector2, r: float, n := 0) -> PackedVector2Array:
	if n <= 0:
		n = clampi(int(r * 1.6), 14, 48)
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func _outline(ci: CanvasItem, r: Rect2, rad: float, col: Color, width: float) -> void:
	var pts := FX.round_rect_points(r, rad)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, width, true)


static func _quad(a: Vector2, ctrl: Vector2, b: Vector2, n: int, out: PackedVector2Array, skip_first := false) -> void:
	for i in range(1 if skip_first else 0, n + 1):
		var t := float(i) / n
		out.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))


## Two-layer drop shadow: a wide soft one and a tight contact one. `lift` (0..1) pushes the card
## "up" (bigger, further, fainter), used while dragging and flying. Pure black so it also works
## on a premultiplied-alpha canvas item.
static func draw_shadow(ci: CanvasItem, r: Rect2, lift := 0.0) -> void:
	var rad := int(corner_radius(r.size.x))
	_sb.set_corner_radius_all(rad)
	_sb.draw_center = true
	_sb.bg_color = Color(0, 0, 0, 0)
	_sb.set_border_width_all(0)
	_sb.shadow_color = Color(0, 0, 0, 0.3 + 0.08 * lift)
	_sb.shadow_size = int(6 + 14 * lift)
	_sb.shadow_offset = Vector2(0, 3.5 + 12.0 * lift)
	ci.draw_style_box(_sb, r)
	_sb.shadow_color = Color(0, 0, 0, 0.45 - 0.2 * lift)
	_sb.shadow_size = 2
	_sb.shadow_offset = Vector2(0, 1.2)
	ci.draw_style_box(_sb, r)


static func _paper(ci: CanvasItem, r: Rect2, seed_: int) -> void:
	var w := r.size.x
	var rad := corner_radius(w)
	FX.draw_round_gradient(ci, r, rad, FACE_TOP, FACE_BOTTOM)
	if detail:
		# fine paper grain, seeded per card so it never shimmers
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_
		var inner := r.grow(-rad * 0.5)
		for i in int(w * 1.4):
			var p := inner.position + Vector2(rng.randf(), rng.randf()) * inner.size
			ci.draw_rect(Rect2(p, Vector2.ONE * rng.randf_range(0.8, 1.6)), Color(0.45, 0.38, 0.25, rng.randf_range(0.03, 0.07)))
	# soft light from the top edge, then a crisp rim and a bright inner bevel
	FX.draw_vgradient(ci, Rect2(r.position + Vector2(rad, 1.0), Vector2(w - rad * 2.0, r.size.y * 0.06)),
		Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.0))
	_outline(ci, r.grow(-0.5), rad, Color(EDGE, 0.55), maxf(1.0, w * 0.011))
	_outline(ci, r.grow(-maxf(1.6, w * 0.018)), rad * 0.8, Color(1, 1, 1, 0.9), maxf(1.0, w * 0.01))


## Card face. `r` is the card rect in the item's space. Pass `xform` when drawing under your own
## draw_set_transform (e.g. a fanned hand): the upside-down halves set a transform of their own
## and restore `xform` afterwards instead of identity.
static func draw_face(ci: CanvasItem, r: Rect2, suit: int, rank: int, lift := 0.0, shadow := true,
		xform := Transform2D.IDENTITY) -> void:
	if shadow:
		draw_shadow(ci, r, lift)
	_paper(ci, r, suit * 13 + rank)
	var w := r.size.x
	var h := r.size.y
	var col := ink(suit)
	_index(ci, r, suit, rank, col)
	# the same index upside down in the opposite corner
	ci.draw_set_transform_matrix(xform * Transform2D(PI, r.position * 2.0 + r.size))
	_index(ci, r, suit, rank, col)
	ci.draw_set_transform_matrix(xform)
	if rank == 1:
		_ace(ci, r, suit, col)
	elif rank >= 11:
		_court(ci, r, suit, rank, col, xform)
	else:
		var area := Rect2(r.position + Vector2(w * 0.27, h * (0.28 if rank >= 9 else 0.3)), Vector2(w * 0.46, h * (0.44 if rank >= 9 else 0.4)))
		var pr := w * (0.094 if rank >= 9 else 0.105 if rank >= 6 else 0.115)
		for p in PIPS[rank]:
			var x: float = area.position.x + area.size.x * (float(p[0]) * 0.5)
			var y: float = area.position.y + area.size.y * float(p[1])
			draw_pip(ci, suit, Vector2(x, y), pr, col, float(p[1]) > 0.55)


static func _index(ci: CanvasItem, r: Rect2, suit: int, rank: int, col: Color) -> void:
	var font := rank_font()
	var w := r.size.x
	var h := r.size.y
	var txt: String = RANKS[rank]
	var fs := int(w * (0.3 if rank == 10 else 0.33))
	var cap := fs * 0.71
	var top := h * 0.055
	var x := r.position.x + w * (0.06 if rank == 10 else 0.085)
	if rank == 10:
		# keep "10" tight so it stays inside the corner
		ci.draw_string(font, Vector2(x, r.position.y + top + cap), "1", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		var one := font.get_string_size("1", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(font, Vector2(x + one * 0.82, r.position.y + top + cap), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	else:
		ci.draw_string(font, Vector2(x, r.position.y + top + cap), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_pip(ci, suit, r.position + Vector2(w * 0.82, top + cap * 0.5), w * 0.088, col)


## Large centre pip inside a fine gold rosette; the ace of spades gets the full ornament.
static func _ace(ci: CanvasItem, r: Rect2, suit: int, col: Color) -> void:
	var w := r.size.x
	var c := r.get_center() + Vector2(0, r.size.y * 0.01)
	var ring := w * 0.36
	ci.draw_arc(c, ring, 0.0, TAU, 72, Color(GOLD, 0.85), maxf(1.0, w * 0.012), true)
	ci.draw_arc(c, ring * 0.92, 0.0, TAU, 72, Color(GOLD, 0.45), maxf(1.0, w * 0.007), true)
	for i in 4:
		var a := PI / 4.0 + i * PI / 2.0
		var p := c + Vector2(cos(a), sin(a)) * ring
		var d := w * 0.025
		fill(ci, PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), GOLD)
	if suit == 0:
		# scalloped rosette behind the big spade
		var pts := PackedVector2Array()
		for i in 96:
			var a := TAU * i / 96.0
			pts.append(c + Vector2(cos(a), sin(a)) * ring * (0.8 + 0.05 * cos(a * 12.0)))
		fill(ci, pts, Color(GOLD_LIGHT, 0.35))
		pts.append(pts[0])
		ci.draw_polyline(pts, Color(GOLD, 0.8), maxf(1.0, w * 0.008), true)
		draw_pip(ci, suit, c, w * 0.25, col)
	else:
		draw_pip(ci, suit, c, w * 0.23, col)


## Court cards: a framed, two-headed portrait (the top half mirrored below, like a real deck),
## with crown, hair, ermine collar, robe pattern and an attribute (sword, rose, staff).
static func _court(ci: CanvasItem, r: Rect2, suit: int, rank: int, col: Color, xform: Transform2D) -> void:
	var w := r.size.x
	var h := r.size.y
	var panel := Rect2(r.position + Vector2(w * 0.15, h * 0.2), Vector2(w * 0.7, h * 0.6))
	var pr := w * 0.04
	var robe: Color
	var trim: Color
	match rank:
		13:
			robe = col
			trim = GOLD
		12:
			robe = Color("#e0701a")
			trim = col
		_:
			robe = Color("#2f6fb3") if suit == 1 or suit == 2 else Color("#c3102f")
			trim = GOLD
	FX.draw_round_gradient(ci, panel, pr, Color("#fff8e6"), Color("#f3e3bd"))
	# faint diagonal lattice behind the figure
	var step := panel.size.x / 7.0
	var lat := Color(col, 0.06)
	var k := -panel.size.y
	while k < panel.size.x:
		var a := Vector2(panel.position.x + k, panel.position.y)
		var b := a + Vector2(panel.size.y, panel.size.y)
		var t1 := maxf(0.0, panel.position.x - a.x)
		a += Vector2(t1, t1)
		var t2 := maxf(0.0, b.x - panel.end.x)
		b -= Vector2(t2, t2)
		if a.x < b.x:
			ci.draw_line(a, b, lat, maxf(1.0, w * 0.008), true)
		k += step
	var half := Rect2(panel.position, Vector2(panel.size.x, panel.size.y / 2.0))
	_court_half(ci, half, suit, rank, col, robe, trim)
	ci.draw_set_transform_matrix(xform * Transform2D(PI, panel.position * 2.0 + panel.size))
	_court_half(ci, half, suit, rank, col, robe, trim)
	ci.draw_set_transform_matrix(xform)
	# divider across the middle and the double frame
	var mid := panel.get_center()
	ci.draw_line(Vector2(panel.position.x + 2.0, mid.y), Vector2(panel.end.x - 2.0, mid.y), Color(GOLD_DARK, 0.9), maxf(1.0, w * 0.012), true)
	ci.draw_line(Vector2(panel.position.x + 2.0, mid.y + w * 0.012), Vector2(panel.end.x - 2.0, mid.y + w * 0.012), Color(GOLD_LIGHT, 0.8), maxf(1.0, w * 0.006), true)
	_outline(ci, panel, pr, Color(col, 0.85), maxf(1.0, w * 0.014))
	_outline(ci, panel.grow(-w * 0.025), pr * 0.6, Color(GOLD, 0.95), maxf(1.0, w * 0.009))


static func _court_half(ci: CanvasItem, hr: Rect2, suit: int, rank: int, col: Color, robe: Color, trim: Color) -> void:
	var W := hr.size.x
	var H := hr.size.y
	var o := hr.position
	var cx := o.x + W * 0.5
	var lw := maxf(1.0, W * 0.014)
	var head := Vector2(cx, o.y + H * 0.43)
	var hx := W * 0.15
	var hy := H * 0.21
	# attribute behind the shoulder
	match rank:
		13:  # sword
			var sx := o.x + W * 0.17
			fill(ci, PackedVector2Array([Vector2(sx - W * 0.025, o.y + H), Vector2(sx - W * 0.025, o.y + H * 0.2),
				Vector2(sx, o.y + H * 0.1), Vector2(sx + W * 0.025, o.y + H * 0.2), Vector2(sx + W * 0.025, o.y + H)]), Color("#d9dde8"))
			ci.draw_line(Vector2(sx, o.y + H * 0.2), Vector2(sx, o.y + H), Color("#9aa0b5"), lw, true)
			fill(ci, PackedVector2Array([Vector2(sx - W * 0.08, o.y + H * 0.66), Vector2(sx + W * 0.08, o.y + H * 0.66),
				Vector2(sx + W * 0.08, o.y + H * 0.71), Vector2(sx - W * 0.08, o.y + H * 0.71)]), GOLD)
		12:  # rose on a stem
			var rc := Vector2(o.x + W * 0.8, o.y + H * 0.5)
			ci.draw_line(rc, rc + Vector2(-W * 0.06, H * 0.5), Color("#2f7d4a"), lw * 1.4, true)
			fill(ci, PackedVector2Array([rc + Vector2(-W * 0.03, H * 0.25), rc + Vector2(W * 0.06, H * 0.18),
				rc + Vector2(-W * 0.01, H * 0.32)]), Color("#2f7d4a"))
			fill(ci, circle_pts(rc, W * 0.075), INK_RED)
			fill(ci, circle_pts(rc + Vector2(-W * 0.01, -W * 0.01), W * 0.045), INK_RED.lightened(0.25))
			ci.draw_arc(rc, W * 0.04, 0.5, 4.5, 12, INK_RED.darkened(0.3), lw, true)
		_:  # staff with a leaf blade
			var sx := o.x + W * 0.83
			ci.draw_line(Vector2(sx, o.y + H), Vector2(sx, o.y + H * 0.22), GOLD_DARK, lw * 2.0, true)
			var tip := Vector2(sx, o.y + H * 0.06)
			fill_shaded(ci, PackedVector2Array([tip, tip + Vector2(W * 0.06, H * 0.12), tip + Vector2(0, H * 0.2),
				tip + Vector2(-W * 0.06, H * 0.12)]), Color("#c9ced9"), tip.y, tip.y + H * 0.2, 0.3)
	# shoulders and robe
	var sh := o.y + H * 0.66
	var robe_pts := PackedVector2Array()
	robe_pts.append(Vector2(o.x + W * 0.06, o.y + H))
	_quad(Vector2(o.x + W * 0.06, o.y + H), Vector2(o.x + W * 0.08, sh), Vector2(cx - W * 0.16, sh - H * 0.02), 8, robe_pts, true)
	robe_pts.append(Vector2(cx + W * 0.16, sh - H * 0.02))
	_quad(Vector2(cx + W * 0.16, sh - H * 0.02), Vector2(o.x + W * 0.92, sh), Vector2(o.x + W * 0.94, o.y + H), 8, robe_pts, true)
	fill_shaded(ci, robe_pts, robe, sh - H * 0.05, o.y + H, 0.25)
	# robe pattern: a gold band down the middle with small suit pips
	var band := PackedVector2Array([Vector2(cx - W * 0.07, sh + H * 0.02), Vector2(cx + W * 0.07, sh + H * 0.02),
		Vector2(cx + W * 0.09, o.y + H), Vector2(cx - W * 0.09, o.y + H)])
	fill(ci, band, trim)
	var pip_col := Color("#fff6dc") if trim == col else col
	draw_pip(ci, suit, Vector2(cx, o.y + H * 0.9), W * 0.045, pip_col)
	for s in [-1.0, 1.0]:
		for j in 3:
			var p := Vector2(cx + s * W * (0.22 + j * 0.07), o.y + H * (0.86 - j * 0.04))
			fill(ci, circle_pts(p, W * 0.018, 10), Color(GOLD_LIGHT, 0.9))
	robe_pts.append(robe_pts[0])
	ci.draw_polyline(robe_pts, robe.darkened(0.45), lw, true)
	# ermine collar (kings and queens), striped collar for jacks
	var collar := PackedVector2Array([Vector2(cx - W * 0.2, sh - H * 0.01), Vector2(cx + W * 0.2, sh - H * 0.01),
		Vector2(cx + W * 0.07, sh + H * 0.13), Vector2(cx - W * 0.07, sh + H * 0.13)])
	if rank == 11:
		fill(ci, collar, GOLD_LIGHT)
		for j in 4:
			var x := cx - W * 0.15 + j * W * 0.1
			ci.draw_line(Vector2(x, sh), Vector2(lerpf(x, cx, 0.6), sh + H * 0.12), Color(col, 0.7), lw, true)
	else:
		fill(ci, collar, ERMINE)
		for j in 5:
			var p := Vector2(cx - W * 0.12 + j * W * 0.06, sh + H * (0.03 + 0.04 * (j % 2)))
			fill(ci, PackedVector2Array([p + Vector2(0, -W * 0.012), p + Vector2(W * 0.01, W * 0.012), p + Vector2(-W * 0.01, W * 0.012)]), INK_BLACK)
	collar.append(collar[0])
	ci.draw_polyline(collar, Color(EDGE, 0.6), lw * 0.8, true)
	# hair behind the face
	var hair := Color("#4a2a17") if rank != 12 else Color("#c98a1a")
	if rank == 12:
		fill(ci, PackedVector2Array([head + Vector2(-hx * 1.25, -hy * 0.4), head + Vector2(hx * 1.25, -hy * 0.4),
			head + Vector2(hx * 1.55, hy * 1.6), head + Vector2(-hx * 1.55, hy * 1.6)]), hair)
	else:
		fill(ci, circle_pts(head + Vector2(0, -hy * 0.1), hx * 1.18), hair)
	# face
	var face := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		face.append(head + Vector2(cos(a) * hx, sin(a) * hy))
	fill_shaded(ci, face, SKIN.darkened(0.06), head.y - hy, head.y + hy, 0.08)
	face.append(face[0])
	ci.draw_polyline(face, SKIN.darkened(0.4), lw * 0.8, true)
	var eye_y := head.y - hy * 0.05
	for s in [-1.0, 1.0]:
		ci.draw_line(Vector2(cx + s * hx * 0.55, eye_y), Vector2(cx + s * hx * 0.2, eye_y), INK_BLACK, lw, true)
	ci.draw_line(Vector2(cx, eye_y + hy * 0.08), Vector2(cx - hx * 0.08, eye_y + hy * 0.4), SKIN.darkened(0.35), lw * 0.8, true)
	ci.draw_line(Vector2(cx - hx * 0.25, head.y + hy * 0.6), Vector2(cx + hx * 0.25, head.y + hy * 0.6), Color("#b0373b"), lw, true)
	if rank == 13:  # beard
		fill(ci, PackedVector2Array([head + Vector2(-hx * 0.95, hy * 0.3), head + Vector2(-hx * 0.4, hy * 0.75),
			head + Vector2(hx * 0.4, hy * 0.75), head + Vector2(hx * 0.95, hy * 0.3), head + Vector2(hx * 0.55, hy * 1.35),
			head + Vector2(0, hy * 1.6), head + Vector2(-hx * 0.55, hy * 1.35)]), hair)
		ci.draw_line(Vector2(cx - hx * 0.4, head.y + hy * 0.62), Vector2(cx + hx * 0.4, head.y + hy * 0.62), hair.darkened(0.3), lw, true)
	# headwear
	var cy := head.y - hy * 0.72
	var cw := hx * 1.35
	match rank:
		13:
			var crown := PackedVector2Array([Vector2(-cw, 0), Vector2(-cw * 1.05, -H * 0.2), Vector2(-cw * 0.5, -H * 0.09),
				Vector2(0, -H * 0.26), Vector2(cw * 0.5, -H * 0.09), Vector2(cw * 1.05, -H * 0.2), Vector2(cw, 0)])
			for i in crown.size():
				crown[i] += Vector2(cx, cy)
			fill_shaded(ci, crown, GOLD, cy - H * 0.26, cy, 0.35)
			crown.append(crown[0])
			ci.draw_polyline(crown, GOLD_DARK, lw, true)
			fill(ci, PackedVector2Array([Vector2(cx - cw, cy - H * 0.035), Vector2(cx + cw, cy - H * 0.035),
				Vector2(cx + cw, cy + H * 0.01), Vector2(cx - cw, cy + H * 0.01)]), GOLD_DARK)
			for s in [-0.6, 0.0, 0.6]:
				fill(ci, circle_pts(Vector2(cx + cw * s, cy - H * 0.012), W * 0.02, 10), INK_RED if s == 0.0 else Color("#2f6fb3"))
			fill(ci, circle_pts(Vector2(cx, cy - H * 0.27), W * 0.022, 10), GOLD_LIGHT)
		12:
			var tiara := PackedVector2Array()
			for i in 17:
				var t := float(i) / 16.0
				tiara.append(Vector2(cx - cw + t * cw * 2.0, cy - H * 0.06 - sin(t * PI) * H * 0.1 - (H * 0.04 if i % 4 == 2 else 0.0)))
			tiara.append(Vector2(cx + cw, cy))
			tiara.append(Vector2(cx - cw, cy))
			fill_shaded(ci, tiara, GOLD, cy - H * 0.2, cy, 0.35)
			tiara.append(tiara[0])
			ci.draw_polyline(tiara, GOLD_DARK, lw, true)
			for s in [-0.5, 0.0, 0.5]:
				fill(ci, circle_pts(Vector2(cx + cw * s, cy - H * (0.21 if s == 0.0 else 0.15)), W * 0.022, 10), Color("#ffffff"))
			fill(ci, circle_pts(Vector2(cx, cy - H * 0.05), W * 0.024, 10), INK_RED)
		_:
			var cap := PackedVector2Array([Vector2(cx - cw * 1.05, cy + H * 0.02), Vector2(cx - cw * 0.9, cy - H * 0.1),
				Vector2(cx, cy - H * 0.16), Vector2(cx + cw * 0.9, cy - H * 0.1), Vector2(cx + cw * 1.05, cy + H * 0.02)])
			fill_shaded(ci, cap, robe, cy - H * 0.16, cy, 0.3)
			cap.append(cap[0])
			ci.draw_polyline(cap, robe.darkened(0.45), lw, true)
			ci.draw_line(Vector2(cx - cw * 1.02, cy), Vector2(cx + cw * 1.02, cy), GOLD, lw * 1.6, true)
			# feather
			var f0 := Vector2(cx + cw * 0.6, cy - H * 0.08)
			var feather := PackedVector2Array()
			_quad(f0, f0 + Vector2(W * 0.03, -H * 0.2), f0 + Vector2(W * 0.14, -H * 0.17), 8, feather)
			_quad(f0 + Vector2(W * 0.14, -H * 0.17), f0 + Vector2(W * 0.06, -H * 0.08), f0 + Vector2(W * 0.02, H * 0.01), 8, feather, true)
			fill(ci, feather, Color("#f2a900"))
	# suit pip in the corner of the half
	draw_pip(ci, suit, o + Vector2(W * 0.13, H * 0.17), W * 0.065, col)


## Card back: ivory border, deep indigo field with fine guilloche, gold rosette medallion.
static func draw_back(ci: CanvasItem, r: Rect2, lift := 0.0, shadow := true) -> void:
	if shadow:
		draw_shadow(ci, r, lift)
	var w := r.size.x
	var rad := corner_radius(w)
	_paper(ci, r, 999)
	var inner := r.grow(-w * 0.07)
	var ir := rad * 0.55
	FX.draw_round_gradient(ci, inner, ir, BACK_TOP, BACK_BOTTOM)
	var lw := maxf(1.0, w * 0.008)
	var mid := r.get_center()
	# guilloche: two families of fine sine waves across the field (clipped to the inner rect)
	var rows := 9 if detail else 5
	var seg := 28
	for fam in 2:
		for j in rows:
			var y0 := inner.position.y + inner.size.y * (j + 0.5) / rows
			var pts := PackedVector2Array()
			for s in seg + 1:
				var x := inner.position.x + 3.0 + (inner.size.x - 6.0) * s / seg
				var ph := s * TAU / seg * 2.0 + (PI if fam == 1 else 0.0)
				pts.append(Vector2(x, clampf(y0 + sin(ph) * inner.size.y / rows * 0.6, inner.position.y + 3.0, inner.end.y - 3.0)))
			ci.draw_polyline(pts, Color(0.62, 0.66, 1.0, 0.18 if fam == 0 else 0.12), lw, true)
	# frames
	_outline(ci, inner, ir, Color(GOLD_LIGHT, 0.95), maxf(1.0, w * 0.014))
	_outline(ci, inner.grow(-w * 0.03), ir * 0.6, Color(FX.TANGERINE, 0.8), lw)
	# corner fleurons
	for k in 4:
		var cp := Vector2(inner.position.x if k % 2 == 0 else inner.end.x, inner.position.y if k < 2 else inner.end.y)
		var dir := Vector2(1 if k % 2 == 0 else -1, 1 if k < 2 else -1)
		var p := cp + dir * w * 0.09
		var d := w * 0.03
		fill(ci, PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), GOLD_LIGHT)
	# rosette medallion
	var R := w * 0.3
	FX.draw_glow(ci, Rect2(mid - Vector2(R, R) * 1.5, Vector2(R, R) * 3.0), Color(FX.TANGERINE, 0.3))
	fill(ci, circle_pts(mid, R * 0.98, 56), BACK_BOTTOM.darkened(0.25))
	for layer in 2:
		var pts := PackedVector2Array()
		var n := 160
		for i in n + 1:
			var a := TAU * i / n
			var rr := R * (0.62 + 0.3 * absf(cos(a * 6.0 + layer * PI / 6.0)))
			pts.append(mid + Vector2(cos(a), sin(a)) * rr)
		ci.draw_polyline(pts, Color(GOLD_LIGHT, 0.85 if layer == 0 else 0.5), lw, true)
	ci.draw_arc(mid, R, 0.0, TAU, 64, GOLD_LIGHT, maxf(1.0, w * 0.014), true)
	ci.draw_arc(mid, R * 0.4, 0.0, TAU, 40, Color(FX.TANGERINE, 0.9), lw, true)
	var star := FX.star_points(mid, R * 0.34, 0.45)
	fill_shaded(ci, star, FX.TANGERINE, mid.y - R * 0.34, mid.y + R * 0.34, 0.4)
	# sheen
	var g := inner.grow(-2.0)
	fill(ci, PackedVector2Array([g.position + Vector2(ir, 0), g.position + Vector2(g.size.x * 0.7, 0),
		g.position + Vector2(0, g.size.y * 0.45), g.position + Vector2(0, ir)]), Color(1, 1, 1, 0.05))


## Suit pip centred at c, radius r (the pip fits a circle of about that size). `flip` turns it
## upside down (the lower pips on a number card, like a real deck).
static func draw_pip(ci: CanvasItem, suit: int, c: Vector2, r: float, col: Color, flip := false) -> void:
	var parts := pip_polys(suit, c, r)
	var light := 0.28 if col.a > 0.9 else 0.0
	for pts in parts:
		if flip:
			for i in pts.size():
				pts[i] = c * 2.0 - pts[i]
		if light > 0.0:
			var y0 := c.y - r if not flip else c.y + r
			var y1 := c.y + r if not flip else c.y - r
			var top := col.lightened(light)
			var cols := PackedColorArray()
			for p in pts:
				cols.append(top.lerp(col, clampf((p.y - y0) / (y1 - y0), 0.0, 1.0)))
			fill(ci, pts, col, cols)
		else:
			fill(ci, pts, col)


## Suit outline polygons (several pieces for spade and club), each a PackedVector2Array.
static func pip_polys(suit: int, c: Vector2, r: float) -> Array:
	match suit:
		0:
			return [_heart(c + Vector2(0, -r * 0.12), r * 0.98, true), _stem(c, r)]
		1:
			return [_heart(c + Vector2(0, r * 0.02), r * 1.02, false)]
		2:
			var pts := PackedVector2Array()
			var t := c + Vector2(0, -r * 1.08)
			var rt := c + Vector2(r * 0.86, 0)
			var b := c + Vector2(0, r * 1.08)
			var lf := c + Vector2(-r * 0.86, 0)
			_quad(t, c + Vector2(r * 0.22, -r * 0.42), rt, 8, pts)
			_quad(rt, c + Vector2(r * 0.22, r * 0.42), b, 8, pts, true)
			_quad(b, c + Vector2(-r * 0.22, r * 0.42), lf, 8, pts, true)
			_quad(lf, c + Vector2(-r * 0.22, -r * 0.42), t, 8, pts, true)
			pts.remove_at(pts.size() - 1)
			return [pts]
		_:
			var lr := r * 0.45
			return [circle_pts(c + Vector2(0, -r * 0.48), lr), circle_pts(c + Vector2(-r * 0.5, r * 0.16), lr),
				circle_pts(c + Vector2(r * 0.5, r * 0.16), lr), circle_pts(c + Vector2(0, r * 0.02), lr * 0.7), _stem(c, r)]


## Flared stem for spade and club.
static func _stem(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	_quad(c + Vector2(-r * 0.08, r * 0.1), c + Vector2(-r * 0.1, r * 0.8), c + Vector2(-r * 0.46, r * 1.02), 6, pts)
	pts.append(c + Vector2(r * 0.46, r * 1.02))
	_quad(c + Vector2(r * 0.46, r * 1.02), c + Vector2(r * 0.1, r * 0.8), c + Vector2(r * 0.08, r * 0.1), 6, pts, true)
	return pts


static func _heart(c: Vector2, r: float, flip: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 40
	for i in n:
		var t := TAU * i / n
		var x := 16.0 * pow(sin(t), 3.0)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		var p := Vector2(x, y) / 16.5 * r
		if flip:
			p.y = -p.y
		pts.append(c + p + Vector2(0, -r * 0.05 if not flip else r * 0.05))
	return pts
