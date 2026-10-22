extends Control
## The reusable card board: piles, card views, drag and drop with snap-back, double-tap and
## tap-to-move, undo, hint, auto-complete and the win cascade. A game supplies a CardRules
## subclass (move validation) and a layout callback (card size + pile positions).
## Load with: const CardTable := preload("res://core/cards/card_table.gd")
## See CLAUDE.md "Card kit" and games/klondike/game.gd for a full example.

const Card := preload("res://core/cards/card.gd")
const Pile := preload("res://core/cards/pile.gd")
const CardView := preload("res://core/cards/card_view.gd")
const CardLayout := preload("res://core/cards/card_layout.gd")
const FX := preload("res://core/fx.gd")

## A move was executed (drag, tap, hint, auto-complete). Also fired for follow-up moves made in after_move.
signal moved(from_id: String, to_id: String, count: int)
## Anything changed on the table (move, undo, new deal). Use it to refresh counters and buttons.
signal changed()
signal win_animation_finished()
signal auto_complete_finished(won: bool)

const DRAG_START := 12.0
const DOUBLE_TAP_MS := 340

var rules: RefCounted          ## a CardRules subclass
var piles := {}                ## id -> Pile
var order: Array = []          ## pile ids, creation order (also z-order)
var cards: Array = []          ## every Card on the table
var views := {}                ## Card.uid -> CardView
var card_size := Vector2(90, 126)
var layout_callback := Callable()  ## func(table): set table.card_size and each pile's origin / max_extent
var tap_to_move := false       ## a single tap sends the card to rules.auto_target (double-tap always does)
var sfx := true                ## kit plays select / place / locked sounds
var input_enabled := true
var busy := false              ## win cascade or auto-complete running: input ignored
var undo_stack: Array = []

var _press := {}
var _drag := {}
var _last_tap_uid := -1
var _last_tap_ms := 0
var _hint_i := 0
var _slot_glow := {}
var _fall: Array = []
var _fall_queue: Array = []
var _fall_t := 0.0
var _fall_total := 0.0
var _ghosts := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false


# --- setup ------------------------------------------------------------------

func add_pile(id: String, kind: String, fan: int = Pile.Fan.NONE) -> RefCounted:
	var p := Pile.new()
	p.id = id
	p.kind = kind
	p.fan = fan
	piles[id] = p
	order.append(id)
	return p


func pile(id: String) -> RefCounted:
	return piles.get(id)


func piles_of(kind: String) -> Array:
	var out: Array = []
	for id in order:
		if piles[id].kind == kind:
			out.append(piles[id])
	return out


## Remove all cards and views (new deal). Piles stay.
func clear_cards() -> void:
	cancel_drag()
	stop_effects()
	for v in views.values():
		v.queue_free()
	views.clear()
	cards.clear()
	for id in order:
		piles[id].cards.clear()
	undo_stack.clear()
	_hint_i = 0
	_press = {}


## Put `list` (Card objects) on top of pile `id`, creating their views.
func add_cards(list: Array, id: String) -> void:
	var p: RefCounted = piles[id]
	for c in list:
		cards.append(c)
		p.cards.append(c)
		var v := CardView.new()
		add_child(v)
		v.setup(c, card_size)
		views[c.uid] = v


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		layout(false)


## Recompute card size and positions (call after changing piles or the screen size).
func layout(animated := false) -> void:
	if layout_callback.is_valid():
		layout_callback.call(self)
	for v in views.values():
		v.resize(card_size)
	refresh(animated)


## Recompute fans and move every view to its pile position (tweened when `animated`).
## `moving` cards get a small staggered delay so a dragged run arrives in order.
func refresh(animated := true, moving: Array = []) -> void:
	for id in order:
		_fan_pile(piles[id])
	var z := 0
	var delays := {}
	for k in moving.size():
		delays[moving[k].uid] = k * 0.02
	for id in order:
		var p: RefCounted = piles[id]
		for i in p.cards.size():
			var c = p.cards[i]
			var v: CardView = views.get(c.uid)
			if v == null:
				continue
			move_child(v, -1)
			v.sync_face(animated)
			_place(v, p.card_pos(i), animated, delays.get(c.uid, 0.0))
			z += 1
	queue_redraw()


