extends "res://tests/suites/playthrough_suite.gd"
## No-teleport quest playthrough (Milestone 7): from a saved, completed tutorial in the plaza, through
## the main menu's Continue, to "The Smith's Apprentice" complete, using only clicks and keys: talk
## to Brann, mine copper and tin in the quarry, smelt a bronze bar at the furnace, smith a dagger on
## the anvil and hand it in. Fails if the player ever jumps between frames.

const QUEST := "smiths_apprentice"


func test_full_tutorial_without_teleporting() -> void:
	note("covered by the playthrough suite")


func _ore_rock(kind: String) -> MiningRock:
	var best: MiningRock = null
	for r in _w.island.mining_rocks:
		if r.rock_type == kind and not r.is_depleted and (best == null \
				or flat_distance(r.global_position, _w.player.global_position) < flat_distance(best.global_position, _w.player.global_position)):
			best = r
	return best


func _mine_one(kind: String) -> bool:
	var ore := kind + "_ore"
	var before := InventoryManager.count(ore)
	for attempt in 3:
		var rock := _ore_rock(kind)
		if rock == null or not await click_target(rock, 0.6):
			continue
		if await wait_until(func() -> bool: return InventoryManager.count(ore) > before, 15.0):
			return true
	return false


func _craft_at(station: CraftStation, recipe: String) -> bool:
	if not await click_target(station, 0.9):
		return false
	if not await wait_until(func() -> bool: return top_modal() is CraftPanel, 15.0):
		return false
	var panel := top_modal() as CraftPanel
	var b := panel.button_for(recipe, "MakeOne")
	if b == null or b.disabled:
		return false
	await click_control(b)
	return await wait_until(func() -> bool: return InventoryManager.has(recipe), 8.0)


func _talk(npc: Npc, picks: Array) -> bool:
	if not await click_target(npc, 1.0):
		return false
	if not await wait_until(func() -> bool: return DialogueManager.active, 15.0):
		return false
	await run_dialogue(_w, picks)
	await frames(2)
	return true


func test_smiths_apprentice_without_teleporting() -> void:
	var t0 := Time.get_ticks_msec()
	var data := GameManager.new_game_data("Wren", Appearance.defaults())
	data.stage = "island"
	data.quest.index = 5
	data.inventory.slots = [{"id": "beginner_sword", "qty": 1}]
	data.player = {"position": [4.5, 0.6, 19.5], "yaw": -PI * 0.5}
	SaveManager.write_save(data)
	GameManager.go_to_main_menu()
	var menu := await wait_for_scene("MainMenu") as MainMenu
	await click_control(menu.continue_button)
	_w = await wait_for_world()
	if not check(_w != null, "world loads"):
		return
	_monitor_on = true
	_last_pos = Vector3.INF
	var brann: Npc = _w.smithy.brann
	# 1. Brann offers the quest and the tools.
	check(await walk_by_clicks(brann.global_position, 5.0), "walked to the smithy")
	check(await _talk(brann, [1]), "talked to Brann")
	check_eq(QuestManager.quest_stage(QUEST), 1, "quest started")
	check(InventoryManager.has("bronze_pickaxe") and InventoryManager.has("hammer"), "got a pickaxe and a hammer")
	# 2. Copper and tin from the quarry.
	check(await walk_by_clicks(_w.island.landmarks.quarry, 2.0), "walked into the quarry")
	check(await _mine_one("copper"), "mined copper ore")
	check(await _mine_one("tin"), "mined tin ore")
	check(QuestManager.has_quest_flag(QUEST, "mined_copper") and QuestManager.has_quest_flag(QUEST, "mined_tin"), "mining ticked the checklist")
	# 3. Smelt and smith at the forge.
	check(await walk_by_clicks(_w.smithy.furnace.front, 3.0), "walked back to the forge")
	check(await _craft_at(_w.smithy.furnace, "bronze_bar"), "smelted a bronze bar")
	check(await _craft_at(_w.smithy.anvil, "bronze_dagger"), "smithed a bronze dagger")
	# 4. Hand it in.
	check(await _talk(brann, []), "talked to Brann again")
	check_eq(QuestManager.quest_stage(QUEST), 2, "quest complete")
	check(not InventoryManager.has("bronze_dagger") and InventoryManager.count("coins") == 60, "dagger traded for 60 coins")
	check(SkillsManager.level("smithing") >= 3 and SkillsManager.level("mining") >= 2, "Smithing and Mining XP")
	await frames(3)
	var saved := saved_data()
	check_eq(int(saved.get("quest", {}).get("quests", {}).get(QUEST, {}).get("stage", 0)), 2, "completion saved")
	check_eq(_jumps, 0, "no teleporting (max step %.3f m)" % _max_step)
	_monitor_on = false
	note("quest playthrough: %.1f s real time; movement %.0f s, actions %.0f s, dialogue %.0f s" % [
			(Time.get_ticks_msec() - t0) / 1000.0, _time.movement, _time.action, _time.dialogue])
