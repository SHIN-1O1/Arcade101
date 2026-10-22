extends Control
## Main menu: one card per game in data/games.json.

const FX := preload("res://core/fx.gd")
const Toast := preload("res://core/toast.gd")

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

	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", -26)
	heading.add_child(UI.title("ARCADE", 90, FX.LEMON))
	heading.add_child(UI.title("101", 90, FX.TANGERINE))
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


## Game card: glossy tile in the game's colour, a little drawn emblem, name, star progress.
class GameCard extends Button:
	var game: Dictionary
	var stars := 0
	var max_stars := 90
	var levels := true  # has a campaign (star bar)
	var best := -1  # endless best score, -1 = no endless mode

	func _draw() -> void:
		var col := Color(game.get("color", "#8e7dbe"))
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 12))
		var cx := r.get_center().x
		var font := FX.font()
		FX.draw_tile(self, r, col, 34)
		# Emblem on a darker plate.
		var plate := Rect2(r.position + Vector2(18, 16), Vector2(r.size.x - 36, r.size.y * 0.46))
		var sb := UI.box(Color(col.darkened(0.45), 0.55), 26)
		draw_style_box(sb, plate)
		_emblem(String(game.get("id", "")), plate.get_center(), plate.size.y * 0.42, col)
		FX.draw_text_centered(self, Vector2(cx, r.position.y + r.size.y * 0.64), game.get("name", ""), 36,
			Color.WHITE, font)
		FX.draw_text_centered(self, Vector2(cx, r.position.y + r.size.y * 0.76), game.get("tagline", ""), 21,
			Color(1, 1, 1, 0.82), font)
		var bar := Rect2(r.position.x + 56, r.position.y + r.size.y * 0.85, r.size.x - 80, 20)
		if levels:  # star progress bar
			var track := UI.box(Color(0, 0, 0, 0.32), 10)
			draw_style_box(track, bar)
			var k := clampf(float(stars) / maxf(1.0, max_stars), 0.0, 1.0)
			if k > 0.0:
				draw_style_box(UI.box(FX.LEMON, 10), Rect2(bar.position, Vector2(maxf(20.0, bar.size.x * k), bar.size.y)))
			FX.draw_star(self, Vector2(r.position.x + 34, bar.get_center().y), 17.0)
		if best >= 0:
			if levels:  # both modes: best score as a small tag in the corner
				var tag := Rect2(r.position.x + 10, r.position.y + 8, 112, 34)
				draw_style_box(UI.box(Color(0.05, 0.04, 0.16, 0.8), 17), tag)
				FX.draw_text_centered(self, tag.get_center(), "BEST %d" % best, 20, FX.LEMON, font)
			else:  # endless only: best score replaces the star bar
				var pill := Rect2(r.position.x + 24, r.position.y + r.size.y * 0.815, r.size.x - 48, 40)
				draw_style_box(UI.box(Color(0.05, 0.04, 0.16, 0.6), 20), pill)
				FX.draw_text_centered(self, pill.get_center(), "BEST  %d" % best if best > 0 else "ENDLESS", 26,
					Color.WHITE, font)
		if game.get("status", "") == "placeholder":
			var tag := Rect2(r.end.x - 96, r.position.y + 8, 84, 34)
			draw_style_box(UI.box(Color(0.05, 0.04, 0.16, 0.8), 17), tag)
			FX.draw_text_centered(self, tag.get_center(), "SOON", 20, FX.LEMON, font)

	## Tiny picture of each game; unknown ids get a glossy ball with the initial.
	func _emblem(id: String, c: Vector2, s: float, col: Color) -> void:
		match id:
			"fruit_merge":
				FX.draw_ball(self, c + Vector2(-s * 0.55, s * 0.25), s * 0.5, Color("#ff5d5d"))
				FX.draw_ball(self, c + Vector2(s * 0.5, s * 0.3), s * 0.42, Color("#8bd448"))
				FX.draw_ball(self, c + Vector2(0, -s * 0.3), s * 0.6, FX.TANGERINE)
			"color_sort":
				for i in 3:
					var x := c.x + (i - 1) * s * 0.75
					var tube := Rect2(x - s * 0.26, c.y - s * 0.9, s * 0.52, s * 1.8)
					draw_style_box(UI.box(Color(1, 1, 1, 0.18), int(s * 0.26)), tube)
					var cols := [FX.LEMON, Color("#ff5d8f"), Color("#4fc3f7")]
					for j in 3:
						FX.draw_ball(self, Vector2(x, c.y + s * 0.62 - j * s * 0.5), s * 0.21, cols[(i + j) % 3])
			"tower_stack":
				for i in 4:
					var w := s * (1.6 - i * 0.22)
					FX.draw_tile(self, Rect2(c.x - w / 2.0 + (i % 2) * s * 0.12, c.y + s * 0.62 - i * s * 0.44,
						w, s * 0.4), [FX.TANGERINE, FX.LEMON, Color("#4fc3f7"), Color("#ff5d8f")][i], 6, false)
			"block_puzzle":
				var cells := [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(0, -1), Vector2(1, 1)]
				var cs := s * 0.5
				for v in cells:
					FX.draw_tile(self, Rect2(c + v * cs * 1.08 - Vector2(cs, cs) / 2.0, Vector2(cs, cs)),
						FX.LEMON if v.y < 0 else Color("#4fc3f7"), 6, false)
			"number_merge":
				var labels := ["2", "4", "8", "16"]
				var ts := s * 0.78
				for i in 4:
					var p := c + Vector2((i % 2) - 0.5, int(i / 2.0) - 0.5) * ts * 1.1 - Vector2(ts, ts) / 2.0
					FX.draw_tile(self, Rect2(p, Vector2(ts, ts)), [Color("#4fc3f7"), FX.LEMON, FX.TANGERINE,
						Color("#ff5d5d")][i], 8, false)
					FX.draw_text_centered(self, p + Vector2(ts, ts) / 2.0, labels[i], int(ts * 0.48), Color.WHITE,
						FX.font())
			"bubble_shooter":
				var bcols := [Color("#ff5d8f"), Color("#4fc3f7"), FX.LEMON, Color("#8bd448")]
				var br := s * 0.3
				for row in 3:
					for i in 3 - row:
						var p := c + Vector2((i - (2 - row) / 2.0) * br * 2.05, (row - 1) * br * 1.8)
						FX.draw_ball(self, p, br, bcols[(i + row) % 4])
			"mahjong_match":
				var tw := s * 0.95
				var th := tw * 1.22
				var spots := [Vector2(-0.62, 0.12), Vector2(0.62, 0.12), Vector2(0.0, -0.18)]
				for k in 3:
					var tr := Rect2(c + spots[k] * tw - Vector2(tw, th) / 2.0, Vector2(tw, th))
					FX.draw_tile(self, tr, Color("#fff6df"), 8, k < 2)
					var tc := tr.get_center() + Vector2(0, -th * 0.04)
					match k:
						0:
							for dx in [-1, 1]:
								draw_circle(tc + Vector2(dx * tw * 0.2, 0), tw * 0.13, Color("#2b7bd6"))
						1:
							draw_rect(Rect2(tc - Vector2(tw * 0.09, th * 0.26), Vector2(tw * 0.18, th * 0.52)), Color("#2f9e5b"))
						_:
							draw_circle(tc, tw * 0.22, Color("#e5484d"))
							draw_circle(tc, tw * 0.12, Color("#fff6df"))
			_:
				FX.draw_ball(self, c, s * 0.7, col.lightened(0.3), String(game.get("name", "?")).left(1))
