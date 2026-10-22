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
		# Diagonal lattice, every third line in gold.
		var step := 78.0
		var n := int((w + h) / step) + 2
		for k in n:
			var x := k * step - h
			var gold := k % 3 == 0
			var col := Color(1.0, 0.82, 0.3, 0.07) if gold else Color(1, 1, 1, 0.035)
			draw_line(Vector2(x, 0), Vector2(x + h, h), col, 2.0)
			draw_line(Vector2(x + h, 0), Vector2(x, h), col, 2.0)
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
		FX.draw_shadow(self, Rect2(mat.position + Vector2(-26, 18), mat.size + Vector2(52, 44)), 0.85)
		FX.draw_round_gradient(self, mat, 44.0, Color("#17806a"), Color("#093c33"))
		FX.draw_glow(self, mat.grow(-6), Color(0.45, 1.0, 0.8, 0.14))
		# felt speckle, seeded so it never shimmers
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 220:
			var p := mat.position + Vector2(rng.randf(), rng.randf()) * mat.size
			draw_circle(p, rng.randf_range(0.8, 1.8), Color(1, 1, 1, rng.randf_range(0.02, 0.07)))
		# faint medallion in the middle of the felt
		var mc := mat.get_center()
		var mr := minf(mat.size.x, mat.size.y) * 0.36
		for i in 3:
			draw_arc(mc, mr * (1.0 - i * 0.18), 0.0, TAU, 64, Color(1.0, 0.85, 0.35, 0.09 - i * 0.02), 3.0, true)
		for i in 12:
			var a := TAU * i / 12.0
			draw_circle(mc + Vector2(cos(a), sin(a)) * mr * 1.0, 5.0, Color(1.0, 0.85, 0.35, 0.12))
			draw_line(mc + Vector2(cos(a), sin(a)) * mr * 0.64, mc + Vector2(cos(a), sin(a)) * mr * 0.82, Color(1.0, 0.85, 0.35, 0.07), 3.0, true)
		_sb.set_corner_radius_all(44)
		_sb.set_border_width_all(5)
		_sb.border_color = Color(LEMON, 0.8)
		draw_style_box(_sb, mat)
		_sb.set_corner_radius_all(34)
		_sb.set_border_width_all(2)
		_sb.border_color = Color(TANGERINE, 0.55)
		draw_style_box(_sb, mat.grow(-11))
		for k in 4:  # corner studs
			var cp := mat.position + Vector2(18 if k % 2 == 0 else mat.size.x - 18, 18 if k < 2 else mat.size.y - 18)
			draw_circle(cp, 7.0, Color("#a8741a"))
			draw_circle(cp, 5.5, LEMON)
			draw_circle(cp + Vector2(-1.5, -1.5), 2.0, Color(1, 1, 1, 0.8))


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
