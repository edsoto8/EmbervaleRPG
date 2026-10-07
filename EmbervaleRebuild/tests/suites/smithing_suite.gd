extends TestSuite
## Milestone 7: mining (tools, levels, depletion and respawn, cancellation), smelting with iron
## failures, smithing through the crafting panel, capacity, Brann's quest stages, tool recovery, the
## hand-in transaction, the shop additions, the tracker and quest save validation.

const DONE := {"index": 5}
const QUEST := "smiths_apprentice"


func before_each() -> void:
	await reset_game()
	wipe_saves()
	SkillsManager.roll_override = null


func after_each() -> void:
	SkillsManager.roll_override = null
	await reset_game()


func _slots(extra: Array = []) -> Array:
	var slots: Array = [{"id": "beginner_sword", "qty": 1}]
	slots.append_array(extra)
	return slots


## Fills the pack to 28 slots with logs-free junk after `extra`.
func _full(extra: Array = []) -> Array:
	var slots := _slots(extra)
	while slots.size() < 28:
		slots.append({"id": "bronze_helm", "qty": 1})
	return slots


func _skills(xp: Dictionary) -> Dictionary:
	var d := {}
	for s in SkillData.SKILLS:
		d[s] = 0
	d.merge(xp, true)
	return {"skills": {"xp": d, "hitpoints": 10}}


func _xp(level: int) -> float:
	return SkillData.xp_for_level(level)


func _said(w: World, text: String) -> bool:
	for m in w.hud.messages:
		if m.contains(text):
			return true
	return false


func _rock(w: World, kind: String, nth: int = 0) -> MiningRock:
	var seen := 0
	for r in w.island.mining_rocks:
		if r.rock_type == kind:
			if seen == nth:
				return r
			seen += 1
	return null


func _mine(w: World, rock: MiningRock) -> void:
	var inward: Vector3 = (w.island.landmarks.quarry - rock.global_position)
	inward.y = 0
	await place_player(w, rock.global_position + inward.normalized() * 1.45)
	w.interaction.use_target(rock)
	await frames(2)


func _open_station(w: World, station: CraftStation) -> CraftPanel:
	await place_player(w, station.front)
	w.interaction.use_target(station)
	await frames(3)
	return top_modal() as CraftPanel


func _talk_brann(w: World, picks: Array = []) -> void:
	w.director.talk_to(w.smithy.brann)
	await frames(2)
	await run_dialogue(w, picks)
	await frames(2)


# --- data -------------------------------------------------------------------------------------------

func test_data_and_formulas() -> void:
	check("mining" in SkillData.SKILLS and "smithing" in SkillData.SKILLS, "Mining and Smithing are skills")
	check_eq(SkillData.SKILLS.size(), 7, "seven skills")
	check_near(SkillData.mine_seconds("copper", 1, false), 2.4, 0.0001, "copper 2.4 s at level 1")
	check_near(SkillData.mine_seconds("iron", 8, false), 3.0, 0.0001, "iron 3.0 s at level 8")
	check_near(SkillData.mine_seconds("tin", 11, false), 2.4 * 0.7, 0.0001, "3% faster per level")
	check_near(SkillData.mine_seconds("tin", 1, true), 2.4 * 0.7, 0.0001, "steel pickaxe x0.70")
	check_near(SkillData.mine_seconds("copper", 99, false), 2.4 * 0.55, 0.0001, "speed-up clamps at 0.55")
	check_near(SkillData.smelt_chance("bronze_bar", 1), 1.0, 0.0001, "bronze never fails")
	check_near(SkillData.smelt_chance("iron_bar", 8), 0.5, 0.0001, "iron 50% at level 8")
	check_near(SkillData.smelt_chance("iron_bar", 12), 0.7, 0.0001, "+5% per level")
	check_near(SkillData.smelt_chance("iron_bar", 30), 1.0, 0.0001, "iron capped at 100%")
	check_eq(SkillData.recipes_for("furnace"), ["bronze_bar", "iron_bar"], "furnace recipes")
	check_eq(SkillData.recipes_for("anvil"), ["bronze_dagger", "bronze_pickaxe", "bronze_helm", "iron_dagger", "iron_helm"], "anvil recipes")
	for id in ["copper_ore", "tin_ore", "iron_ore", "bronze_bar", "iron_bar", "bronze_dagger", "bronze_helm",
			"iron_dagger", "iron_helm", "hammer", "bronze_pickaxe", "steel_pickaxe"]:
		check(ItemDB.exists(id) and ItemDB.info(id).has("icon") and ItemDB.examine_text(id) != "", "%s defined with an icon" % id)
	check(ItemDB.is_stackable("copper_ore") and ItemDB.is_stackable("bronze_bar"), "ores and bars stack")
	check(not ItemDB.is_stackable("bronze_dagger") and not ItemDB.is_stackable("hammer"), "gear does not stack")
	check_eq(ItemDB.sell_price("steel_pickaxe"), 0, "Marla won't buy back her pickaxe")


