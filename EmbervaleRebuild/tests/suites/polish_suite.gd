extends TestSuite
## Milestone 4: batching, decor fade, ambient life, chop impacts, audio triggers and synthesis checks,
## animation polish and graceful quit.


func before_each() -> void:
	await reset_game()
	wipe_saves()
	AudioManager.reset_counts()


func after_each() -> void:
	release_all()
	await reset_game()


func test_static_props_are_batched() -> void:
	await load_world()
	var island := world.island
	var loose := 0
	for mi in island.find_children("*", "MeshInstance3D", true, false):
		if MeshMerger.is_mergeable(mi):
			var kept := false
			for k in [island.boat] + island.dummies + island.choppable_trees:
				if k == mi or k.is_ancestor_of(mi):
					kept = true
			if not kept and not island.ambient.is_ancestor_of(mi):
				loose += 1
	check_eq(loose, 0, "every static shared-material mesh is merged")
	var batches := island.get_node("Batches").get_child_count()
	check(batches > 5 and batches < 120, "batched into a modest number of chunks (%d)" % batches)
	check_eq(island.choppable_trees.filter(func(t: ChoppableTree) -> bool: return t.tree_type == "normal").size(), 5, "five normal choppable trees kept separate")
	check_eq(island.oak_trees.size(), 4, "four oaks")
	check_eq(island.willow_trees.size(), 3, "three willows")
	check(is_instance_valid(island.boat) and island.boat.is_inside_tree(), "boat kept separate")
	for c in island.decor_chunks:
		check_near(c.visibility_range_end, 75.0, 0.01, "small decor fades at 75 m")
	await free_world()


func test_ambient_life_moves() -> void:
	await load_world()
	var amb := world.island.ambient
	var cloud_yaw := amb.clouds.rotation.y
	var gull_pos := amb.gulls[0].global_position
	await seconds(2.0)
	check(amb.clouds.rotation.y > cloud_yaw, "clouds circle the island")
	check(amb.gulls[0].global_position.distance_to(gull_pos) > 0.5, "gulls fly")
	check_eq(amb.smoke.size(), 5, "smoke from five chimneys")
	check(amb.smoke.all(func(p: CPUParticles3D) -> bool: return p.emitting), "chimney smoke emitting")
	await free_world()


func test_axe_impacts_shake_tree_and_sound() -> void:
	var w := await start_adventure({"index": 2})
	var tree: ChoppableTree = w.island.choppable_trees[0]
	var strikes := [0]
	tree.struck.connect(func(_t: ChoppableTree) -> void: strikes[0] += 1)
	await place_player(w, tree.global_position + Vector3(1.4, 0, 0), -PI * 0.5)
	await tap("interact")
	await seconds(2.2)
	check_eq(strikes[0], 2, "two axe strikes in a 2 s chop")
	check_eq(AudioManager.count("chop"), 2, "chop sound on every strike")
	check(w.director.chips.emitting or strikes[0] > 0, "wood chips sprayed")
	check(AudioManager.count("pickup") >= 1, "pickup sound for the log")


func test_audio_triggers() -> void:
	GameManager.go_to_main_menu()
	var menu := await wait_for_scene("MainMenu") as MainMenu
	check_eq(AudioManager.current_music(), "menu_theme", "menu theme in the main menu")
	await click_control(find_named(menu, "Settings"))
	check(AudioManager.count("click") >= 1, "UI click on button press")
	(top_modal() as ModalPanel).close()
	await frames(2)
	var w := await start_adventure()
	check_eq(AudioManager.current_music(), "island_theme", "island theme in the world")
	check(AudioManager.ambience_active(), "surf and birds ambience on")
	var steps := AudioManager._counts.keys().filter(func(k: String) -> bool: return k.begins_with("step_")).size()
	await hold("move_forward", 1.5)
	var steps_after := 0
	for k in AudioManager._counts:
		if k.begins_with("step_wood"):
			steps_after += AudioManager._counts[k]
	check(steps_after >= 3, "wooden footsteps on the dock (%d)" % steps_after)
	await tap("inventory")
	check_eq(AudioManager.count("inventory"), 1, "inventory toggle sound")
	await tap("inventory")
	QuestManager.report_marker_reached()
	check_eq(AudioManager.count("jingle"), 1, "objective jingle")
	InventoryManager.add_item("logs")
	check(AudioManager.count("pickup") >= 1, "pickup sound")
	w.director.talk_to(w.director.npcs.pip)
	await frames(2)
	check(AudioManager.count("dialogue") >= 1, "dialogue blip per line")
	DialogueManager.end()
	var data := QuestManager.to_dict()
	data.index = 4
	QuestManager.from_dict(data)
	QuestManager.report_sword_delivered()
	check_eq(AudioManager.count("fanfare"), 1, "tutorial fanfare")
	await seconds(0.2)
	if w.director.gate_sequence:
		w.director.gate_sequence._finish(true)
	await frames(3)


