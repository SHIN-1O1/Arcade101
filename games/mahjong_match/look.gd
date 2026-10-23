extends RefCounted
## Visual pieces for Mahjong Match: the table backdrop, drifting motes, per-tile nodes, the action
## buttons and the HUD chips. Everything is drawn in code with the shared FX kit.
## Tiles are their own nodes so Godot caches each tile's drawing; only tiles that change redraw,
## and sliding, popping and flipping are plain transforms.

const FX := preload("res://core/fx.gd")
const INDIGO := Color("#2B2A6B")
const TANGERINE := Color("#FF8A1F")
const LEMON := Color("#FFD23F")
const Icons := preload("res://games/mahjong_match/icons.gd")


## Static table: gradient, lattice, rings, vignette and the felt mat the tiles sit on.
class Backdrop extends Control:
	var mat := Rect2()
	var _sb := StyleBoxFlat.new()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_sb.draw_center = false

	func set_mat(r: Rect2) -> void:
		if r != mat:
			mat = r
			queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		FX.draw_vgradient(self, Rect2(0, 0, w, h * 0.5), Color("#1a1f52"), Color("#0f4150"))
		FX.draw_vgradient(self, Rect2(0, h * 0.5, w, h * 0.5), Color("#0f4150"), Color("#0a1630"))
		FX.draw_glow(self, Rect2(-w * 0.25, h * 0.18, w * 1.5, h * 0.64), Color(0.2, 0.85, 0.65, 0.2))
		FX.draw_glow(self, Rect2(w * 0.1, -h * 0.1, w * 0.8, h * 0.4), Color(1.0, 0.55, 0.15, 0.1))
		# Seigaiha wave pattern, faint gold on the lacquer (one tiled texture).
		draw_texture_rect(_waves(), Rect2(0, 0, w, h), true, Color(1.0, 0.82, 0.3, 0.09))
		# Big ornamental rings behind the board.
		var c := mat.get_center() if mat.size.x > 0.0 else size / 2.0
		for i in 3:
			draw_arc(c, 330.0 + i * 70.0, 0.0, TAU, 96, Color(1.0, 0.82, 0.3, 0.07 - i * 0.015), 3.0, true)
		for i in 24:
			var a := TAU * i / 24.0
			draw_circle(c + Vector2(cos(a), sin(a)) * 330.0, 4.0, Color(1.0, 0.82, 0.3, 0.12))
		# Edges melt into the host screen colours so the table has no hard border.
		var bt := Color(FX.BG_TOP, 1.0)
		var bb := Color(FX.BG_BOTTOM, 1.0)
		var bt0 := Color(FX.BG_TOP, 0.0)
		var bb0 := Color(FX.BG_BOTTOM, 0.0)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.1), Vector2(0, h * 0.1)]),
			PackedColorArray([bt, bt, bt0, bt0]))
		draw_polygon(PackedVector2Array([Vector2(0, h * 0.88), Vector2(w, h * 0.88), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([bb0, bb0, bb, bb]))
		var side := Color(FX.BG_TOP.lerp(FX.BG_BOTTOM, 0.5), 0.95)
		var side0 := Color(side, 0.0)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.05, 0), Vector2(w * 0.05, h), Vector2(0, h)]),
			PackedColorArray([side, side0, side0, side]))
		draw_polygon(PackedVector2Array([Vector2(w * 0.95, 0), Vector2(w, 0), Vector2(w, h), Vector2(w * 0.95, h)]),
			PackedColorArray([side0, side, side, side0]))
		if mat.size.x > 0.0:
			_draw_mat()

	func _draw_mat() -> void:
		FX.draw_shadow(self, Rect2(mat.position + Vector2(-26, 18), mat.size + Vector2(52, 44)), 0.9)
		# lacquered frame, then a brocade band, then the jade felt
		FX.draw_round_gradient(self, mat, 44.0, Color("#6b2a1e"), Color("#2a0e0b"))
		var band := mat.grow(-9.0)
		var felt := mat.grow(-22.0)
		FX.draw_round_gradient(self, band, 36.0, Color("#0e4d40"), Color("#06281f"))
		FX.draw_round_gradient(self, felt, 26.0, Color("#1b8f71"), Color("#0a4436"))
		var pts := FX.round_rect_points(felt, 26.0)
		var uvs := PackedVector2Array()
		for q in pts:
			uvs.append(q / 128.0)
		draw_polygon(pts, PackedColorArray([Color(1, 1, 1, 0.8)]), uvs, _grain())
		# gold diamonds along the brocade band
		var per := band.size.x + band.size.y
		var n := int(per * 2.0 / 34.0)
		for i in n:
			var t := float(i) / n
			var p := _on_rect(mat.grow(-15.5), t)
			var d := 3.6
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]),
				Color(LEMON, 0.55))
		# faint medallion in the middle of the felt
		var mc := felt.get_center()
		var mr := minf(felt.size.x, felt.size.y) * 0.36
		for i in 3:
			draw_arc(mc, mr * (1.0 - i * 0.18), 0.0, TAU, 64, Color(1.0, 0.85, 0.35, 0.09 - i * 0.02), 3.0, true)
		for i in 12:
			var a := TAU * i / 12.0
			draw_circle(mc + Vector2(cos(a), sin(a)) * mr, 5.0, Color(1.0, 0.85, 0.35, 0.12))
			draw_line(mc + Vector2(cos(a), sin(a)) * mr * 0.64, mc + Vector2(cos(a), sin(a)) * mr * 0.82, Color(1.0, 0.85, 0.35, 0.07), 3.0, true)
		# inner shade below the frame
		FX.draw_vgradient(self, Rect2(felt.position + Vector2(20, 0), Vector2(felt.size.x - 40, 30)), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0))
		_line(mat, 44.0, Color("#f2c14e"), 3.0)
		_line(mat.grow(-1.5), 43.0, Color(1, 1, 1, 0.25), 1.0)
		_line(band, 36.0, Color("#c8961e"), 2.0)
		_line(felt, 26.0, Color("#f2c14e"), 2.5)
		for k in 4:  # corner rosettes
			var cp := mat.position + Vector2(20 if k % 2 == 0 else mat.size.x - 20, 20 if k < 2 else mat.size.y - 20)
			draw_circle(cp, 11.0, Color("#6b4710"))
			for j in 6:
				var a := TAU * j / 6.0
				draw_circle(cp + Vector2(cos(a), sin(a)) * 5.5, 4.0, Color("#f2c14e"))
			draw_circle(cp, 4.0, Color("#ff8a1f"))
			draw_circle(cp + Vector2(-1.2, -1.2), 1.5, Color(1, 1, 1, 0.85))

	func _line(r: Rect2, rad: float, col: Color, w: float) -> void:
		var pts := FX.round_rect_points(r, rad)
		pts.append(pts[0])
		draw_polyline(pts, col, w, true)

	## Point at fraction t (0..1) around the rectangle's perimeter, clockwise from the top-left.
	func _on_rect(r: Rect2, t: float) -> Vector2:
		var per := (r.size.x + r.size.y) * 2.0
		var d := t * per
		if d < r.size.x:
			return r.position + Vector2(d, 0)
		d -= r.size.x
		if d < r.size.y:
			return Vector2(r.end.x, r.position.y + d)
		d -= r.size.y
		if d < r.size.x:
			return Vector2(r.end.x - d, r.end.y)
		d -= r.size.x
		return Vector2(r.position.x, r.end.y - d)

	static var _grain_tex: ImageTexture
	static var _waves_tex: ImageTexture

	## Tileable seigaiha (overlapping fans of rings): each pixel takes the ring of the lowest
	## circle covering it, like scales laid row over row.
	static func _waves() -> ImageTexture:
		if _waves_tex == null:
			var wr := 36.0
			var tw := int(wr * 2.0)
			var th := int(wr)
			var img := Image.create(tw, th, false, Image.FORMAT_LA8)
			for py in th:
				for px in tw:
					var p := Vector2(px + 0.5, py + 0.5)
					var best := -1.0e9
					var dist := 0.0
					for j in range(-1, 4):
						for i in range(-1, 3):
							var cc := Vector2(i * wr * 2.0 + (wr if posmod(j, 2) == 1 else 0.0), j * wr * 0.5)
							var d := p.distance_to(cc)
							if d < wr and cc.y > best:
								best = cc.y
								dist = d
					var f := fposmod(dist / (wr * 0.25), 1.0)
					var a := clampf(1.0 - absf(f - 0.5) * 2.0 * 3.0, 0.0, 1.0) if dist > wr * 0.2 else 0.0
					img.set_pixel(px, py, Color(1, 1, 1, a))
			_waves_tex = ImageTexture.create_from_image(img)
		return _waves_tex

	## Tileable felt fibres, made once.
	static func _grain() -> ImageTexture:
		if _grain_tex == null:
			var n := 128
			var img := Image.create(n, n, false, Image.FORMAT_LA8)
			img.fill(Color(1, 1, 1, 0))
			var rng := RandomNumberGenerator.new()
			rng.seed = 9
			for k in 2600:
				var x := rng.randi_range(0, n - 1)
				var y := rng.randi_range(0, n - 1)
				var v := 1.0 if rng.randf() < 0.5 else 0.0
				var a := rng.randf_range(0.05, 0.15)
				var dx := rng.randi_range(-1, 1)
				for s in rng.randi_range(1, 3):
					img.set_pixel(posmod(x + dx * s, n), (y + s) % n, Color(v, v, v, a))
			_grain_tex = ImageTexture.create_from_image(img)
		return _grain_tex


