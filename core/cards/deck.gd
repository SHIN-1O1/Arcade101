extends RefCounted
## Deck building and seeded shuffling. Load with: const Deck := preload("res://core/cards/deck.gd")
## Same seed => same deal, so levels replay identically. Games that need guaranteed-winnable
## deals store the shuffled `codes` in levels.json instead (see games/klondike).

const Card := preload("res://core/cards/card.gd")


## Ordered card codes 0..51 for `decks` decks. suits < 4 keeps only the first `suits` suits
## and repeats them to fill each deck (Spider: 1 or 2 suits across 104 cards).
static func codes(decks := 1, suits := 4) -> Array:
	var out: Array = []
	for d in decks:
		for i in 52:
			var s := (i / 13) % suits if suits < 4 else i / 13
			out.append(s * 13 + i % 13)
	return out


## Fisher-Yates shuffle of a copy, driven by a seeded RNG.
static func shuffled(list: Array, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var a := list.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
	return a


## Card objects for `code_list`; uid = position in the list, all face down.
static func make_cards(code_list: Array) -> Array:
	var out: Array = []
	for i in code_list.size():
		out.append(Card.from_code(int(code_list[i]), i))
	return out


## Same deal with suits relabelled (perm[old] = new). Keeps Klondike solvability as long as perm is a bijection.
static func permute_suits(code_list: Array, perm: Array) -> Array:
	var out: Array = []
	for c in code_list:
		out.append(int(perm[int(c) / 13]) * 13 + int(c) % 13)
	return out
