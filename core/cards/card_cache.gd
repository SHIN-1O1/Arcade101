extends Node
## Renders all 52 card faces and the back once into one atlas texture at the card's real pixel
## size, so a table of cards costs one textured quad each per frame instead of hundreds of
## vector shapes, and faces can carry fine detail (paper grain, guilloche).
## CardView uses it automatically through CardView.cache(); it falls back to vector drawing until
## the atlas is ready, and for good where the GPU cannot be read back (headless runs).

const CardArt := preload("res://core/cards/card_art.gd")

const COLS := 8
const ROWS := 7       ## 8 x 7 = 56 cells: codes 0..51 faces, 52 back
const PAD := 3        ## transparent gutter around each cell so filtering never bleeds
const BACK := 52
const MAX_W := 360    ## cap a cell's pixel width (very large tablets)

signal rebuilt

var tex: Texture2D        ## null until the first atlas is ready
var cell := Vector2i.ZERO ## pixel size of one card in `tex`
var failed := false
var _want := Vector2i.ZERO
var _busy := false


## Card pixel size the views want. Rebuilds (once, deferred) when it changes.
func request(px: Vector2i) -> void:
	if failed or px.x < 8 or px.y < 8:
		return
	px.x = mini(px.x, MAX_W)
	px.y = mini(px.y, int(MAX_W * 1.6))
	if px == _want:
		return
	_want = px
	if not _busy:
		_build.call_deferred()


## Region of `code` (0..51 = suit * 13 + rank - 1, or BACK) inside `tex`.
func region(code: int) -> Rect2:
	var stride := cell + Vector2i(PAD * 2, PAD * 2)
	return Rect2(Vector2((code % COLS) * stride.x + PAD, (code / COLS) * stride.y + PAD), Vector2(cell))


func ready_for(px_w: float) -> bool:
	return tex != null and absf(cell.x - minf(px_w, MAX_W)) <= 1.5


func _build() -> void:
	_busy = true
	while not failed and _want != cell:
		var want := _want
		if DisplayServer.get_name() == "headless":
			failed = true
			break
		var vp := SubViewport.new()
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.size = Vector2i(COLS * (want.x + PAD * 2), ROWS * (want.y + PAD * 2))
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var painter := _Painter.new()
		painter.cell = want
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
		cell = want
	_busy = false
	if not failed:
		rebuilt.emit()


class _Painter extends Control:
	var cell := Vector2i.ZERO

	func _draw() -> void:
		CardArt.detail = true
		var stride := cell + Vector2i(PAD * 2, PAD * 2)
		for code in BACK + 1:
			var r := Rect2(Vector2((code % COLS) * stride.x + PAD, (code / COLS) * stride.y + PAD), Vector2(cell))
			if code == BACK:
				CardArt.draw_back(self, r, 0.0, false)
			else:
				CardArt.draw_face(self, r, code / 13, code % 13 + 1, 0.0, false)
		CardArt.detail = false
