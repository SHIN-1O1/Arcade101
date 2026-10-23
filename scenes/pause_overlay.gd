extends Control
## "Paused" card game_host shows when the app loses focus (call, notification shade, home
## button). The tree is paused underneath; this card keeps running. Tap Resume (or Back) to go on.

const FX := preload("res://core/fx.gd")

var on_resume := Callable()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.1, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.card_box())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	card.add_child(box)
	box.add_child(UI.title("Paused", 64, FX.LEMON))
	var resume := UI.button("Resume", func():
		if on_resume.is_valid():
			on_resume.call(), UI.GOOD.darkened(0.08), 44)
	resume.custom_minimum_size = Vector2(420, 104)
	box.add_child(resume)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(card)
	add_child(center)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
