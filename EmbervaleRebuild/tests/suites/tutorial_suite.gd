extends TestSuite
## Milestone 3: the five objectives through real input paths, dialogue outcomes, chopping and
## cancellation, inventory, full-inventory reward retry, autosaves, NPCs and save round-trips.


func before_each() -> void:
	await reset_game()
	wipe_saves()


func after_each() -> void:
	await reset_game()


func _tree(w: World, i: int = 0) -> ChoppableTree:
	return w.island.choppable_trees[i]


func _full_slots(id: String = "tinderbox", count: int = 28) -> Array:
	var slots := []
	for i in count:
		slots.append({"id": id, "qty": 1})
	return slots


func test_learn_to_move_keyboard_then_marker() -> void:
	var w := await start_adventure()
	check_eq(QuestManager.current_id(), "learn_to_move", "first objective")
	await hold("move_forward", 1.6)
	check(QuestManager.wasd_distance >= 4.0, "4 m of keyboard movement counted (%.2f)" % QuestManager.wasd_distance)
	check_eq(QuestManager.index, 0, "keyboard alone does not complete it")
	await click_world(w.island.landmarks.move_marker)
	var done := await wait_until(func() -> bool: return QuestManager.index == 1, 10.0)
	check(done, "clicking to the marker completes Learn to move")
	await frames(3)
	check_eq(saved_data().get("quest", {}).get("index", -1), 1, "autosaved after the objective")


func test_learn_to_move_marker_then_keyboard() -> void:
	var w := await start_adventure()
	await click_world(w.island.landmarks.move_marker)
	await wait_until(func() -> bool: return QuestManager.marker_reached, 10.0)
	check(QuestManager.marker_reached and QuestManager.index == 0, "marker first, still waiting for keyboard")
	await hold("move_forward", 1.6)
	check_eq(QuestManager.index, 1, "keyboard after the marker completes it")


func test_marker_needs_click_navigation() -> void:
	var w := await start_adventure()
	# Walk onto the marker with the keyboard only.
	await hold("move_forward", 2.6)
	var d := flat_distance(w.player.global_position, w.island.landmarks.move_marker)
	check(d < 2.5, "walked past the marker area (%.2f m)" % d)
	check(not QuestManager.marker_reached, "keyboard walking doesn't count as reaching the marker")


func test_maelis_before_movement_gives_no_progress() -> void:
	var w := await start_adventure()
	await place_player(w, w.island.landmarks.npc_instructor + Vector3(-1.5, 0, 0), PI * 0.5)
	await tap("interact")
	check(DialogueManager.active and DialogueManager.npc_id == "maelis", "E talks to Maelis")
	await run_dialogue(w)
	check_eq(QuestManager.index, 0, "no progression before the movement objective")
	check(w.gameplay_enabled, "controls back after talking")


func test_introduction_conversation_branches() -> void:
	var w := await start_adventure({"index": 1})
	await place_player(w, w.island.landmarks.courtyard_entrance, PI * 0.5)
	var maelis: Npc = w.director.npcs.maelis
	await click_world(maelis.global_position + Vector3(0, 1.0, 0))
	var talking := await wait_until(func() -> bool: return DialogueManager.active, 10.0)
	check(talking, "clicking Maelis walks over and talks")
	check(not w.gameplay_enabled and not w.hud.log_panel.visible, "movement disabled and log hidden while talking")
	var first: String = DialogueManager.current.text
	check(first.contains("Tester"), "Maelis greets the player by name")
	# Space first reveals unfinished text, then advances.
	await tap("dialogue_continue")
	check(not w.hud.dialogue_panel.is_typing() and DialogueManager.current.text == first, "first press reveals the line")
	await tap("dialogue_continue")
	check(DialogueManager.current.text != first, "second press advances")
	await run_dialogue(w, [1, 2, 3], 6)
	check(DialogueManager.active, "informational branches return to the choices")
	await run_dialogue(w, [3])
	check(not DialogueManager.active, "conversation finished")
	check_eq(QuestManager.index, 2, "accepting the assignment completes Meet the instructor")
	await frames(3)
	check_eq(saved_data().quest.index, 2, "autosaved")
	await place_player(w, w.island.landmarks.npc_instructor + Vector3(-1.5, 0, 0), PI * 0.5)
	await tap("interact")
	check(DialogueManager.current.text.contains("0 of the 3 logs"), "gathering dialogue reports the log count")
	await run_dialogue(w)


func test_wasd_blocked_during_dialogue() -> void:
	var w := await start_adventure({"index": 1})
	await place_player(w, w.island.landmarks.npc_instructor + Vector3(-1.5, 0, 0), PI * 0.5)
	await tap("interact")
	var before := w.player.global_position
	await hold("move_back", 0.6)
	check(flat_distance(before, w.player.global_position) < 0.05, "no movement while talking")
	await click_world(w.island.landmarks.courtyard)
	check(not w.player.nav.is_active(), "world clicks ignored while talking")
	DialogueManager.end()


