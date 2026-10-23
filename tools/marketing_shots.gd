extends SceneTree
## Renders Play Store screenshots: hub, level select and one board per playable game.
##   tools/marketing_shots.sh           (Linux / the cloud, uses xvfb)
## Writes store/screenshots/NN_name.png. It fills a throwaway save with some stars so the
## hub looks lived in, so run it with the save redirected (the .sh does this), never on your real save.

const OUT := "res://store/screenshots/"
var _n := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var save: Node = root.get_node("Save")
	var nav: Node = root.get_node("Nav")
	var games: Node = root.get_node("Games")
	save.reset_all()
	save.set_setting("music", false)
	save.set_setting("sound", false)
	var playable := []
	for g in games.games:
		if g.get("status", "") != "placeholder":
			playable.append(g)
	# A believable save: first levels done with a mix of stars, one best score for endless games.
	for g in playable:
		save.set_howto_seen(g.id)  # no first-entry how-to card over the board
		if games.has_levels(g.id):
			for i in 9:
				save.record_result(g.id, i, 1 + (i * 7 + g.id.length()) % 3)
		if games.has_endless(g.id):
			save.record_score(g.id, 800 + g.id.length() * 310)
	nav.to_hub()
	await _shot("hub", 1.2)
	var first_levels = playable.filter(func(g): return games.has_levels(g.id))
	if not first_levels.is_empty():
		nav.to_level_select(first_levels[0].id)
		await _shot("levels_" + first_levels[0].id, 1.2)
	for g in playable:
		if games.has_levels(g.id):
			nav.play(g.id, 9)
		else:
			nav.play_endless(g.id)
		await _shot("play_" + g.id, 2.0)
	print("MARKETING SHOTS DONE: ", _n)
	quit(0)


func _shot(label: String, wait_sec: float) -> void:
	await create_timer(0.6).timeout  # screen transition
	await create_timer(wait_sec).timeout
	_n += 1
	var img := root.get_texture().get_image()
	var path := "%s%02d_%s.png" % [OUT, _n, label]
	img.save_png(path)
	print("saved ", path, " ", img.get_size())
