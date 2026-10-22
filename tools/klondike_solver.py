"""Klondike solver + deal finder for games/klondike (run from the project root).

  python tools/klondike_solver.py build [--per-mode 260] [--workers 4]   # writes tools/klondike_deals.json
  python tools/klondike_solver.py solution <level>                       # atomic winning move list for a level

Cards are ints 0..51: suit = c // 13 (0 spades, 1 hearts, 2 diamonds, 3 clubs), rank index = c % 13 (0 = ace).
A deal is the shuffled 52-card order; dealing (identical in games/klondike/game.gd):
for row r in 0..6, for pile p in r..6: next card to tableau p, face up when r == p. The other 24 cards are
the stock (the last list item is the top). Draw 1 or 3 moves cards stock -> waste (last drawn on top); an
empty stock turns the waste over (stock = reversed waste). Unlimited redeals.

Atomic moves (what the game replays in tests): ["D"] draw/recycle, ["WF"], ["WT", j], ["TF", i],
["TT", i, k, j] (k cards from pile i onto pile j). The search treats "draw until a playable waste card, then
play it" as one macro step and applies safe foundation moves eagerly.
"""
import json, os, random, sys
from multiprocessing import Pool

sys.setrecursionlimit(20000)
RED = (False, True, True, False)
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def deal(deck):
    tab = [[] for _ in range(7)]
    idx = 0
    for r in range(7):
        for p in range(r, 7):
            tab[p].append(deck[idx])
            idx += 1
    return tab, [r for r in range(7)], list(deck[28:])


