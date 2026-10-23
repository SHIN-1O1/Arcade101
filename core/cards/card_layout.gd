extends RefCounted
## Layout maths shared by card games. Load with: const CardLayout := preload("res://core/cards/card_layout.gd")
## Everything adapts to the width/height it is given, so 9:16 up to 9:21 portrait phones all fit.

const ASPECT := 1.4  ## card height / width


## Card size so `columns` cards plus gaps fit in `width` (never wider than max_w).
static func card_size(width: float, columns: int, margin: float, gap: float, max_w := 130.0) -> Vector2:
	var w := minf((width - margin * 2.0 - gap * (columns - 1)) / columns, max_w)
	return Vector2(floorf(w), floorf(w * ASPECT))


## X of column `col` (0-based) so the columns are centred in `width`.
static func column_x(width: float, columns: int, cs: Vector2, gap: float, col: int) -> float:
	var total := columns * cs.x + (columns - 1) * gap
	return (width - total) / 2.0 + col * (cs.x + gap)


## Offsets (from the pile origin) for a downward fan. Face-down cards overlap tighter than face-up ones.
## If the pile would be taller than `avail_h` every step shrinks together (down to a minimum peek).
static func fan_down(cards: Array, card_h: float, avail_h: float, down_frac := 0.17, up_frac := 0.4) -> PackedVector2Array:
	var steps: Array = []
	var total := 0.0
	for i in cards.size() - 1:
		var s := card_h * (up_frac if cards[i].face_up else down_frac)
		steps.append(s)
		total += s
	var scale := 1.0
	var room := avail_h - card_h
	if total > room and total > 0.0:
		scale = maxf(0.0, room) / total
	var out := PackedVector2Array()
	var y := 0.0
	out.append(Vector2.ZERO)
	for s in steps:
		y += maxf(s * scale, card_h * 0.07)
		out.append(Vector2(0, y))
	return out


## Spread the last `visible` cards to the right by `step`; the rest sit on the base slot.
static func fan_right(count: int, visible: int, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in count:
		var k := i - (count - visible)
		out.append(Vector2(step * k if k > 0 else 0.0, 0))
	return out
