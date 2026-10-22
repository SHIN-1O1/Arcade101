"""FreeCell solver + deal finder for games/freecell (run from the project root).

  python tools/freecell_solver.py build [--count 400] [--workers 4]   # writes tools/freecell_deals.json
  python tools/freecell_solver.py solution <deal_seed>                # move list for one deal

Cards are ints 0..51: suit = c // 13 (0 spades, 1 hearts, 2 diamonds, 3 clubs), rank index = c % 13 (0 = ace).
A deal is a shuffled 52-card order, dealt (identical in games/freecell/game.gd) round-robin: card i goes to
column i % 8, so columns 0-3 get 7 cards and columns 4-7 get 6. The last card of a column is its top.

Moves (what the game's rules accept, and what tests/freecell_level1_moves.json replays):
  ["F", card]            card (a column top or a cell) -> its suit's foundation
  ["C", card]            column top -> a free cell
  ["T", card, col]       `card` and every card below it in its column (or the single cell card) -> column col
Safe foundation moves (aces, twos, and cards both opposite-colour piles already passed) are made for free, like
the game's auto-foundation option; they appear in the list as ["A", card] but are not counted in "moves" (the par).
A multi-card move is one move when (free cells + 1) * 2^(empty columns, not counting the destination) allows it.
"""
import heapq, json, os, random, sys
from multiprocessing import Pool

RED = (False, True, True, False)
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DEALS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "freecell_deals.json")


def shuffled_deck(seed):
    deck = list(range(52))
    random.Random(seed).shuffle(deck)
    return deck


def deal(deck):
    cols = [[] for _ in range(8)]
    for i, c in enumerate(deck):
        cols[i % 8].append(c)
    return cols


def opposite(s):
    return (1, 2) if not RED[s] else (0, 3)


def safe(f, c):
    s, r = c // 13, c % 13
    if f[s] != r:
        return False
    if r <= 1:
        return True
    a, b = opposite(s)
    return f[a] >= r and f[b] >= r


