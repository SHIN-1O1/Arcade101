extends Control
## 5-column grid of levels: completed (accent + gold stars), next (glowing), locked.

const FX := preload("res://core/fx.gd")
const COLUMNS := 5
const TILE := Vector2(112, 124)
const GAP := 16

var _tiles: Array = []


func _ready() -> void:
	var id := Nav.game_id
	var game := Games.get_game(id)
	var accent := Color(game.get("color", "#8e7dbe"))
	var col := UI.screen(self, accent)
	var count := Games.level_count(id)

	col.add_child(UI.top_bar(game.get("name", id), Nav.to_hub, null, Color.WHITE, accent.darkened(0.55)))
	var pill_row := CenterContainer.new()
	pill_row.add_child(UI.star_pill("%d / %d" % [Save.total_stars(id), count * 3]))
	col.add_child(pill_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	col.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var pad := MarginContainer.new()  # room for the next tile's glow
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	center.add_child(pad)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	pad.add_child(grid)

	var next := -1
	for i in count:
		var tile := _level_tile(id, i, accent)
		if tile.state == LevelTile.NEXT and next < 0:
			next = i
		grid.add_child(tile)
		_tiles.append(tile)

	var play_index := next if next >= 0 else count - 1
	var play := UI.button("Play  Level %d" % (play_index + 1), func(): Nav.play(id, play_index), FX.TANGERINE, 40)
	play.custom_minimum_size = Vector2(460, 104)
	var play_row := CenterContainer.new()
	play_row.add_child(play)
	col.add_child(play_row)

	await get_tree().process_frame
	UI.stagger_pop(_tiles, 0.018)
	FX.pop(play, 0.6, 0.35)


func _level_tile(id: String, i: int, accent: Color) -> LevelTile:
	var t := LevelTile.new()
	t.number = i + 1
	t.stars = Save.get_stars(id, i)
	t.accent = accent
	if not Save.is_unlocked(id, i):
		t.state = LevelTile.LOCKED
	elif t.stars > 0:
		t.state = LevelTile.DONE
	else:
		t.state = LevelTile.NEXT
	t.custom_minimum_size = TILE
	UI.flat(t)
	UI.squash(t)
	t.pressed.connect(func():
		if t.state == LevelTile.LOCKED:
			Feedback.sfx("locked")
			Feedback.vibrate(30)
			FX.shake(t, 6.0, 0.25)
		else:
			Feedback.sfx("select")
			Feedback.vibrate(15)
			Nav.play(id, i))
	return t


## One level button, fully drawn: glossy tile, number, stars or lock.
class LevelTile extends Button:
	enum { LOCKED, DONE, NEXT }
	var number := 1
	var stars := 0
	var state := LOCKED
	var accent := FX.TANGERINE
	var _time := 0.0

	func _ready() -> void:
		set_process(state == NEXT)

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(3, 3), size - Vector2(6, 12))
		var cx := r.get_center().x
		var font := FX.font()
		var col := Color("#3b3970")
		match state:
			DONE:
				col = accent
			NEXT:
				col = FX.TANGERINE
				var pulse := 0.5 + 0.5 * sin(_time * 4.0)
				FX.draw_glow(self, r.grow(26.0 + 8.0 * pulse), Color(FX.LEMON, 0.3 + 0.25 * pulse))
		FX.draw_tile(self, r, col, 24)
		if state == NEXT:
			var ring := StyleBoxFlat.new()
			ring.draw_center = false
			ring.set_corner_radius_all(26)
			ring.set_border_width_all(4)
			ring.border_color = FX.LEMON
			draw_style_box(ring, r.grow(3.0))
		if state == LOCKED:
			FX.draw_lock(self, Vector2(cx, r.position.y + r.size.y * 0.38), r.size.y * 0.42, Color(1, 1, 1, 0.42))
			FX.draw_text_centered(self, Vector2(cx, r.position.y + r.size.y * 0.8), str(number), 24,
				Color(1, 1, 1, 0.45), font)
			return
		FX.draw_text_centered(self, Vector2(cx, r.position.y + r.size.y * 0.38), str(number), 48, Color.WHITE, font)
		var sy := r.position.y + r.size.y * 0.76
		for k in 3:
			var lift := -4.0 if k == 1 else 0.0
			FX.draw_star(self, Vector2(cx + (k - 1) * 30.0, sy + lift), 13.0, FX.LEMON, k < stars)
