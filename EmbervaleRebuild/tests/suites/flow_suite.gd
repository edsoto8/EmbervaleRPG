extends TestSuite
## Milestone 2: menu, settings, validation, character creation, intro, pause, save and Continue,
## isolated paths, write failures and version 1 import.

var _quits := 0


func before_each() -> void:
	await reset_game()
	wipe_saves()
	SettingsManager.load_settings()
	_quits = 0
	GameManager.quit_handler = func() -> void: _quits += 1


func after_each() -> void:
	await reset_game()
	GameManager.quit_handler = Callable()


func _menu() -> MainMenu:
	GameManager.go_to_main_menu()
	return await wait_for_scene("MainMenu") as MainMenu


## Creates a character through the real UI and returns the world (intro playing).
func _create_character(char_name: String = "Rowan") -> World:
	var menu := await _menu()
	await click_control(menu.new_game_button)
	var top := top_modal()
	if top is ConfirmPanel:
		(top as ConfirmPanel).press("Start new game")
	var cc := await wait_for_scene("CharacterCreation") as CharacterCreation
	if cc == null:
		return null
	cc.name_edit.text = char_name
	cc.name_edit.text_changed.emit(char_name)
	await click_control(cc.create_button)
	return await wait_for_world()


func _skip_intro(w: World) -> void:
	await seconds(0.5)
	await tap("skip")
	await frames(2)


func test_paths_are_isolated() -> void:
	check(AppPaths.is_isolated(), "test run uses an isolated data directory")
	check(AppPaths.save_path().begins_with("user://test_runs/"), "save path isolated (%s)" % AppPaths.save_path())
	check(AppPaths.settings_path().begins_with("user://test_runs/"), "settings path isolated")


func test_menu_continue_disabled_without_save() -> void:
	var menu := await _menu()
	check(menu != null, "main menu loads")
	check(menu.continue_button.disabled, "Continue disabled with no save")
	check(not FileAccess.file_exists(AppPaths.save_path()), "menu-only session writes no save")