# --- mining -----------------------------------------------------------------------------------------

func test_mining_needs_a_pickaxe_and_the_level() -> void:
	var w := await start_adventure(DONE, _slots())
	var copper := _rock(w, "copper")
	await _mine(w, copper)
	check(_said(w, "need a pickaxe"), "no pickaxe: told to find one")
	check_eq(w.player.current_action(), "", "nothing started")
	InventoryManager.add_item("bronze_pickaxe")
	var iron := _rock(w, "iron")
	await _mine(w, iron)
	check(_said(w, "Mining level of 8"), "iron needs Mining 8")
	await seconds(3.3)
	check_eq(InventoryManager.count("iron_ore"), 0, "no iron below the level")


func test_mining_gives_ore_xp_then_rubble_and_respawn() -> void:
	var w := await start_adventure(DONE, _slots([{"id": "bronze_pickaxe", "qty": 1}]))
	var copper := _rock(w, "copper")
	await _mine(w, copper)
	check_eq(w.player.current_action(), "mine", "swinging the pickaxe")
	await seconds(1.0)
	check_eq(InventoryManager.count("copper_ore"), 0, "nothing before the swing completes")
	await seconds(1.6)
	check_eq(InventoryManager.count("copper_ore"), 1, "one copper ore after 2.4 s")
	check_near(SkillsManager.xp.mining, 17.5, 0.001, "17.5 Mining XP")
	check(copper.is_depleted and not copper.is_available(), "the rock is rubble")
	check(QuestManager.has_quest_flag(QUEST, "mined_copper"), "mining copper ticks the quest flag (even before starting)")
	copper.interact(w.player)
	await frames(1)
	check(_said(w, "no ore left"), "rubble says it is empty")
	await seconds(8.3)
	check(not copper.is_depleted, "copper respawns after 8 s")
	check(AudioManager.count("mine") >= 2, "pickaxe impacts clink")


func test_mining_cancel_and_full_inventory() -> void:
	var w := await start_adventure(DONE, _slots([{"id": "bronze_pickaxe", "qty": 1}]))
	var tin := _rock(w, "tin")
	await _mine(w, tin)
	await seconds(1.0)
	await hold("move_back", 0.3)
	await seconds(2.0)
	check_eq(InventoryManager.count("tin_ore"), 0, "moving away grants nothing")
	check(not tin.is_depleted, "and leaves the rock full")
	await reset_game()
	w = await start_adventure(DONE, _full([{"id": "bronze_pickaxe", "qty": 1}]))
	await _mine(w, _rock(w, "tin"))
	check(_said(w, "too full to hold any more ore"), "a full pack stops mining before it starts")
	check_eq(w.player.current_action(), "", "no swing")


func test_steel_pickaxe_and_iron() -> void:
	var w := await start_adventure(DONE, _slots([{"id": "steel_pickaxe", "qty": 1}]), _skills({"mining": _xp(8)}))
	var iron := _rock(w, "iron")
	await _mine(w, iron)
	await seconds(2.1 + 0.15)
	check_eq(InventoryManager.count("iron_ore"), 1, "steel pickaxe mines iron in 2.1 s")
	check_near(SkillsManager.xp.mining, _xp(8) + 35.0, 0.001, "35 XP for iron")
	await seconds(15.3)
	check(not iron.is_depleted, "iron respawns after 15 s")