func _fan_pile(p: RefCounted) -> void:
	match p.fan:
		Pile.Fan.DOWN:
			p.offsets = CardLayout.fan_down(p.cards, card_size.y, p.max_extent if p.max_extent > 0.0 else 100000.0)
		Pile.Fan.RIGHT:
			var step: float = card_size.x * p.fan_step
			if p.max_extent > 0.0:
				step = minf(step, (p.max_extent - card_size.x) / maxf(1.0, p.right_visible - 1.0))
			p.offsets = CardLayout.fan_right(p.cards.size(), p.right_visible, step)
		_:
			var o := PackedVector2Array()
			for i in p.cards.size():
				o.append(Vector2.ZERO)
			p.offsets = o


func _place(v: CardView, target: Vector2, animated: bool, delay := 0.0) -> void:
	if v.move_tween:
		v.move_tween.kill()
	if not animated or not is_inside_tree() or (v.position.distance_to(target) < 0.5 and absf(v.rotation) < 0.01):
		v.position = target
		v.rotation = 0.0
		v.z_index = 0
		v.lift = 0.0
		return
	v.z_index = 30
	v.lift = maxf(v.lift, 0.55)
	v.move_tween = create_tween()
	if delay > 0.0:
		v.move_tween.tween_interval(delay)
	v.move_tween.tween_property(v, "position", target, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	v.move_tween.parallel().tween_property(v, "lift", 0.0, 0.24)
	v.move_tween.parallel().tween_property(v, "rotation", 0.0, 0.2)
	v.move_tween.tween_callback(func():
		v.z_index = 0
		v.settle())


# --- moves and undo ----------------------------------------------------------

## Move pile.cards[index:] onto `to`. `record` pushes an undo snapshot first (pass false for
## follow-up moves made inside rules.after_move or during auto-complete).
func move_cards(from: RefCounted, index: int, to: RefCounted, record := true) -> void:
	move_list(from, from.cards.slice(index), to, record)


## Move exactly `list` (cards of `from`, in the order they should land) onto `to`. Use it when the
## order flips, e.g. Klondike drawing three cards or turning the waste back into the stock.
func move_list(from: RefCounted, list: Array, to: RefCounted, record := true) -> void:
	if record:
		push_undo()
	for c in list:
		from.cards.erase(c)
	to.cards.append_array(list)
	if rules:
		rules.after_move(self, from, to, list.size())
	if sfx:
		Feedback.sfx("place")
	refresh(true, list)
	_hint_i = 0
	moved.emit(from.id, to.id, list.size())
	changed.emit()


func push_undo() -> void:
	var snap := {"piles": {}, "faces": {}, "extra": rules.get_extra() if rules else null}
	for id in order:
		snap.piles[id] = piles[id].cards.duplicate()
	for c in cards:
		snap.faces[c.uid] = c.face_up
	undo_stack.append(snap)


func can_undo() -> bool:
	return not undo_stack.is_empty() and not busy


func undo() -> bool:
	if not can_undo():
		return false
	cancel_drag()
	var snap: Dictionary = undo_stack.pop_back()
	for id in order:
		piles[id].cards = snap.piles[id]
	for c in cards:
		c.face_up = snap.faces[c.uid]
	if rules:
		rules.set_extra(snap.extra)
	if sfx:
		Feedback.sfx("tap")
	_hint_i = 0
	clear_hint()
	refresh(true)
	changed.emit()
	return true


# --- hint and auto-complete -------------------------------------------------

## Highlight the next useful move from rules.hints(); repeated calls cycle through them.
func show_hint() -> bool:
	if busy:
		return false
	var hs: Array = rules.hints(self)
	if hs.is_empty():
		return false
	var h: Dictionary = hs[_hint_i % hs.size()]
	_hint_i += 1
	clear_hint()
	var from: RefCounted = h.from
	if h.index >= 0:
		for i in range(h.index, from.cards.size()):
			views[from.cards[i].uid].pulse()
	elif not from.cards.is_empty():
		views[from.cards.back().uid].pulse()
	var to: RefCounted = h.to
	if h.index < 0 and to == from:
		_glow_slot(to.id)
	elif to.cards.is_empty():
		_glow_slot(to.id)
	else:
		views[to.cards.back().uid].pulse()
	return true


func clear_hint() -> void:
	for v in views.values():
		v.glow = 0.0
	_slot_glow.clear()
	queue_redraw()


func _glow_slot(id: String) -> void:
	_slot_glow[id] = 1.0
	var tw := create_tween()
	for i in 3:
		tw.tween_method(func(a: float):
			_slot_glow[id] = a
			queue_redraw(), 1.0, 0.3, 0.2)
		tw.tween_method(func(a: float):
			_slot_glow[id] = a
			queue_redraw(), 0.3, 1.0, 0.2)
	tw.tween_callback(func():
		_slot_glow.erase(id)
		queue_redraw())


## Play rules.auto_step() moves one by one until it returns {} (solved or stuck).
func auto_complete(step_time := 0.1) -> void:
	if busy:
		return
	cancel_drag()
	clear_hint()
	busy = true
	push_undo()
	_auto_step(step_time)


func _auto_step(step_time: float) -> void:
	var m: Dictionary = rules.auto_step(self)
	if m.is_empty():
		busy = false
		auto_complete_finished.emit(rules.is_won(self))
		return
	if m.has("action"):
		m.action.call()  # a non-card step such as drawing from the stock
	else:
		move_cards(m.from, m.index, m.to, false)
	get_tree().create_timer(step_time).timeout.connect(_auto_step.bind(step_time))


# --- input -------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	# One touch is delivered as a real event plus an emulated twin (see CLAUDE.md): act on the real one.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		if event is InputEventMouseButton or event is InputEventMouseMotion \
				or event is InputEventScreenTouch or event is InputEventScreenDrag:
			accept_event()
		return
	if not input_enabled:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_pointer(event.pressed, event.position)
			accept_event()
	elif event is InputEventScreenTouch:
		if event.index == 0:
			_pointer(event.pressed, event.position)
			accept_event()
	elif event is InputEventMouseMotion or event is InputEventScreenDrag:
		_pointer_move(event.position)
		accept_event()


func _pointer(pressed: bool, pos: Vector2) -> void:
	if busy:
		if pressed and (not _fall.is_empty() or not _fall_queue.is_empty()):
			_finish_win()  # a tap skips the cascade
		return
	if pressed:
		_press = {"hit": hit_test(pos), "pos": pos}
		var hit: Dictionary = _press.hit
		if not hit.is_empty() and hit.index >= 0 and rules.can_pick(self, hit.pile, hit.index):
			_press.pick = true
			_press.grab = pos - hit.pile.card_pos(hit.index)
		return
	if _press.is_empty():
		return
	var press := _press
	_press = {}
	if not _drag.is_empty():
		_drop(pos)
	else:
		_tap(press.hit)


func _pointer_move(pos: Vector2) -> void:
	if busy:
		return
	if _drag.is_empty():
		if _press.is_empty() or not _press.get("pick", false):
			return
		if pos.distance_to(_press.pos) < DRAG_START:
			return
		_begin_drag(_press.hit, _press.grab)
	var first: Vector2 = pos - _drag.grab
	first.x = clampf(first.x, 0.0, maxf(0.0, size.x - card_size.x))
	first.y = clampf(first.y, 0.0, maxf(0.0, size.y - card_size.y))
	var base: Vector2 = _drag.pile.offsets[_drag.index]
	var tilt := clampf((pos.x - _drag.get("last", pos).x) * 0.012, -0.16, 0.16)
	_drag.last = pos
	for k in _drag.cards.size():
		var v: CardView = views[_drag.cards[k].uid]
		v.position = first + _drag.pile.offsets[_drag.index + k] - base
		v.rotation = lerpf(v.rotation, tilt, 0.3)


func _begin_drag(hit: Dictionary, grab: Vector2) -> void:
	clear_hint()
	var p: RefCounted = hit.pile
	_drag = {"pile": p, "index": hit.index, "cards": p.cards.slice(hit.index), "grab": grab}
	for k in _drag.cards.size():
		var v: CardView = views[_drag.cards[k].uid]
		if v.move_tween:
			v.move_tween.kill()
		v.z_index = 100 + k
		v.lift = 1.0
		move_child(v, -1)
	if sfx:
		Feedback.sfx("select")


func cancel_drag() -> void:
	if _drag.is_empty():
		return
	_drag = {}
	refresh(true)


func _drop(pos: Vector2) -> void:
	var d := _drag
	_drag = {}
	var first_v: CardView = views[d.cards[0].uid]
	var rect := Rect2(first_v.position, card_size)
	var best: Array = []
	for id in order:
		var p: RefCounted = piles[id]
		if p == d.pile:
			continue
		var r := _drop_rect(p)
		var score := rect.intersection(r).get_area()
		if r.has_point(pos):
			score += card_size.x * card_size.y
		if score > card_size.x * card_size.y * 0.1:
			best.append([score, p])
	best.sort_custom(func(a, b): return a[0] > b[0])
	for b in best:
		if rules.can_drop(self, d.cards, d.pile, b[1]):
			move_cards(d.pile, d.index, b[1])
			return
	if sfx and not best.is_empty():
		Feedback.sfx("locked")
	refresh(true)  # snap back


func _drop_rect(p: RefCounted) -> Rect2:
	if p.cards.is_empty():
		return Rect2(p.origin, card_size)
	if p.fan == Pile.Fan.DOWN:
		return p.extent_rect(card_size)
	return Rect2(p.card_pos(p.cards.size() - 1), card_size)


func _tap(hit: Dictionary) -> void:
	if hit.is_empty():
		return
	var p: RefCounted = hit.pile
	var i: int = hit.index
	if i >= 0:
		var uid: int = p.cards[i].uid
		var now := Time.get_ticks_msec()
		var dbl := uid == _last_tap_uid and now - _last_tap_ms < DOUBLE_TAP_MS
		_last_tap_uid = uid
		_last_tap_ms = now
		if dbl and p.cards[i].face_up:
			_last_tap_uid = -1
			_auto_move(p, i)
			return
	if rules.on_tap(self, p, i):
		clear_hint()
		return
	if tap_to_move and i >= 0 and p.cards[i].face_up:
		_auto_move(p, i)


func _auto_move(p: RefCounted, i: int) -> void:
	if not rules.can_pick(self, p, i):
		return
	var to = rules.auto_target(self, p, i)
	if to == null:
		if sfx:
			Feedback.sfx("locked")
		nudge(p.cards[i])
		return
	move_cards(p, i, to)


## Sparkle burst on top of pile `id` (foundation completes, a card lands somewhere special).
func sparkle(id: String, amount := 14) -> void:
	var p: RefCounted = piles[id]
	var c: Vector2 = (p.card_pos(p.cards.size() - 1) if not p.cards.is_empty() else p.origin) + card_size / 2.0
	FX.burst(self, c, [FX.LEMON, FX.TANGERINE, Color.WHITE], amount, 0.6)


## Little horizontal wobble: "that card cannot go anywhere".
func nudge(c: RefCounted) -> void:
	var v: CardView = views.get(c.uid)
	if v == null or v.move_tween and v.move_tween.is_running():
		return
	var home := v.position
	v.move_tween = create_tween()
	for dx in [8.0, -8.0, 5.0, 0.0]:
		v.move_tween.tween_property(v, "position:x", home.x + dx, 0.05)


## {"pile": Pile, "index": int} under `pos` (index -1 = the empty slot), or {}.
func hit_test(pos: Vector2) -> Dictionary:
	for id in order:
		var p: RefCounted = piles[id]
		for i in range(p.cards.size() - 1, -1, -1):
			var cp: Vector2 = p.card_pos(i)
			var r := Rect2(cp, card_size)
			if i < p.cards.size() - 1:
				var nxt: Vector2 = p.card_pos(i + 1)
				if p.fan == Pile.Fan.DOWN:
					r.size.y = nxt.y - cp.y
				elif p.fan == Pile.Fan.RIGHT:
					r.size.x = nxt.x - cp.x
				else:
					continue
				if r.size.x < 1.0 or r.size.y < 1.0:
					continue
			if r.has_point(pos):
				return {"pile": p, "index": i}
		if p.cards.is_empty() and Rect2(p.origin, card_size).has_point(pos):
			return {"pile": p, "index": -1}
	return {}


# --- win cascade -------------------------------------------------------------

## Foundation cards launch one after another, bounce off the floor and leave trails. Emits
## win_animation_finished when the cards have left the table (a tap skips it).
func play_win() -> void:
	cancel_drag()
	clear_hint()
	busy = true
	_fall_queue.clear()
	_fall.clear()
	var stacks: Array = []
	for p in piles_of("foundation"):
		stacks.append(p.cards.duplicate())
	var more := true
	while more:
		more = false
		for s in stacks:
			if not s.is_empty():
				_fall_queue.append(views[s.pop_back().uid])
				more = true
	_fall_t = 0.0
	_fall_total = 0.0
	if sfx:
		Feedback.sfx("star")
	FX.burst(self, Vector2(size.x / 2.0, size.y * 0.3), [FX.LEMON, FX.TANGERINE, Color("#ff5d8f"), Color("#4fc3f7")], 40, 1.3)
	set_process(true)


func _process(delta: float) -> void:
	if _fall.is_empty() and _fall_queue.is_empty():
		set_process(false)
		return
	_fall_total += delta
	_fall_t -= delta
	if _fall_t <= 0.0 and not _fall_queue.is_empty():
		_fall_t = 0.065
		var v: CardView = _fall_queue.pop_front()
		if v.move_tween:
			v.move_tween.kill()
		v.z_index = 200 + _fall.size()
		v.lift = 0.6
		var dir := -1.0 if randf() < 0.5 else 1.0
		_fall.append({"v": v, "vel": Vector2(dir * randf_range(220.0, 520.0), randf_range(-900.0, -300.0)), "g": 0.0})
	for f in _fall:
		var v: CardView = f.v
		f.vel.y += 2000.0 * delta
		v.position += f.vel * delta
		if v.position.y + card_size.y > size.y:
			v.position.y = size.y - card_size.y
			f.vel.y = -absf(f.vel.y) * 0.76
			if absf(f.vel.y) < 140.0:
				f.vel.y = -420.0
		f.g -= delta
		if f.g <= 0.0:
			f.g = 0.035
			_ghost(v)
	_fall = _fall.filter(func(f):
		var x: float = f.v.position.x
		var alive := x > -card_size.x and x < size.x
		if not alive:
			f.v.visible = false
		return alive)
	if _fall_total > 6.0:
		_finish_win()
	elif _fall.is_empty() and _fall_queue.is_empty():
		_finish_win()


func _ghost(v: CardView) -> void:
	if _ghosts > 140:
		return
	var g := CardView.new()
	add_child(g)
	g.setup(v.card, card_size)
	g.position = v.position
	g.z_index = 150
	g.modulate.a = 0.5
	_ghosts += 1
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func():
		_ghosts -= 1
		g.queue_free())