func test_chop_trees_to_three_logs() -> void:
	var w := await start_adventure({"index": 2})
	await place_player(w, w.island.landmarks.forest_clearing, 0.0)
	for i in 3:
		var tree := _tree(w, i)
		w.camera_rig.snap()
		await frames(2)
		await click_world(tree.global_position + Vector3(0, 2.4, 0))
		var got := await wait_until(func() -> bool: return tree.is_stump, 8.0)
		check(got, "clicking tree %d walks over and chops it" % i)
	check_eq(InventoryManager.count("logs"), 3, "three logs")
	check_eq(QuestManager.index, 3, "Gather logs complete")
	var tree := _tree(w, 0)
	check(tree.is_stump and not tree.is_available(), "chopped tree is a stump")
	await seconds(20.5)
	check(not tree.is_stump, "stump regrows after 20 s")


func test_chop_takes_two_seconds_and_cancels_on_move() -> void:
	var w := await start_adventure({"index": 2})
	var tree := _tree(w, 1)
	await place_player(w, tree.global_position + Vector3(1.4, 0, 0), -PI * 0.5)
	await tap("interact")
	check(w.player.is_busy(), "E starts chopping the nearest tree without walking")
	await seconds(1.0)
	check_eq(InventoryManager.count("logs"), 0, "no log before 2 s")
	await hold("move_back", 0.3)
	await seconds(1.5)
	check_eq(InventoryManager.count("logs"), 0, "moving cancels the chop with no reward")
	check(not tree.is_stump, "tree untouched")
	await place_player(w, tree.global_position + Vector3(1.4, 0, 0), -PI * 0.5)
	await tap("interact")
	await seconds(2.2)
	check_eq(InventoryManager.count("logs"), 1, "uninterrupted chop gives one log")


func test_pause_freezes_chop() -> void:
	var w := await start_adventure({"index": 2})
	var tree := _tree(w, 2)
	await place_player(w, tree.global_position + Vector3(1.4, 0, 0), -PI * 0.5)
	await tap("interact")
	await seconds(1.0)
	w.open_pause_menu()
	await frames(150)
	check_eq(InventoryManager.count("logs"), 0, "no progress while paused")
	(top_modal() as PausePanel).close()
	await seconds(1.3)
	check_eq(InventoryManager.count("logs"), 1, "chop finishes after resuming")


func test_chop_with_full_inventory() -> void:
	var w := await start_adventure({"index": 2}, _full_slots())
	var tree := _tree(w, 0)
	await place_player(w, tree.global_position + Vector3(1.4, 0, 0), -PI * 0.5)
	await tap("interact")
	check(not w.player.is_busy(), "full inventory: no chop starts")
	check(w.hud.messages.back().contains("too full"), "explains the full inventory")


func test_early_logs_count_when_objective_starts() -> void:
	var w := await start_adventure({"index": 1}, [{"id": "logs", "qty": 3}])
	await place_player(w, w.island.landmarks.npc_instructor + Vector3(-1.5, 0, 0), PI * 0.5)
	await tap("interact")
	await run_dialogue(w, [3])
	check_eq(QuestManager.index, 3, "logs held before the objective count at once")


func test_inspect_inventory_rules() -> void:
	var w := await start_adventure({"index": 3}, [{"id": "logs", "qty": 3}])
	InventoryManager.inspect(0)
	check_eq(QuestManager.index, 3, "examining without the panel doesn't count")
	await tap("inventory")
	check(w.hud.inventory_panel.visible and QuestManager.inventory_opened, "I opens the inventory")
	await frames(2)
	await click_control(w.hud.inventory_panel.slot_buttons[0])
	check_eq(QuestManager.index, 4, "examining the logs in the open inventory completes the objective")
	check(w.hud.messages.has(ItemDB.examine_text("logs")), "examine text shown")
	await tap("pause")
	check(not w.hud.inventory_panel.visible and not get_tree().paused, "Esc closes the inventory before pausing")


func test_earlier_inspection_does_not_count() -> void:
	var w := await start_adventure({"index": 2}, [{"id": "logs", "qty": 2}])
	w.hud.inventory_panel.show_panel()
	w.hud.inventory_panel.select_slot(0)
	w.hud.inventory_panel.hide_panel()
	InventoryManager.add_item("logs")
	check_eq(QuestManager.index, 3, "third log completes Gather logs")
	check(not QuestManager.logs_inspected and not QuestManager.inventory_opened, "earlier inspection did not carry over")