# --- smelting ---------------------------------------------------------------------------------------

func test_smelting_bronze_and_iron() -> void:
	var w := await start_adventure(DONE, _slots([{"id": "copper_ore", "qty": 2}, {"id": "tin_ore", "qty": 2},
			{"id": "iron_ore", "qty": 3}]))
	var panel := await _open_station(w, w.smithy.furnace)
	if not check(panel is CraftPanel, "the furnace opens the crafting panel"):
		return
	check(not panel.button_for("bronze_bar", "MakeAll").disabled, "bronze bar available")
	check(panel.button_for("iron_bar", "MakeOne").disabled, "iron bar disabled below level 8")
	check(panel.list.get_node("Row_iron_bar").find_child("Reason", true, false).text.contains("Smithing level of 8"), "with the reason")
	await click_control(panel.button_for("bronze_bar", "MakeAll"))
	await frames(2)
	check(top_modal() == null, "choosing closes the panel")
	check(w.smithy.furnace.active, "the furnace roars while smelting")
	await seconds(1.8 * 2 + 0.4)
	check_eq(InventoryManager.count("bronze_bar"), 2, "two bronze bars")
	check_eq(InventoryManager.count("copper_ore") + InventoryManager.count("tin_ore"), 0, "ore used up")
	check_near(SkillsManager.xp.smithing, 24.0, 0.001, "12 XP per bronze bar")
	check(QuestManager.has_quest_flag(QUEST, "smelted_bronze"), "smelting ticks the quest flag")
	check(_said(w, "nothing left to smelt"), "the loop stops when the ore runs out")
	check(not w.smithy.furnace.active, "and the furnace calms down")
	# Iron: one failure (ore lost), then a success.
	SkillsManager.xp.smithing = _xp(8)
	SkillsManager.roll_override = 0.9
	w.smithy.craft("iron_bar", 1, w.smithy.furnace)
	await seconds(2.1)
	check_eq(InventoryManager.count("iron_ore"), 2, "a failed smelt still uses the ore")
	check_eq(InventoryManager.count("iron_bar"), 0, "and makes no bar")
	check(_said(w, "too impure"), "failure message")
	check_near(SkillsManager.xp.smithing, _xp(8), 0.001, "no XP for a failure")
	SkillsManager.roll_override = 0.1
	w.smithy.craft("iron_bar", 1, w.smithy.furnace)
	await seconds(2.1)
	check_eq(InventoryManager.count("iron_bar"), 1, "an iron bar")
	check_near(SkillsManager.xp.smithing, _xp(8) + 25.0, 0.001, "25 XP for iron")


func test_smelting_cancelled_grants_nothing() -> void:
	var w := await start_adventure(DONE, _slots([{"id": "copper_ore", "qty": 1}, {"id": "tin_ore", "qty": 1}]))
	await place_player(w, w.smithy.furnace.front)
	w.smithy.craft("bronze_bar", 1, w.smithy.furnace)
	await seconds(0.8)
	await hold("move_back", 0.3)
	await seconds(1.5)
	check_eq(InventoryManager.count("bronze_bar"), 0, "no bar")
	check_eq(InventoryManager.count("copper_ore"), 1, "ore kept")


# --- smithing ---------------------------------------------------------------------------------------

func test_smithing_needs_a_hammer() -> void:
	var w := await start_adventure(DONE, _slots([{"id": "bronze_bar", "qty": 1}]))
	var panel := await _open_station(w, w.smithy.anvil)
	check(panel == null, "no hammer: no panel")
	check(_said(w, "need a hammer"), "told to get a hammer")
	check_eq(w.smithy.craft_error("bronze_dagger"), "You need a hammer.", "recipes need the hammer")


