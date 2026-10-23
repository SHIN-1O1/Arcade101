extends RefCounted
## Mahjong Match board logic with no drawing: shapes, stacking, the free-tile rule and the
## solvable-by-construction pair order. Positions are integer half-tile units (a tile covers a
## 2x2 square of units). Layer k rests on layer k-1, shifted by one unit so each tile sits on four.
##
## Solvability: generate() removes random free pairs from the full layout until it is empty
## (retrying on the rare dead end), then gives each removed pair one match key. Replaying that
## order is therefore always a legal way to clear the board.

const SHAPES: Array[String] = ["rect", "oct", "diamond", "cross", "ring", "towers"]
## Base grid sizes (tile columns x rows), smallest first. The first one that holds enough tiles wins.
const SIZES: Array = [[4, 3], [4, 4], [5, 4], [5, 5], [6, 5], [6, 6], [7, 6], [7, 7], [8, 7], [8, 8], [8, 9]]
const FLOWER := 25  # match keys 25 (flowers) and 26 (seasons) are families: any two of a family match
const SEASON := 26
const KEY_COUNT := 27
## Suit groups of match keys, used to mix suits when picking the tile types of a level.
const GROUPS: Array = [[0, 1, 2, 3, 4, 5], [6, 7, 8, 9, 10, 11], [12, 13, 14, 15, 16, 17],
	[18, 19, 20, 21], [22, 23, 24], [25, 26]]


## One board: tile positions plus the cover/neighbour tables behind the free rule.
class Board:
	var n := 0
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	var ls := PackedInt32Array()  # layer
	var above: Array = []  # per tile: tiles on a higher layer overlapping it
	var left: Array = []  # per tile: same-layer tiles touching its left edge
	var right: Array = []
	var layers := 1

	func add(x: int, y: int, l: int) -> void:
		xs.append(x)
		ys.append(y)
		ls.append(l)
		n += 1
		layers = maxi(layers, l + 1)

	func finish() -> void:
		above.clear()
		left.clear()
		right.clear()
		for i in n:
			var up := PackedInt32Array()
			var lf := PackedInt32Array()
			var rt := PackedInt32Array()
			for j in n:
				if i == j:
					continue
				var dx := xs[j] - xs[i]
				var dy := ys[j] - ys[i]
				if ls[j] > ls[i] and absi(dx) < 2 and absi(dy) < 2:
					up.append(j)
				elif ls[j] == ls[i] and absi(dy) < 2:
					if dx == -2:
						lf.append(j)
					elif dx == 2:
						rt.append(j)
			above.append(up)
			left.append(lf)
			right.append(rt)

	## Free = alive, nothing on top, and the left or the right side open.
	func is_free(i: int, alive: PackedByteArray) -> bool:
		if alive[i] == 0:
			return false
		for j in above[i]:
			if alive[j] != 0:
				return false
		var l_open := true
		for j in left[i]:
			if alive[j] != 0:
				l_open = false
				break
		if l_open:
			return true
		for j in right[i]:
			if alive[j] != 0:
				return false
		return true

	func free_list(alive: PackedByteArray) -> PackedInt32Array:
		var out := PackedInt32Array()
		for i in n:
			if is_free(i, alive):
				out.append(i)
		return out

	## A random order of removable pairs that empties every alive tile, or [] if this attempt
	## dead-ends. Each entry is [a, b].
	func try_pairing(alive_in: PackedByteArray, rng: RandomNumberGenerator) -> Array:
		var alive := alive_in.duplicate()
		var left_count := 0
		for v in alive:
			left_count += 1 if v != 0 else 0
		var order: Array = []
		while left_count > 0:
			var fr := free_list(alive)
			if fr.size() < 2:
				return []
			var a := fr[rng.randi() % fr.size()]
			var b := a
			while b == a:
				b = fr[rng.randi() % fr.size()]
			alive[a] = 0
			alive[b] = 0
			left_count -= 2
			order.append([a, b])
		return order

	func pairing(alive: PackedByteArray, rng: RandomNumberGenerator, tries := 60) -> Array:
		for _t in tries:
			var p := try_pairing(alive, rng)
			if not p.is_empty():
				return p
		return []


