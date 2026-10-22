extends Control
## On-screen card: draws a Card's face or back, flips with a squash animation, glows for hints.
## Created and moved by CardTable; games rarely touch it directly.

const Card := preload("res://core/cards/card.gd")
const CardArt := preload("res://core/cards/card_art.gd")
const FX := preload("res://core/fx.gd")

var card: RefCounted
var shown_up := false  ## what is drawn right now (lags card.face_up during a flip)
var lift := 0.0:       ## 0..1, dragged cards cast a bigger shadow
	set(v):
		lift = v
		queue_redraw()
var glow := 0.0:       ## 0..1 pulse used by hints
	set(v):
		glow = v
		queue_redraw()
var dim := 0.0:        ## 0..1 darkens (cards that cannot be picked up)
	set(v):
		dim = v
		queue_redraw()
var move_tween: Tween
var _flip_tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # the CardTable does hit testing


func setup(c: RefCounted, card_size: Vector2) -> void:
	card = c
	shown_up = c.face_up
	size = card_size
	pivot_offset = card_size / 2.0
	queue_redraw()


func resize(card_size: Vector2) -> void:
	size = card_size
	pivot_offset = card_size / 2.0
	queue_redraw()


## Make the drawn side match card.face_up, with a flip animation when `animated`.
func sync_face(animated: bool) -> void:
	if shown_up == card.face_up:
		return
	if not animated or not is_inside_tree():
		shown_up = card.face_up
		scale.x = 1.0
		queue_redraw()
		return
	if _flip_tween:
		_flip_tween.kill()
	_flip_tween = create_tween()
	_flip_tween.tween_property(self, "scale:x", 0.04, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_flip_tween.tween_callback(func():
		shown_up = card.face_up
		queue_redraw())
	_flip_tween.tween_property(self, "scale:x", 1.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Landing squash: the card presses down a touch and springs back.
func settle() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.05, 0.95), 0.06).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A short pulse (hint). Safe to call repeatedly.
func pulse(times := 3) -> void:
	var tw := create_tween()
	for i in times:
		tw.tween_property(self, "glow", 1.0, 0.18)
		tw.tween_property(self, "glow", 0.25, 0.18)
	tw.tween_property(self, "glow", 0.0, 0.25)


func _draw() -> void:
	if card == null:
		return
	var r := Rect2(Vector2.ZERO, size)
	if shown_up:
		CardArt.draw_face(self, r, card.suit, card.rank, lift)
	else:
		CardArt.draw_back(self, r, lift)
	if dim > 0.0:
		FX.draw_round_gradient(self, r, size.x * 0.12, Color(0, 0, 0.1, 0.4 * dim), Color(0, 0, 0.1, 0.4 * dim))
	if glow > 0.0:
		var pts := FX.round_rect_points(r.grow(2.0), size.x * 0.13)
		pts.append(pts[0])
		draw_polyline(pts, Color(FX.LEMON, glow), 4.0, true)
		FX.draw_glow(self, r.grow(size.x * 0.25), Color(FX.LEMON, 0.35 * glow))
