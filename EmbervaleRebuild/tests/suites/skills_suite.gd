extends TestSuite
## Milestone 6: XP table and formulas, every activity, burning and eating, Attack training, the shop,
## island tasks and pending rewards, the Skills panel and XP drops, save/load and old saves.

const DONE := {"index": 5}


func before_each() -> void:
	await reset_game()
	wipe_saves()
	SkillsManager.roll_override = null


func after_each() -> void:
	SkillsManager.roll_override = null
	await reset_game()


func _done_slots(extra: Array = []) -> Array:
	var slots: Array = [{"id": "beginner_sword", "qty": 1}]
	slots.append_array(extra)
	return slots


func _skills(xp: Dictionary, hp: int = 10) -> Dictionary:
	var d := {"attack": 0, "woodcutting": 0, "fishing": 0, "firemaking": 0, "cooking": 0}
	d.merge(xp, true)
	return {"skills": {"xp": d, "hitpoints": hp}}


func _xp(level: int) -> float:
	return SkillData.xp_for_level(level)


func _messages_contain(w: World, text: String) -> bool:
	for m in w.hud.messages:
		if m.contains(text):
			return true
	return false


# --- data and formulas ---------------------------------------------------------------------------------

func test_xp_table() -> void:
	check_eq(SkillData.xp_for_level(1), 0.0, "level 1 at 0 XP")
	check_eq(SkillData.xp_for_level(2), 83.0, "level 2 at 83 XP")
	check_eq(SkillData.xp_for_level(5), 388.0, "level 5 at 388 XP")
	check_eq(SkillData.xp_for_level(10), 1154.0, "level 10 at 1,154 XP")
	check_eq(SkillData.xp_for_level(99), 13034431.0, "level 99 at 13,034,431 XP")
	check_eq(SkillData.level_for_xp(82.9), 1, "just below level 2")
	check_eq(SkillData.level_for_xp(83), 2, "exactly level 2")
	check_eq(SkillData.level_for_xp(1e12), 99, "capped at 99")
	check_near(SkillData.xp_cap(), 13034431.0 * 1.5, 0.01, "XP cap is 1.5 x the level-99 threshold")
	check_near(SkillData.level_progress(SkillData.xp_cap()), 1.0, 0.0001, "progress at 99 is 100%")
	SkillsManager.reset()
	var ups: Array = []
	var cb := func(s: String, l: int) -> void: ups.append([s, l])
	SkillsManager.level_up.connect(cb)
	SkillsManager.add_xp("cooking", 1200.0)
	SkillsManager.level_up.disconnect(cb)
	check_eq(ups, [["cooking", 10]], "a gain crossing several levels notifies once with the final level")
	SkillsManager.add_xp("cooking", 1e9)
	SkillsManager.add_xp("cooking", 1e9)
	check_near(SkillsManager.xp.cooking, SkillData.xp_cap(), 0.01, "XP stops at the cap")
	SkillsManager.reset()


