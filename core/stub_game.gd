extends BaseGame
## Placeholder used by every game until its real scene is built.
## Shows the level parameters and debug buttons to exercise the flow.

func _on_start() -> void:
	for c in get_children():
		c.queue_free()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	add_child(box)

	var game: Dictionary = Games.get_game(Nav.game_id)
	box.add_child(UI.label("%s\n(placeholder)" % game.get("name", "?"), 40))
	var params := UI.label(JSON.stringify(level, "  "), 22)
	params.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	params.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(params)

	for s in [1, 2, 3]:
		box.add_child(UI.button("Win %d★" % s, func(): win(s), UI.GOOD))
	box.add_child(UI.button("Fail", fail, UI.BAD))
	status_changed.emit("Debug controls")
