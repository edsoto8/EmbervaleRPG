extends "res://tests/suites/playthrough_suite.gd"
## No-teleport skills playthrough: from the end of the tutorial (a saved, completed tutorial standing
## by Maelis) to buying the steel axe, using only clicks and keys: borrow gear from Tobin, catch fish,
## chop logs, light a fire, cook, eat, sell to Marla and buy the steel axe. Rolls are deterministic.


func before_each() -> void:
	await super.before_each()
	SkillsManager.roll_override = null


func after_each() -> void:
	SkillsManager.roll_override = null
	await super.after_each()


func test_full_tutorial_without_teleporting() -> void:
	note("covered by the playthrough suite")


func _open_inventory() -> void:
	if not _w.hud.inventory_panel.visible:
		await tap("inventory")
	await frames(2)


func _use_item(id: String, action: String) -> bool:
	await _open_inventory()
	var slot := InventoryManager.first_slot_of(id)
	if slot < 0:
		return false
	await click_control(_w.hud.inventory_panel.slot_buttons[slot])
	var b := _w.hud.inventory_panel.actions_row.get_node_or_null("Action" + action) as Button
	if b == null:
		return false
	await click_control(b)
	return true


func test_tutorial_end_to_steel_axe_without_teleporting() -> void:
	var t0 := Time.get_ticks_msec()
	var maelis_spot: Vector3
	# Start where the tutorial ends: next to Maelis with the sword, via the real Continue path.
	var data := GameManager.new_game_data("Wren", Appearance.defaults())
	data.stage = "island"
	data.quest.index = 5
	data.inventory.slots = [{"id": "beginner_sword", "qty": 1}]
	data.player = {"position": [19.9, 0.0, 4.0], "yaw": PI * 0.5}
	data.player.position[1] = 0.9
	SaveManager.write_save(data)
	GameManager.go_to_main_menu()
	var menu := await wait_for_scene("MainMenu") as MainMenu
	await click_control(menu.continue_button)
	_w = await wait_for_world()
	if not check(_w != null, "world loads"):
		return
	_monitor_on = true
	_last_pos = Vector3.INF
	# 1. Borrow a rod and tinderbox from Old Tobin.
	var tobin: Npc = _w.director.npcs.tobin
	check(await walk_by_clicks(tobin.global_position, 7.0), "walked to the pond")
	check(await click_target(tobin, 1.0), "clicked Tobin")
	check(await wait_until(func() -> bool: return DialogueManager.active, 10.0), "talking to Tobin")
	await run_dialogue(_w, [1])
	check(InventoryManager.has("fishing_rod") and InventoryManager.has("tinderbox"), "got a rod and a tinderbox")
	# 2. Catch fish (every cast succeeds).
	SkillsManager.roll_override = 0.0
	var spot: FishingSpot = _w.skills.fishing_spots[0]
	check(await click_target(spot, 0.0), "clicked a fishing spot")
	check(await wait_until(func() -> bool: return InventoryManager.count("raw_shrimp") >= 8, 40.0), "caught eight shrimp")
	await hold("move_back", 0.2)
	check(QuestManager.is_task_done("catch_shrimp"), "Catch a shrimp")
	# 3. Chop logs in the forest clearing.
	check(await walk_by_clicks(_w.island.landmarks.forest_clearing, 4.0), "walked to the forest clearing")
	var guard := 0
	while InventoryManager.count("logs") < 2 and guard < 8:
		guard += 1
		var best: ChoppableTree = null
		for tree in _w.island.choppable_trees:
			if tree.tree_type == "normal" and not tree.is_stump and (best == null \
					or flat_distance(tree.global_position, _w.player.global_position) < flat_distance(best.global_position, _w.player.global_position)):
				best = tree
		var had := InventoryManager.count("logs")
		if best and await click_target(best, 2.6):
			await wait_until(func() -> bool: return InventoryManager.count("logs") > had, 12.0)
	check(InventoryManager.count("logs") >= 2, "chopped logs")
	# 4. Light a fire on open ground (walk to the clearing centre and face north).
	check(await walk_by_clicks(_w.island.landmarks.forest_clearing, 0.8), "back to the clearing centre")
	await hold("move_forward", 0.15)
	await seconds(0.3)
	var lit := false
	for attempt in 6:
		if _w.skills.placement_error(_w.skills.fire_spot()) == "":
			check(await _use_item("logs", "Light"), "clicked Light on the logs")
			lit = await wait_until(func() -> bool: return _w.skills.fires.size() > 0, 6.0)
			break
		await hold("move_left", 0.3)
	check(lit, "lit a fire")
	await tap("inventory")
	check(QuestManager.is_task_done("light_fire"), "Light a fire")
	# 5. Cook everything (no burning).
	SkillsManager.roll_override = 0.99
	var fire: Fire = _w.skills.fires[0] if _w.skills.fires.size() > 0 else null
	if fire:
		check(await click_target(fire, 0.4), "clicked the fire")
		check(await wait_until(func() -> bool: return InventoryManager.count("raw_shrimp") == 0, 30.0), "cooked all the shrimp")
	check(QuestManager.is_task_done("cook_fish"), "Cook a fish")
	# 6. Eat one.
	check(await _use_item("shrimp", "Eat"), "clicked Eat on shrimp")
	await wait_until(func() -> bool: return QuestManager.is_task_done("eat_cooked"), 4.0)
	check(QuestManager.is_task_done("eat_cooked"), "Eat some food you cooked")
	await tap("inventory")
	# 7. Sell to Marla and buy the steel axe.
	var stall: MarketStall = _w.skills.stall
	check(await walk_by_clicks(stall.global_position, 6.0), "walked to the market")
	check(await click_target(stall, 0.8), "clicked the market stall")
	var opened := await wait_until(func() -> bool: return top_modal() is ShopPanel, 10.0)
	if not check(opened, "shop opened"):
		return
	var shop := top_modal() as ShopPanel
	await click_control(shop.button_for("shrimp", "SellAll", true))
	check(QuestManager.is_task_done("sell_item"), "Sell something to Marla")
	if InventoryManager.count("coins") < 60 and InventoryManager.has("logs"):
		await click_control(shop.button_for("logs", "SellAll", true))
	check(InventoryManager.count("coins") >= 60, "earned 60 coins (%d)" % InventoryManager.count("coins"))
	await click_control(shop.button_for("steel_axe", "Buy", false))
	check(InventoryManager.has("steel_axe"), "bought the steel axe")
	check(QuestManager.is_task_done("buy_steel_axe"), "Buy the steel axe")
	await click_control(find_named(shop, "Close"))
	check_eq(_jumps, 0, "no teleporting (max step %.3f m)" % _max_step)
	await frames(3)
	var saved := saved_data()
	check(saved.inventory.slots.any(func(s: Variant) -> bool: return s != null and s.id == "steel_axe"), "progress saved")
	var total := 0.0
	for k in _time:
		total += _time[k]
	print("    pacing (game seconds): movement %.1f, dialogue %.1f, action %.1f, idle %.1f, total %.1f; real %.1f s"
			% [_time.movement, _time.dialogue, _time.action, _time.idle, total, (Time.get_ticks_msec() - t0) / 1000.0])
	print("    tasks done: %s; coins %d; levels: fishing %d, woodcutting %d, firemaking %d, cooking %d"
			% [QuestManager.tasks, InventoryManager.count("coins"), SkillsManager.level("fishing"),
			SkillsManager.level("woodcutting"), SkillsManager.level("firemaking"), SkillsManager.level("cooking")])
	print("    (accelerated, deterministic rolls: diagnostic only; human target 5-15 minutes)")
