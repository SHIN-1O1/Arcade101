extends "res://core/cards/card_rules.gd"
## FreeCell rules on top of the card kit. Piles: "c0".."c3" (kind cell, one card each), "f0".."f3" (kind foundation),
## "t0".."t7" (kind tableau, all cards face up). Also owns the per-deal counters so undo restores them.

var moves := 0               ## player moves this deal (a multi-card move is one move; automatic foundation moves are free)
var points := 0              ## endless scoring: 10 per card on a foundation
var counting := true         ## false while auto-complete plays
var auto_foundation := true  ## after each move send "safe" cards up to the foundations
var _in_auto := false


func get_extra() -> Variant:
	return [moves, points]


func set_extra(v) -> void:
	moves = v[0]
	points = v[1]


# --- capacity ----------------------------------------------------------------------

static func free_cells(t) -> int:
	var n := 0
	for p in t.piles_of("cell"):
		if p.cards.is_empty():
			n += 1
	return n


static func empty_columns(t, skip = null) -> int:
	var n := 0
	for p in t.piles_of("tableau"):
		if p != skip and p.cards.is_empty():
			n += 1
	return n


## Most cards one move can carry: (free cells + 1) * 2^(empty columns), the destination column not counted.
static func max_cards(t, dest = null) -> int:
	return (free_cells(t) + 1) * (1 << empty_columns(t, dest))


static func stacks(under, c) -> bool:
	return under.rank == c.rank + 1 and under.is_red() != c.is_red()


static func fits_foundation(c, dest) -> bool:
	if dest.cards.is_empty():
		return c.rank == 1
	var top = dest.top()
	return top.suit == c.suit and top.rank == c.rank - 1


## The foundation that takes card c: its suit's pile, or the first empty one for an ace.
func foundation_for(t, c):
	var first_empty = null
	for f in t.piles_of("foundation"):
		if f.cards.is_empty():
			if first_empty == null:
				first_empty = f
		elif fits_foundation(c, f):
			return f
	return first_empty if c.rank == 1 else null


## Cards pile.cards[index:] form a descending, alternating-colour run.
static func is_run(pile, index: int) -> bool:
	for i in range(index, pile.cards.size() - 1):
		if not stacks(pile.cards[i], pile.cards[i + 1]):
			return false
	return true


# --- kit interface -------------------------------------------------------------------

func can_pick(t, pile, index: int) -> bool:
	match pile.kind:
		"tableau":
			return is_run(pile, index) and pile.cards.size() - index <= max_cards(t)
		"cell":
			return index == 0
		"foundation":
			return index == pile.cards.size() - 1
	return false


func can_drop(t, cards: Array, from, to) -> bool:
	match to.kind:
		"tableau":
			if cards.size() > max_cards(t, to):
				return false
			return to.cards.is_empty() or stacks(to.top(), cards[0])
		"foundation":
			return cards.size() == 1 and fits_foundation(cards[0], to)
		"cell":
			return cards.size() == 1 and to.cards.is_empty() and from.kind != "cell"
	return false


func auto_target(t, pile, index: int):
	var c = pile.cards[index]
	var cards: Array = pile.cards.slice(index)
	if cards.size() == 1:
		var f = foundation_for(t, c)
		if f != null:
			return f
	var empty_col = null
	for p in t.piles_of("tableau"):
		if p == pile or not can_drop(t, cards, pile, p):
			continue
		if p.cards.is_empty():
			if index == 0 and pile.kind == "tableau":
				continue  # a whole column onto an empty one gains nothing
			if empty_col == null:
				empty_col = p
		else:
			return p
	if cards.size() == 1 and pile.kind == "tableau":
		for cell in t.piles_of("cell"):
			if cell.cards.is_empty():
				return cell
	return empty_col


func after_move(t, from, to, count: int) -> void:
	if to.kind == "foundation" and from.kind != "foundation":
		points += 10 * count
	elif from.kind == "foundation" and to.kind != "foundation":
		points = maxi(0, points - 10 * count)
	if _in_auto:
		return
	if counting:
		moves += 1
	if auto_foundation and counting and from.kind != "foundation":
		_in_auto = true
		sweep_safe(t)
		_in_auto = false


func is_won(t) -> bool:
	var n := 0
	for f in t.piles_of("foundation"):
		n += f.cards.size()
	return n == 52


# --- automatic foundation moves ----------------------------------------------------------

## Safe to send up for good: an ace or a two, or both opposite-colour piles already hold the rank below.
## (A card that is safe can never be needed as a place to park something else.)
func is_safe(t, c) -> bool:
	if c.rank <= 2:
		return true
	var reached := {}
	for f in t.piles_of("foundation"):
		if not f.cards.is_empty():
			reached[f.top().suit] = f.top().rank
	for suit in 4:
		if (suit == 1 or suit == 2) != c.is_red() and int(reached.get(suit, 0)) < c.rank - 1:
			return false
	return true


