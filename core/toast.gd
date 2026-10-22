extends RefCounted
## One-line message that floats up from the bottom and fades. `Toast.show_text(self, "Ads removed")`
## Load with `const Toast := preload("res://core/toast.gd")`.

static func show_text(root: Control, text: String, color := Color.WHITE) -> void:
	if text == "" or not root.is_inside_tree():
		return
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.04, 0.16, 0.92), 28))
	var l := UI.label(text, 30, color)
	l.custom_minimum_size = Vector2(560, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(l)
	root.add_child(panel)
	panel.reset_size()
	var vp := root.get_viewport_rect().size
	panel.position = Vector2((vp.x - panel.size.x) / 2.0, vp.y - panel.size.y - 140.0)
	var tw := panel.create_tween()
	tw.tween_property(panel, "position:y", panel.position.y - 24.0, 0.25).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(panel, "modulate:a", 1.0, 0.0)
	tw.tween_interval(2.4)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(panel.queue_free)