## A few soft lights drifting up the table.
class Motes extends Control:
	var _m: Array = []
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for i in 16:
			_m.append({"x": rng.randf(), "y": rng.randf(), "r": rng.randf_range(10.0, 26.0),
				"v": rng.randf_range(0.012, 0.03), "ph": rng.randf() * TAU,
				"c": [LEMON, TANGERINE, Color("#7fe8c8"), Color.WHITE][i % 4]})

	func _process(delta: float) -> void:
		_t += delta
		for m in _m:
			m.y -= m.v * delta
			if m.y < -0.05:
				m.y = 1.05
		queue_redraw()

	func _draw() -> void:
		for m in _m:
			var p := Vector2(m.x * size.x + sin(_t * 0.6 + m.ph) * 20.0, m.y * size.y)
			var a := 0.1 + 0.07 * sin(_t * 1.3 + m.ph)
			FX.draw_glow(self, Rect2(p - Vector2(m.r, m.r), Vector2(m.r, m.r) * 2.0), Color(m.c.r, m.c.g, m.c.b, a))


## One tile. Its drawing lives in the game (draw_tile_node) so the game owns the state.
class TileNode extends Node2D:
	var g
	var idx := 0

	func _draw() -> void:
		g.draw_tile_node(self, idx)


## Everything that floats above the tiles: HUD chips, rings, score pops, banner.
class Overlay extends Control:
	var g

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if g:
			g.draw_overlay(self)