func test_reward_retry_when_full_then_complete() -> void:
	var slots := _full_slots()
	slots[0] = {"id": "logs", "qty": 3}
	var w := await start_adventure({"index": 4, "inventory_opened": true, "logs_inspected": true}, slots)
	await place_player(w, w.island.landmarks.npc_instructor + Vector3(-1.5, 0, 0), PI * 0.5)
	await tap("interact")
	await run_dialogue(w)
	check_eq(QuestManager.index, 4, "full inventory: tutorial not finished")
	check(not InventoryManager.has("beginner_sword"), "no sword yet")
	check(w.gameplay_enabled, "controls usable after the failed delivery")
	InventoryManager.drop_slot(5)
	await tap("interact")
	await run_dialogue(w)
	check_eq(InventoryManager.count("beginner_sword"), 1, "sword delivered on retry")
	check(QuestManager.is_tutorial_complete(), "tutorial complete")
	check_eq(InventoryManager.count("logs"), 3, "Maelis doesn't take the logs")
	var seq := w.director.gate_sequence
	check(seq != null, "gate sequence starts")
	await seconds(1.0)
	await tap("skip")
	await frames(3)
	var panel := top_modal() as TutorialCompletePanel
	check(panel != null, "Tutorial Complete screen after the gate sequence")
	await click_control(find_named(panel, "ContinueExploring"))
	await frames(2)
	check(w.gameplay_enabled and top_modal() == null, "Continue Exploring stays on the island")
	var data := saved_data()
	check(data.quest.index == 5 and data.inventory.slots.any(func(s: Variant) -> bool: return s != null and s.id == "beginner_sword"), "completion and sword saved together")


func test_completed_tutorial_does_not_replay() -> void:
	var w := await start_adventure({"index": 5}, [{"id": "beginner_sword", "qty": 1}])
	check(w.director.gate_sequence == null and top_modal() == null, "Continue doesn't replay the closing sequence")
	await place_player(w, w.island.landmarks.npc_instructor + Vector3(-1.5, 0, 0), PI * 0.5)
	await tap("interact")
	check(DialogueManager.current.text.contains("Safe travels"), "Maelis's afterward dialogue")
	await run_dialogue(w)
	check_eq(InventoryManager.count("beginner_sword"), 1, "no duplicate sword")
	check_eq(w.hud.tracker_title.text, "Ready for adventure", "final tracker title")


func test_gate_sequence_watched() -> void:
	var w := await start_adventure({"index": 4, "inventory_opened": true, "logs_inspected": true}, [{"id": "logs", "qty": 3}])
	await place_player(w, w.island.landmarks.npc_instructor + Vector3(-1.5, 0, 0), PI * 0.5)
	await tap("interact")
	await run_dialogue(w)
	check(w.director.gate_sequence != null, "sequence playing")
	check_eq(GameManager.state, GameManager.State.CUTSCENE, "cutscene state")
	await seconds(7.0)
	check(top_modal() == null, "still panning at 7 s")
	await seconds(0.4)
	check(top_modal() is TutorialCompletePanel, "Tutorial Complete after 7.2 s")
	await click_control(find_named(top_modal(), "ReturnToMainMenu"))
	var menu := await wait_for_scene("MainMenu")
	check(menu != null, "Return to Main Menu works")
	check_eq(saved_data().quest.index, 5, "saved as complete")


func test_npcs_present_and_talkable() -> void:
	var w := await start_adventure({"index": 2})
	for id in ["maelis", "marla", "tobin", "pip"]:
		check(w.director.npcs.has(id), "%s spawned" % id)
	check_near(w.director.npcs.maelis.global_position.x, 21.5, 0.01, "Maelis at (21.5, 4)")
	w.director.talk_to(w.director.npcs.marla)
	check(DialogueManager.current.text.contains("training"), "Marla: trade unlocks after training")
	await run_dialogue(w)
	w.director.talk_to(w.director.npcs.pip)
	check(DialogueManager.current.text.contains("adventurer"), "Pip hopes to become an adventurer")
	await run_dialogue(w)
	var pip: Npc = w.director.npcs.pip
	var max_d := 0.0
	var moved := false
	var start := pip.global_position
	for i in 40:
		await seconds(0.5)
		max_d = maxf(max_d, flat_distance(pip.global_position, pip.home))
		moved = moved or flat_distance(pip.global_position, start) > 0.5
	check(moved, "Pip wanders")
	check(max_d <= 5.2, "Pip stays within 5 m of home (%.2f)" % max_d)


func test_marla_reachable_by_click() -> void:
	var w := await start_adventure({"index": 5}, [{"id": "beginner_sword", "qty": 1}])
	await place_player(w, w.island.landmarks.village, 0.0)
	var marla: Npc = w.director.npcs.marla
	check(w.interaction.use_target(marla), "route to Marla")
	var talking := await wait_until(func() -> bool: return DialogueManager.active, 10.0)
	if not check(talking, "reached Marla behind her stall"):
		return
	check(DialogueManager.current.text.contains("stall"), "Marla mentions her stall after the tutorial")
	await run_dialogue(w)


