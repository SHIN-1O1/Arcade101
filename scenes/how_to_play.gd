extends Control
## How-to-play card that game_host lays over a game: automatically the first time a player
## enters that game (saved per game), and from the "i" button any time. Text comes from
## data/how_to_play.json via Games.how_to_play(id). Set the vars, then add it as a full-rect child.

const FX := preload("res://core/fx.gd")
const ResultOverlay := preload("res://scenes/result_overlay.gd")

const CARD_W := 620.0
const PAD := 36.0
const BADGE := 52.0

var game_name := ""
var steps: Array = []
var extra := ""  # mode tip (Endless), shown after the steps in lemon
var accent := FX.TANGERINE
var on_close := Callable()  # called once the card starts closing

var _dim: Control
var _card: PanelContainer
var _head: Control
var _closing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = ResultOverlay.Dim.new()
	_dim.accent = accent
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_card = PanelContainer.new()
	var sb := StyleBoxEmpty.new()
	sb.set_content_margin_all(PAD)
	sb.content_margin_top = 26
	_card.add_theme_stylebox_override("panel", sb)
	_card.draw.connect(_draw_card)
	add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	_card.add_child(box)

	_head = VBoxContainer.new()
	_head.add_theme_constant_override("separation", 0)
	box.add_child(_head)
	_head.add_child(UI.label("HOW TO PLAY", 26, Color(1, 1, 1, 0.8)))
	_head.add_child(UI.title(game_name, 56, FX.LEMON, Color(0, 0, 0, 0.35)))
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	box.add_child(gap)

	var text_w := CARD_W - PAD * 2.0 - BADGE - 18.0
	var rows: Array = []
	for i in steps.size():
		var row := _step_row(str(i + 1), str(steps[i]), text_w, Color.WHITE)
		box.add_child(row)
		rows.append(row)
	if extra != "":
		var row := _step_row("+", extra, text_w, FX.LEMON)
		box.add_child(row)
		rows.append(row)

	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 8
	box.add_child(gap2)
	var buttons: Array = []
	var ok := UI.button("Got it!", _press, UI.GOOD.darkened(0.08), 44)
	ok.custom_minimum_size.y = 104
	box.add_child(ok)
	buttons.append(ok)

	resized.connect(_layout)
	_intro(rows, buttons)


## Number badge + wrapped line. Fixed text width so the card can size itself in one pass.
func _step_row(mark: String, text: String, text_w: float, col: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var badge := Badge.new()
	badge.mark = mark
	badge.color = accent if mark != "+" else FX.TANGERINE
	badge.custom_minimum_size = Vector2(BADGE, BADGE)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(badge)
	var l := UI.label(text, 30, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = text_w
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


func _layout(slide := 0.0) -> void:
	_card.size = Vector2(minf(CARD_W, size.x - 32.0), 0)
	_card.size = Vector2(_card.size.x, _card.get_combined_minimum_size().y)
	var y := maxf(16.0, (size.y - _card.size.y) / 2.0)
	_card.position = Vector2((size.x - _card.size.x) / 2.0, y + slide)
	_card.pivot_offset = _card.size / 2.0


func _intro(rows: Array, buttons: Array) -> void:
	_dim.modulate.a = 0.0
	_card.modulate.a = 0.0
	for n in rows + buttons:
		n.modulate.a = 0.0
	for b in buttons:
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	await get_tree().process_frame  # let the containers size themselves
	if _closing:
		return
	_layout(80.0)
	_card.scale = Vector2(0.8, 0.8)
	var tw := create_tween().set_parallel()
	tw.tween_property(_dim, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "modulate:a", 1.0, 0.18)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(_layout, 80.0, 0.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var t := 0.18
	for n in rows:  # steps fade in one after another (the container owns their positions)
		tw.tween_property(n, "modulate:a", 1.0, 0.22).set_delay(t)
		t += 0.07
	tw.chain().tween_callback(func():
		for b in buttons:
			b.modulate.a = 1.0
			b.mouse_filter = Control.MOUSE_FILTER_STOP
		UI.stagger_pop(buttons, 0.06, 0.0))


func _press() -> void:
	if _closing:
		return
	close()
	if on_close.is_valid():
		on_close.call()


## Fade out, then free.
func close() -> void:
	_closing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_property(_card, "scale", Vector2(0.92, 0.92), 0.2).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)


func _draw_card() -> void:
	FX.draw_neon_card(_card, Rect2(Vector2.ZERO, _card.size), 44, FX.neon(accent),
		_head.position.y + _head.size.y + 24.0)


## Glossy round step number.
class Badge extends Control:
	var mark := "1"
	var color := FX.TANGERINE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		FX.draw_ball(self, c, size.x / 2.0, color, "", false)
		FX.draw_text_centered(self, c, mark, 30, Color.WHITE, FX.font())
