"""Regenerates games/<id>/levels.json (endless-only games such as number_merge have none) with a smooth difficulty curve.
Run from the project root:  python tools/gen_levels.py
Hand-edit the JSON afterwards if a level needs tuning; re-running overwrites it.
Every level has "seed" (deterministic layout) and "stars": [1-star, 2-star, 3-star]
thresholds for that game's star metric (see "star_metric")."""
import json, os

N = 30

def lerp(a, b, t): return a + (b - a) * t
def ri(a, b, t): return int(round(lerp(a, b, t)))

def fruit_merge(i, t):
    # Score attack: reach target_tier before the jar overflows.
    target = ri(6, 11, t)
    return {"target_tier": target, "spawn_max_tier": 3 if i < 10 else 4,
            "jar_width": ri(520, 440, t), "stars": [ri(400, 4000, t), ri(700, 6500, t), ri(1000, 9000, t)]}

def _pour(tubes, a, b, cap):
    src, dst = tubes[a], tubes[b]
    if not src or len(dst) >= cap or (dst and dst[-1] != src[-1]):
        return None
    c, n = src[-1], 0
    while n < len(src) and src[-1 - n] == c:
        n += 1
    n = min(n, cap - len(dst))
    t = [list(x) for x in tubes]
    t[a] = src[:-n]
    t[b] = dst + [c] * n
    return t

def _solve(tubes, cap):
    """Best-first search; returns move count of a solution found, or None. Same pour rule as the game."""
    import heapq
    def key(t): return tuple(sorted(tuple(x) for x in t))
    def h(t): return sum(sum(1 for j in range(1, len(x)) if x[j] != x[j - 1]) + (1 if x else 0) for x in t)
    def done(t): return all(not x or (len(x) == cap and len(set(x)) == 1) for x in t)
    seen, heap, n = {key(tubes)}, [(h(tubes), 0, 0, tubes)], 0
    while heap and n < 200000:
        _, g, _, t = heapq.heappop(heap)
        if done(t): return g
        for a in range(len(t)):
            for b in range(len(t)):
                if a == b: continue
                u = _pour(t, a, b, cap)
                if u is None: continue
                k = key(u)
                if k in seen: continue
                seen.add(k); n += 1
                heapq.heappush(heap, (h(u) + g * 0.5, g + 1, n, u))
    return None

def color_sort(i, t):
    import random
    colors = ri(3, 12, t)
    cap = 4
    empty = 2 if i < 20 else 1 if colors <= 9 else 2
    rng = random.Random(1000 + i * 7919)
    while True:
        balls = [c for c in range(colors) for _ in range(cap)]
        rng.shuffle(balls)
        tubes = [balls[k * cap:(k + 1) * cap] for k in range(colors)] + [[] for _ in range(empty)]
        if any(len(set(x)) == 1 for x in tubes[:colors]):
            continue  # avoid pre-solved tubes
        par = _solve(tubes, cap)
        if par is not None:
            break
    # stars: 1 = finish, 2 = within 1.5x par, 3 = within 1.15x par (par is an upper bound from the solver)
    return {"colors": colors, "capacity": cap, "empty_tubes": empty, "tubes": tubes, "par": par,
            "stars": [par * 2 + 4, int(par * 1.5) + 1, int(par * 1.15) + 1]}

def tower_stack(i, t):
    # Taller, faster, narrower; wind (speed wobble) from level 8 on every 3rd level,
    # sway (the slide range drifts) from level 12 on every 4th level.
    target = ri(8, 40, t)
    wind = round(lerp(0.25, 0.6, t), 2) if i >= 7 and i % 3 == 1 else 0
    sway = ri(40, 100, t) if i >= 11 and i % 4 == 3 else 0
    return {"target_height": target, "speed": round(lerp(240, 560, t)), "speed_step": round(lerp(3, 9, t), 1),
            "block_width": ri(360, 240, t), "tolerance": ri(14, 9, t), "wind": wind, "sway": sway,
            "stars": [0, max(3, round(target * 0.35)), max(5, round(target * 0.65))]}

