extends Control
## Main menu: one card per game in data/games.json.

var _ads_button: Button


func _ready() -> void:
	var col := UI.screen(self)
	col.add_child(UI.label("Pocket Arcade", 64, UI.ACCENT))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	scroll.add_child(grid)

	for game in Games.games:
		grid.add_child(_card(game))

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 20)
	col.add_child(bar)
	var settings := UI.button("Settings", Nav.to_settings)
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(settings)
	_ads_button = UI.button("Remove Ads", func(): IAP.purchase(IAP.REMOVE_ADS), UI.BAD)
	_ads_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_ads_button)
	_refresh_ads_button()
	Save.no_ads_changed.connect(func(_on): _refresh_ads_button())
	Ads.show_banner()


func _card(game: Dictionary) -> Button:
	var id: String = game.id
	var count := Games.level_count(id)
	var text := "%s\n%s\n%s %d/%d" % [game.name, game.get("tagline", ""), "★", Save.total_stars(id), count * 3]
	var b := UI.button(text, func(): Nav.to_level_select(id), Color(game.get("color", "#2b2d42")), 28)
	b.custom_minimum_size = Vector2(0, 280)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return b


func _refresh_ads_button() -> void:
	_ads_button.disabled = Save.has_no_ads()
	_ads_button.text = "Ads removed" if Save.has_no_ads() else "Remove Ads"
