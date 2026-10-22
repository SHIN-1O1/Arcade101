# Contributing / development cycle

The goal: `main` always opens and runs in Godot, and any mistake can be undone in one step.

## Branches
| Branch | Purpose | Rules |
|---|---|---|
| `main` | Stable, playable build | Protected. No direct commits, no force push. Changes arrive only by PR. |
| `feature/<game-or-topic>` | New game or feature, e.g. `feature/color_sort`, `feature/real-ads` | Cut from latest `main`. One game or one topic per branch. |
| `fix/<topic>` | Bug fix or revert, e.g. `fix/save-migration` | Cut from latest `main`. |

Delete the branch after its PR merges. Start the next piece of work from a fresh `main`:
```
git checkout main && git pull
git checkout -b feature/<name>
```

## Scope (keep games from disturbing each other)
- A game PR touches only `games/<id>/`, its entry in `data/games.json`, and its generator in
  `tools/gen_levels.py` (then regenerated `games/<id>/levels.json`).
- Shared foundation (`autoload/`, `core/`, `scenes/`, `project.godot`, `tests/`, other games)
  is changed only by a PR whose title and description say so, e.g. "core: add tween helper".
- Save format changes bump `Save.SAVE_VERSION` and migrate in `load_game()`.

## Commits
- Small and focused; one logical change each, message in imperative mood
  ("Add tube pour animation").
- Run the smoke test before every push:
  `godot --headless --import` then `godot --headless -s res://tests/smoke_test.gd`.

## Pull requests
- Open into `main` using the PR template; fill in scope, test, and rollback notes.
- CI runs the headless smoke test on every PR; it must be green before merge.
- Merge with **Squash and merge** so each PR is one commit on `main` (easy to revert).

## Releases and rollback
- Tag releases on `main`: `vMAJOR.MINOR.PATCH` (e.g. `v0.2.0` when the first real game lands).
  `v0.1.0-foundation` marks the original foundation.
  ```
  git checkout main && git pull
  git tag -a v0.2.0 -m "Tube Sort playable" && git push origin v0.2.0
  ```
- Undo a merged PR: `git checkout -b fix/revert-<topic> main`, `git revert <squash-sha>`,
  push, open a PR. Never rewrite `main` history.
- Inspect or build an old version: `git checkout v0.1.0-foundation` (read-only; branch off it
  if a hotfix is needed).