def block_puzzle(i, t):
    # Every 3rd level (from the 3rd) is "clear all marked blocks"; the rest are "clear N lines".
    piece_set = "basic" if i < 10 else "extended"
    if i % 3 == 2:
        pre = ri(6, 26, t)
        eq = max(4, pre // 2)
        return {"grid": 8, "goal": "clear", "target_lines": 0, "prefilled": pre,
                "piece_set": piece_set, "stars": [0, eq * 22, eq * 34]}
    lines = ri(3, 20, t)
    return {"grid": 8, "goal": "lines", "target_lines": lines, "prefilled": ri(0, 14, t),
            "piece_set": piece_set, "stars": [0, lines * 22, lines * 34]}

def bubble_shooter(i, t):
    return {"rows": ri(4, 11, t), "colors": ri(3, 6, t), "shots": ri(30, 40, t),
            "stars": [0, ri(8, 6, t), ri(14, 10, t)]}

MJ_SHAPES = ["rect", "oct", "diamond", "cross", "ring", "towers"]
MJ_SIZES = [(4, 3), (4, 4), (5, 4), (5, 5), (6, 5), (6, 6), (7, 6), (7, 7), (8, 7), (8, 8), (8, 9)]  # same as layout.gd

def _mj_cell(shape, i, j, w, h):
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    if shape == "oct":
        c = max(1, min(w, h) // 3)
        return i + j >= c and (w - 1 - i) + j >= c and i + (h - 1 - j) >= c and (w - 1 - i) + (h - 1 - j) >= c
    if shape == "diamond": return abs(i - cx) / (w / 2.0) + abs(j - cy) / (h / 2.0) <= 1.0001
    if shape == "cross": return abs(i - cx) < max(1.0, w / 4.0 + 0.01) or abs(j - cy) < max(1.0, h / 4.0 + 0.01)
    if shape == "ring": return i < 2 or j < 2 or i >= w - 2 or j >= h - 2
    if shape == "towers": return w < 5 or i != w // 2 or abs(j - cy) <= 1.0
    return True

def _mj_layer_sizes(shape, w, h, layers):
    # Mirrors layout.gd stack(): layer k sits on four tiles of layer k-1 (offset by one unit).
    cur = {(2 * i, 2 * j) for j in range(h) for i in range(w) if _mj_cell(shape, i, j, w, h)}
    out = [len(cur)]
    for _ in range(1, layers):
        cur = {(x + 1, y + 1) for (x, y) in cur if {(x + 2, y), (x, y + 2), (x + 2, y + 2)} <= cur}
        out.append(len(cur))
    return out

def _mj_fit(shape, layers, want):
    """(tiles, layers actually used) for the smallest base that holds `want` tiles (layout.gd make_board)."""
    for w, h in MJ_SIZES:
        sizes = _mj_layer_sizes(shape, w, h, layers)
        if sum(sizes) >= want: break
    tiles = min(want, sum(sizes))
    tiles -= tiles % 2
    used, acc = 0, 0
    for n in sizes:
        if acc >= tiles: break
        used += 1
        acc += n
    return tiles, used

def mahjong_match(i, t):
    # Taller stacks, more tiles and kinds, fewer hints/shuffles/undos. "tiles" is what the board really
    # holds (the shape may not reach the target); stars are seconds, lower is better.
    layers = 1 if i < 3 else 2 if i < 9 else 3 if i < 16 else 4 if i < 23 else 5
    want = ri(16, 128, t)
    # Rotate through the shapes; take the first that holds the target with the full stack height,
    # else the first that holds the target, else rect (which always can).
    fits = [(MJ_SHAPES[(i + k) % len(MJ_SHAPES)],) + _mj_fit(MJ_SHAPES[(i + k) % len(MJ_SHAPES)], layers, want)
            for k in range(len(MJ_SHAPES))]
    pick = next((f for f in fits if f[1] >= want and f[2] >= layers), None) \
        or next((f for f in fits if f[1] >= want), None) or ("rect",) + _mj_fit("rect", layers, want)
    shape, tiles = pick[0], pick[1]
    pairs = tiles // 2
    return {"shape": shape, "layers": layers, "tiles": tiles, "types": ri(6, 27, t),
            "hints": ri(5, 2, t), "shuffles": ri(4, 1, t), "undos": ri(6, 3, t),
            "stars": [int(pairs * 9), int(pairs * 5.5), int(pairs * 3.6)]}

GAMES = {
    "fruit_merge":    (fruit_merge,    "score"),
    "color_sort":     (color_sort,     "moves_used (lower is better)"),
    "tower_stack":    (tower_stack,    "perfect_drops"),
    "block_puzzle":   (block_puzzle,   "score"),
    "bubble_shooter": (bubble_shooter, "shots_left"),
    "mahjong_match":  (mahjong_match,  "seconds incl. hint/shuffle/undo penalty (lower is better)"),
}

root = os.path.join(os.path.dirname(__file__), "..", "games")
for gid, (fn, metric) in GAMES.items():
    levels = []
    for i in range(N):
        lvl = {"id": i + 1, "seed": 1000 + i * 7919}
        lvl.update(fn(i, i / (N - 1)))
        levels.append(lvl)
    os.makedirs(os.path.join(root, gid), exist_ok=True)
    with open(os.path.join(root, gid, "levels.json"), "w") as f:
        json.dump({"star_metric": metric, "levels": levels}, f, indent=1)
print("wrote", len(GAMES), "games x", N, "levels")