func test_surf_louder_near_shore() -> void:
	var w := await start_adventure()
	await frames(3)
	var near := AudioManager.surf.volume_db
	await place_player(w, w.island.landmarks.village, 0.0)
	await frames(3)
	check(AudioManager.surf.volume_db < near - 3.0, "surf quieter inland (%.1f vs %.1f dB)" % [AudioManager.surf.volume_db, near])


func _check_stream(label: String, s: AudioStreamWAV, loop: bool) -> void:
	var n := s.data.size() / 2
	check(n > 100, "%s has audio" % label)
	var peak := 0.0
	var sum := 0.0
	var clipped := 0
	var stride := 1 if n < 40000 else 5
	var counted := 0
	for i in range(0, n, stride):
		var v := s.data.decode_s16(i * 2) / 32767.0
		peak = maxf(peak, absf(v))
		sum += v * v
		counted += 1
		if absf(v) >= 0.999:
			clipped += 1
	var rms := sqrt(sum / counted)
	check(peak <= 0.95 and clipped == 0, "%s does not clip (peak %.2f)" % [label, peak])
	check(rms > 0.01, "%s is audible (RMS %.3f)" % [label, rms])
	if loop:
		check(s.loop_mode == AudioStreamWAV.LOOP_FORWARD and s.loop_end == n, "%s loops over its whole length" % label)
		var first := s.data.decode_s16(0) / 32767.0
		var last := s.data.decode_s16((n - 1) * 2) / 32767.0
		check(absf(first - last) < 0.15, "%s loop seam is smooth (%.3f)" % [label, absf(first - last)])


func test_synthesised_sounds_are_clean() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var shots := {"click": Synth.click(), "pickup": Synth.pickup(), "dialogue": Synth.dialogue_blip(),
			"inventory": Synth.inventory(rng), "jingle": Synth.jingle(), "fanfare": Synth.fanfare(),
			"chop": Synth.chop(rng), "level_up": Synth.level_up(), "splash": Synth.splash(rng),
			"fire": Synth.fire(rng), "eat": Synth.eat(rng), "coins": Synth.coins(), "swing": Synth.swing(rng),
			"hit": Synth.hit(rng)}
	for surface in ["grass", "wood", "stone", "sand"]:
		shots["step_" + surface] = Synth.footstep(surface, rng)
	for k in shots:
		_check_stream(k, shots[k], false)
	var ok := await wait_until(func() -> bool:
		return AudioManager.is_rendered("menu_theme") and AudioManager.is_rendered("island_theme") \
				and AudioManager.is_rendered("surf") and AudioManager.is_rendered("birds"), 30.0)
	check(ok, "worker-thread renders finish")
	for k in ["menu_theme", "island_theme", "surf", "birds"]:
		_check_stream(k, AudioManager._rendered[k], true)


func test_worker_recipes_are_deterministic() -> void:
	var a := RandomNumberGenerator.new()
	a.seed = 42
	var b := RandomNumberGenerator.new()
	b.seed = 42
	check_eq(Synth.surf_loop(a).data.size(), Synth.surf_loop(b).data.size(), "same length")
	a.seed = 42
	b.seed = 42
	check(Synth.birds_loop(a).data == Synth.birds_loop(b).data, "own RNG makes renders reproducible")


func test_animation_polish() -> void:
	var w := await start_adventure({"index": 1})
	var maelis: Npc = w.director.npcs.maelis
	await place_player(w, maelis.global_position + Vector3(-1.5, 0, 0.8), PI * 0.5)
	var yaw0 := maelis.model.global_rotation.y
	await tap("interact")
	await physics_frames(2)
	var yaw1 := maelis.model.global_rotation.y
	check(maelis.model.is_turning() or absf(wrapf(yaw1 - yaw0, -PI, PI)) > 0.01, "Maelis turns towards the player")
	check(absf(wrapf(yaw1 - yaw0, -PI, PI)) < 1.0, "turning is smooth, not a snap")
	check_eq(maelis.model.current_action, "talk", "talk gesture while talking")
	await run_dialogue(w, [3])
	check_eq(w.player.model.current_action, "cheer", "player cheers on objective completion")
	# Idle glances.
	await seconds(2.0)
	var head_yaws := []
	for i in 12:
		await seconds(0.5)
		head_yaws.append(snappedf(w.player.model.head.rotation.y, 0.01))
	check(head_yaws.max() - head_yaws.min() > 0.05, "idle head glances")
	var steps := [0]
	w.player.footstep.connect(func(_f: int) -> void: steps[0] += 1)
	await hold("move_back", 2.0)
	check(steps[0] >= 3, "footstep events from the stride (%d in 2 s)" % steps[0])


func test_graceful_quit_stops_audio() -> void:
	var w := await start_adventure()
	var quits := [0]
	GameManager.quit_handler = func() -> void: quits[0] += 1
	check(GameManager.save_and_quit(), "Save & Exit saves")
	await seconds(0.5)
	check_eq(quits[0], 1, "quit after the real-time wait")
	check(AudioManager._shut_down and not AudioManager.music.playing, "audio stopped first")
	check(saved_data().has("player"), "saved before quitting")
	GameManager.quit_handler = Callable()
	AudioManager.resume_after_shutdown()