func test_formulas() -> void:
	check_near(SkillData.chop_seconds("normal", 1, false), 2.0, 0.0001, "normal tree 2.0 s")
	check_near(SkillData.chop_seconds("oak", 5, false), 2.6, 0.0001, "oak at level 5: 2.6 s")
	check_near(SkillData.chop_seconds("oak", 15, false), 2.6 * 0.7, 0.0001, "oak 30% faster ten levels later")
	check_near(SkillData.chop_seconds("willow", 10, true), 3.0 * 0.7, 0.0001, "steel axe x0.70")
	check_near(SkillData.chop_seconds("normal", 99, false), 2.0 * 0.55, 0.0001, "speed-up clamps at 0.55")
	check_near(SkillData.catch_chance(1, false), 0.40, 0.0001, "catch 40% at level 1")
	check_near(SkillData.catch_chance(6, false), 0.60, 0.0001, "+4% per level")
	check_near(SkillData.catch_chance(40, false), 0.85, 0.0001, "catch capped at 85%")
	check_near(SkillData.catch_chance(40, true), 1.0, 0.0001, "oak rod +15 points, capped at 100%")
	check_near(SkillData.trout_chance(4), 0.0, 0.0001, "no trout below level 5")
	check_near(SkillData.trout_chance(5), 0.25, 0.0001, "trout 25% at level 5")
	check_near(SkillData.trout_chance(30), 0.60, 0.0001, "trout capped at 60%")
	check_near(SkillData.light_chance(1, 1), 0.60, 0.0001, "light 60% at the required level")
	check_near(SkillData.light_chance(9, 1), 1.0, 0.0001, "light chance capped at 100%")
	check_near(SkillData.burn_chance("raw_shrimp", 1), 0.55, 0.0001, "shrimp burn 55% at level 1")
	check_near(SkillData.burn_chance("raw_shrimp", 16), 0.0, 0.0001, "shrimp never burns from 16")
	check_near(SkillData.burn_chance("raw_trout", 5), 0.55, 0.0001, "trout burn 55% at level 5")
	check_near(SkillData.burn_chance("raw_trout", 12), 0.55 * 8.0 / 15.0, 0.0001, "trout burn falls with level")
	check_near(SkillData.burn_chance("raw_trout", 20), 0.0, 0.0001, "trout never burns from 20")
	SkillsManager.roll_override = 0.3
	check(SkillsManager.chance(0.31) and not SkillsManager.chance(0.3), "roll override is deterministic")


# --- woodcutting ---------------------------------------------------------------------------------------

func test_woodcutting_normal_tree_gives_xp() -> void:
	var w := await start_adventure(DONE, _done_slots())
	var tree: ChoppableTree = w.island.choppable_trees[0]
	await place_player(w, tree.global_position + Vector3(1.4, 0, 0), -PI * 0.5)
	var drops := w.hud.xp_drops.get_child_count()
	await tap("interact")
	await seconds(2.2)
	check_eq(InventoryManager.count("logs"), 1, "one log")
	check_near(SkillsManager.xp.woodcutting, 25.0, 0.001, "25 Woodcutting XP")
	check(tree.is_stump, "normal tree falls after one log")
	check(w.hud.xp_drops.get_child_count() > drops, "XP drop shown")


func test_oak_and_willow_requirements_and_loops() -> void:
	var w := await start_adventure(DONE, _done_slots(), _skills({}))
	var oak: ChoppableTree = w.island.oak_trees[0]
	await place_player(w, oak.global_position + Vector3(1.6, 0, 0), -PI * 0.5)
	w.interaction.use_target(oak)
	await frames(2)
	check(_messages_contain(w, "Woodcutting level of 5"), "oak needs Woodcutting 5")
	check_eq(InventoryManager.count("oak_logs"), 0, "nothing chopped below the level")
	SkillsManager.xp.woodcutting = _xp(5)
	SkillsManager.roll_override = 0.99   # never deplete
	w.interaction.use_target(oak)
	await seconds(2.6 * 3 + 0.3)
	check_eq(InventoryManager.count("oak_logs"), 3, "the player keeps chopping the oak (3 logs in ~7.8 s)")
	check_near(SkillsManager.xp.woodcutting, _xp(5) + 120.0, 0.01, "40 XP per oak log")
	check(QuestManager.is_task_done("chop_oak"), "Chop an oak tree task")
	await hold("move_back", 0.3)
	var held := InventoryManager.count("oak_logs")
	await seconds(3.0)
	check_eq(InventoryManager.count("oak_logs"), held, "moving stops the loop")
	SkillsManager.roll_override = 0.0   # always deplete
	await place_player(w, oak.global_position + Vector3(1.6, 0, 0), -PI * 0.5)
	w.interaction.use_target(oak)
	await seconds(2.0 * 1.0 + 1.0)
	check(oak.is_stump, "depletion roll fells the oak after a log")
	check_eq(InventoryManager.count("oak_logs"), held + 1, "log awarded before the depletion roll")
	var willow: ChoppableTree = w.island.willow_trees[0]
	SkillsManager.xp.woodcutting = _xp(10)
	InventoryManager.add_item("coins", 100)
	await place_player(w, willow.global_position + Vector3(1.6, 0, 0), -PI * 0.5)
	w.interaction.use_target(willow)
	await seconds(3.0 + 0.2)
	check_eq(InventoryManager.count("willow_logs"), 1, "willow log after 3.0 s at level 10")
	check(QuestManager.is_task_done("chop_willow"), "Chop a willow tree task")


