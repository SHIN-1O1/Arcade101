extends RefCounted
## Original tile faces for Mahjong Match, all drawn from shapes and the Lilita One font.
## Match keys: 0-5 dots 1-6, 6-11 sticks 1-6, 12-17 numerals 1-6, 18-21 winds (N E S W),
## 22-24 gems (red, green, blue), 25 flowers (4 looks), 26 seasons (4 looks).

const BLUE := Color("#2b7bd6")
const RED := Color("#e5484d")
const GREEN := Color("#2f9e5b")
const DEEP := Color("#23408e")
const INK := Color("#2a2540")
const ORANGE := Color("#ff8a1f")
const LEMON := Color("#ffd23f")
const FLOWER_COLORS: Array[Color] = [Color("#ff5d8f"), Color("#ff8a1f"), Color("#9b5de5"), Color("#00b4d8")]
const IVORY := Color("#fff6df")

## Pip layouts (normalised -0.5..0.5 inside the face) for 1..6 dots or sticks.
const PIPS: Array = [
	[[0.0, 0.0]],
	[[0.0, -0.22], [0.0, 0.22]],
	[[-0.2, -0.26], [0.0, 0.0], [0.2, 0.26]],
	[[-0.19, -0.2], [0.19, -0.2], [-0.19, 0.2], [0.19, 0.2]],
	[[-0.19, -0.23], [0.19, -0.23], [0.0, 0.0], [-0.19, 0.23], [0.19, 0.23]],
	[[-0.19, -0.26], [0.19, -0.26], [-0.19, 0.0], [0.19, 0.0], [-0.19, 0.26], [0.19, 0.26]],
]


static func draw_face(ci: CanvasItem, r: Rect2, key: int, variant: int, font: Font) -> void:
	var c := r.get_center()
	var w := r.size.x
	var h := r.size.y
	if key < 6:
		_dots(ci, c, w, h, key + 1)
	elif key < 12:
		_sticks(ci, c, w, h, key - 5)
	elif key < 18:
		_numeral(ci, c, w, h, key - 11, font)
	elif key < 22:
		_wind(ci, c, w, h, key - 18, font)
	elif key < 25:
		_gem(ci, c, w, h, key - 22)
	elif key == 25:
		_flower(ci, c, w, variant)
	else:
		_season(ci, c, w, variant)


## Main colour of a face, for particle bursts.
static func key_color(key: int, variant: int) -> Color:
	if key < 6:
		return [BLUE, RED, GREEN][key % 3]
	if key < 12:
		return GREEN
	if key < 18:
		return RED
	if key < 22:
		return DEEP.lightened(0.3)
	if key < 25:
		return [RED, GREEN, BLUE][key - 22]
	if key == 25:
		return FLOWER_COLORS[variant % 4]
	return [ORANGE, GREEN, Color("#4fc3f7"), BLUE][variant % 4]


static func _dots(ci: CanvasItem, c: Vector2, w: float, h: float, n: int) -> void:
	var cols := [BLUE, RED, GREEN]
	var rad := w * (0.3 if n == 1 else 0.17 if n <= 3 else 0.15)
	if n == 6 or n == 4:
		rad = w * 0.15
	for i in n:
		var p: Array = PIPS[n - 1][i]
		var pc := c + Vector2(p[0] * w * 1.05, p[1] * h * 1.0)
		var col: Color = cols[(i + (n if n > 3 else 0)) % 3] if n != 1 else RED
		ci.draw_circle(pc + Vector2(0, rad * 0.12), rad, Color(0, 0, 0, 0.18))
		ci.draw_circle(pc, rad * 1.06, col.darkened(0.45))
		ci.draw_circle(pc, rad, col)
		ci.draw_circle(pc, rad * 0.62, IVORY)
		ci.draw_circle(pc, rad * 0.34, col)
		ci.draw_circle(pc + Vector2(-rad * 0.3, -rad * 0.34), rad * 0.18, Color(1, 1, 1, 0.55))


static func _sticks(ci: CanvasItem, c: Vector2, w: float, h: float, n: int) -> void:
	var bw := w * (0.2 if n > 1 else 0.24)
	var bh := h * (0.34 if n > 3 else 0.4 if n > 1 else 0.62)
	for i in n:
		var p: Array = PIPS[n - 1][i]
		var pc := c + Vector2(p[0] * w * 1.05, p[1] * h)
		var col := GREEN if (n == 1 or i % 2 == 0) else RED.lerp(GREEN, 0.15)
		if n == 1:
			col = ORANGE
		var bar := Rect2(pc - Vector2(bw, bh) / 2.0, Vector2(bw, bh))
		ci.draw_rect(bar, col.darkened(0.25))
		ci.draw_rect(Rect2(bar.position + Vector2(bw * 0.15, 0), Vector2(bw * 0.55, bh)), col)
		ci.draw_rect(Rect2(bar.position + Vector2(bw * 0.2, 0), Vector2(bw * 0.14, bh)), col.lightened(0.45))
		for k in 2:  # bamboo-like joints
			ci.draw_rect(Rect2(bar.position + Vector2(-bw * 0.08, bh * (0.3 + 0.4 * k) - 1.5), Vector2(bw * 1.16, 3.0)),
				col.darkened(0.45))


static func _numeral(ci: CanvasItem, c: Vector2, w: float, h: float, n: int, font: Font) -> void:
	var fs := int(h * 0.58)
	var tp := c + Vector2(-font.get_string_size(str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x / 2.0, -h * 0.04 + fs * 0.34)
	ci.draw_string(font, tp + Vector2(2, 3), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.2))
	ci.draw_string_outline(font, tp, str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, RED.darkened(0.5))
	ci.draw_string(font, tp, str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, RED.lightened(0.05))
	var by := c.y + h * 0.33  # a little brush mark under the numeral
	ci.draw_rect(Rect2(c.x - w * 0.3, by, w * 0.6, h * 0.045), INK)
	ci.draw_circle(Vector2(c.x, by + h * 0.12), h * 0.05, BLUE)


