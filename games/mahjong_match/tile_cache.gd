extends Node
## Renders every resting tile look (33 faces x free / blocked) once into one atlas texture at the
## tile's real pixel size, so a board costs one textured quad per tile each frame instead of a few
## dozen vector shapes (a 144-tile board went from ~4,000 draw calls a frame to a few hundred).
## Same approach as core/cards/card_cache.gd. Tiles fall back to vector drawing until the atlas is
## ready, while selected / hinted / shaking, and for good where the GPU cannot be read back (headless).

const FACES := 33  ## keys 0..24, then 4 flower and 4 season variants
const COLS := 11
const ROWS := 6    ## 11 x 6 = 66 cells: free faces, then blocked faces
const PAD := 4.0   ## margin around the tile body, in board units (AA rims, side layers)
const MAX_SCALE := 3.0

signal rebuilt

var tex: Texture2D  ## null until the first atlas is ready
var failed := false
var ts := Vector2.ZERO  ## tile size and thickness (board units) the atlas was built for
var tt := 0.0
var k := 0.0            ## pixels per board unit in `tex`
var _want := Vector3.ZERO  # ts.x, tt, k
var _busy := false
var _paint: Callable    # func(ci, ts, tt, key, variant, free) draws a resting tile centred on the origin


func _init(paint: Callable) -> void:
	_paint = paint


static func face_index(key: int, variant: int) -> int:
	return key if key < 25 else 25 + (key - 25) * 4 + variant % 4


## Board-unit rect of one cell, relative to the tile centre.
static func cell_rect(tile: Vector2, thick: float) -> Rect2:
	return Rect2(-tile / 2.0 - Vector2(PAD, PAD), tile + Vector2(thick, thick) + Vector2(PAD, PAD) * 2.0)


func ready_for(tile: Vector2, thick: float, scale: float) -> bool:
	return tex != null and ts.is_equal_approx(tile) and is_equal_approx(tt, thick) \
		and absf(k - minf(scale, MAX_SCALE)) < 0.01


## Size the tiles want. Rebuilds (once, deferred) when it changes.
func request(tile: Vector2, thick: float, scale: float) -> void:
	if failed or tile.x < 4.0:
		return
	var want := Vector3(tile.x, thick, minf(scale, MAX_SCALE))
	if want.is_equal_approx(_want):
		return
	_want = want
	if not _busy:
		_build.call_deferred(tile.y / tile.x)


func region(key: int, variant: int, free: bool) -> Rect2:
	var cell := _cell_px(ts, tt, k)
	var i := face_index(key, variant) + (0 if free else FACES)
	return Rect2(Vector2((i % COLS) * cell.x, (i / COLS) * cell.y), Vector2(cell))


static func _cell_px(tile: Vector2, thick: float, scale: float) -> Vector2i:
	return Vector2i((cell_rect(tile, thick).size * scale).ceil())


func _build(aspect: float) -> void:
	_busy = true
	while not failed and not _want.is_equal_approx(Vector3(ts.x, tt, k)):
		var want := _want
		if DisplayServer.get_name() == "headless":
			failed = true
			break
		var tile := Vector2(want.x, want.x * aspect)
		var cell := _cell_px(tile, want.y, want.z)
		var vp := SubViewport.new()
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.size = Vector2i(COLS * cell.x, ROWS * cell.y)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var painter := _Painter.new()
		painter.paint = _paint
		painter.tile = tile
		painter.thick = want.y
		painter.scale_k = want.z
		painter.cell = cell
		painter.off = -cell_rect(tile, want.y).position  # tile centre inside its cell, in board units
		painter.size = Vector2(vp.size)
		vp.add_child(painter)
		add_child(vp)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		vp.queue_free()
		if img == null or img.is_empty():
			failed = true
			break
		tex = ImageTexture.create_from_image(img)
		ts = tile
		tt = want.y
		k = want.z
	_busy = false
	if not failed:
		rebuilt.emit()


class _Painter extends Control:
	var paint: Callable
	var tile := Vector2.ZERO
	var thick := 0.0
	var scale_k := 1.0
	var cell := Vector2i.ZERO
	var off := Vector2.ZERO

	func _draw() -> void:
		for i in FACES * 2:
			var f := i % FACES
			var key := f if f < 25 else 25 + (f - 25) / 4
			var variant := 0 if f < 25 else (f - 25) % 4
			var o := Vector2((i % COLS) * cell.x, (i / COLS) * cell.y)
			draw_set_transform(o + off * scale_k, 0.0, Vector2(scale_k, scale_k))
			paint.call(self, tile, thick, key, variant, i < FACES)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