func test_steel_axe_is_faster() -> void:
	var w := await start_adventure(DONE, _done_slots([{"id": "steel_axe", "qty": 1}]))
	var tree: ChoppableTree = w.island.choppable_trees[1]
	await place_player(w, tree.global_position + Vector3(1.4, 0, 0), -PI * 0.5)
	await tap("interact")
	await seconds(1.45)
	check_eq(InventoryManager.count("logs"), 1, "steel axe: 2.0 s x 0.70 = 1.4 s per log")


# --- fishing and Tobin -------------------------------------------------------------------------------

func _to_spot(w: World, k: int = 0) -> FishingSpot:
	var spot: FishingSpot = w.skills.fishing_spots[k]
	var dir := Vector2(spot.global_position.x - IslandLayout.POND.x, spot.global_position.z - IslandLayout.POND.y).normalized()
	await place_player(w, w.island.ground_point(IslandLayout.POND + dir * 7.3), IslandLayout.yaw_towards(IslandLayout.POND + dir * 9.0, IslandLayout.POND))
	return spot


func test_tobin_gives_gear_and_fishing_loop() -> void:
	var w := await start_adventure(DONE, _done_slots())
	var spot := await _to_spot(w)
	w.interaction.use_target(spot)
	await frames(2)
	check(_messages_contain(w, "need a fishing rod"), "no rod: fishing explains Tobin")
	w.director.talk_to(w.director.npcs.tobin)
	check(DialogueManager.current.text.contains("borrow"), "Tobin offers gear")
	await run_dialogue(w, [1])
	check(InventoryManager.has("fishing_rod") and InventoryManager.has("tinderbox"), "Tobin gives a rod and a tinderbox")
	SkillsManager.roll_override = 0.0
	w.interaction.use_target(spot)
	await seconds(2.4 * 3 + 0.2)
	check_eq(InventoryManager.count("raw_shrimp"), 3, "catches every 2.4 s with a successful roll")
	check_near(SkillsManager.xp.fishing, 30.0, 0.01, "10 XP per shrimp")
	check(QuestManager.is_task_done("catch_shrimp") and InventoryManager.count("coins") == 10, "Catch a shrimp pays 10 coins")
	await hold("move_back", 0.3)
	SkillsManager.roll_override = 0.99
	await _to_spot(w)
	w.interaction.use_target(spot)
	await seconds(2.4 * 2 + 0.2)
	check_eq(InventoryManager.count("raw_shrimp"), 3, "failed casts grant nothing")
	check_near(SkillsManager.xp.fishing, 30.0, 0.01, "no XP for failed casts")
	await hold("move_back", 0.3)
	w.director.talk_to(w.director.npcs.tobin)
	check(not DialogueManager.has_choices(), "equipped: Tobin gives a tip")
	await run_dialogue(w)


