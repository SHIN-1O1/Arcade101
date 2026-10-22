extends Control
## Main menu: one card per game in data/games.json.

const FX := preload("res://core/fx.gd")

var _ads_button: Button


func _ready() -> void:
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
	heading.add_child(UI.title("POCKET", 90, FX.LEMON))
	heading.add_child(UI.title("ARCADE", 90, FX.TANGERINE))
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
	c.custom_minimum_size = Vector2(0, 272)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.flat(c)
	UI.squash(c, 0.95)
	UI.wire(c, func(): Nav.to_level_select(id))
	return c


func _refresh_ads_button() -> void:
	_ads_button.visible = not Save.has_no_ads()


## Game card: glossy tile in the game's colour, a little drawn emblem, name, star progress.
class GameCard extends Button:
	var game: Dictionary
	var stars := 0
	var max_stars := 90

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
		# Star progress bar.
		var bar := Rect2(r.position.x + 56, r.position.y + r.size.y * 0.85, r.size.x - 80, 20)
		var track := UI.box(Color(0, 0, 0, 0.32), 10)
		draw_style_box(track, bar)
		var k := clampf(float(stars) / maxf(1.0, max_stars), 0.0, 1.0)
		if k > 0.0:
			draw_style_box(UI.box(FX.LEMON, 10), Rect2(bar.position, Vector2(maxf(20.0, bar.size.x * k), bar.size.y)))
		FX.draw_star(self, Vector2(r.position.x + 34, bar.get_center().y), 17.0)
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
			_:
				FX.draw_ball(self, c, s * 0.7, col.lightened(0.3), String(game.get("name", "?")).left(1))