func test_smithing_recipes_levels_and_make_all() -> void:
	var w := await start_adventure(DONE, _slots([{"id": "hammer", "qty": 1}, {"id": "bronze_bar", "qty": 3}]))
	var panel := await _open_station(w, w.smithy.anvil)
	if not check(panel is CraftPanel, "the anvil opens the crafting panel"):
		return
	check(not panel.button_for("bronze_dagger", "MakeOne").disabled, "dagger available at level 1")
	check(panel.button_for("bronze_pickaxe", "MakeOne").disabled, "pickaxe needs level 3")
	check(panel.button_for("bronze_helm", "MakeOne").disabled, "helm needs level 5")
	check(panel.button_for("iron_dagger", "MakeOne").disabled, "iron dagger needs level 10")
	await click_control(panel.button_for("bronze_dagger", "MakeAll"))
	await seconds(2.4 * 3 + 0.5)
	check_eq(InventoryManager.count("bronze_dagger"), 3, "three daggers from three bars")
	check_eq(InventoryManager.count("bronze_bar"), 0, "bars used")
	check_near(SkillsManager.xp.smithing, 75.0, 0.001, "25 XP each")
	check(QuestManager.has_quest_flag(QUEST, "smithed_dagger"), "smithing a dagger ticks the quest flag")
	check(AudioManager.count("anvil") >= 3, "hammer strikes ring the anvil")
	# Two-bar helm at level 5.
	SkillsManager.xp.smithing = _xp(5)
	InventoryManager.add_item("bronze_bar", 3)
	w.smithy.craft("bronze_helm", SmithyDirector.MAKE_ALL, w.smithy.anvil)
	await seconds(2.4 * 2 + 0.5)
	check_eq(InventoryManager.count("bronze_helm"), 1, "one helm from three bars")
	check_eq(InventoryManager.count("bronze_bar"), 1, "one bar left over")


func test_smithing_capacity() -> void:
	# 27 slots used plus a stack of bars: a dagger needs a free slot, so nothing happens.
	var slots := _slots([{"id": "hammer", "qty": 1}, {"id": "bronze_bar", "qty": 2}])
	while slots.size() < 28:
		slots.append({"id": "bronze_helm", "qty": 1})
	var w := await start_adventure(DONE, slots)
	await place_player(w, w.smithy.anvil.front)
	w.smithy.craft("bronze_dagger", 1, w.smithy.anvil)
	await frames(3)
	check(_said(w, "inventory is too full"), "full pack: told so")
	check_eq(InventoryManager.count("bronze_bar"), 2, "bars untouched")
	# With exactly one bar the slot it frees holds the dagger.
	InventoryManager.remove_item("bronze_bar")
	w.smithy.craft("bronze_dagger", 1, w.smithy.anvil)
	await seconds(2.7)
	check_eq(InventoryManager.count("bronze_dagger"), 1, "the last bar becomes a dagger in its slot")


# --- Brann's quest ----------------------------------------------------------------------------------

func test_brann_waits_for_the_tutorial() -> void:
	var w := await start_adventure({"index": 2}, [])
	await _talk_brann(w)
	check_eq(QuestManager.quest_stage(QUEST), 0, "no quest before the tutorial ends")
	check(not InventoryManager.has("hammer"), "no tools")


