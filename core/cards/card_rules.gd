extends RefCounted
## The move-validation interface. Each card game subclasses this and passes an instance to
## CardTable.rules. Load with: const CardRules := preload("res://core/cards/card_rules.gd")
## `t` is the CardTable (use t.piles / t.pile("id")), piles are Pile objects, cards are Card objects.
## A "move" everywhere is {"from": Pile, "index": int, "to": Pile}: cards from[index:] go onto `to`.


## May the player pick up from[index:]? Default: only a face-up top card.
func can_pick(_t, pile, index: int) -> bool:
	return index == pile.cards.size() - 1 and pile.cards[index].face_up


## May `cards` (already lifted from `from`, in order) be dropped on `to`?
func can_drop(_t, _cards: Array, _from, _to) -> bool:
	return false


## A tap (no drag) on a pile; index is -1 for an empty slot. Return true if handled
## (e.g. Klondike's stock draws a card). Unhandled taps fall through to tap-to-move.
func on_tap(_t, _pile, _index: int) -> bool:
	return false


## Where double-tap (or tap-to-move) sends pile.cards[index:]. Return the destination Pile or null.
func auto_target(_t, _pile, _index: int):
	return null


## Called inside CardTable.move_cards after the cards landed on `to`: flip exposed cards, score,
## clear completed runs (call t.move_cards(..., false) for follow-up moves so they share the undo step).
func after_move(_t, _from, _to, _count: int) -> void:
	pass


## Useful moves, best first, for the hint button. May include {"from": p, "index": -1, "to": p} to
## point at a pile itself (e.g. the stock).
func hints(_t) -> Array:
	return []


## The next move of auto-complete, or {} when it is finished or stuck. Instead of a move it may
## return {"action": Callable} for a step that is not a card move (Klondike's stock draw).
func auto_step(_t) -> Dictionary:
	return {}


func is_won(_t) -> bool:
	return false


## Rules-owned state (counters, pass counts...) saved with every undo snapshot.
func get_extra() -> Variant:
	return null


func set_extra(_value) -> void:
	pass
