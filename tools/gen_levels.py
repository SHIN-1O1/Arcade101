"""Regenerates games/<id>/levels.json with a smooth difficulty curve.
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
    return {"target_height": ri(10, 45, t), "speed": round(lerp(260, 620, t)), "speed_step": round(lerp(4, 12, t), 1),
            "block_width": ri(360, 260, t), "stars": [0, ri(3, 12, t), ri(6, 22, t)]}

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

def number_merge(i, t):
    tiers = [128, 128, 256, 256, 256, 512, 512, 512, 512, 1024]
    target = tiers[i] if i < len(tiers) else (1024 if i < 18 else 2048 if i < 26 else 4096)
    return {"grid": 5 if i < 4 else 4, "target_tile": target, "blockers": 0 if i < 12 else ri(1, 3, t),
            "move_limit": 0, "stars": [10_000, int(target * 1.2), int(target * 0.8)]}

def bubble_shooter(i, t):
    return {"rows": ri(4, 11, t), "colors": ri(3, 6, t), "shots": ri(30, 40, t),
            "stars": [0, ri(8, 6, t), ri(14, 10, t)]}

GAMES = {
    "fruit_merge":    (fruit_merge,    "score"),
    "color_sort":     (color_sort,     "moves_used (lower is better)"),
    "tower_stack":    (tower_stack,    "perfect_drops"),
    "block_puzzle":   (block_puzzle,   "score"),
    "number_merge":   (number_merge,   "moves_used (lower is better)"),
    "bubble_shooter": (bubble_shooter, "shots_left"),
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