# --- shapes ------------------------------------------------------------------

static func cell_in_shape(shape: String, i: int, j: int, w: int, h: int) -> bool:
	var cx := (w - 1) / 2.0
	var cy := (h - 1) / 2.0
	match shape:
		"oct":
			var c := maxi(1, mini(w, h) / 3)
			return i + j >= c and (w - 1 - i) + j >= c and i + (h - 1 - j) >= c and (w - 1 - i) + (h - 1 - j) >= c
		"diamond":
			return absf(i - cx) / (w / 2.0) + absf(j - cy) / (h / 2.0) <= 1.0001
		"cross":
			return absf(i - cx) < maxf(1.0, w / 4.0 + 0.01) or absf(j - cy) < maxf(1.0, h / 4.0 + 0.01)
		"ring":
			return i < 2 or j < 2 or i >= w - 2 or j >= h - 2
		"towers":
			return w < 5 or i != w / 2 or absf(j - cy) <= 1.0
	return true


## Every position of `shape` stacked `layers` high on a w x h tile grid.
static func stack(shape: String, w: int, h: int, layers: int) -> Board:
	var b := Board.new()
	var placed := {}  # Vector3i(x, y, layer) -> true
	for j in h:
		for i in w:
			if cell_in_shape(shape, i, j, w, h):
				b.add(i * 2, j * 2, 0)
				placed[Vector3i(i * 2, j * 2, 0)] = true
	for l in range(1, layers):
		var added := []
		for k in b.n:
			if b.ls[k] != l - 1:
				continue
			var x := b.xs[k] + 1
			var y := b.ys[k] + 1
			if placed.has(Vector3i(x - 1, y - 1, l - 1)) and placed.has(Vector3i(x + 1, y - 1, l - 1)) \
					and placed.has(Vector3i(x - 1, y + 1, l - 1)) and placed.has(Vector3i(x + 1, y + 1, l - 1)):
				added.append(Vector3i(x, y, l))
		for p in added:
			b.add(p.x, p.y, l)
			placed[p] = true
	return b


## Board for the given shape/layers with about `tiles` tiles (always even, never more than the
## shape holds). Extra tiles are trimmed from the top layer down, ragged edges first, so the
## stack stays supported.
static func make_board(shape: String, layers: int, tiles: int, rng: RandomNumberGenerator) -> Board:
	var full: Board = null
	for sz in SIZES:
		full = stack(shape, sz[0], sz[1], layers)
		if full.n >= tiles:
			break
	var keep: Array = range(full.n)
	var target := mini(tiles, full.n)
	target -= target % 2
	while keep.size() > target:
		var top := 0
		for k in keep:
			top = maxi(top, full.ls[k])
		var cands: Array = []
		var best := 99
		for k in keep:
			if full.ls[k] != top:
				continue
			var nb := 0
			for m in keep:
				if m != k and full.ls[m] == top and (absi(full.xs[m] - full.xs[k]) + absi(full.ys[m] - full.ys[k])) == 2:
					nb += 1
			if nb < best:
				best = nb
				cands = [k]
			elif nb == best:
				cands.append(k)
		keep.erase(cands[rng.randi() % cands.size()])
	var out := Board.new()
	for k in keep:
		out.add(full.xs[k], full.ys[k], full.ls[k])
	out.finish()
	return out