func test_trout_and_capacity_rules() -> void:
	var slots := _done_slots([{"id": "fishing_rod", "qty": 1}, {"id": "raw_shrimp", "qty": 5}])
	for i in 25:
		slots.append({"id": "tinderbox", "qty": 1})
	var w := await start_adventure(DONE, slots)
	var spot := await _to_spot(w)
	SkillsManager.roll_override = 0.0
	w.interaction.use_target(spot)
	await seconds(2.6)
	check_eq(InventoryManager.count("raw_shrimp"), 6, "a full pack still grows an existing stack")
	await hold("move_back", 0.3)
	SkillsManager.xp.fishing = _xp(5)
	await _to_spot(w)
	w.interaction.use_target(spot)
	await frames(2)
	check(_messages_contain(w, "too full to hold any more fish") and not w.player.is_busy(), "at level 5 trout also needs room, so no cast")
	# The first freed slot pays the pending Catch a shrimp reward; the second leaves room for trout.
	InventoryManager.drop_slot(27)
	check_eq(InventoryManager.count("coins"), 10, "pending shrimp-task reward paid into the freed slot")
	InventoryManager.drop_slot(26)
	w.interaction.use_target(spot)
	await seconds(2.6)
	if not check_eq(InventoryManager.count("raw_trout"), 1, "trout once there is room (roll under 25%)"):
		print("    messages: ", w.hud.messages.slice(-6), " busy=", w.player.is_busy(), " free=", InventoryManager.free_slots())
	check_near(SkillsManager.xp.fishing - _xp(5), 50.0, 0.01, "50 XP for trout")


func test_tobin_full_inventory_is_repeatable() -> void:
	var slots := _done_slots()
	for i in 27:
		slots.append({"id": "tinderbox", "qty": 1})
	var w := await start_adventure(DONE, slots)
	w.director.talk_to(w.director.npcs.tobin)
	await run_dialogue(w, [1])
	check(not InventoryManager.has("fishing_rod"), "no room: no rod")
	InventoryManager.drop_slot(5)
	w.director.talk_to(w.director.npcs.tobin)
	check(DialogueManager.current.text.contains("rod"), "asks again: Tobin still offers (they have a tinderbox, no rod)")
	await run_dialogue(w, [1])
	check(InventoryManager.has("fishing_rod"), "repeat request gives the rod")


# --- firemaking ----------------------------------------------------------------------------------------

## Puts the player somewhere a fire may be lit.
func _fire_ready(w: World) -> bool:
	for c in [Vector2(-8, 4), Vector2(8, 34), Vector2(-14, -2), Vector2(6, -24), Vector2(-16, 40)]:
		for k in 8:
			var yaw := k * TAU / 8.0
			await place_player(w, w.island.ground_point(c), yaw)
			w.player.model.face_yaw(yaw)
			if w.skills.placement_error(w.skills.fire_spot()) == "":
				return true
	return false


func test_firemaking_rules() -> void:
	var w := await start_adventure(DONE, _done_slots([{"id": "logs", "qty": 5}]))
	var actions: Array = w.skills.item_actions("logs", 1)
	check(actions.size() == 1 and actions[0][0] == "Light", "logs offer Light")
	w.skills.light("logs")
	check(_messages_contain(w, "need a tinderbox"), "Light needs a tinderbox")
	InventoryManager.add_item("tinderbox")
	await place_player(w, w.island.landmarks.village, 0.0)
	w.skills.light("logs")
	check(_messages_contain(w, "find some open ground"), "no fires in the plaza")
	await place_player(w, w.island.landmarks.dock, 0.0)
	w.skills.light("logs")
	check(_messages_contain(w, "dock or the bridge"), "no fires on the dock")
	if not check(await _fire_ready(w), "found open ground"):
		return
	SkillsManager.roll_override = 0.99   # 60% at level 1: fails
	w.skills.light("logs")
	await seconds(1.9)
	check(_messages_contain(w, "fail to light"), "lighting can fail")
	check_eq(InventoryManager.count("logs"), 5, "a failed attempt consumes no log")
	check_near(SkillsManager.xp.firemaking, 0.0, 0.001, "and grants no XP")
	check(w.player.current_action() == "light", "the player tries again automatically")
	SkillsManager.roll_override = 0.0
	await seconds(1.9)
	check_eq(w.skills.fires.size(), 1, "a fire springs up")
	check_eq(InventoryManager.count("logs"), 4, "one log used")
	check_near(SkillsManager.xp.firemaking, 40.0, 0.001, "40 XP for normal logs")
	check(QuestManager.is_task_done("light_fire"), "Light a fire task")
	check(not w.player.is_busy(), "lighting doesn't repeat after success")
	var fire: Fire = w.skills.fires[0]
	check(Vector2(fire.global_position.x, fire.global_position.z).distance_to(Vector2(w.player.global_position.x, w.player.global_position.z)) < 1.2, "fire 1 m ahead")
	w.skills.light("logs")
	check(_messages_contain(w, "already a fire"), "no fire next to another")
	SkillsManager.xp.firemaking = 0.0
	InventoryManager.add_item("oak_logs")
	w.skills.light("oak_logs")
	check(_messages_contain(w, "Firemaking level of 5"), "oak logs need Firemaking 5")
	await seconds(57.0)
	check(is_instance_valid(fire) and fire.time_left < 3.5, "fire fading near the end")
	await seconds(3.5)
	check(w.skills.fires.is_empty() and not is_instance_valid(fire), "fire burns out after 60 s")