func test_hover_text_and_e_with_nothing_near() -> void:
	var w := await start_adventure()
	await tap("interact")
	check(w.hud.messages.back().contains("nothing"), "E with nothing in reach explains")
	# Camera west of the player, looking east at Maelis.
	await place_player(w, w.island.landmarks.npc_instructor + Vector3(-3.5, 0, 0), -PI * 0.5)
	var maelis: Npc = w.director.npcs.maelis
	var cam := get_viewport().get_camera_3d()
	var screen := cam.unproject_position(maelis.global_position + Vector3(0, 1.0, 0))
	var motion := InputEventMouseMotion.new()
	motion.position = get_tree().root.get_final_transform() * screen
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await frames(3)
	check(w.interaction.hovered == maelis or w.hud.hover_label.text == "Talk-to Instructor Maelis",
			"hovering Maelis shows 'Talk-to Instructor Maelis' (got '%s')" % w.hud.hover_label.text)


func test_ui_clicks_never_move_player() -> void:
	var w := await start_adventure()
	await click_control(w.hud.inventory_button)
	check(w.hud.inventory_panel.visible, "inventory button opens the panel")
	check(not w.player.nav.is_active(), "clicking the HUD doesn't move the player")
	await click_control(w.hud.inventory_panel.slot_buttons[10])
	check(not w.player.nav.is_active(), "clicking inside the panel doesn't move the player")
	await hold("move_forward", 0.5)
	check(w.player.keyboard_distance > 0.5, "gameplay continues with the inventory open")


func test_drop_confirm_and_sword_protected() -> void:
	var w := await start_adventure({"index": 5}, [{"id": "beginner_sword", "qty": 1}, {"id": "logs", "qty": 7}])
	w.hud.inventory_panel.show_panel()
	await frames(2)
	await click_control(w.hud.inventory_panel.slot_buttons[0])
	await frames(2)
	check(find_named(w.hud.inventory_panel, "ActionDrop") == null, "sword has no Drop action")
	check(not InventoryManager.drop_slot(0).ok, "sword can't be dropped")
	await click_control(w.hud.inventory_panel.slot_buttons[1])
	await frames(2)
	var drop := find_named(w.hud.inventory_panel, "ActionDrop") as Button
	if not check(drop != null, "logs can be dropped"):
		return
	await click_control(drop)
	var confirm := top_modal() as ConfirmPanel
	check(confirm != null and str(confirm.box.get_child(1).text).contains("all 7"), "confirmation shows the quantity")
	confirm.press("Keep")
	check_eq(InventoryManager.count("logs"), 7, "Keep cancels")
	await click_control(drop)
	(top_modal() as ConfirmPanel).press("Drop")
	check_eq(InventoryManager.count("logs"), 0, "Drop discards the whole stack")


func test_save_round_trip_mid_tutorial() -> void:
	var w := await start_adventure({"index": 2}, [{"id": "logs", "qty": 2}])
	await place_player(w, w.island.landmarks.forest_clearing, 0.0)
	GameManager.save_and_return_to_menu()
	var menu := await wait_for_scene("MainMenu") as MainMenu
	await click_control(menu.continue_button)
	var w2 := await wait_for_world()
	check_eq(QuestManager.index, 2, "quest progress restored")
	check_eq(InventoryManager.count("logs"), 2, "inventory restored")
	check(flat_distance(w2.player.global_position, w2.island.landmarks.forest_clearing) < 1.0, "position restored")


func test_imported_completed_tutorial_gets_sword_once() -> void:
	var res := GameManager.import_save(ProjectSettings.globalize_path("res://tests/fixtures/v1_m6_full.json"))
	check(res.ok, "fixture imports")
	GameManager.continue_game()
	var w := await wait_for_world()
	check_eq(InventoryManager.count("beginner_sword"), 1, "replacement sword granted")
	await frames(3)
	await reset_game()
	GameManager.continue_game()
	await wait_for_world()
	check_eq(InventoryManager.count("beginner_sword"), 1, "no duplicate on the next Continue")


func test_imported_completed_tutorial_full_inventory_retry() -> void:
	var w := await start_adventure({"index": 5}, _full_slots())
	check(not InventoryManager.has("beginner_sword"), "no room for the replacement")
	InventoryManager.drop_slot(0)
	await place_player(w, w.island.landmarks.npc_instructor + Vector3(-1.5, 0, 0), PI * 0.5)
	await tap("interact")
	await run_dialogue(w)
	check_eq(InventoryManager.count("beginner_sword"), 1, "Maelis provides the replacement when there is room")
