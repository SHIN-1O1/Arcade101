extends Control
## Main menu: one card per game in data/games.json.

const FX := preload("res://core/fx.gd")
const Toast := preload("res://core/toast.gd")
const CardArt := preload("res://core/cards/card_art.gd")

var _ads_button: Button


func _ready() -> void:
	Feedback.play_music("menu")
	var col := UI.screen(self)

	var top := HBoxContainer.new()
	col.add_child(top)
	var total := 0
	var max_total := 0
	for game in Games.games:
		total += Save.total_stars(game.id)
		max_total += Games.level_count(game.id) * 3
	var pill_box := CenterContainer.new()
	pill_box.add_child(UI.star_pill("%d / %d" % [total, max_total]))
	top.add_child(pill_box)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_ads_button = UI.button("No Ads", func(): IAP.purchase(IAP.REMOVE_ADS), FX.TANGERINE, 28)
	_ads_button.custom_minimum_size = Vector2(150, 88)
	top.add_child(_ads_button)
	top.add_theme_constant_override("separation", 16)
	top.add_child(UI.icon_button("settings", Nav.to_settings))

	var heading := NeonTitle.new()
	heading.custom_minimum_size = Vector2(0, 210)
	col.add_child(heading)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	col.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	scroll.add_child(pad)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 22)
	pad.add_child(grid)
	var cards: Array = []
	for game in Games.games:
		var card := _card(game)
		grid.add_child(card)
		cards.append(card)

	_refresh_ads_button()
	Save.no_ads_changed.connect(func(_on): _refresh_ads_button())
	IAP.busy_changed.connect(_on_iap_busy)
	IAP.purchase_message.connect(func(m): Toast.show_text(self, m))
	IAP.purchase_finished.connect(func(_id, ok):
		if ok:
			Toast.show_text(self, "Ads removed. Thank you!", FX.LEMON))
	_on_iap_busy(IAP.busy)
	Ads.show_banner()

	await get_tree().process_frame
	heading.pivot_offset = heading.size / 2.0
	FX.pop(heading, 0.6, 0.4)
	UI.stagger_pop(cards, 0.06, 0.15)


func _card(game: Dictionary) -> GameCard:
	var id: String = game.id
	var c := GameCard.new()
	c.game = game
	c.stars = Save.total_stars(id)
	c.max_stars = Games.level_count(id) * 3
	c.levels = Games.has_levels(id)
	c.best = Save.get_high_score(id) if Games.has_endless(id) else -1
	c.custom_minimum_size = Vector2(0, 272)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.flat(c)
	UI.squash(c, 0.95)
	UI.wire(c, func(): _open(id))
	return c


## Level-only and endless-only games open directly; a game with both modes asks first.
func _open(id: String) -> void:
	if Games.has_levels(id) and Games.has_endless(id):
		_pick_mode(id)
	else:
		Nav.open_game(id)


func _pick_mode(id: String) -> void:
	var game := Games.get_game(id)
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.1, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.device != InputEvent.DEVICE_ID_EMULATION:
			layer.queue_free())
	layer.add_child(dim)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.card_box())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	card.add_child(box)
	box.add_child(UI.title(game.get("name", id), 52, FX.LEMON))
	var camp := UI.button("Campaign", func(): Nav.to_level_select(id), FX.TANGERINE, 40)
	camp.custom_minimum_size = Vector2(440, 100)
	box.add_child(camp)
	box.add_child(UI.label("%d / %d stars" % [Save.total_stars(id), Games.level_count(id) * 3], 24, Color(1, 1, 1, 0.75)))
	var endless := UI.button("Endless", func(): Nav.play_endless(id), UI.GOOD.darkened(0.08), 40)
	endless.custom_minimum_size = Vector2(440, 100)
	box.add_child(endless)
	box.add_child(UI.label("Best %d" % Save.get_high_score(id), 24, Color(1, 1, 1, 0.75)))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(card)
	layer.add_child(center)
	add_child(layer)
	card.pivot_offset = card.size / 2.0
	FX.pop(card, 0.8, 0.25)


func _refresh_ads_button() -> void:
	_ads_button.visible = not Save.has_no_ads()  # bought: the button disappears for good


func _on_iap_busy(busy: bool) -> void:
	_ads_button.disabled = busy
	_ads_button.modulate.a = 0.6 if busy else 1.0


