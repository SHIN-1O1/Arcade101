extends RefCounted
## One playing card (data only). Load with: const Card := preload("res://core/cards/card.gd")
## Suits: 0 spades, 1 hearts, 2 diamonds, 3 clubs. Rank: 1 (ace) .. 13 (king).
## `uid` is unique per card within a deal (multi-deck games have duplicate suit/rank pairs),
## `code()` is the compact 0..51 id (suit * 13 + rank - 1) used in levels.json decks.

const SPADES := 0
const HEARTS := 1
const DIAMONDS := 2
const CLUBS := 3
const RANK_TEXT := ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

var rank := 1
var suit := 0
var face_up := false
var uid := 0


static func from_code(code: int, new_uid := -1) -> RefCounted:
	var c: RefCounted = (load("res://core/cards/card.gd") as GDScript).new()
	c.suit = code / 13
	c.rank = code % 13 + 1
	c.uid = new_uid if new_uid >= 0 else code
	return c


func code() -> int:
	return suit * 13 + rank - 1


func is_red() -> bool:
	return suit == HEARTS or suit == DIAMONDS


func rank_text() -> String:
	return RANK_TEXT[rank]


func _to_string() -> String:
	return "%s%s%s" % [rank_text(), "SHDC"[suit], "" if face_up else "~"]
