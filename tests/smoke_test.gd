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
		if games.how_to_play(g.id).get("steps", []).is_empty():
			push_error("%s has no how-to-play steps in data/how_to_play.json" % g.id); errors += 1
		# A game may ship res://games/<id>/check.gd with check_levels(levels) -> error count (e.g. solvability).
		var check_path := "res://games/%s/check.gd" % g.id
		if levels.size() > 0 and ResourceLoader.exists(check_path):
			errors += load(check_path).check_levels(levels)
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
	assert(not save.is_howto_seen("color_sort"))
	save.set_howto_seen("color_sort")
	assert(save.is_howto_seen("color_sort") and not save.is_howto_seen("klondike"))
	save.reset_all()
	errors += await _test_monetization()
	errors += _test_cards()
	for path in ["res://scenes/hub.tscn", "res://scenes/level_select.tscn", "res://scenes/settings.tscn", "res://scenes/game_host.tscn"]:
		root.get_node("Nav").game_id = "color_sort"  # a levels game; endless-only games have no level list
		change_scene_to_file(path)
		await process_frame
		await process_frame
		print("ok ", path)
	for id in ["fruit_merge", "number_merge"]:  # endless runs
		root.get_node("Nav").game_id = id
		root.get_node("Nav").mode = "endless"
		change_scene_to_file("res://scenes/game_host.tscn")
		for i in 10:
			await physics_frame
		print("ok endless ", id)
	root.get_node("Nav").mode = "levels"
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
	# Level 1 won, level 2 failed, level 2 won: the 2nd completed level makes an interstitial due.
	ads.on_level_finished(true, 0)
	if ads.interstitial_due(): push_error("ad due after 1 win"); errors += 1
	ads.on_level_finished(false, 1)  # a fail never counts
	if ads.interstitial_due(): push_error("fail counted toward an ad"); errors += 1
	ads.on_level_finished(true, 1)
	if not ads.interstitial_due(): push_error("no ad due after 2 wins"); errors += 1
	ads.run_after_interstitial(go)
	if ads.provider.shown_interstitials != 1 or shown.size() != 1:
		push_error("interstitial not shown exactly once"); errors += 1
	# Cooldown: more wins right away must not show another ad within the cooldown.
	for i in 2:
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


## Card kit and Klondike: seeded deck, stored deals, and a full headless win of level 1 from a solver move list.
func _test_cards() -> int:
	var errors := 0
	var Deck = load("res://core/cards/deck.gd")
	var CardTable = load("res://core/cards/card_table.gd")
	var Rules = load("res://games/klondike/klondike_rules.gd")
	var Pile = load("res://core/cards/pile.gd")
	var base: Array = Deck.codes()
	var a: Array = Deck.shuffled(base, 42)
	if a != Deck.shuffled(base, 42) or a == Deck.shuffled(base, 43):
		push_error("seeded shuffle is not reproducible"); errors += 1
	var sorted_a := a.duplicate()
	sorted_a.sort()
	if sorted_a != base:
		push_error("shuffle lost cards"); errors += 1
	var games: Node = root.get_node("Games")
	for lv in games.get_levels("klondike"):
		var d: Array = lv.deck.map(func(x): return int(x))
		d.sort()
		if d != base or not [1, 3].has(int(lv.draw)):
			push_error("klondike level %d has a bad deck" % lv.id); errors += 1
	var pool = JSON.parse_string(FileAccess.get_file_as_string("res://games/klondike/deals.json"))
	for key in ["draw1", "draw3"]:
		if pool[key].size() < 20:
			push_error("klondike %s pool too small" % key); errors += 1
	# replay level 1
	var moves = JSON.parse_string(FileAccess.get_file_as_string("res://tests/klondike_level1_moves.json"))
	var t = CardTable.new()
	t.sfx = false
	var rules = Rules.new()
	t.rules = rules
	t.add_pile("stock", "stock")
	t.add_pile("waste", "waste")
	for i in 4:
		t.add_pile("f%d" % i, "foundation")
	for i in 7:
		t.add_pile("t%d" % i, "tableau", Pile.Fan.DOWN)
	var cards: Array = Deck.make_cards(games.get_levels("klondike")[0].deck)
	var idx := 0
	for r in 7:
		for p in range(r, 7):
			t.add_cards([cards[idx]], "t%d" % p)
			cards[idx].face_up = r == p
			idx += 1
	t.add_cards(cards.slice(idx), "stock")
	for m in moves:
		var w = t.pile("waste")
		match m[0]:
			"D":
				rules.draw(t)
			"WF":
				t.move_cards(w, w.cards.size() - 1, rules.foundation_for(t, w.top()))
			"WT":
				t.move_cards(w, w.cards.size() - 1, t.pile("t%d" % m[1]))
			"TF":
				var p = t.pile("t%d" % m[1])
				t.move_cards(p, p.cards.size() - 1, rules.foundation_for(t, p.top()))
			"TT":
				var p = t.pile("t%d" % m[1])
				if not rules.can_drop(t, p.cards.slice(p.cards.size() - m[2]), p, t.pile("t%d" % m[3])):
					push_error("klondike replay: illegal move %s" % [m]); errors += 1
					break
				t.move_cards(p, p.cards.size() - m[2], t.pile("t%d" % m[3]))
	if not rules.is_won(t) or rules.moves != moves.size():
		push_error("klondike replay did not win (moves %d of %d)" % [rules.moves, moves.size()]); errors += 1
	var undone := 0
	while t.undo():
		undone += 1
	if undone != moves.size() or t.pile("stock").cards.size() != 24 or rules.moves != 0:
		push_error("klondike undo did not restore the deal (%d)" % undone); errors += 1
	t.free()
	print("card checks done")
	return errors