func test_settings_apply_persist_and_sanitise() -> void:
	SettingsManager.set_value("master_volume", 0.3)
	SettingsManager.set_value("mouse_sensitivity", 2.0)
	var db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	check_near(db, linear_to_db(0.3), 0.01, "volume applied immediately")
	SettingsManager.load_settings()
	check_near(SettingsManager.get_value("master_volume"), 0.3, 0.001, "volume persisted")
	check_near(SettingsManager.get_value("mouse_sensitivity"), 2.0, 0.001, "sensitivity persisted")
	write_json(AppPaths.settings_path(), {"resolution": [999, 333], "fullscreen": "yes", "master_volume": 7,
			"mouse_sensitivity": -3, "graphics_quality": 9, "mystery": true})
	SettingsManager.load_settings()
	check_eq(SettingsManager.get_value("resolution"), Vector2i(1280, 720), "unsupported resolution -> 1280x720")
	check_eq(SettingsManager.get_value("fullscreen"), false, "invalid fullscreen -> default")
	check_near(SettingsManager.get_value("master_volume"), 1.0, 0.001, "volume clamped to [0, 1]")
	check_near(SettingsManager.get_value("mouse_sensitivity"), 0.25, 0.001, "sensitivity clamped")
	check_eq(SettingsManager.get_value("graphics_quality"), 1, "invalid quality -> Medium")
	var f := FileAccess.open(AppPaths.settings_path(), FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	SettingsManager.load_settings()
	check_near(SettingsManager.get_value("master_volume"), 0.8, 0.001, "corrupt settings -> defaults")


func test_settings_write_failure_keeps_change() -> void:
	SettingsManager.fail_next_write = true
	SettingsManager.set_value("master_volume", 0.5)
	check_near(SettingsManager.get_value("master_volume"), 0.5, 0.001, "change applies in memory")
	check(SettingsManager.last_error != "", "failure reported")


func test_settings_panel_controls() -> void:
	var menu := await _menu()
	await click_control(find_named(menu, "Settings"))
	var panel := top_modal() as SettingsPanel
	if not check(panel != null, "settings panel opens"):
		return
	panel.volume.value = 0.4
	check_near(SettingsManager.get_value("master_volume"), 0.4, 0.001, "slider applies immediately")
	await tap("pause")
	await frames(2)
	check(top_modal() == null, "Esc closes the settings panel")


func test_name_validation() -> void:
	for good in ["Rowan", "Ash 2", "A", "Ab Cd Ef", "abcdefghijkl"]:
		check(Appearance.is_valid_name(good), "'%s' is valid" % good)
	for bad in ["", "abcdefghijklm", "Two  spaces", "Bad!", "Émile", " x", "x ", "a_b"]:
		check(not Appearance.is_valid_name(bad), "'%s' is invalid" % bad)
	check_eq(Appearance.clean_name("  Rowan  "), "Rowan", "names are trimmed")


func test_creation_validation_and_randomize() -> void:
	GameManager.start_new_game()
	var cc := await wait_for_scene("CharacterCreation") as CharacterCreation
	if not check(cc != null, "creation scene loads"):
		return
	check(cc.create_button.disabled, "Create disabled with an empty name")
	cc.name_edit.text = "Bad!!"
	cc.name_edit.text_changed.emit("Bad!!")
	check(cc.create_button.disabled and cc.name_error.text != "", "invalid name shows a reason")
	cc.name_edit.text = ""
	var before := cc.appearance.duplicate()
	await click_control(find_named(cc, "Randomize"))
	for k in before:
		check(cc.appearance[k] != before[k], "Randomize changed %s" % k)
	check(cc.name_edit.text != "" and not cc.create_button.disabled, "Randomize suggests a name when empty")
	cc.name_edit.text = "Keeper"
	await click_control(find_named(cc, "Randomize"))
	check_eq(cc.name_edit.text, "Keeper", "Randomize keeps an entered name")
	var yaw := cc.turntable.rotation.y
	cc.rotate_preview(100)
	check_near(cc.turntable.rotation.y - yaw, 1.2, 0.001, "drag rotates 0.012 rad/pixel")
	var held := cc.turntable.rotation.y
	await seconds(1.0)
	check_near(cc.turntable.rotation.y, held, 0.001, "auto-rotation paused after a drag")
	await seconds(1.3)
	check(cc.turntable.rotation.y > held + 0.05, "auto-rotation resumes after 2 s")


func test_create_character_saves_and_plays_intro() -> void:
	var writes := [0]
	SaveManager.save_written.connect(func(_p: String) -> void: writes[0] += 1)
	var w := await _create_character("Rowan")
	if not check(w != null, "world loads after creation"):
		return
	var data: Variant = read_json(AppPaths.save_path())
	check(data is Dictionary and data.version == 2, "version 2 save written")
	check(data.character.name == "Rowan" and data.stage == "intro", "save has the character at stage intro")
	check(not data.has("player"), "no player position during intro")
	check(w.intro != null, "intro plays")
	check_eq(GameManager.state, GameManager.State.CUTSCENE, "state CUTSCENE")
	check(not w.player.visible and not w.gameplay_enabled, "player hidden and controls off")
	check_eq(writes[0], 1, "saved once on creation")


func _check_final_intro_state(w: World) -> void:
	check(w.intro == null, "intro finished")
	check(w.player.visible, "player visible")
	check(flat_distance(w.player.global_position, w.island.landmarks.dock) < 0.2, "player on the dock")
	check(w.gameplay_enabled and w.player.input_enabled and w.camera_rig.input_enabled, "controls enabled")
	check(w.camera_rig.following, "gameplay camera following")
	check_near(w.camera_rig.yaw, 0.0, 0.001, "gameplay camera yaw")
	check(flat_distance(w.island.boat.position, Vector3(IslandLayout.BOAT.x, 0, IslandLayout.BOAT.y)) < 0.05, "boat moored")
	check_eq(get_tree().get_nodes_in_group("world").size(), 1, "one world")
	check_eq(w.find_children("*", "PlayerController", true, false).size(), 1, "one player")
	check_eq(w.find_children("Passenger", "", true, false).size(), 0, "passenger removed")
	check_eq(GameManager.stage, "island", "stage island")
	check_eq(GameManager.state, GameManager.State.PLAYING, "state PLAYING")
	var data: Variant = read_json(AppPaths.save_path())
	check(data is Dictionary and data.stage == "island", "saved at stage island")


func test_intro_skip_with_space_matches_watching() -> void:
	var w := await _create_character()
	var writes := [0]
	SaveManager.save_written.connect(func(_p: String) -> void: writes[0] += 1)
	await _skip_intro(w)
	_check_final_intro_state(w)
	check_eq(writes[0], 1, "skipping saves exactly once")
	await tap("skip")
	await seconds(0.3)
	check_eq(writes[0], 1, "a second skip press does nothing")


func test_intro_watched_to_the_end() -> void:
	var w := await _create_character("Mira")
	var intro := w.intro
	var shown: Array[String] = []
	intro.finished.connect(func(_s: bool) -> void: shown.assign(intro.shown_messages))
	var appeared := await wait_until(func() -> bool: return w.player.visible, 11.5)
	check(appeared, "player appears on the dock")
	check(intro.time >= 10.9, "player appears at about 11 s (%.2f)" % intro.time)
	await wait_until(func() -> bool: return w.intro == null, 5.0)
	check_eq(shown, ["Welcome, Mira.", "Driftwood Isle.", "Your journey begins."], "three intro messages in order")
	_check_final_intro_state(w)


func test_intro_skip_with_escape_enter_and_button() -> void:
	for how in ["esc", "enter", "button"]:
		await reset_game()
		wipe_saves()
		var w := await _create_character()
		await seconds(0.4)
		match how:
			"esc":
				await key(KEY_ESCAPE)
			"enter":
				await key(KEY_ENTER)
			"button":
				await click_control(find_named(w.intro, "SkipButton"))
		await frames(2)
		check(w.intro == null and w.player.visible, "%s skips the intro" % how)
		check_eq(GameManager.state, GameManager.State.PLAYING, "%s: playing" % how)
		check(not GameManager.is_modal_open(), "%s: no pause menu opened" % how)


func test_mid_intro_save_restarts_intro() -> void:
	var w := await _create_character()
	await seconds(2.0)
	GameManager.save_game()
	var data: Variant = read_json(AppPaths.save_path())
	check(data.stage == "intro", "mid-intro save keeps stage intro")
	await reset_game()
	var menu := await _menu()
	check(not menu.continue_button.disabled, "Continue enabled")
	await click_control(menu.continue_button)
	var w2 := await wait_for_world()
	check(w2 != null and w2.intro != null, "Continue replays the intro")


func test_continue_restores_position() -> void:
	var w := await _create_character()
	await _skip_intro(w)
	await hold("move_forward", 1.5)
	await physics_frames(10)
	var saved_pos := w.player.global_position
	await tap("pause")
	var pause := top_modal() as PausePanel
	if not check(pause != null, "Esc opens the pause menu"):
		return
	check(get_tree().paused, "tree paused")
	await click_control(find_named(pause, "SaveAndMainMenu"))
	var menu := await wait_for_scene("MainMenu") as MainMenu
	check(menu != null and not GameManager.adventure_loaded, "back at the menu")
	await click_control(menu.continue_button)
	var w2 := await wait_for_world()
	check(w2 != null and w2.intro == null, "island save resumes without the intro")
	check(flat_distance(w2.player.global_position, saved_pos) < 0.3, "position restored")
	check_eq(GameManager.state, GameManager.State.PLAYING, "resumes PLAYING")


func test_pause_resume_with_escape() -> void:
	var w := await _create_character()
	await _skip_intro(w)
	await tap("pause")
	check(top_modal() is PausePanel and get_tree().paused, "pause opens")
	await tap("pause")
	await frames(2)
	check(top_modal() == null and not get_tree().paused, "Esc closes pause")
	await tap("pause")
	await click_control(find_named(top_modal(), "Resume"))
	await frames(2)
	check(not get_tree().paused and GameManager.state == GameManager.State.PLAYING, "Resume continues")


func test_inaccessible_position_resets_to_dock() -> void:
	var data := GameManager.new_game_data("Sailor", Appearance.defaults())
	data.stage = "island"
	data.player = {"position": [30.0, 0.0, 70.0], "yaw": 1.0}
	check(SaveManager.write_save(data), "fixture written")
	var menu := await _menu()
	await click_control(menu.continue_button)
	var w := await wait_for_world()
	check(flat_distance(w.player.global_position, w.island.landmarks.dock) < 0.2, "inaccessible save position resets to the dock")


func test_new_game_cancel_preserves_save() -> void:
	var data := GameManager.new_game_data("Keeper", Appearance.defaults())
	data.stage = "island"
	SaveManager.write_save(data)
	var before := FileAccess.get_file_as_string(AppPaths.save_path())
	var menu := await _menu()
	await click_control(menu.new_game_button)
	var confirm := top_modal() as ConfirmPanel
	check(confirm != null, "New Game asks before replacing a save")
	confirm.press("Start new game")
	var cc := await wait_for_scene("CharacterCreation") as CharacterCreation
	await click_control(find_named(cc, "Back"))
	await wait_for_scene("MainMenu")
	check_eq(FileAccess.get_file_as_string(AppPaths.save_path()), before, "backing out keeps the old save")


func test_creation_save_failure_stays_in_creation() -> void:
	var data := GameManager.new_game_data("Keeper", Appearance.defaults())
	SaveManager.write_save(data)
	var before := FileAccess.get_file_as_string(AppPaths.save_path())
	GameManager.start_new_game()
	var cc := await wait_for_scene("CharacterCreation") as CharacterCreation
	cc.name_edit.text = "Newcomer"
	cc.name_edit.text_changed.emit("Newcomer")
	SaveManager.fail_next_write = "replace"
	await click_control(cc.create_button)
	await seconds(1.0)
	check(get_tree().current_scene == cc, "stays in character creation")
	check(cc.status.text != "", "shows the error")
	check(not GameManager.adventure_loaded, "no adventure loaded")
	check_eq(FileAccess.get_file_as_string(AppPaths.save_path()), before, "old save untouched")


func test_save_and_menu_failure_offers_retry_or_leave() -> void:
	var w := await _create_character()
	await _skip_intro(w)
	var before := FileAccess.get_file_as_string(AppPaths.save_path())
	await tap("pause")
	SaveManager.fail_next_write = "open"
	await click_control(find_named(top_modal(), "SaveAndMainMenu"))
	await frames(2)
	var confirm := top_modal() as ConfirmPanel
	check(confirm != null, "failure dialog shown")
	check(get_tree().current_scene == w, "still in the game")
	check_eq(FileAccess.get_file_as_string(AppPaths.save_path()), before, "previous save kept")
	confirm.press("Retry")
	var menu := await wait_for_scene("MainMenu")
	check(menu != null, "retry succeeds and returns to the menu")


func test_save_and_exit_and_window_close() -> void:
	var w := await _create_character()
	await _skip_intro(w)
	await hold("move_forward", 0.6)
	SaveManager.fail_next_write = "open"
	GameManager.request_close()
	await frames(3)
	check(top_modal() is ConfirmPanel, "failed save on close asks instead of quitting")
	check_eq(_quits, 0, "did not quit")
	(top_modal() as ConfirmPanel).press("Retry")
	await seconds(0.5)
	check_eq(_quits, 1, "retry saves and quits")
	var data: Variant = read_json(AppPaths.save_path())
	check(data.has("player"), "close saved the position")


func test_direct_world_run_never_saves() -> void:
	await load_world()
	check(not GameManager.adventure_loaded, "no adventure")
	GameManager.save_game()
	GameManager.request_save()
	await frames(3)
	check(not FileAccess.file_exists(AppPaths.save_path()), "direct world run wrote no save")
	await free_world()


func test_validation_rules() -> void:
	var base := GameManager.new_game_data("Valid", Appearance.defaults())
	check(SaveManager.validate(base).ok, "new game data is valid")
	var v3 := base.duplicate(true)
	v3.version = 3
	var r := SaveManager.validate(v3)
	check(not r.ok and r.get("unsupported", false) and r.error.contains("newer"), "version 3 rejected with an explanation")
	var no_char := base.duplicate(true)
	no_char.erase("character")
	check(not SaveManager.validate(no_char).ok, "missing character rejected")
	var bad_stage := base.duplicate(true)
	bad_stage.stage = "mainland"
	check(not SaveManager.validate(bad_stage).ok, "unknown stage rejected")
	var no_stage := base.duplicate(true)
	no_stage.erase("stage")
	check_eq(SaveManager.validate(no_stage).data.stage, "island", "missing stage -> island")
	var bad_name := base.duplicate(true)
	bad_name.character.name = "!!"
	bad_name.character.appearance = {"body_type": 7, "skin_tone": "4a3121", "hair_style": "x"}
	var bn: Dictionary = SaveManager.validate(bad_name).data
	check_eq(bn.character.name, "Adventurer", "invalid name -> Adventurer")
	check_eq(bn.character.appearance.body_type, 1, "invalid body type -> default")
	check_eq(bn.character.appearance.skin_tone, "4a3121", "valid field kept")
	var bad_player := base.duplicate(true)
	bad_player.player = {"position": [1, "x", 2], "yaw": 0}
	check(not SaveManager.validate(bad_player).data.has("player"), "invalid player -> dock spawn")
	var quest := base.duplicate(true)
	quest.quest = {"index": 9, "wasd_distance": 99, "marker_reached": "yes", "tasks": ["light_fire", "light_fire", "nope"],
			"pending_task_rewards": ["light_fire", "cook_fish"]}
	var q: Dictionary = SaveManager.validate(quest).data.quest
	check_eq(q.index, 5, "index clamped")
	check_near(q.wasd_distance, 4.0, 0.001, "distance clamped")
	check_eq(q.marker_reached, false, "non-boolean flag -> false")
	check_eq(q.tasks, ["light_fire"], "tasks unique and known")
	check_eq(q.pending_task_rewards, ["light_fire"], "pending rewards must be completed tasks")
	var bad_quest := base.duplicate(true)
	bad_quest.quest = [1, 2]
	check(not SaveManager.validate(bad_quest).ok, "wrong quest type rejected")
	for bad_inv in [{"slots": [{"id": "dragon", "qty": 1}]}, {"slots": [{"id": "logs", "qty": 0}]},
			{"slots": [{"id": "logs", "qty": 1.5}]}, {"slots": [{"id": "steel_axe", "qty": 2}]}, {"slots": "x"},
			{"slots": range(29).map(func(_i: int) -> Variant: return null)}]:
		var d := base.duplicate(true)
		d.inventory = bad_inv
		check(not SaveManager.validate(d).ok, "malformed inventory rejected: %s" % str(bad_inv).left(60))
	var dup := base.duplicate(true)
	dup.inventory = {"slots": [{"id": "logs", "qty": 2}, null, {"id": "logs", "qty": 3}, {"id": "tinderbox", "qty": 1}]}
	var slots: Array = SaveManager.validate(dup).data.inventory.slots
	check_eq(slots.size(), 28, "slots expanded to 28")
	check(slots[0].qty == 5 and slots[2] == null, "duplicate stacks consolidated")
	var skills := base.duplicate(true)
	skills.skills = {"xp": {"attack": -5, "fishing": 1e12, "cooking": 12.5}, "hitpoints": 40}
	var sk: Dictionary = SaveManager.validate(skills).data.skills
	check_eq(sk.xp.attack, 0.0, "negative XP -> 0")
	check_near(sk.xp.fishing, SkillData.xp_cap(), 0.001, "XP clamped to cap")
	check_near(sk.xp.cooking, 12.5, 0.001, "fractional XP kept")
	check_eq(sk.hitpoints, 10, "hitpoints clamped")
	var legacy := base.duplicate(true)
	legacy.erase("skills")
	legacy.hitpoints = 4
	check_eq(SaveManager.validate(legacy).data.skills.hitpoints, 4, "legacy top-level hitpoints moved inside skills")


func test_unsupported_save_disables_continue() -> void:
	var data := GameManager.new_game_data("Future", Appearance.defaults())
	data.version = 3
	write_json(AppPaths.save_path(), data)
	var menu := await _menu()
	check(menu.continue_button.disabled, "Continue disabled for a newer save")
	check(menu.notice.text.contains("newer"), "menu explains why")


func test_atomic_write_failure_keeps_previous() -> void:
	var a := GameManager.new_game_data("First", Appearance.defaults())
	check(SaveManager.write_save(a), "first write")
	var b := GameManager.new_game_data("Second", Appearance.defaults())
	for step in ["open", "verify", "replace"]:
		SaveManager.fail_next_write = step
		check(not SaveManager.write_save(b), "%s failure reported" % step)
		check_eq(read_json(AppPaths.save_path()).character.name, "First", "%s failure keeps the previous save" % step)
		check(not FileAccess.file_exists(SaveManager.temp_path()), "%s failure leaves no temp file" % step)
	check(SaveManager.write_save(b), "write succeeds afterwards")
	check_eq(read_json(SaveManager.backup_path()).character.name, "First", "previous save kept as backup")


func test_corrupt_primary_recovers_from_backup() -> void:
	SaveManager.write_save(GameManager.new_game_data("Older", Appearance.defaults()))
	SaveManager.write_save(GameManager.new_game_data("Newer", Appearance.defaults()))
	var f := FileAccess.open(AppPaths.save_path(), FileAccess.WRITE)
	f.store_string("{\"version\": 2, \"character\": ")
	f.close()
	var st := SaveManager.save_status()
	check(st.can_continue and st.get("needs_recovery", false), "backup offered for a corrupt primary")
	var menu := await _menu()
	check(not menu.continue_button.disabled and menu.notice.text != "", "menu explains and allows recovery")
	await click_control(menu.continue_button)
	var confirm := top_modal() as ConfirmPanel
	if not check(confirm != null, "recovery is confirmed"):
		return
	confirm.press("Restore backup")
	var w := await wait_for_world()
	check(w != null and GameManager.character.name == "Older", "backup adventure loaded")
	var kept := DirAccess.get_files_at(AppPaths.root())
	var corrupt_kept := false
	for fname in kept:
		if fname.contains("corrupt"):
			corrupt_kept = true
	check(corrupt_kept, "corrupt file preserved for inspection")


func test_new_save_keeps_corrupt_primary() -> void:
	SaveManager.write_save(GameManager.new_game_data("Older", Appearance.defaults()))
	var f := FileAccess.open(AppPaths.save_path(), FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	check(SaveManager.write_save(GameManager.new_game_data("Newer", Appearance.defaults())), "new save written")
	var kept := Array(DirAccess.get_files_at(AppPaths.root())).filter(func(n: String) -> bool: return n.contains("corrupt"))
	check_eq(kept.size(), 1, "the damaged primary is preserved, not overwritten")


func test_no_valid_file_disables_continue() -> void:
	var f := FileAccess.open(AppPaths.save_path(), FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	var menu := await _menu()
	check(menu.continue_button.disabled, "corrupt save with no backup disables Continue")


func test_version1_imports() -> void:
	for fixture in ["v1_m2_character", "v1_m3_quest_inventory", "v1_m6_full"]:
		wipe_saves()
		var src := "res://tests/fixtures/%s.json" % fixture
		var original := FileAccess.get_file_as_string(src)
		var res := GameManager.import_save(ProjectSettings.globalize_path(src))
		check(res.ok, "%s imports (%s)" % [fixture, res.get("error", "")])
		check_eq(FileAccess.get_file_as_string(src), original, "%s source untouched" % fixture)
		var data: Variant = read_json(AppPaths.save_path())
		check(data is Dictionary and data.version == 2, "%s written as version 2" % fixture)
		if fixture == "v1_m3_quest_inventory":
			check_eq(data.skills.hitpoints, 7, "legacy hitpoints migrated into skills")
			check_eq(data.inventory.slots[0].qty, 4, "duplicate log stacks consolidated")
			check_eq(data.quest.index, 3, "quest progress kept")
		if fixture == "v1_m6_full":
			check_eq(data.quest.pending_task_rewards, [], "legacy completed tasks count as paid")
			check_eq(data.quest.tasks, ["catch_shrimp", "light_fire"], "unknown legacy task ignored")
	await reset_game()
	var menu := await _menu()
	await click_control(menu.continue_button)
	var w := await wait_for_world()
	check(w != null and GameManager.character.name == "Hale", "imported save continues")