class Solver:
    def __init__(self, deck, draw, limit):
        tab, nd, stock = deal(deck)
        self.draw, self.limit, self.nodes = draw, limit, 0
        self.seen = set()
        self.root = (tab, nd, [0, 0, 0, 0], stock, [])
        self.path = None

    @staticmethod
    def key(st):
        tab, nd, f, stock, waste = st
        return (tuple(sorted((tuple(t), n) for t, n in zip(tab, nd))), tuple(f), tuple(stock), tuple(waste))

    def solve(self):
        try:
            self.path = self._dfs(self.root, [])
        except StopIteration:
            self.path = None
        return self.path

    @staticmethod
    def _safe(f, c):
        s, r = c // 13, c % 13
        if f[s] != r:
            return False
        if r <= 1:
            return True
        o = (1, 2) if not RED[s] else (0, 3)
        return min(f[o[0]], f[o[1]]) >= r

    def _auto(self, st, atoms):
        """Apply all safe foundation moves. Mutates st (already a copy) and appends atoms."""
        tab, nd, f, stock, waste = st
        moved = True
        while moved:
            moved = False
            for i in range(7):
                t = tab[i]
                if len(t) > nd[i] and self._safe(f, t[-1]):
                    f[t[-1] // 13] += 1
                    t.pop()
                    if len(t) == nd[i] and nd[i] > 0:
                        nd[i] -= 1
                    atoms.append(["TF", i])
                    moved = True
            if waste and self._safe(f, waste[-1]):
                f[waste[-1] // 13] += 1
                waste.pop()
                atoms.append(["WF"])
                moved = True

    @staticmethod
    def _copy(st):
        tab, nd, f, stock, waste = st
        return ([list(t) for t in tab], list(nd), list(f), list(stock), list(waste))

    def _fits(self, c, tab, nd, j):
        t = tab[j]
        if not t:
            return c % 13 == 12
        if len(t) <= nd[j]:
            return False
        tc = t[-1]
        return tc % 13 == c % 13 + 1 and RED[tc // 13] != RED[c // 13]

    def _moves(self, st):
        """Yield (priority, next_state, atoms)."""
        tab, nd, f, stock, waste = st
        out = []
        # tableau -> tableau
        empty_done = False
        for i in range(7):
            t = tab[i]
            if len(t) <= nd[i]:
                continue
            for s in range(nd[i], len(t)):
                if s > nd[i]:
                    prev = t[s - 1]
                    if f[prev // 13] != prev % 13:
                        continue
                # run s..end must be an alternating descending sequence
                ok = True
                for q in range(s, len(t) - 1):
                    a, b = t[q], t[q + 1]
                    if not (a % 13 == b % 13 + 1 and RED[a // 13] != RED[b // 13]):
                        ok = False
                        break
                if not ok:
                    continue
                c = t[s]
                for j in range(7):
                    if j == i:
                        continue
                    if not tab[j]:
                        if c % 13 != 12 or s == 0 or empty_done:
                            continue
                    elif not self._fits(c, tab, nd, j):
                        continue
                    n = self._copy(st)
                    run = n[0][i][s:]
                    del n[0][i][s:]
                    n[0][j].extend(run)
                    pri = 0
                    if s == nd[i] and nd[i] > 0:
                        n[1][i] -= 1
                        pri = 3
                    elif s == 0:
                        pri = 2
                    out.append((pri, n, [["TT", i, len(run), j]]))
                    if not tab[j]:
                        empty_done = True
        # waste macro: draw until the top card has a destination
        s, w = list(stock), list(waste)
        atoms = []
        seen = set()
        while True:
            kk = (tuple(s), tuple(w))
            if kk in seen:
                break
            seen.add(kk)
            if w:
                c = w[-1]
                dests = []
                if f[c // 13] == c % 13:
                    dests.append("F")
                for j in range(7):
                    if self._fits(c, tab, nd, j):
                        dests.append(j)
                        if not tab[j]:
                            break
                for d in dests:
                    n = self._copy(st)
                    n[3][:] = s
                    n[4][:] = w
                    n[4].pop()
                    if d == "F":
                        n[2][c // 13] += 1
                        a = atoms + [["WF"]]
                    else:
                        n[0][d].append(c)
                        a = atoms + [["WT", d]]
                    out.append((1 if d != "F" else 2, n, a))
            if s:
                for _ in range(min(self.draw, len(s))):
                    w.append(s.pop())
                atoms = atoms + [["D"]]
            elif w:
                s = w[::-1]
                w = []
                atoms = atoms + [["D"]]
            else:
                break
        out.sort(key=lambda m: -m[0])
        return out

    def _dfs(self, st, path):
        self.nodes += 1
        if self.nodes > self.limit:
            raise StopIteration
        if sum(st[2]) == 52:
            return path
        for _, n, atoms in self._moves(st):
            self._auto(n, atoms)
            k = self.key(n)
            if k in self.seen:
                continue
            self.seen.add(k)
            r = self._dfs(n, path + atoms)
            if r is not None:
                return r
        return None


def solve(deck, draw, limit=60000):
    sv = Solver(deck, draw, limit)
    st = sv.root
    first = []
    sv._auto(st, first)
    sv.seen.add(sv.key(st))
    try:
        r = sv._dfs(st, first)
    except StopIteration:
        r = None
    return (r, sv.nodes)


def _job(args):
    seed, draw, limit = args
    deck = list(range(52))
    random.Random(seed).shuffle(deck)
    path, nodes = solve(deck, draw, limit)
    return {"seed": seed, "deck": deck, "nodes": nodes, "moves": len(path) if path else 0, "ok": path is not None}


def build(per_mode, workers):
    out = {}
    for name, draw in (("draw1", 1), ("draw3", 3)):
        jobs = [(100000 * draw + k * 7919 + 13, draw, 60000) for k in range(per_mode)]
        with Pool(workers) as p:
            res = p.map(_job, jobs, chunksize=2)
        good = [r for r in res if r["ok"]]
        print(name, "solved", len(good), "of", len(res), flush=True)
        out[name] = good
    with open(os.path.join(ROOT, "tools", "klondike_deals.json"), "w") as f:
        json.dump(out, f)


def replay_check(deck, draw, atoms):
    """Independent replay of atoms with the plain rules; True if it ends with all 52 on the foundation."""
    tab, nd, stock = deal(deck)
    waste, f = [], [0] * 4
    for a in atoms:
        m = a[0]
        if m == "D":
            if stock:
                for _ in range(min(draw, len(stock))):
                    waste.append(stock.pop())
            else:
                stock, waste = waste[::-1], []
        elif m == "WF":
            c = waste.pop(); assert f[c // 13] == c % 13; f[c // 13] += 1
        elif m == "WT":
            c = waste.pop(); t = tab[a[1]]
            assert (not t and c % 13 == 12) or (t and len(t) > nd[a[1]] and t[-1] % 13 == c % 13 + 1 and RED[t[-1] // 13] != RED[c // 13])
            t.append(c)
        elif m == "TF":
            t = tab[a[1]]; c = t.pop(); assert f[c // 13] == c % 13; f[c // 13] += 1
            if len(t) == nd[a[1]] and nd[a[1]] > 0: nd[a[1]] -= 1
        elif m == "TT":
            _, i, k, j = a
            run = tab[i][-k:]; del tab[i][-k:]
            t = tab[j]
            assert (not t and run[0] % 13 == 12) or (t and t[-1] % 13 == run[0] % 13 + 1 and RED[t[-1] // 13] != RED[run[0] // 13])
            t.extend(run)
            if len(tab[i]) == nd[i] and nd[i] > 0: nd[i] -= 1
    return sum(f) == 52


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "build":
        n = int(sys.argv[sys.argv.index("--per-mode") + 1]) if "--per-mode" in sys.argv else 260
        w = int(sys.argv[sys.argv.index("--workers") + 1]) if "--workers" in sys.argv else 4
        build(n, w)
    elif cmd == "solution":
        lv = json.load(open(os.path.join(ROOT, "games", "klondike", "levels.json")))["levels"][int(sys.argv[2]) - 1]
        path, nodes = solve(lv["deck"], lv["draw"], 400000)
        assert path and replay_check(lv["deck"], lv["draw"], path)
        print(json.dumps(path))
    else:
        print(__doc__)
