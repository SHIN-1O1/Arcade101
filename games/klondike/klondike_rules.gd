extends "res://core/cards/card_rules.gd"
## Klondike rules on top of the card kit. Piles: "stock", "waste", "f0".."f3" (kind foundation),
## "t0".."t6" (kind tableau). Also owns the per-deal counters so undo restores them.

var draw_count := 1       ## 1 or 3
var moves := 0            ## player moves this deal (draws count, auto-complete does not)
var points := 0           ## classic scoring, used by endless mode
var counting := true      ## false while auto-complete plays
var _idle_draws := 0


func get_extra() -> Variant:
	return [moves, points]


func set_extra(v) -> void:
	moves = v[0]
	points = v[1]


func can_pick(_t, pile, index: int) -> bool:
	match pile.kind:
		"tableau":
			return pile.cards[index].face_up
		"waste", "foundation":
			return index == pile.cards.size() - 1
	return false


static func fits_tableau(c, dest) -> bool:
	if dest.cards.is_empty():
		return c.rank == 13
	var top = dest.top()
	return top.face_up and top.rank == c.rank + 1 and top.is_red() != c.is_red()


static func fits_foundation(c, dest) -> bool:
	if dest.cards.is_empty():
		return c.rank == 1
	var top = dest.top()
	return top.suit == c.suit and top.rank == c.rank - 1


func can_drop(_t, cards: Array, _from, to) -> bool:
	if to.kind == "tableau":
		return fits_tableau(cards[0], to)
	if to.kind == "foundation":
		return cards.size() == 1 and fits_foundation(cards[0], to)
	return false


func on_tap(t, pile, _index: int) -> bool:
	if pile.kind != "stock":
		return false
	draw(t)
	return true


## Stock tap: draw `draw_count` cards onto the waste, or turn the waste over when the stock is empty.
func draw(t) -> bool:
	var stock = t.pile("stock")
	var waste = t.pile("waste")
	if stock.cards.is_empty() and waste.cards.is_empty():
		return false
	t.push_undo()
	if counting:
		moves += 1
	if stock.cards.is_empty():
		var back: Array = waste.cards.duplicate()
		back.reverse()
		for c in back:
			c.face_up = false
		if counting:
			points = maxi(0, points - (100 if draw_count == 1 else 20))
		t.move_list(waste, back, stock, false)
	else:
		var n := mini(draw_count, stock.cards.size())
		var list: Array = []
		for i in n:
			var c = stock.cards[stock.cards.size() - 1 - i]
			c.face_up = true
			list.append(c)
		t.move_list(stock, list, waste, false)
	return true


func auto_target(t, pile, index: int):
	var c = pile.cards[index]
	if index == pile.cards.size() - 1:
		var f = foundation_for(t, c)
		if f != null:
			return f
	var empty_dest = null
	for p in t.piles_of("tableau"):
		if p == pile or not fits_tableau(c, p):
			continue
		if p.cards.is_empty():
			if index == 0 and pile.kind == "tableau":
				continue  # a king alone in its column gains nothing
			if empty_dest == null:
				empty_dest = p
		else:
			return p
	return empty_dest


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


func after_move(t, from, to, count: int) -> void:
	if from.kind == "tableau" and not from.cards.is_empty() and not from.top().face_up:
		from.top().face_up = true
		points += 5
	if to.kind == "foundation" and from.kind != "foundation":
		points += 10 * count
	elif from.kind == "foundation" and to.kind == "tableau":
		points = maxi(0, points - 15)
	elif from.kind == "waste" and to.kind == "tableau":
		points += 5
	if counting and from.kind != "stock" and to.kind != "stock":
		moves += 1


func is_won(t) -> bool:
	var n := 0
	for f in t.piles_of("foundation"):
		n += f.cards.size()
	return n == 52


## Every tableau card is face up (the game is a formality from here).
func all_revealed(t) -> bool:
	for p in t.piles_of("tableau"):
		for c in p.cards:
			if not c.face_up:
				return false
	return true


## Auto-complete: send anything to the foundation; draw from the stock when nothing else is left.
func reset_auto() -> void:
	_idle_draws = 0


