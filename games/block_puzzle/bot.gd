extends SceneTree
## Star calibration bot for Block Fit. Plays every campaign level through the real game script and
## writes games/block_puzzle/par.json, which tools/gen_levels.py turns into the star thresholds.
##   godot --headless -s res://games/block_puzzle/bot.gd
## "greedy" always takes the best (piece, cell) by the heuristic below. "casual" picks at random among
## the few best placements, CASUAL_RUNS times. "best" (fewest pieces of any winning run) stands for a
## careful player, "median" (of all winning runs) for a typical one.

const CASUAL_RUNS := 12
const CASUAL_TOP := 4
const OUT := "res://games/block_puzzle/par.json"

var pick_rng := RandomNumberGenerator.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var levels: Array = root.get_node("Games").get_levels("block_puzzle")
	var out: Array = []
	for i in levels.size():
		var greedy := _play(levels[i], i, 0)
		var wins: Array[int] = []
		for k in CASUAL_RUNS:
			pick_rng.seed = 77 + k * 1013 + i
			var n := _play(levels[i], i, CASUAL_TOP)
			if n > 0:
				wins.append(n)
		var casual_wins := wins.size()
		if greedy > 0:
			wins.append(greedy)
		wins.sort()
		var best := wins[0] if not wins.is_empty() else -1
		var med := wins[wins.size() / 2] if not wins.is_empty() else -1
		out.append({"level": i + 1, "greedy": greedy, "best": best, "median": med,
			"casual_wins": casual_wins, "casual_runs": CASUAL_RUNS})
		print("level %2d  greedy %3d  best %3d  median %3d  casual wins %d/%d" % [i + 1, greedy, best, med,
			casual_wins, CASUAL_RUNS])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify({"levels": out}, " "))
	f.close()
	quit()


## Plays one level; returns pieces used on a win, -1 on a loss. top = 0: always the best move.
func _play(lvl: Dictionary, index: int, top: int) -> int:
	var game: BaseGame = load("res://games/block_puzzle/game.tscn").instantiate()
	root.add_child(game)
	game.start_level(lvl, index)
	var result := -1
	for guard in 400:
		if game.over:
			break
		var moves := _moves(game)
		if moves.is_empty():
			break
		moves.sort_custom(func(a, b): return a.v > b.v)
		var m: Dictionary = moves[0] if top <= 1 else moves[pick_rng.randi_range(0, mini(top, moves.size()) - 1)]
		game._place(m.slot, m.x, m.y)
	if game.over and game._goal_met():
		result = game.placed
	game.free()
	return result


func _moves(game) -> Array:
	var out: Array = []
	for s in game.pieces.size():
		var p = game.pieces[s]
		if p == null:
			continue
		for oy in game.g - p.h + 1:
			for ox in game.g - p.w + 1:
				if game._fits(p, ox, oy):
					out.append({"slot": s, "x": ox, "y": oy, "v": _value(game, s, p, ox, oy)})
	return out


## Heuristic: lines (and marked blocks) cleared, then a tidy board: long runs of filled cells per
## line, few isolated holes, and the rest of the tray still fitting.
func _value(game, slot: int, p: Dictionary, ox: int, oy: int) -> float:
	var g: int = game.g
	var sim: Array = game.cells.duplicate()
	var pre: Array = game.pre.duplicate()
	for c: Vector2i in p.cells:
		sim[(oy + c.y) * g + ox + c.x] = 1
	var kill := {}
	var lines := 0
	for r in g:
		var full := true
		for x in g:
			full = full and sim[r * g + x] != 0
		if full:
			lines += 1
			for x in g:
				kill[r * g + x] = true
	for c in g:
		var full := true
		for y in g:
			full = full and sim[y * g + c] != 0
		if full:
			lines += 1
			for y in g:
				kill[y * g + c] = true
	var marked := 0
	for i in kill:
		if pre[i]:
			marked += 1
			pre[i] = false
		sim[i] = 0
	var v := lines * 100.0 + lines * lines * 20.0
	if game.goal == "clear":
		v += marked * 120.0
	var holes := 0
	for y in g:
		var row_fill := 0
		var col_fill := 0
		var row_pre := false
		var col_pre := false
		for x in g:
			if sim[y * g + x] != 0:
				row_fill += 1
				row_pre = row_pre or pre[y * g + x]
			if sim[x * g + y] != 0:
				col_fill += 1
				col_pre = col_pre or pre[x * g + y]
		var wr := 1.6 if (game.goal == "clear" and row_pre) else 1.0
		var wc := 1.6 if (game.goal == "clear" and col_pre) else 1.0
		v += row_fill * row_fill * 0.6 * wr + col_fill * col_fill * 0.6 * wc
		for x in g:
			if sim[y * g + x] != 0:
				continue
			var closed := 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= g or ny >= g or sim[ny * g + nx] != 0:
					closed += 1
			if closed >= 3:
				holes += 1
	v -= holes * 9.0
	# keep the rest of the tray placeable
	var saved: Array = game.cells
	game.cells = sim
	for s in game.pieces.size():
		if s != slot and game.pieces[s] != null and not game._fits_anywhere(game.pieces[s]):
			v -= 400.0
	game.cells = saved
	return v