def can_stack(under, c):
    """card c may sit on card `under` (descending, alternating colour)."""
    return under % 13 == c % 13 + 1 and RED[under // 13] != RED[c // 13]


def heuristic(cols, cells, f):
    h = (52 - sum(f)) * 3 + len(cells)
    for col in cols:
        n = len(col)
        for i in range(n):
            c = col[i]
            if i + 1 < n and not can_stack(c, col[i + 1]):
                h += 1  # something sits on it that does not belong there
            # cards above the next-needed card of each suit cost extra
    for s in range(4):
        need = s * 13 + f[s]
        if f[s] < 13:
            for col in cols:
                if need in col:
                    h += (len(col) - 1 - col.index(need)) * 2
    return h


class State:
    __slots__ = ("cols", "cells", "f")

    def __init__(self, cols, cells, f):
        self.cols, self.cells, self.f = cols, cells, f

    def key(self):
        return (tuple(sorted(tuple(c) for c in self.cols)), tuple(sorted(self.cells)), tuple(self.f))


def auto_safe(cols, cells, f, path):
    """Apply every safe foundation move; append them to path as ["F", card, 1]."""
    again = True
    while again:
        again = False
        for col in cols:
            if col and safe(f, col[-1]):
                c = col.pop()
                f[c // 13] += 1
                path.append(["A", c])
                again = True
        for c in list(cells):
            if safe(f, c):
                cells.remove(c)
                f[c // 13] += 1
                path.append(["A", c])
                again = True


def successors(st):
    """Yield (move, new_state). Moves are not yet followed by the free safe moves."""
    cols, cells, f = st.cols, st.cells, st.f
    free = 4 - len(cells)
    empties = [i for i, c in enumerate(cols) if not c]
    # to foundation
    for i, col in enumerate(cols):
        if col and f[col[-1] // 13] == col[-1] % 13:
            c = col[-1]
            nc = [list(x) for x in cols]
            nc[i].pop()
            nf = list(f)
            nf[c // 13] += 1
            yield ["F", c], State(nc, list(cells), nf)
    for c in cells:
        if f[c // 13] == c % 13:
            nf = list(f)
            nf[c // 13] += 1
            yield ["F", c], State([list(x) for x in cols], [x for x in cells if x != c], nf)
    # cell -> column
    for c in cells:
        done_empty = False
        for j, col in enumerate(cols):
            if col:
                if not can_stack(col[-1], c):
                    continue
            else:
                if done_empty:
                    continue
                done_empty = True
            nc = [list(x) for x in cols]
            nc[j].append(c)
            yield ["T", c, j], State(nc, [x for x in cells if x != c], list(f))
    # column -> column (runs)
    for i, col in enumerate(cols):
        if not col:
            continue
        run = 1
        while run < len(col) and can_stack(col[-run - 1], col[-run]):
            run += 1
        for j, dst in enumerate(cols):
            if i == j:
                continue
            empty_dest = not dst
            if empty_dest and j != empties[0]:
                continue  # all empty columns are equivalent
            e = len(empties) - (1 if empty_dest else 0)
            cap = (free + 1) * (2 ** e)
            for n in range(1, min(run, cap) + 1):
                c = col[-n]
                if empty_dest:
                    if n == len(col):
                        continue  # moving a whole column to an empty one gains nothing
                elif not can_stack(dst[-1], c):
                    continue
                nc = [list(x) for x in cols]
                moved = nc[i][-n:]
                del nc[i][-n:]
                nc[j].extend(moved)
                yield ["T", c, j], State(nc, list(cells), list(f))
    # column top -> cell
    if free > 0:
        for i, col in enumerate(cols):
            if col:
                nc = [list(x) for x in cols]
                c = nc[i].pop()
                yield ["C", c], State(nc, cells + [c], list(f))


def solve(deck, limit=60000, weight=1.0):
    """Best-first search. Returns (moves list incl. free safe moves, par, nodes) or None."""
    cols = deal(deck)
    cells, f, path0 = [], [0, 0, 0, 0], []
    auto_safe(cols, cells, f, path0)
    root = State(cols, cells, f)
    seen = {root.key(): None}
    nodes_state = {}
    heap = [(heuristic(cols, cells, f), 0, 0, root.key(), root, None)]
    store = {root.key(): (None, [])}
    counter = 0
    expanded = 0
    while heap and expanded < limit:
        _, g, _, k, st, _ = heapq.heappop(heap)
        expanded += 1
        if sum(st.f) == 52:
            # rebuild path
            seq = []
            cur = k
            while cur is not None:
                parent, mv = store[cur]
                seq = mv + seq
                cur = parent
            full = path0 + seq
            par = sum(1 for m in full if m[0] != "A")
            return full, par, expanded
        for mv, ns in successors(st):
            extra = []
            auto_safe(ns.cols, ns.cells, ns.f, extra)
            nk = ns.key()
            if nk in seen:
                continue
            seen[nk] = None
            store[nk] = (k, [mv] + extra)
            counter += 1
            heapq.heappush(heap, (heuristic(ns.cols, ns.cells, ns.f) * weight + (g + 1) * 0.35, g + 1, counter, nk, ns, None))
    return None


def _work(seed):
    r = solve(shuffled_deck(seed))
    if r is None:
        return None
    full, par, nodes = r
    return {"seed": seed, "deck": shuffled_deck(seed), "moves": par, "nodes": nodes}


def build(count, workers):
    out = []
    seeds = range(1, count * 2)
    with Pool(workers) as pool:
        for r in pool.imap(_work, seeds, chunksize=4):
            if r:
                out.append(r)
            if len(out) >= count:
                break
    with open(DEALS_PATH, "w") as fh:
        json.dump(out, fh, separators=(",", ":"))
    print("wrote", len(out), "deals to", DEALS_PATH)


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "build":
        count, workers = 400, 4
        if "--count" in sys.argv:
            count = int(sys.argv[sys.argv.index("--count") + 1])
        if "--workers" in sys.argv:
            workers = int(sys.argv[sys.argv.index("--workers") + 1])
        build(count, workers)
    elif len(sys.argv) >= 3 and sys.argv[1] == "solution":
        r = solve(shuffled_deck(int(sys.argv[2])))
        print(json.dumps(r[0]) if r else "unsolved")
    else:
        print(__doc__)