func _finish_win() -> void:
	for f in _fall:
		f.v.visible = false
	for v in _fall_queue:
		v.visible = false
	_fall.clear()
	_fall_queue.clear()
	busy = false
	set_process(false)
	win_animation_finished.emit()


## Stop cascades and tweens (new deal / leaving the screen).
func stop_effects() -> void:
	_fall.clear()
	_fall_queue.clear()
	busy = false
	set_process(false)


# --- slots ---------------------------------------------------------------------

func _draw() -> void:
	var font := FX.font()
	var rad := card_size.x * 0.12
	for id in order:
		var p: RefCounted = piles[id]
		if not p.show_slot:
			continue
		var r := Rect2(p.origin, card_size)
		# recessed well: dark gradient, bright lower lip, darker top edge
		draw_style_box(_slot_box(rad), r.grow(1.5))
		FX.draw_round_gradient(self, r, rad, Color(0, 0, 0.1, 0.5), Color(0, 0, 0.1, 0.22))
		var pts := FX.round_rect_points(r, rad)
		pts.append(pts[0])
		draw_polyline(pts, Color(FX.LEMON, 0.22), 1.6, true)
		var inner := FX.round_rect_points(r.grow(-4.0), rad * 0.8)
		inner.append(inner[0])
		draw_polyline(inner, Color(1, 1, 1, 0.07), 1.0, true)
		if p.cards.is_empty():
			if p.recycle:
				_draw_recycle(r.get_center(), card_size.x * 0.22)
			elif p.slot_label != "":
				var c := r.get_center()
				draw_arc(c, card_size.x * 0.27, 0.0, TAU, 32, Color(FX.LEMON, 0.18), 2.0, true)
				FX.draw_text_centered(self, c, p.slot_label, int(card_size.x * 0.38), Color(FX.LEMON, 0.3), font)
		var g: float = _slot_glow.get(id, 0.0)
		if g > 0.0:
			draw_polyline(pts, Color(FX.LEMON, g), 4.0, true)
			FX.draw_glow(self, r.grow(card_size.x * 0.25), Color(FX.LEMON, 0.3 * g))


static var _slot_sb := StyleBoxFlat.new()


static func _slot_box(rad: float) -> StyleBoxFlat:
	_slot_sb.set_corner_radius_all(int(rad))
	_slot_sb.bg_color = Color(1, 1, 1, 0.05)
	return _slot_sb


func _draw_recycle(c: Vector2, r: float) -> void:
	var col := Color(1, 1, 1, 0.45)
	draw_arc(c, r, -PI * 0.2, PI * 1.5, 32, col, 4.0, true)
	var tip := c + Vector2(cos(-PI * 0.2), sin(-PI * 0.2)) * r
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-r * 0.5, -r * 0.15), tip + Vector2(r * 0.4, -r * 0.25),
		tip + Vector2(r * 0.15, r * 0.5)]), col)