func auto_step(t) -> Dictionary:
	var best := {}
	var best_rank := 99
	var sources: Array = t.piles_of("tableau")
	sources.append(t.pile("waste"))
	for p in sources:
		if p.cards.is_empty() or not p.top().face_up:
			continue
		var f = foundation_for(t, p.top())
		if f != null and p.top().rank < best_rank:
			best_rank = p.top().rank
			best = {"from": p, "index": p.cards.size() - 1, "to": f}
	if not best.is_empty():
		_idle_draws = 0
		return best
	var stock = t.pile("stock")
	var waste = t.pile("waste")
	var span: int = (stock.cards.size() + waste.cards.size()) / draw_count + 2
	if (stock.cards.is_empty() and waste.cards.is_empty()) or _idle_draws > span:
		return {}
	_idle_draws += 1
	return {"action": func(): draw(t)}


# --- hints and dead-end detection ------------------------------------------------

## Cards that will appear on top of the waste while drawing through the stock (the current top is not included).
func waste_cycle(t) -> Array:
	var stock: Array = t.pile("stock").cards.duplicate()
	var waste: Array = t.pile("waste").cards.duplicate()
	var out: Array = []
	var seen := {}
	while true:
		var key := str(stock.size()) + ":" + str(waste.size())
		if seen.has(key):
			break
		seen[key] = true
		if stock.is_empty():
			if waste.is_empty():
				break
			stock = waste.duplicate()
			stock.reverse()
			waste = []
			continue
		for i in mini(draw_count, stock.size()):
			waste.append(stock.pop_back())
		out.append(waste.back())
	return out


func _is_useful_tableau_move(pile, s: int, dest, t) -> bool:
	var first := 0
	while first < pile.cards.size() and not pile.cards[first].face_up:
		first += 1
	if s == first:
		if first > 0:
			return true  # reveals a face-down card
		return not dest.cards.is_empty() and _king_waiting(t, pile)  # empties the column for a king
	var below = pile.cards[s - 1]
	return foundation_for(t, below) != null  # frees a card that can go up


func _king_waiting(t, skip) -> bool:
	var w = t.pile("waste")
	if not w.cards.is_empty() and w.top().rank == 13:
		return true
	for p in t.piles_of("tableau"):
		if p != skip and not p.cards.is_empty() and p.cards[0].face_up == false:
			for c in p.cards:
				if c.face_up and c.rank == 13:
					return true
	return false


func hints(t) -> Array:
	var out: Array = []
	var waste = t.pile("waste")
	var stock = t.pile("stock")
	# 1. to the foundation
	var srcs: Array = t.piles_of("tableau")
	srcs.append(waste)
	for p in srcs:
		if p.cards.is_empty() or not p.top().face_up:
			continue
		var f = foundation_for(t, p.top())
		if f != null:
			out.append({"from": p, "index": p.cards.size() - 1, "to": f})
	# 2. tableau moves that open something up
	for p in t.piles_of("tableau"):
		for s in p.cards.size():
			if not p.cards[s].face_up:
				continue
			for d in t.piles_of("tableau"):
				if d != p and fits_tableau(p.cards[s], d) and _is_useful_tableau_move(p, s, d, t):
					if d.cards.is_empty() and s == 0:
						continue
					out.append({"from": p, "index": s, "to": d})
					break
	# 3. waste to the tableau
	if not waste.cards.is_empty():
		for d in t.piles_of("tableau"):
			if fits_tableau(waste.top(), d):
				out.append({"from": waste, "index": waste.cards.size() - 1, "to": d})
				break
	# 4. draw, only when some card in the stock can be played
	if not stock.cards.is_empty() or not waste.cards.is_empty():
		for c in waste_cycle(t):
			if _playable(t, c):
				out.append({"from": stock, "index": -1, "to": stock})
				break
	return out


func _playable(t, c) -> bool:
	if foundation_for(t, c) != null:
		return true
	for d in t.piles_of("tableau"):
		if fits_tableau(c, d):
			return true
	return false


## True when nothing useful is left: no tableau/foundation move and no playable card in the stock.
func is_stuck(t) -> bool:
	return hints(t).is_empty() and not is_won(t)