func test_quest_start_hand_in_and_no_replay() -> void:
	var w := await start_adventure(DONE, _slots())
	check(w.director.objective_target().distance_to(w.smithy.brann.global_position) < 0.01, "the minimap star points at Brann")
	check(w.director.objective_arrow.visible, "an arrow marks Brann")
	await _talk_brann(w, [3])
	check_eq(QuestManager.quest_stage(QUEST), 0, "declining leaves the quest unstarted")
	await _talk_brann(w, [1])
	check_eq(QuestManager.quest_stage(QUEST), 1, "accepting starts the quest")
	check(InventoryManager.has("bronze_pickaxe") and InventoryManager.has("hammer"), "Brann hands over a pickaxe and hammer")
	check(not w.director.objective_arrow.visible, "no arrow while working")
	check(w.director.objective_target().distance_to(w.island.landmarks.quarry) < 0.01, "the star moves to the quarry")
	var data := saved_data()
	check_eq(int(data.quest.quests[QUEST].stage), 1, "starting the quest saves")
	check(AudioManager.count("jingle") >= 1, "a jingle")
	# The tracker lists the checklist.
	var text := ""
	for c in w.hud.tracker_list.find_children("*", "Label", true, false):
		text += (c as Label).text + "\n"
	check(text.contains("The Smith's Apprentice") and text.contains("Mine some copper ore"), "tracker shows the checklist")
	# Hand in a dagger.
	InventoryManager.add_item("bronze_dagger")
	await frames(2)
	check(w.director.objective_arrow.visible, "the arrow returns once the dagger is ready")
	var coins := InventoryManager.count("coins")
	await _talk_brann(w)
	check_eq(QuestManager.quest_stage(QUEST), 2, "quest complete")
	check(not InventoryManager.has("bronze_dagger"), "dagger handed over")
	check_eq(InventoryManager.count("coins"), coins + 60, "60 coins")
	check_near(SkillsManager.xp.smithing, 250.0, 0.001, "250 Smithing XP")
	check_near(SkillsManager.xp.mining, 100.0, 0.001, "100 Mining XP")
	check(AudioManager.count("fanfare") >= 1, "fanfare")
	await frames(3)
	data = saved_data()
	check_eq(int(data.quest.quests[QUEST].stage), 2, "completion saved")
	check_eq(InventoryManager.count("coins"), int(data.inventory.slots.filter(func(s: Variant) -> bool: return s != null and s.id == "coins")[0].qty), "coins and stage in one snapshot")
	check_eq(w.director.objective_target(), Vector3.INF, "no star after the quest")
	# Continue: nothing replays.
	var fanfares := AudioManager.count("fanfare")
	await reset_game()
	GameManager.continue_game()
	w = await wait_for_world()
	await frames(3)
	check_eq(QuestManager.quest_stage(QUEST), 2, "stage restored")
	check_eq(AudioManager.count("fanfare"), fanfares, "no fanfare on load")
	check_near(SkillsManager.xp.smithing, 250.0, 0.001, "no repeated XP")
	await _talk_brann(w)
	check_eq(InventoryManager.count("coins"), coins + 60, "talking again pays nothing")


func test_quest_tools_retry_when_full_and_recovery() -> void:
	var w := await start_adventure(DONE, _full())
	await _talk_brann(w, [1])
	check_eq(QuestManager.quest_stage(QUEST), 1, "the quest starts even with a full pack")
	check(not InventoryManager.has("hammer"), "but the tools don't fit")
	check(_said(w, "too full for Brann's tools"), "told to make room")
	InventoryManager.remove_item("bronze_helm")
	await _talk_brann(w)
	check(not InventoryManager.has("hammer") and not InventoryManager.has("bronze_pickaxe"), "one free slot: all or nothing")
	InventoryManager.remove_item("bronze_helm")
	await _talk_brann(w)
	check(InventoryManager.has("hammer") and InventoryManager.has("bronze_pickaxe"), "two free slots: tools delivered")
	# Lost tools are replaced, but a steel pickaxe counts as a pickaxe.
	InventoryManager.remove_item("bronze_pickaxe")
	InventoryManager.add_item("steel_pickaxe")
	InventoryManager.remove_item("hammer")
	await _talk_brann(w)
	check(InventoryManager.has("hammer"), "hammer replaced")
	check(not InventoryManager.has("bronze_pickaxe"), "no spare pickaxe when holding a steel one")


func test_hand_in_needs_room_for_the_coins() -> void:
	var w := await start_adventure(DONE, _slots([{"id": "coins", "qty": ItemDB.MAX_QTY - 10}, {"id": "bronze_dagger", "qty": 1}]),
			{"quest": {"index": 5, "quests": {QUEST: {"stage": 1, "flags": []}}}})
	await _talk_brann(w)
	check_eq(QuestManager.quest_stage(QUEST), 1, "the quest waits")
	check(InventoryManager.has("bronze_dagger"), "the dagger stays")
	check_near(SkillsManager.xp.smithing, 0.0, 0.001, "no XP")


# --- shop, tracker and saves --------------------------------------------------------------------------