# --- cooking and eating ----------------------------------------------------------------------------------

func _with_fire(w: World) -> Fire:
	InventoryManager.add_item("tinderbox")
	InventoryManager.add_item("logs")
	await _fire_ready(w)
	SkillsManager.roll_override = 0.0
	w.skills.light("logs")
	await seconds(1.9)
	return w.skills.fires[0] if w.skills.fires.size() > 0 else null


func test_cooking_burning_and_singeing() -> void:
	var w := await start_adventure(DONE, _done_slots([{"id": "raw_shrimp", "qty": 2}]))
	var fire := await _with_fire(w)
	if not check(fire != null, "fire lit"):
		return
	SkillsManager.roll_override = 0.0   # burns (55% at level 1) and singes (35%)
	w.interaction.use_target(fire)
	await seconds(1.9)
	check_eq(InventoryManager.count("burnt_shrimp"), 1, "burnt shrimp")
	check_near(SkillsManager.xp.cooking, 0.0, 0.001, "burning gives no XP")
	check_eq(SkillsManager.hitpoints, 9, "singed fingers: -1 hitpoint")
	SkillsManager.roll_override = 0.99   # no burn
	await seconds(1.9)
	check_eq(InventoryManager.count("shrimp"), 1, "cooked shrimp")
	check_near(SkillsManager.xp.cooking, 30.0, 0.001, "30 Cooking XP")
	check(QuestManager.is_task_done("cook_fish"), "Cook a fish task")
	check(not w.player.is_busy(), "stops when no raw fish is left")


func test_cooking_order_capacity_and_fire_expiry() -> void:
	var slots := _done_slots([{"id": "raw_shrimp", "qty": 2}, {"id": "raw_trout", "qty": 1}])
	var w := await start_adventure(DONE, slots, _skills({"cooking": _xp(5)}))
	var fire := await _with_fire(w)
	SkillsManager.roll_override = 0.99
	w.interaction.use_target(fire)
	await seconds(1.9)
	check_eq(InventoryManager.count("trout"), 1, "trout cooks before shrimp")
	check_near(SkillsManager.xp.cooking - _xp(5), 70.0, 0.01, "70 XP for trout")
	await hold("move_back", 0.3)
	check_eq(InventoryManager.count("raw_shrimp"), 2, "moving stopped cooking")
	# Capacity: two raw shrimp and no free slot for either result.
	while InventoryManager.free_slots() > 0:
		InventoryManager.add_item("steel_axe")
	await place_player(w, fire.global_position + Vector3(1.2, 0, 0), -PI * 0.5)
	w.interaction.use_target(fire)
	await frames(2)
	check(_messages_contain(w, "too full to cook") and InventoryManager.count("raw_shrimp") == 2, "no room for the result: raw fish preserved")
	InventoryManager.remove_item("steel_axe", 3)
	fire.time_left = 1.0
	w.interaction.use_target(fire)
	await seconds(1.5)
	check(not w.player.is_busy() and InventoryManager.count("raw_shrimp") == 2, "the fire going out cancels the cook safely")


