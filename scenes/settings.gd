extends Control
## Sound / music / vibration toggles, restore purchases, reset progress.


func _ready() -> void:
	var col := UI.screen(self)
	var top := HBoxContainer.new()
	col.add_child(top)
	var back := UI.button("<", Nav.to_hub)
	back.custom_minimum_size = Vector2(96, 96)
	top.add_child(back)
	var title := UI.label("Settings", 48, UI.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)

	for key in ["sound", "music", "vibration"]:
		col.add_child(_toggle(key))
	col.add_child(UI.button("Restore purchases", IAP.restore_purchases))
	var reset := UI.button("Reset progress", func(): pass, UI.BAD)
	reset.pressed.connect(func():
		# Two taps to confirm.
		if reset.text == "Tap again to confirm":
			Save.reset_all()
			reset.text = "Progress reset"
		else:
			reset.text = "Tap again to confirm")
	col.add_child(reset)


func _toggle(key: String) -> CheckButton:
	var t := CheckButton.new()
	t.text = key.capitalize()
	t.button_pressed = bool(Save.get_setting(key))
	t.custom_minimum_size = Vector2(0, 96)
	t.add_theme_font_size_override("font_size", 36)
	t.toggled.connect(func(on): Save.set_setting(key, on))
	return t