## Move every safe card (column tops and cells) to its foundation; repeats until none is left.
func sweep_safe(t) -> void:
	var again := true
	while again:
		again = false
		for p in t.piles_of("tableau") + t.piles_of("cell"):
			if p.cards.is_empty():
				continue
			var c = p.top()
			var f = foundation_for(t, c)
			if f != null and is_safe(t, c):
				t.move_cards(p, p.cards.size() - 1, f, false)
				again = true


## Auto-complete: the lowest card that can go up, until nothing can.
func auto_step(t) -> Dictionary:
	var best := {}
	var best_rank := 99
	for p in t.piles_of("tableau") + t.piles_of("cell"):
		if p.cards.is_empty():
			continue
		var f = foundation_for(t, p.top())
		if f != null and p.top().rank < best_rank:
			best_rank = p.top().rank
			best = {"from": p, "index": p.cards.size() - 1, "to": f}
	return best


## True when sending cards to the foundations alone finishes the deal (the Auto button shows then).
func can_finish(t) -> bool:
	var cols: Array = []
	for p in t.piles_of("tableau") + t.piles_of("cell"):
		cols.append(p.cards.map(func(c): return c))
	var next := {}
	for f in t.piles_of("foundation"):
		if not f.cards.is_empty():
			next[f.top().suit] = f.top().rank
	var left := 0
	for col in cols:
		left += col.size()
	var progress := true
	while left > 0 and progress:
		progress = false
		for col in cols:
			if col.is_empty():
				continue
			var c = col.back()
			if int(next.get(c.suit, 0)) == c.rank - 1:
				next[c.suit] = c.rank
				col.pop_back()
				left -= 1
				progress = true
	return left == 0


# --- hints and dead-end detection -----------------------------------------------------------

## Every legal move as {"from", "index", "to"}.
func legal_moves(t) -> Array:
	var out: Array = []
	var cells: Array = t.piles_of("cell")
	var empty_cell = null
	for c in cells:
		if c.cards.is_empty():
			empty_cell = c
			break
	var tabs: Array = t.piles_of("tableau")
	var srcs: Array = tabs + cells
	for p in srcs:
		if p.cards.is_empty():
			continue
		var first: int = p.cards.size() - 1
		if p.kind == "tableau":
			while first > 0 and stacks(p.cards[first - 1], p.cards[first]):
				first -= 1
		for s in range(first, p.cards.size()):
			var run: Array = p.cards.slice(s)
			if run.size() > max_cards(t):
				continue
			if run.size() == 1:
				var f = foundation_for(t, run[0])
				if f != null:
					out.append({"from": p, "index": s, "to": f})
			var seen_empty := false
			for d in tabs:
				if d == p or not can_drop(t, run, p, d):
					continue
				if d.cards.is_empty():
					if seen_empty or (s == 0 and p.kind == "tableau"):
						continue
					seen_empty = true
				out.append({"from": p, "index": s, "to": d})
		if p.kind == "tableau" and empty_cell != null:
			out.append({"from": p, "index": p.cards.size() - 1, "to": empty_cell})
	return out


func _score(t, m: Dictionary) -> int:
	var p = m.from
	var s: int = m.index
	var to = m.to
	var c = p.cards[s]
	if to.kind == "foundation":
		return 100 if is_safe(t, c) else 70
	var below = p.cards[s - 1] if s > 0 and p.kind == "tableau" else null
	var score := 0
	if below != null:
		if stacks(below, c):
			return -1  # would split a run that is already built
		if foundation_for(t, below) != null:
			score += 60  # frees a card for a foundation
		else:
			var fits := false
			for d in t.piles_of("tableau"):
				if d != p and not d.cards.is_empty() and stacks(d.top(), below):
					fits = true
			score += 35 if fits else 10
	elif p.kind == "tableau":
		score += 45  # empties a column
	if p.kind == "cell":
		score += 40  # frees a cell
	if to.kind == "cell":
		score = maxi(0, score - 25)
	elif to.cards.is_empty():
		score -= 15
	else:
		score += 15
	return score


func hints(t) -> Array:
	var scored: Array = []
	for m in legal_moves(t):
		var sc := _score(t, m)
		if sc > 0:
			scored.append([sc, m])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	return scored.slice(0, 8).map(func(e): return e[1])


## No legal move at all (every cell full and no card fits anywhere).
func is_stuck(t) -> bool:
	return not is_won(t) and legal_moves(t).is_empty()