## Chunky icon button (Hint / Shuffle / Undo) with a count badge.
class ActionButton extends Button:
	var kind := "hint"
	var accent := TANGERINE
	var count := 0
	var pulse := 0.0

	func _init(k: String, col: Color) -> void:
		kind = k
		accent = col
		custom_minimum_size = Vector2(0, 104)
		focus_mode = Control.FOCUS_NONE
		for s in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(s, StyleBoxEmpty.new())
		button_down.connect(func(): FX.scale_to(self, 0.94, 0.08))
		button_up.connect(func(): FX.scale_to(self, 1.0, 0.12))
		resized.connect(func(): pivot_offset = size / 2.0)
		Callable(self, "_wire").call()

	func _wire() -> void:
		pressed.connect(func(): Feedback.sfx("button"))

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var down := is_pressed() and not disabled
		var base := accent
		if disabled:
			base = accent.darkened(0.55).lerp(Color(0.32, 0.32, 0.42), 0.5)
		elif pulse > 0.0:
			base = base.lerp(Color.WHITE, 0.3 * pulse)
		var depth := 8.0
		var top := 3.0 if down else 0.0
		FX.draw_shadow(self, Rect2(-6, h * 0.5, w + 12, h * 0.55), 0.5)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(32)
		sb.bg_color = base.darkened(0.5)
		draw_style_box(sb, Rect2(0, depth, w, h - depth))
		var face := Rect2(0, top, w, h - depth)
		FX.draw_round_gradient(self, face, 32.0, base.lightened(0.28), base.darkened(0.08))
		sb.bg_color = Color(1, 1, 1, 0.2)
		sb.set_corner_radius_all(26)
		draw_style_box(sb, Rect2(face.position + Vector2(10, 6), Vector2(w - 20, face.size.y * 0.34)))
		sb.draw_center = false
		sb.set_border_width_all(2)
		sb.border_color = Color(1, 1, 1, 0.3)
		sb.set_corner_radius_all(32)
		draw_style_box(sb, face)
		var ic := face.position + Vector2(w / 2.0, face.size.y * 0.4)
		var s := face.size.y * 0.46
		var ink := Color(1, 1, 1, 0.5 if disabled else 1.0)
		draw_set_transform(Vector2(1.5, 3.0), 0.0, Vector2.ONE)
		Icons.draw_action_icon(self, kind, ic, s, Color(0, 0, 0, 0.28))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		Icons.draw_action_icon(self, kind, ic, s, ink)
		FX.draw_text_centered(self, face.position + Vector2(w / 2.0, face.size.y * 0.8), kind.capitalize(), 24,
			Color(1, 1, 1, 0.5 if disabled else 0.95), FX.font())
		var bc := face.position + Vector2(w - 24, 24)
		draw_circle(bc, 22.0, Color(0, 0, 0, 0.35))
		draw_circle(bc, 19.0, Color.WHITE if not disabled else Color(1, 1, 1, 0.5))
		draw_circle(bc, 15.0, base.darkened(0.35))
		FX.draw_text_centered(self, bc, str(count), 22, Color.WHITE, FX.font())