func test_eating_and_hitpoint_regen() -> void:
	var w := await start_adventure(DONE, _done_slots([{"id": "shrimp", "qty": 2}, {"id": "bread", "qty": 1}]), _skills({}, 4))
	check_eq(w.hud.hp_label.text, "Hitpoints  4 / 10", "HUD shows hitpoints")
	w.skills.eat("bread")
	await seconds(1.1)
	check_eq(SkillsManager.hitpoints, 6, "bread heals 2")
	check(not QuestManager.is_task_done("eat_cooked"), "bread doesn't count as food you cooked")
	w.skills.eat("shrimp")
	await seconds(1.1)
	check_eq(SkillsManager.hitpoints, 9, "shrimp heals 3")
	check(not QuestManager.is_task_done("eat_cooked"), "eating needs the cook-fish task first")
	QuestManager.report_task("cook_fish")
	w.skills.eat("shrimp")
	await seconds(1.1)
	check_eq(SkillsManager.hitpoints, 10, "healing caps at 10")
	check(QuestManager.is_task_done("eat_cooked"), "eating cooked fish completes the task")
	InventoryManager.add_item("trout")
	w.skills.eat("trout")
	await seconds(1.1)
	check_eq(InventoryManager.count("trout"), 0, "eating at full health is allowed")
	SkillsManager.damage(20)
	check_eq(SkillsManager.hitpoints, 1, "hitpoints never drop below 1")
	await seconds(29.5)
	check_eq(SkillsManager.hitpoints, 1, "no regen before 30 s")
	await seconds(0.6)
	check_eq(SkillsManager.hitpoints, 2, "1 hitpoint per 30 s")
	w.open_pause_menu()
	await frames(1900)
	(top_modal() as PausePanel).close()
	await seconds(0.5)
	check_eq(SkillsManager.hitpoints, 2, "pausing freezes regeneration")


# --- attack training -----------------------------------------------------------------------------------

func test_attack_training() -> void:
	var w := await start_adventure({"index": 3}, [])
	var dummy: TrainingDummy = w.island.dummies[0]
	await place_player(w, dummy.global_position + Vector3(-1.5, 0, 0), PI * 0.5)
	w.interaction.use_target(dummy)
	await frames(2)
	check(_messages_contain(w, "Beginner sword"), "training needs the sword")
	await reset_game()
	w = await start_adventure(DONE, _done_slots(), _skills({"attack": _xp(10) - 10.0}))
	dummy = w.island.dummies[0]
	await place_player(w, dummy.global_position + Vector3(-1.5, 0, 0), PI * 0.5)
	await tap("interact")
	await seconds(1.25)
	check_near(SkillsManager.xp.attack, _xp(10) - 2.0, 0.01, "8 Attack XP per 1.2 s swing")
	await seconds(1.25)
	check_eq(SkillsManager.level("attack"), 10, "reached level 10")
	await seconds(1.3)
	check(not w.player.is_busy(), "no new swing at level 10")
	check(QuestManager.is_task_done("attack_5") and QuestManager.is_task_done("level_10"), "level tasks complete")
	await tap("interact")
	check(_messages_contain(w, "nothing more"), "dummies teach nothing past level 10")


# --- shop -----------------------------------------------------------------------------------------------