func test_shop_sells_and_buys_smithing_goods() -> void:
	var w := await start_adventure(DONE, _slots([{"id": "coins", "qty": 60}, {"id": "copper_ore", "qty": 4},
			{"id": "bronze_dagger", "qty": 1}]))
	check(w.skills.buy("steel_pickaxe").ok, "buy the steel pickaxe")
	check_eq(InventoryManager.count("coins"), 10, "50 coins")
	check(not w.skills.buy("steel_pickaxe").ok, "only one steel pickaxe")
	check(w.skills.buy("hammer").ok, "buy a hammer")
	check_eq(w.skills.sell("copper_ore", true).get("coins", 0), 12, "copper ore sells for 3 each")
	check_eq(w.skills.sell("bronze_dagger", false).get("coins", 0), 12, "a dagger sells for 12")
	check(not w.skills.sell("steel_pickaxe", false).ok, "Marla won't buy her pickaxe back")


func test_quest_save_validation() -> void:
	var base := GameManager.new_game_data("Val", Appearance.defaults())
	var v := SaveManager.validate(base)
	check(v.ok and v.data.quest.quests == {}, "new games start with no quests")
	var old := base.duplicate(true)
	old.quest.erase("quests")
	v = SaveManager.validate(old)
	check(v.ok and v.data.quest.quests == {}, "older saves without quests load at stage 0")
	var odd := base.duplicate(true)
	odd.quest.quests = {QUEST: {"stage": 9, "flags": ["mined_tin", "bogus", "mined_tin", 3]},
			"dragon_slayer": {"stage": 1}, "x": "nope"}
	v = SaveManager.validate(odd)
	check(v.ok, "odd quest data still loads")
	check_eq(v.data.quest.quests.keys(), [QUEST], "unknown quests ignored")
	check_eq(v.data.quest.quests[QUEST].stage, 2, "stage clamped")
	check_eq(v.data.quest.quests[QUEST].flags, ["mined_tin"], "only known flags, once")
	var neg := base.duplicate(true)
	neg.quest.quests = {QUEST: {"stage": -3.5, "flags": "no"}}
	v = SaveManager.validate(neg)
	check(v.ok and v.data.quest.quests[QUEST].stage == 0 and v.data.quest.quests[QUEST].flags == [], "negative stage and bad flags default")
	var bad := base.duplicate(true)
	bad.quest.quests = ["smiths_apprentice"]
	v = SaveManager.validate(bad)
	check(not v.ok and v.error.contains("quest list"), "a non-dictionary quest list is malformed")


func test_quest_progress_round_trip() -> void:
	var w := await start_adventure(DONE, _slots([{"id": "bronze_pickaxe", "qty": 1}, {"id": "hammer", "qty": 1}]),
			{"quest": {"index": 5, "quests": {QUEST: {"stage": 1, "flags": ["mined_copper"]}}}})
	check_eq(QuestManager.quest_stage(QUEST), 1, "stage loaded")
	check(QuestManager.has_quest_flag(QUEST, "mined_copper"), "flags loaded")
	await _mine(w, _rock(w, "tin"))
	await seconds(2.7)
	check(QuestManager.has_quest_flag(QUEST, "mined_tin"), "new flag")
	await frames(3)
	var data := saved_data()
	check_eq(data.quest.quests[QUEST].flags, ["mined_copper", "mined_tin"], "flag checkpoint saved")
	check_eq(InventoryManager.count("tin_ore"), int(data.inventory.slots.filter(func(s: Variant) -> bool: return s != null and s.id == "tin_ore")[0].qty), "with the ore")
	await reset_game()
	GameManager.continue_game()
	w = await wait_for_world()
	check(QuestManager.has_quest_flag(QUEST, "mined_tin"), "flags restored on Continue")
	check(not _rock(w, "tin").is_depleted, "rocks are full after a load")
	check(w.director.objective_target().distance_to(w.smithy.furnace.front) > 0.01, "the star doesn't point at the furnace without both ores")


func test_skills_panel_fits_seven_skills() -> void:
	var w := await start_adventure(DONE, _slots())
	await tap("skills")
	await frames(3)
	var panel := w.hud.skills_panel
	check(panel.visible, "skills panel open")
	check(panel.rows.has("mining") and panel.rows.has("smithing"), "Mining and Smithing rows")
	var rect := panel.get_global_rect()
	var view := w.get_viewport().get_visible_rect()
	check(view.encloses(rect), "the panel fits on screen (%s in %s)" % [rect, view])