## "ARCADE 101" as a neon sign: pink and tangerine tubes that hum and now and then flicker.
class NeonTitle extends Control:
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	## 1 most of the time; a quick stutter for a moment every few seconds.
	func _flicker(offset: float) -> float:
		var k := fposmod(_t + offset, 5.3)
		if k < 0.32:
			return 0.35 if int(k * 22.0) % 3 == 0 else 1.0
		return 0.93 + 0.07 * sin(_t * 9.0 + offset)

	func _draw() -> void:
		var c := size / 2.0
		var f := FX.font()
		FX.draw_glow(self, Rect2(c.x - size.x * 0.45, 0, size.x * 0.9, size.y), Color(FX.NEON_PINK, 0.16))
		FX.draw_neon_text(self, c + Vector2(0, -46), "ARCADE", 100, FX.NEON_PINK, f, _flicker(0.0))
		FX.draw_neon_text(self, c + Vector2(0, 58), "101", 96, FX.TANGERINE, f, _flicker(2.4))
		var y := c.y + 4.0  # thin neon rules either side, like a sign's frame
		for side in [-1, 1]:
			var x0: float = c.x + side * 150.0
			FX.draw_neon_polyline(self, PackedVector2Array([Vector2(x0, y), Vector2(x0 + side * 120.0, y)]),
				FX.NEON_CYAN, 3.0, false, 0.8)


