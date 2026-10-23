extends RefCounted
## Solvability checks for Mahjong Match, used by tests/smoke_test.gd and selftest.gd.
## Written against raw positions (not Board.is_free) so a bug in the free rule cannot hide itself.

const Layout := preload("res://games/mahjong_match/layout.gd")


static func naive_free(b, alive: PackedByteArray, i: int) -> bool:
	if alive[i] == 0:
		return false
	var left := false
	var right := false
	for j in b.n:
		if j == i or alive[j] == 0:
			continue
		var dx: int = b.xs[j] - b.xs[i]
		var dy: int = b.ys[j] - b.ys[i]
		if b.ls[j] > b.ls[i] and absi(dx) < 2 and absi(dy) < 2:
			return false
		if b.ls[j] == b.ls[i] and absi(dy) < 2:
			left = left or dx == -2
			right = right or dx == 2
	return not (left and right)


## Depth-first search for any way to clear the board; returns the pair list or [].
## `budget` is a one-element array counting remaining nodes.
static func solve(b, keys: PackedInt32Array, alive: PackedByteArray, seen: Dictionary, budget: Array) -> Array:
	var left := 0
	for v in alive:
		left += 1 if v != 0 else 0
	if left == 0:
		return [[]]
	budget[0] -= 1
	if budget[0] < 0:
		return []
	var h := alive.hex_encode()
	if seen.has(h):
		return []
	seen[h] = true
	var free: Array = Array(b.free_list(alive))
	# Forced move: a key with exactly two tiles left must be matched together, so take it at once.
	var count := {}
	for i in b.n:
		if alive[i] != 0:
			count[keys[i]] = count.get(keys[i], 0) + 1
	# Most-blocking tiles first: weight = alive tiles that wait on a tile.
	var weight := {}
	for j in b.n:
		if alive[j] != 0:
			for i in b.above[j]:
				weight[i] = weight.get(i, 0) + 3
			for i in b.left[j]:
				weight[i] = weight.get(i, 0) + 1
			for i in b.right[j]:
				weight[i] = weight.get(i, 0) + 1
	# Dead end: a key with two tiles left where one lies on the other can never be matched.
	for k in count:
		if count[k] == 2:
			var two: Array = []
			for i in b.n:
				if alive[i] != 0 and keys[i] == k:
					two.append(i)
			for pair in [[two[0], two[1]], [two[1], two[0]]]:
				if pair[0] in b.above[pair[1]]:
					return []
	var moves: Array = []
	for x in free.size():
		for y in range(x + 1, free.size()):
			if keys[free[x]] == keys[free[y]]:
				var w: int = weight.get(free[x], 0) + weight.get(free[y], 0) + 100 * int(count[keys[free[x]]] == 2) + 12 * (8 - mini(count[keys[free[x]]], 8))
				moves.append([w, free[x], free[y]])
	moves.sort_custom(func(m, n): return m[0] > n[0])
	for m in moves:
		var next := alive.duplicate()
		next[m[1]] = 0
		next[m[2]] = 0
		var rest := solve(b, keys, next, seen, budget)
		if not rest.is_empty():
			rest.push_front([m[1], m[2]])
			return rest
	return []


## Returns the number of problems found across the given campaign levels (also prints them).
static func check_levels(levels: Array, verbose := false) -> int:
	var errors := 0
	for lv in levels:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(lv.seed)
		var gen: Dictionary = Layout.generate(String(lv.shape), int(lv.layers), int(lv.tiles), int(lv.types), rng)
		var b = gen.board
		var keys: PackedInt32Array = gen.keys
		var tag := "level %d" % lv.id
		if b.n != int(lv.tiles):
			push_error("%s: board has %d tiles, level says %d" % [tag, b.n, lv.tiles]); errors += 1
		# 1) the construction order really is a legal clearing order (independent free test)
		var alive := PackedByteArray()
		alive.resize(b.n)
		alive.fill(1)
		for pr in gen.solution:
			if keys[pr[0]] != keys[pr[1]] or not naive_free(b, alive, pr[0]) or not naive_free(b, alive, pr[1]):
				push_error("%s: stored solution has an illegal move" % tag); errors += 1
				break
			alive[pr[0]] = 0
			alive[pr[1]] = 0
		if alive.count(1) != 0:
			push_error("%s: stored solution leaves tiles" % tag); errors += 1
		# 2) Board.is_free agrees with the naive rule at every step of the stored solution
		alive.fill(1)
		var mismatch := false
		for pr in gen.solution:
			for i in b.n:
				if b.is_free(i, alive) != naive_free(b, alive, i):
					mismatch = true
			alive[pr[0]] = 0
			alive[pr[1]] = 0
		if mismatch:
			push_error("%s: free rule mismatch" % tag); errors += 1
		# 3) a search that ignores the stored order also finds a clearing
		alive.fill(1)
		var budget := [60000]
		var found := solve(b, keys, alive, {}, budget)
		if found.is_empty():
			push_error("%s: search found no solution (budget left %d)" % [tag, budget[0]]); errors += 1
		if verbose:
			print("%s ok: %d tiles, %d layers, %d kinds, search nodes %d" % [tag, b.n, b.layers, lv.types, 60000 - budget[0]])
	return errors
