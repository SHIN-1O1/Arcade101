class_name BaseGame
extends Control
## Contract every mini-game follows. A game is a scene whose root extends
## BaseGame, plus res://games/<id>/levels.json. The GameHost does the rest
## (top bar, saving, results, ads).
##
## Lifecycle: GameHost instances the scene, adds it, then calls
## start_level(level_data, index). The game emits `finished` exactly once.

## won=false means failed. stars is 1..3 when won, 0 when failed.
signal finished(won: bool, stars: int)
## Optional: update the host's HUD line (score, moves left, etc).
signal status_changed(text: String)
## Optional but expected: drives the host's live star meter. Emit through report_progress().
signal star_progress(value: float, lower_is_better: bool)

## Endless mode: the run is over (no winning). The host records the score and shows the card.
signal run_ended(score: int)
## Endless mode: the live score, for the host's Score / Best bar. Emit through report_score().
signal score_changed(score: int)

var level: Dictionary = {}
var level_index := 0
var _done := false


func start_level(level_data: Dictionary, index: int) -> void:
	level = level_data
	level_index = index
	_done = false
	_on_start()


## Override: build the board from `level`.
func _on_start() -> void:
	pass


## Stars from a score using the level's "stars" thresholds [one, two, three].
## Set lower_is_better for metrics like moves used.
func stars_for(value: float, lower_is_better := false) -> int:
	var t: Array = level.get("stars", [])
	var stars := 0
	for i in t.size():
		if (value <= t[i]) if lower_is_better else (value >= t[i]):
			stars = i + 1
	return stars


## Call whenever the star metric changes (and once at start) so the player sees which
## star they are heading for. Same value and direction you pass to stars_for().
func report_progress(value: float, lower_is_better := false) -> void:
	star_progress.emit(value, lower_is_better)


## Endless mode: call whenever the score changes (and once at start with 0).
func report_score(score: int) -> void:
	score_changed.emit(score)


## Endless mode: call exactly once when the run is over (instead of win/fail).
func end_run(score: int) -> void:
	if _done:
		return
	_done = true
	run_ended.emit(score)


## Endless mode: true when this run is endless (level.endless, set by the host).
func is_endless() -> bool:
	return bool(level.get("endless", false))


## Difficulty-by-score hook: 0.0 at score 0 rising to 1.0 at the game's "ramp_score"
## (games.json "endless" block, default 5000). Games map it to their own knobs.
func difficulty(score: int) -> float:
	return clampf(float(score) / maxf(1.0, float(level.get("ramp_score", 5000))), 0.0, 1.0)


func win(stars: int) -> void:
	if _done:
		return
	_done = true
	finished.emit(true, clampi(stars, 1, 3))


func fail() -> void:
	if _done:
		return
	_done = true
	finished.emit(false, 0)


## Seeded RNG so a level plays the same every time.
func make_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(level.get("seed", level_index + 1))
	return rng