## Distinct match keys for a level: `count` of them, taken round-robin across the suits.
static func pick_keys(count: int, rng: RandomNumberGenerator) -> Array:
	var groups: Array = []
	for g in GROUPS:
		var c: Array = g.duplicate()
		for i in range(c.size() - 1, 0, -1):
			var j := rng.randi() % (i + 1)
			var t = c[i]
			c[i] = c[j]
			c[j] = t
		groups.append(c)
	var out: Array = []
	var gi := rng.randi() % groups.size()
	var guard := 0
	while out.size() < mini(count, KEY_COUNT) and guard < 200:
		guard += 1
		var g: Array = groups[gi % groups.size()]
		gi += 1
		if not g.is_empty():
			out.append(g.pop_back())
	return out


## Everything a game needs for one fresh board: positions, per-tile match key and face variant,
## and `solution` (the pair order the board was built from).
static func generate(shape: String, layers: int, tiles: int, types: int, rng: RandomNumberGenerator) -> Dictionary:
	var board := make_board(shape, layers, tiles, rng)
	var alive := PackedByteArray()
	alive.resize(board.n)
	alive.fill(1)
	var solution := board.pairing(alive, rng, 400)
	var pool := pick_keys(types, rng)
	var keys := PackedInt32Array()
	keys.resize(board.n)
	var variants := PackedInt32Array()
	variants.resize(board.n)
	# Each key goes on two pairs (the usual four copies); the bag is shuffled across the solution.
	var bag: Array = []
	var p := 0
	while bag.size() < solution.size():
		bag.append(pool[(p / 2) % pool.size()])
		p += 1
	for i in range(bag.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = bag[i]
		bag[i] = bag[j]
		bag[j] = t
	for k in solution.size():
		_stamp(solution[k], bag[k], keys, variants, rng)
	return {"board": board, "keys": keys, "variants": variants, "solution": solution}


static func _stamp(pair: Array, key: int, keys: PackedInt32Array, variants: PackedInt32Array,
		rng: RandomNumberGenerator) -> void:
	keys[pair[0]] = key
	keys[pair[1]] = key
	var v := rng.randi() % 4
	variants[pair[0]] = v
	variants[pair[1]] = (v + 1 + rng.randi() % 3) % 4  # a flower pair shows two different flowers


## New faces for the tiles still alive: a fresh solvable pair order when one exists, otherwise at
## least one matching free pair. Returns the pair order (a single [a, b] in the fallback case), or
## null when no free pair can exist at all (dead board).
static func reshuffle(board: Board, alive: PackedByteArray, keys: PackedInt32Array, variants: PackedInt32Array,
		rng: RandomNumberGenerator) -> Variant:
	var live: Array = []
	for i in board.n:
		if alive[i] != 0:
			live.append(i)
	# Multiset of keys now on the board, so a shuffle keeps the same faces.
	var pool: Array = []
	for i in live:
		pool.append(keys[i])
	var order := board.pairing(alive, rng, 80)
	if not order.is_empty():
		var by_key := {}
		for k in pool:
			by_key[k] = by_key.get(k, 0) + 1
		var bag: Array = []
		for k in by_key:
			for _c in range(by_key[k] / 2):
				bag.append(k)
		# Odd counts can only come from a broken board; fall back to random keys for the rest.
		while bag.size() < order.size():
			bag.append(pool[rng.randi() % pool.size()])
		for i in range(bag.size() - 1, 0, -1):
			var j := rng.randi() % (i + 1)
			var t = bag[i]
			bag[i] = bag[j]
			bag[j] = t
		for k in order.size():
			_stamp(order[k], bag[k], keys, variants, rng)
		return order
	var fr := board.free_list(alive)
	if fr.size() < 2:
		return null
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	for k in live.size():
		keys[live[k]] = pool[k]
	keys[fr[1]] = keys[fr[0]]
	return [[fr[0], fr[1]]]


## Free tiles grouped by match key; returns the first matching free pair [a, b] or [].
static func find_pair(board: Board, alive: PackedByteArray, keys: PackedInt32Array) -> Array:
	var seen := {}
	for i in board.free_list(alive):
		if seen.has(keys[i]):
			return [seen[keys[i]], i]
		seen[keys[i]] = i
	return []
