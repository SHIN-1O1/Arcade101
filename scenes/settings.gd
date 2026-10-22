extends Control
## Sound / music / vibration toggles, restore purchases, reset progress.

const FX := preload("res://core/fx.gd")


func _ready() -> void:
	var col := UI.screen(self)
	col.add_theme_constant_override("separation", 28)
	col.add_child(UI.top_bar("Settings", Nav.to_hub))

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.card_box())
	col.add_child(card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 18)
	card.add_child(rows)
	for key in ["sound", "music", "vibration"]:
		rows.add_child(_toggle(key))

	col.add_child(UI.button("Restore purchases", IAP.restore_purchases))
	var reset := UI.button("Reset progress", func(): pass, UI.BAD)
	reset.pressed.connect(func():
		# Two taps to confirm.
		if reset.text == "Tap again to confirm":
			Save.reset_all()
			reset.text = "Progress reset"
		else:
			reset.text = "Tap again to confirm"
			FX.shake(reset, 6.0, 0.25))
	col.add_child(reset)

	await get_tree().process_frame
	UI.stagger_pop([card, col.get_child(2), reset], 0.07, 0.05)


func _toggle(key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 80)
	var l := UI.label(key.capitalize(), 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var sw := UI.Switch.new()
	sw.set_on(bool(Save.get_setting(key)))
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.toggled.connect(func(on):
		Save.set_setting(key, on)
		Feedback.sfx("tap")
		Feedback.vibrate(15))
	row.add_child(sw)
	return row
