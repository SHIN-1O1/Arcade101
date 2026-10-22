extends RefCounted
## A stack of cards on the table with a layout rule. Load with: const Pile := preload("res://core/cards/pile.gd")
## `kind` is free-form ("tableau", "foundation", "stock", "waste", "cell"); games' rules switch on it.

enum Fan { NONE, DOWN, RIGHT }

var id := ""
var kind := ""
var cards: Array = []
var fan: int = Fan.NONE
var origin := Vector2.ZERO   ## top-left of the slot, in table coordinates (set by the game's layout)
var max_extent := 0.0        ## DOWN fan: height available for the whole pile; RIGHT fan: width
var fan_step := 0.3          ## RIGHT fan: spread per card as a fraction of card width
var right_visible := 3       ## RIGHT fan: how many top cards are spread out
var slot_label := ""         ## faint letter in the empty slot ("A", "K"...)
var show_slot := true        ## draw the empty-slot outline
var recycle := false         ## draw a "turn over" arrow in the empty slot (stock)
var offsets := PackedVector2Array()  ## per card, from origin; filled by CardTable.layout()


func is_empty() -> bool:
	return cards.is_empty()


func top():
	return cards.back() if not cards.is_empty() else null


func card_pos(i: int) -> Vector2:
	return origin + (offsets[i] if i < offsets.size() else Vector2.ZERO)


## Rect of the slot plus every card, used for drop targets and hit tests.
func extent_rect(card_size: Vector2) -> Rect2:
	var r := Rect2(origin, card_size)
	if not cards.is_empty():
		r = r.merge(Rect2(card_pos(cards.size() - 1), card_size))
	return r