## Game card: arcade-cabinet tile with a neon rim in the game's colour, a little CRT screen
## with a neon line-art emblem, the name in neon type, and star progress.
class GameCard extends Button:
	var game: Dictionary
	var stars := 0
	var max_stars := 90
	var levels := true  # has a campaign (star bar)
	var best := -1  # endless best score, -1 = no endless mode

	func _ready() -> void:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # scanlines

	func _draw() -> void:
		var col := FX.neon(Color(game.get("color", "#8e7dbe")))
		var r := Rect2(Vector2(8, 8), size - Vector2(16, 18))
		var cx := r.get_center().x
		var font := FX.font()
		FX.draw_neon_panel(self, r, 26, col, 3.5)
		# CRT screen with the emblem.
		var plate := Rect2(r.position + Vector2(16, 16), Vector2(r.size.x - 32, r.size.y * 0.47))
		FX.draw_round_gradient(self, plate, 16, FX.NIGHT, FX.NIGHT.lerp(col, 0.18))
		for i in range(1, 6):  # faint perspective floor lines
			var y := plate.end.y - plate.size.y * 0.06 * i * i * 0.5
			draw_line(Vector2(plate.position.x + 8, y), Vector2(plate.end.x - 8, y), Color(col, 0.08), 1.5)
		FX.draw_scanlines(self, plate.grow(-2.0), 0.22)
		FX.draw_neon_rect(self, plate, 16, Color(col, 0.6), 1.6, 0.4)
		_emblem(String(game.get("id", "")), plate.get_center(), plate.size.y * 0.4, col)
		FX.draw_neon_text(self, Vector2(cx, r.position.y + r.size.y * 0.64), game.get("name", ""), 34, col, font, 0.8)
		FX.draw_text_centered(self, Vector2(cx, r.position.y + r.size.y * 0.755), game.get("tagline", ""), 20,
			Color(1, 1, 1, 0.72), font)
		var bar := Rect2(r.position.x + 56, r.position.y + r.size.y * 0.855, r.size.x - 80, 14)
		if levels:  # star progress bar
			var track := UI.box(Color(FX.NIGHT, 0.9), 7)
			track.border_color = Color(col, 0.45)
			track.set_border_width_all(2)
			draw_style_box(track, bar.grow(2.0))
			var k := clampf(float(stars) / maxf(1.0, max_stars), 0.0, 1.0)
			if k > 0.0:
				var fr := Rect2(bar.position, Vector2(maxf(14.0, bar.size.x * k), bar.size.y))
				FX.draw_glow(self, fr.grow(10.0), Color(FX.LEMON, 0.3))
				FX.draw_round_gradient(self, fr, 7, FX.LEMON.lightened(0.3), FX.TANGERINE)
			FX.draw_star(self, Vector2(r.position.x + 32, bar.get_center().y), 16.0)
		if best >= 0:
			if levels:  # both modes: best score as a tag riding the top rim, once there is one
				if best > 0:
					var font_w := font.get_string_size("BEST %d" % best, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
					var tag := Rect2(r.end.x - font_w - 46, r.position.y - 6, font_w + 30, 30)
					draw_style_box(UI.box(Color(FX.NIGHT, 0.95), 15), tag)
					FX.draw_neon_rect(self, tag, 15, FX.LEMON, 1.6, 0.5)
					FX.draw_text_centered(self, tag.get_center(), "BEST %d" % best, 18, FX.LEMON, font)
			else:  # endless only: best score replaces the star bar
				var pill := Rect2(r.position.x + 26, r.position.y + r.size.y * 0.815, r.size.x - 52, 38)
				draw_style_box(UI.box(Color(FX.NIGHT, 0.85), 19), pill)
				FX.draw_neon_rect(self, pill, 19, Color(col, 0.7), 1.8, 0.5)
				FX.draw_text_centered(self, pill.get_center(), "BEST  %d" % best if best > 0 else "ENDLESS", 24,
					FX.LEMON if best > 0 else Color.WHITE, font)
		if game.get("status", "") == "placeholder":
			var tag := Rect2(plate.end.x - 90, plate.position.y + 6, 84, 30)
			draw_style_box(UI.box(Color(FX.NIGHT, 0.85), 15), tag)
			FX.draw_text_centered(self, tag.get_center(), "SOON", 18, FX.LEMON, font)

	## Neon line-art picture of each game; unknown ids get a neon ring with the initial.
	func _emblem(id: String, c: Vector2, s: float, col: Color) -> void:
		var pink := FX.NEON_PINK
		var cyan := FX.NEON_CYAN
		var green := Color("#7dff6a")
		match id:
			"fruit_merge":
				var fruits := [[Vector2(-0.6, 0.3), 0.48, Color("#ff4f6a")], [Vector2(0.58, 0.36), 0.4, green],
					[Vector2(0, -0.2), 0.62, FX.TANGERINE]]
				for fr in fruits:
					var p: Vector2 = c + fr[0] * s
					var rad: float = fr[1] * s
					draw_circle(p, rad, Color(fr[2], 0.22))
					FX.draw_neon_circle(self, p, rad, fr[2], 3.0)
					draw_arc(p, rad * 0.62, PI * 1.1, PI * 1.45, 10, Color(1, 1, 1, 0.6), 3.0, true)
				var top := c + Vector2(0, -0.82) * s
				FX.draw_neon_polyline(self, PackedVector2Array([top, top + Vector2(s * 0.08, -s * 0.22)]), green, 3.0)
				FX.draw_neon_polyline(self, PackedVector2Array([top + Vector2(s * 0.06, -s * 0.14),
					top + Vector2(s * 0.3, -s * 0.28), top + Vector2(s * 0.42, -s * 0.12), top + Vector2(s * 0.06, -s * 0.14)]),
					green, 2.5)
			"color_sort":
				var cols := [FX.LEMON, pink, cyan]
				for i in 3:
					var x := c.x + (i - 1) * s * 0.78
					var tw := s * 0.25
					var top := c.y - s * 0.95
					var bot := c.y + s * 0.85
					var tube := PackedVector2Array([Vector2(x - tw, top), Vector2(x - tw, bot - tw)])
					for k in 9:
						tube.append(Vector2(x, bot - tw) + Vector2.from_angle(PI - k * PI / 8.0) * tw)
					tube.append(Vector2(x + tw, top))
					FX.draw_neon_polyline(self, tube, Color(0.85, 0.95, 1.0), 2.5, false, 0.6)
					for j in 3:
						var bc: Color = cols[(i + j) % 3]
						var p := Vector2(x, bot - tw - j * s * 0.48)
						FX.draw_glow(self, Rect2(p - Vector2(tw, tw) * 1.6, Vector2(tw, tw) * 3.2), Color(bc, 0.45))
						draw_circle(p, tw * 0.78, bc)
						draw_circle(p - Vector2(tw, tw) * 0.25, tw * 0.22, Color(1, 1, 1, 0.7))
			"tower_stack":
				var bcols := [FX.TANGERINE, FX.LEMON, cyan, pink]
				for i in 4:
					var w := s * (1.7 - i * 0.24)
					var br := Rect2(c.x - w / 2.0 + ((i % 2) * 2 - 1) * s * 0.07, c.y + s * 0.55 - i * s * 0.46, w, s * 0.36)
					draw_rect(br, Color(bcols[i], 0.25))
					FX.draw_neon_rect(self, br, 4, bcols[i], 2.5, 0.8)
			"block_puzzle":
				var cells := [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(0, -1), Vector2(1, 1)]
				var cs := s * 0.5
				for v in cells:
					var cr := Rect2(c + v * cs * 1.16 - Vector2(cs, cs) / 2.0, Vector2(cs, cs))
					var bc := FX.LEMON if v.y < 0 else cyan
					draw_rect(cr, Color(bc, 0.3))
					FX.draw_neon_rect(self, cr, 4, bc, 2.5, 0.8)
			"number_merge":
				var labels := ["2", "4", "8", "16"]
				var tcols := [cyan, FX.LEMON, FX.TANGERINE, pink]
				var ts := s * 0.8
				for i in 4:
					var p := c + Vector2((i % 2) - 0.5, int(i / 2.0) - 0.5) * ts * 1.18 - Vector2(ts, ts) / 2.0
					var tr := Rect2(p, Vector2(ts, ts))
					draw_rect(tr, Color(tcols[i], 0.16))
					FX.draw_neon_rect(self, tr, 8, tcols[i], 2.5, 0.8)
					FX.draw_neon_text(self, tr.get_center(), labels[i], int(ts * 0.48), tcols[i], FX.font(), 0.7)
			"bubble_shooter":
				var bcols := [pink, cyan, FX.LEMON, green]
				var br := s * 0.28
				for row in 3:
					for i in 3 - row:
						var p := c + Vector2((i - (2 - row) / 2.0) * br * 2.15, (row - 1.3) * br * 1.9)
						var bc: Color = bcols[(i + row) % 4]
						draw_circle(p, br, Color(bc, 0.2))
						FX.draw_neon_circle(self, p, br, bc, 2.5, 0.8)
						draw_arc(p, br * 0.6, PI * 1.1, PI * 1.45, 8, Color(1, 1, 1, 0.6), 2.5, true)
				var gun := c + Vector2(0, s * 0.95)
				for k in 4:  # dotted aim line
					draw_circle(gun.lerp(c + Vector2(br * 1.1, -s * 0.05), (k + 1) / 5.0), 2.5, Color(1, 1, 1, 0.7))
				draw_circle(gun, br * 0.75, Color(FX.TANGERINE, 0.3))
				FX.draw_neon_circle(self, gun, br * 0.75, FX.TANGERINE, 2.5, 0.8)
			"mahjong_match":
				var tw := s * 0.88
				var th := tw * 1.25
				var spots := [Vector2(-0.66, 0.14), Vector2(0.66, 0.14), Vector2(0.0, -0.16)]
				var ivory := Color("#fff1cf")
				for k in 3:
					var tr := Rect2(c + spots[k] * tw - Vector2(tw, th) / 2.0, Vector2(tw, th))
					draw_style_box(UI.box(Color(FX.NIGHT, 0.95), 8), tr)
					FX.draw_neon_rect(self, tr, 8, ivory, 2.5, 0.7)
					var tc := tr.get_center()
					match k:
						0:
							for dy in [-1, 1]:
								FX.draw_neon_circle(self, tc + Vector2(0, dy * th * 0.2), tw * 0.15, cyan, 2.0, 0.7)
						1:
							for dx in [-1, 1]:
								FX.draw_neon_polyline(self, PackedVector2Array([tc + Vector2(dx * tw * 0.14, -th * 0.28),
									tc + Vector2(dx * tw * 0.14, th * 0.28)]), green, 3.0, false, 0.7)
						_:
							FX.draw_neon_circle(self, tc, tw * 0.24, pink, 2.5, 0.8)
							draw_circle(tc, tw * 0.07, pink)
			"klondike":
				var cw := s * 0.95
				var ch := cw * 1.4
				for i in 3:
					draw_set_transform(c + Vector2((i - 1) * s * 0.44, s * 0.8), deg_to_rad((i - 1) * 18.0), Vector2.ONE)
					var cr := Rect2(Vector2(-cw / 2.0, -ch), Vector2(cw, ch))
					draw_style_box(UI.box(Color(FX.NIGHT, 0.95), 8), cr)
					var ink: Color = [Color(0.85, 0.95, 1.0), pink, pink][i]
					FX.draw_neon_rect(self, cr, 8, ink, 2.2, 0.7)
					CardArt.draw_pip(self, [0, 1, 2][i], cr.get_center(), cw * 0.24, ink)
					FX.draw_text_centered(self, cr.position + Vector2(cw * 0.2, ch * 0.13), "A", int(cw * 0.22), ink, FX.font())
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_:
				FX.draw_neon_circle(self, c, s * 0.7, col, 3.0)
				FX.draw_neon_text(self, c, String(game.get("name", "?")).left(1), int(s * 0.8), col, FX.font())
