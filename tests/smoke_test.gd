extends SceneTree
## Headless smoke test:  godot --headless -s res://tests/smoke_test.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var errors := 0
	var games: Node = root.get_node("Games")
	for g in games.games:
		var levels: Array = games.get_levels(g.id)
		if levels.size() != 30:
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
	errors += await _test_monetization()
	for path in ["res://scenes/hub.tscn", "res://scenes/level_select.tscn", "res://scenes/settings.tscn", "res://scenes/game_host.tscn"]:
		root.get_node("Nav").game_id = "fruit_merge"
		change_scene_to_file(path)
		await process_frame
		await process_frame
		print("ok ", path)
	print("SMOKE TEST ", "PASSED" if errors == 0 else "FAILED (%d)" % errors)
	quit(errors)



## Ad pacing and purchase flow against the mock providers (no plugin needed).
func _test_monetization() -> int:
	var errors := 0
	var ads: Node = root.get_node("Ads")
	var iap: Node = root.get_node("IAP")
	var save: Node = root.get_node("Save")
	var cfg = load("res://core/monetization/ad_config.gd")
	save.reset_all()
	save.set_no_ads(false)
	if ads.provider_name != "mock" or iap.provider_name != "mock":
		push_error("expected mock providers, got %s / %s" % [ads.provider_name, iap.provider_name]); errors += 1
	# Test unit IDs only, and nothing real committed.
	for id in [cfg.interstitial_id(), cfg.rewarded_id(), cfg.banner_id()]:
		if not id.begins_with("ca-app-pub-3940256099942544/"):
			push_error("non-test ad unit id in use: %s" % id); errors += 1
	var shown := []
	var go := func(): shown.append(ads.provider.shown_interstitials)
	# Levels 1-3 won: the 3rd completed level makes an interstitial due.
	ads.on_level_finished(true, 0); ads.on_level_finished(true, 1)
	if ads.interstitial_due(): push_error("ad due after 2 wins"); errors += 1
	ads.on_level_finished(false, 2)  # a fail never counts
	if ads.interstitial_due(): push_error("fail counted toward an ad"); errors += 1
	ads.on_level_finished(true, 2)
	if not ads.interstitial_due(): push_error("no ad due after 3 wins"); errors += 1
	ads.run_after_interstitial(go)
	if ads.provider.shown_interstitials != 1 or shown.size() != 1:
		push_error("interstitial not shown exactly once"); errors += 1
	# Cooldown: three more wins right away must not show another ad within 60 s.
	for i in 3:
		ads.on_level_finished(true, 5 + i)
	if ads.interstitial_due(): push_error("cooldown ignored"); errors += 1
	ads.run_after_interstitial(go)
	if ads.provider.shown_interstitials != 1 or shown.size() != 2:
		push_error("cooldown: ad shown or continuation lost"); errors += 1
	# No Ads suppresses everything.
	save.set_no_ads(true)
	ads.on_level_finished(true, 10)
	if ads.interstitial_due(): push_error("ad due despite remove_ads"); errors += 1
	save.set_no_ads(false)
	# Purchase flow (mock succeeds after a short delay) and restore.
	var result := []
	iap.purchase_finished.connect(func(id, ok): result.append([id, ok]))
	iap.purchase()
	await create_timer(0.6).timeout
	if result != [["remove_ads", true]] or not save.has_no_ads():
		push_error("mock purchase did not grant remove_ads: %s" % [result]); errors += 1
	save.set_no_ads(false)
	var restored := []
	iap.restore_finished.connect(func(found, _m): restored.append(found))
	iap.restore_purchases()
	if restored != [true] or not save.has_no_ads():
		push_error("restore did not re-grant remove_ads"); errors += 1
	# Rewarded hook.
	var granted := []
	ads.rewarded_finished.connect(func(g): granted.append(g))
	ads.show_rewarded()
	await create_timer(0.6).timeout
	if granted != [true]: push_error("rewarded not granted"); errors += 1
	save.reset_all()
	print("monetization checks done")
	return errors
