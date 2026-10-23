extends Control
## On-screen card: draws a Card's face or back, flips with a squash animation, glows for hints.
## Created and moved by CardTable; games rarely touch it directly.

const Card := preload("res://core/cards/card.gd")
const CardArt := preload("res://core/cards/card_art.gd")
const FX := preload("res://core/fx.gd")
const CardCache := preload("res://core/cards/card_cache.gd")

static var _cache: CardCache
static var _premult: CanvasItemMaterial

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
		if _art:
			var k := 1.0 - 0.4 * v
			_art.self_modulate = Color(k, k, k + 0.1 * v)
var buried := false:   ## exactly under another card: skip the shadow so stacks do not darken
	set(v):
		if v != buried:
			buried = v
			queue_redraw()
var move_tween: Tween
var _flip_tween: Tween
var _art: Control  # draws the cached atlas image above this node's shadow


## The shared CardCache (created on first use, lives under the scene tree root).
static func cache() -> CardCache:
	if _cache == null or not is_instance_valid(_cache):
		_cache = CardCache.new()
		_cache.name = "CardCache"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_cache)
	return _cache


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # the CardTable does hit testing
	if _premult == null:
		_premult = CanvasItemMaterial.new()
		_premult.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA  # the atlas is rendered premultiplied
	_art = _Art.new()
	_art.material = _premult
	add_child(_art)


func _enter_tree() -> void:
	var c := cache()
	if not c.rebuilt.is_connected(_on_atlas):
		c.rebuilt.connect(_on_atlas)
	_request()


func _exit_tree() -> void:
	if _cache and is_instance_valid(_cache) and _cache.rebuilt.is_connected(_on_atlas):
		_cache.rebuilt.disconnect(_on_atlas)


func _on_atlas() -> void:
	queue_redraw()
	_art.queue_redraw()


func _px_width() -> float:
	return size.x * get_tree().root.get_final_transform().get_scale().x


func _request() -> void:
	if is_inside_tree():
		var k := get_tree().root.get_final_transform().get_scale().x
		cache().request(Vector2i(roundi(size.x * k), roundi(size.y * k)))


func _use_atlas() -> bool:
	return is_inside_tree() and _cache != null and _cache.ready_for(_px_width())


func setup(c: RefCounted, card_size: Vector2) -> void:
	card = c
	shown_up = c.face_up
	size = card_size
	pivot_offset = card_size / 2.0
	_art.size = card_size
	_request()
	queue_redraw()
	_art.queue_redraw()


func resize(card_size: Vector2) -> void:
	size = card_size
	pivot_offset = card_size / 2.0
	_art.size = card_size
	_request()
	queue_redraw()
	_art.queue_redraw()


## Make the drawn side match card.face_up, with a flip animation when `animated`.
func sync_face(animated: bool) -> void:
	if shown_up == card.face_up:
		return
	if not animated or not is_inside_tree():
		shown_up = card.face_up
		scale.x = 1.0
		queue_redraw()
		_art.queue_redraw()
		return
	if _flip_tween:
		_flip_tween.kill()
	_flip_tween = create_tween()
	_flip_tween.tween_property(self, "scale:x", 0.04, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_flip_tween.tween_callback(func():
		shown_up = card.face_up
		queue_redraw()
		_art.queue_redraw())
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
	if not buried or lift > 0.0:
		CardArt.draw_shadow(self, r, lift)
	if glow > 0.0:
		var pts := FX.round_rect_points(r.grow(2.0), size.x * 0.1)
		pts.append(pts[0])
		draw_polyline(pts, Color(FX.LEMON, glow), 5.0, true)
		FX.draw_glow(self, r.grow(size.x * 0.25), Color(FX.LEMON, 0.35 * glow))
	if _use_atlas():
		return
	if shown_up:
		CardArt.draw_face(self, r, card.suit, card.rank, lift, false)
	else:
		CardArt.draw_back(self, r, lift, false)
	if dim > 0.0:
		FX.draw_round_gradient(self, r, CardArt.corner_radius(size.x), Color(0, 0, 0.1, 0.4 * dim), Color(0, 0, 0.1, 0.4 * dim))


func _draw_art(ci: CanvasItem) -> void:
	if card == null or not _use_atlas():
		return
	var code: int = card.code() if shown_up else CardCache.BACK
	ci.draw_texture_rect_region(_cache.tex, Rect2(Vector2.ZERO, size), _cache.region(code))


## Child that shows the atlas image (premultiplied blend) on top of the parent's shadow.
class _Art extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		get_parent()._draw_art(self)