func test_shop_buy_and_sell() -> void:
	var w := await start_adventure({"index": 4, "inventory_opened": true, "logs_inspected": true}, [{"id": "logs", "qty": 5}])
	await place_player(w, w.island.landmarks.village, 0.0)
	w.interaction.use_target(w.skills.stall)
	await seconds(3.0)
	check(_messages_contain(w, "opens to adventurers"), "stall closed during the tutorial")
	QuestManager.from_dict({"index": 5})
	InventoryManager.add_item("beginner_sword")
	w.interaction.use_target(w.skills.stall)
	var opened := await wait_until(func() -> bool: return top_modal() is ShopPanel, 6.0)
	if not check(opened, "Browse Market stall opens the shop"):
		return
	var shop := top_modal() as ShopPanel
	await frames(3)
	await click_control(shop.button_for("steel_axe", "Buy", false))
	check(shop.status.text.contains("60 coins"), "can't afford the axe")
	await click_control(shop.button_for("logs", "SellOne", true))
	check_eq(InventoryManager.count("coins"), 2 + 10, "sold one log for 2 coins (+10 for the sell task)")
	check(QuestManager.is_task_done("sell_item"), "Sell something to Marla task")
	await click_control(shop.button_for("logs", "SellAll", true))
	check_eq(InventoryManager.count("logs"), 0, "sold all logs")
	check_eq(InventoryManager.count("coins"), 20, "4 more logs at 2 each")
	check(shop.button_for("beginner_sword", "SellOne", true) == null, "the sword can't be sold")
	InventoryManager.add_item("coins", 100)
	InventoryManager.add_item("burnt_shrimp")
	check(not w.skills.sell("burnt_shrimp", true).ok, "burnt fish is worthless")
	await click_control(shop.button_for("steel_axe", "Buy", false))
	check(InventoryManager.has("steel_axe"), "bought the steel axe")
	check(QuestManager.is_task_done("buy_steel_axe"), "Buy the steel axe task (+20)")
	check_eq(InventoryManager.count("coins"), 120 - 60 + 20, "paid 60 coins, earned the task reward")
	check(not w.skills.buy("steel_axe").ok, "a second steel axe is refused")
	check(w.skills.buy("tinderbox").ok and w.skills.buy("tinderbox").ok, "spare tinderboxes are fine")
	await tap("pause")
	await frames(2)
	check(top_modal() == null and not get_tree().paused, "Esc closes the shop")


func test_shop_transactions_use_freed_slots() -> void:
	var slots := _done_slots([{"id": "coins", "qty": 5}])
	for i in 26:
		slots.append({"id": "tinderbox", "qty": 1})
	var w := await start_adventure(DONE, slots)
	check_eq(InventoryManager.free_slots(), 0, "pack full")
	check(w.skills.buy("tinderbox").ok, "paying all coins frees the slot the tinderbox needs")
	check_eq(InventoryManager.count("coins"), 0, "coins spent")
	InventoryManager.add_item("coins", 2)
	var before := InventoryManager.to_dict()
	check(not w.skills.buy("bread").ok, "not enough coins")
	check_eq(InventoryManager.to_dict(), before, "a failed purchase changes nothing")


# --- tasks and rewards ---------------------------------------------------------------------------------

func test_tasks_tracker_pending_rewards_and_finale() -> void:
	var slots := _done_slots()
	for i in 27:
		slots.append({"id": "tinderbox", "qty": 1})
	var w := await start_adventure(DONE, slots)
	check_eq(w.hud.tracker_title.text, "Ready for adventure", "tracker title after the tutorial")
	check(QuestManager.next_tasks(3) == ["catch_shrimp", "light_fire", "cook_fish"], "next three tasks shown")
	QuestManager.report_task("light_fire")
	check(QuestManager.pending_task_rewards == ["light_fire"], "full pack: reward pending")
	await frames(3)
	check_eq(saved_data().quest.pending_task_rewards, ["light_fire"], "pending reward saved")
	InventoryManager.drop_slot(4)
	check_eq(InventoryManager.count("coins"), 10, "pending reward paid once there is room")
	check(QuestManager.pending_task_rewards.is_empty(), "nothing pending")
	await frames(3)
	check_eq(saved_data().quest.pending_task_rewards, [], "payment saved")
	var mastered := [0]
	QuestManager.all_tasks_completed.connect(func() -> void: mastered[0] += 1)
	for t in TaskData.ids():
		QuestManager.report_task(t)
	check_eq(mastered[0], 1, "Driftwood Isle mastered once")
	check(_messages_contain(w, "Driftwood Isle mastered!"), "finale message")
	var coins := InventoryManager.count("coins")
	await frames(3)
	await reset_game()
	GameManager.continue_game()
	await wait_for_world()
	check_eq(mastered[0], 1, "no finale on reload")
	check_eq(InventoryManager.count("coins"), coins, "no rewards paid twice on Continue")


