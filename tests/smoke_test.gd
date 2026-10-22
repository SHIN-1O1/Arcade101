extends SceneTree
## Headless smoke test:  godot --headless -s res://tests/smoke_test.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var errors := 0
	var games: Node = root.get_node("Games")
	for g in games.games:
		var levels: Array = games.get_levels(g.id)
		if games.has_levels(g.id) and levels.size() != 30:
			push_error("%s has %d levels" % [g.id, levels.size()]); errors += 1
		var game = load(g.scene).instantiate()
		if not game is BaseGame:
			push_error("%s root is not BaseGame" % g.id); errors += 1
		game.free()
	var fb: Node = root.get_node("Feedback")
	for sfx_name in fb.SFX:
		if load("%s%s.ogg" % [fb.SFX_DIR, fb.SFX[sfx_name][0]]) == null:
			push_error("missing sfx %s" % sfx_name); errors += 1
	for track in ["menu", "game"]:
		if load("%s%s.ogg" % [fb.MUSIC_DIR, track]) == null:
			push_error("missing music %s" % track); errors += 1
	var save: Node = root.get_node("Save")
	save.reset_all()
	assert(save.is_unlocked("color_sort", 0) and not save.is_unlocked("color_sort", 1))
	save.record_result("color_sort", 0, 2)
	assert(save.is_unlocked("color_sort", 1) and save.total_stars("color_sort") == 2)
	save.record_result("color_sort", 0, 1)
	assert(save.get_stars("color_sort", 0) == 2)
	save.reset_all()
	assert(save.get_high_score("number_merge") == 0)
	assert(save.record_score("number_merge", 120) and not save.record_score("number_merge", 100))
	assert(save.get_high_score("number_merge") == 120)
	assert(games.has_endless("number_merge") and not games.has_levels("number_merge"))
	assert(games.endless_level("number_merge").endless)
	save.reset_all()
	for path in ["res://scenes/hub.tscn", "res://scenes/level_select.tscn", "res://scenes/settings.tscn", "res://scenes/game_host.tscn"]:
		root.get_node("Nav").game_id = "fruit_merge"
		change_scene_to_file(path)
		await process_frame
		await process_frame
		print("ok ", path)
	print("SMOKE TEST ", "PASSED" if errors == 0 else "FAILED (%d)" % errors)
	quit(errors)
