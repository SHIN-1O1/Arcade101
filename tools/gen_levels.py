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

def color_sort(i, t):
    colors = ri(3, 12, t)
    return {"colors": colors, "capacity": 4, "empty_tubes": 2 if i < 20 else 1 if colors <= 9 else 2,
            "stars": [colors * 6, colors * 4, colors * 3]}

def tower_stack(i, t):
    return {"target_height": ri(10, 45, t), "speed": round(lerp(260, 620, t)), "speed_step": round(lerp(4, 12, t), 1),
            "block_width": ri(360, 260, t), "stars": [0, ri(3, 12, t), ri(6, 22, t)]}

def block_puzzle(i, t):
    return {"grid": 8, "target_lines": ri(4, 40, t), "prefilled": ri(0, 18, t),
            "piece_set": "basic" if i < 10 else "extended", "stars": [0, ri(300, 3000, t), ri(600, 5500, t)]}

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