func test_tasks_count_during_tutorial() -> void:
	var w := await start_adventure({"index": 2}, [{"id": "raw_shrimp", "qty": 1}])
	QuestManager.report_task("catch_shrimp")
	check(QuestManager.is_task_done("catch_shrimp"), "tasks complete during the tutorial")
	check_eq(InventoryManager.count("coins"), 10, "and pay")


func test_level_tasks_on_import_once() -> void:
	var res := GameManager.import_save(ProjectSettings.globalize_path("res://tests/fixtures/v1_m6_full.json"))
	check(res.ok, "import")
	GameManager.continue_game()
	var w := await wait_for_world()
	check(QuestManager.is_task_done("level_10"), "imported Woodcutting 10 completes Reach level 10")
	check(not QuestManager.is_task_done("attack_5"), "Attack 1 does not complete Reach Attack 5")
	check_eq(InventoryManager.count("coins"), 35 + 50, "imported coins plus the level task reward")
	check_near(SkillsManager.xp.woodcutting, 1200.5, 0.001, "fractional XP kept")
	await frames(3)
	await reset_game()
	GameManager.continue_game()
	await wait_for_world()
	check_eq(InventoryManager.count("coins"), 85, "no duplicate grant on the next Continue")


# --- UI and saves ----------------------------------------------------------------------------------------

func test_skills_panel_and_level_up_feedback() -> void:
	var w := await start_adventure(DONE, _done_slots())
	await tap("skills")
	check(w.hud.skills_panel.visible, "K opens the Skills panel")
	check_eq(w.hud.skills_panel.rows.woodcutting.level.text, "Level 1", "levels listed")
	AudioManager.reset_counts()
	SkillsManager.add_xp("woodcutting", 400)
	check_eq(w.hud.skills_panel.rows.woodcutting.level.text, "Level 5", "panel updates")
	check(w.hud.skills_panel.rows.woodcutting.xp.text.contains("/"), "XP towards the next level")
	check(_messages_contain(w, "Congratulations, your Woodcutting level is now 5."), "level-up message")
	check(w.skills.sparks.emitting, "gold sparks")
	check_eq(AudioManager.count("level_up"), 1, "level-up jingle")
	await tap("pause")
	check(not w.hud.skills_panel.visible and not get_tree().paused, "Esc closes the Skills panel first")
	await click_control(w.hud.skills_button)
	check(w.hud.skills_panel.visible, "Skills button opens it")


func test_save_round_trip_and_old_saves() -> void:
	var w := await start_adventure(DONE, _done_slots(), _skills({"fishing": 12.5, "cooking": 400}, 7))
	QuestManager.report_task("catch_shrimp")
	GameManager.save_game()
	var data := saved_data()
	check(not data.has("hitpoints") and data.skills.hitpoints == 7, "hitpoints nested in skills")
	check_near(data.skills.xp.fishing, 12.5, 0.001, "fractional XP saved")
	check(not data.skills.has("levels"), "levels are never stored")
	await reset_game()
	GameManager.continue_game()
	await wait_for_world()
	check_eq(SkillsManager.level("cooking"), 5, "XP restored")
	check_eq(SkillsManager.hitpoints, 7, "hitpoints restored")
	check(QuestManager.is_task_done("catch_shrimp"), "tasks restored")
	# An earlier rebuild save without skills or tasks.
	await reset_game()
	var old := {"version": 2, "character": {"name": "Old", "appearance": Appearance.defaults()}, "stage": "island",
			"quest": {"index": 5}, "inventory": {"slots": [{"id": "beginner_sword", "qty": 1}]}}
	write_json(AppPaths.save_path(), old)
	GameManager.continue_game()
	await wait_for_world()
	check_eq(SkillsManager.highest_level(), 1, "older saves load at level 1")
	check_eq(SkillsManager.hitpoints, 10, "and full health")