static func _wind(ci: CanvasItem, c: Vector2, w: float, h: float, n: int, font: Font) -> void:
	var rad := w * 0.38
	ci.draw_circle(c, rad, DEEP)
	ci.draw_circle(c, rad * 0.86, Color("#dbe6ff"))
	var fs := int(rad * 1.35)
	var t := "NESW"[n]
	var tp := c + Vector2(-font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x / 2.0, fs * 0.34)
	ci.draw_string(font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DEEP)
	for k in 4:  # compass nubs
		var a := k * PI / 2.0 + PI / 4.0
		ci.draw_circle(c + Vector2(cos(a), sin(a)) * rad * 1.02, rad * 0.1, ORANGE)


static func _gem(ci: CanvasItem, c: Vector2, w: float, h: float, n: int) -> void:
	var col: Color = [RED, GREEN, BLUE][n]
	var s := w * 0.36
	if n == 0:  # red: faceted diamond
		var pts := PackedVector2Array([c + Vector2(0, -s * 1.3), c + Vector2(s, 0), c + Vector2(0, s * 1.3), c + Vector2(-s, 0)])
		ci.draw_colored_polygon(pts, col.darkened(0.15))
		ci.draw_colored_polygon(PackedVector2Array([pts[0], pts[1], c, pts[3]]), col.lightened(0.25))
		ci.draw_polyline(pts + PackedVector2Array([pts[0]]), col.darkened(0.5), 2.5, true)
	elif n == 1:  # green: four-leaf clover
		for k in 4:
			var a := k * PI / 2.0 + PI / 4.0
			var lc := c + Vector2(cos(a), sin(a)) * s * 0.55
			ci.draw_circle(lc, s * 0.58, col.darkened(0.12))
			ci.draw_circle(lc + Vector2(-s * 0.1, -s * 0.12), s * 0.3, col.lightened(0.3))
		ci.draw_circle(c, s * 0.2, col.darkened(0.4))
	else:  # blue: hollow square frame
		var outer := Rect2(c - Vector2(s, s) * 0.95, Vector2(s, s) * 1.9)
		ci.draw_rect(outer, col, false, s * 0.34)
		ci.draw_rect(outer.grow(-s * 0.55), col.lightened(0.4), false, s * 0.16)


static func _flower(ci: CanvasItem, c: Vector2, w: float, v: int) -> void:
	var col := FLOWER_COLORS[v % 4]
	var pr := w * 0.15
	var petals := 5 + (v % 2)
	for k in petals:
		var a := TAU * k / petals - PI / 2.0
		var pc := c + Vector2(cos(a), sin(a)) * w * 0.2
		ci.draw_circle(pc, pr, col.darkened(0.12))
		ci.draw_circle(pc + Vector2(-pr * 0.2, -pr * 0.25), pr * 0.55, col.lightened(0.35))
	ci.draw_circle(c, w * 0.11, LEMON)
	ci.draw_circle(c + Vector2(-w * 0.03, -w * 0.03), w * 0.045, Color.WHITE)


static func _season(ci: CanvasItem, c: Vector2, w: float, v: int) -> void:
	match v % 4:
		0:  # sun
			for k in 8:
				var a := TAU * k / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * w * 0.24, c + Vector2(cos(a), sin(a)) * w * 0.38,
					ORANGE, 4.0, true)
			ci.draw_circle(c, w * 0.2, LEMON)
			ci.draw_arc(c, w * 0.2, 0, TAU, 24, ORANGE, 3.0, true)
		1:  # leaf
			var pts := PackedVector2Array()
			for k in range(1, 16):  # right edge, tip to stem (end points added once)
				var t := k / 16.0
				pts.append(c + Vector2(sin(t * PI) * w * 0.26, (t - 0.5) * w * 0.8))
			pts.append(c + Vector2(0, w * 0.4))
			for k in range(15, 0, -1):
				var t := k / 16.0
				pts.append(c + Vector2(-sin(t * PI) * w * 0.26, (t - 0.5) * w * 0.8))
			pts.append(c + Vector2(0, -w * 0.4))
			ci.draw_colored_polygon(pts, GREEN)
			ci.draw_line(c + Vector2(0, -w * 0.4), c + Vector2(0, w * 0.42), GREEN.darkened(0.5), 3.0, true)
		2:  # snowflake
			for k in 3:
				var a := PI * k / 3.0
				var d := Vector2(cos(a), sin(a)) * w * 0.36
				ci.draw_line(c - d, c + d, Color("#4fc3f7"), 4.0, true)
				for s in [-1.0, 1.0]:
					var tip: Vector2 = c + d * s * 0.62
					var perp := Vector2(-d.y, d.x).normalized() * w * 0.09
					ci.draw_line(tip, tip + d.normalized() * s * -w * 0.08 + perp, Color("#4fc3f7"), 3.0, true)
					ci.draw_line(tip, tip + d.normalized() * s * -w * 0.08 - perp, Color("#4fc3f7"), 3.0, true)
		_:  # rain drop
			var cc := c + Vector2(0, w * 0.12)
			var pts := PackedVector2Array([c + Vector2(0, -w * 0.4)])
			for k in 21:
				var a := lerpf(-0.153 * PI, 1.153 * PI, k / 20.0)
				pts.append(cc + Vector2(cos(a), sin(a)) * w * 0.24)
			ci.draw_colored_polygon(pts, BLUE)
			ci.draw_circle(c + Vector2(-w * 0.08, w * 0.06), w * 0.05, Color(1, 1, 1, 0.8))
