extends TestSuite
## No-teleport playthrough: main menu -> character creation -> intro -> all five objectives ->
## gate sequence -> Tutorial Complete -> main menu -> Continue. Only real input (clicks projected from
## the camera, keys, typed text). Fails if the player ever jumps between frames. Prints a pacing report
## (headless timings are diagnostic, not human pacing).

const MAX_STEP := 0.25   ## metres per physics frame (run speed is ~0.1)

var _monitor_on := false
var _last_pos := Vector3.INF
var _max_step := 0.0
var _jumps := 0
var _time := {"movement": 0.0, "dialogue": 0.0, "action": 0.0, "idle": 0.0, "cutscene": 0.0}
var _w: World


func before_each() -> void:
	await reset_game()
	wipe_saves()


func after_each() -> void:
	_monitor_on = false
	await reset_game()


func _physics_process(delta: float) -> void:
	if not _monitor_on or _w == null or not is_instance_valid(_w):
		return
	var p := _w.player.global_position
	if _last_pos != Vector3.INF:
		var step := flat_distance(p, _last_pos)
		_max_step = maxf(_max_step, step)
		if step > MAX_STEP:
			_jumps += 1
	_last_pos = p
	if GameManager.state == GameManager.State.CUTSCENE:
		_time.cutscene += delta
	elif DialogueManager.active:
		_time.dialogue += delta
	elif _w.player.is_busy():
		_time.action += delta
	elif _w.player.nav.is_active() or _w.player.velocity.length() > 0.2:
		_time.movement += delta
	else:
		_time.idle += delta


func _type_text(text: String) -> void:
	for ch in text:
		var e := InputEventKey.new()
		e.pressed = true
		e.unicode = ch.unicode_at(0)
		e.keycode = OS.find_keycode_from_string(ch) if ch != " " else KEY_SPACE
		Input.parse_input_event(e)
		await frames(1)
		var r := e.duplicate()
		r.pressed = false
		Input.parse_input_event(r)
		await frames(1)


func _on_screen(cam: Camera3D, p: Vector3) -> bool:
	if cam.is_position_behind(p):
		return false
	var s := cam.unproject_position(p)
	var r := get_viewport().get_visible_rect().grow(-60.0)
	return r.has_point(s)


## Walks towards a target by clicking visible ground ahead along the navmesh route.
func walk_by_clicks(target: Vector3, reach: float, timeout: float = 120.0) -> bool:
	var player := _w.player
	var frames_left := int(timeout * 60.0)
	while flat_distance(player.global_position, target) > reach:
		if frames_left <= 0:
			return false
		var map := _w.island.navigation_map()
		var goal := NavigationServer3D.map_get_closest_point(map, target)
		var path := NavigationServer3D.map_get_path(map, player.global_position, goal, true)
		var cam := get_viewport().get_camera_3d()
		var clicked := false
		for ahead in [10.0, 8.0, 6.0, 4.0, 2.5, 1.5]:
			var p := _along(path, ahead)
			if not _on_screen(cam, p):
				continue
			var screen := cam.unproject_position(p)
			var hit := player.nav.pick(screen)
			if hit.is_empty() or InteractionSystem.interactable_from(hit.collider) != null:
				continue
			if flat_distance(hit.position, p) > 1.2:
				continue
			await click_screen(screen)
			clicked = true
			break
		if not clicked:
			# Turn the camera with the arrow keys until the route ahead is visible.
			await hold("camera_left", 0.3)
			frames_left -= 18
			continue
		var started := Time.get_ticks_msec()
		var waited := 0
		while player.nav.is_active() and waited < 240 and flat_distance(player.global_position, target) > reach:
			await get_tree().physics_frame
			waited += 1
		frames_left -= waited + 2
	return true


static func _along(path: PackedVector3Array, dist: float) -> Vector3:
	var left := dist
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		if seg >= left:
			return path[i].lerp(path[i + 1], left / seg)
		left -= seg
	return path[path.size() - 1]


## Clicks an interactable once it's on screen; returns when the interaction starts.
func click_target(target: Node3D, height: float) -> bool:
	var cam := get_viewport().get_camera_3d()
	var p := target.global_position + Vector3(0, height, 0)
	for i in 6:
		if _on_screen(cam, p):
			var hit := _w.player.nav.pick(cam.unproject_position(p))
			if not hit.is_empty() and InteractionSystem.interactable_from(hit.collider) == target:
				await click_screen(cam.unproject_position(p))
				return true
		await hold("camera_left", 0.25)
	return false


func test_full_tutorial_without_teleporting() -> void:
	var t0 := Time.get_ticks_msec()
	GameManager.go_to_main_menu()
	var menu := await wait_for_scene("MainMenu") as MainMenu
	await click_control(menu.new_game_button)
	var cc := await wait_for_scene("CharacterCreation") as CharacterCreation
	await frames(3)
	await click_control(cc.name_edit)
	await _type_text("Wren Ash")
	check_eq(cc.name_edit.text, "Wren Ash", "name typed")
	await click_control(find_named(cc, "Randomize"))
	await click_control(cc.create_button)
	_w = await wait_for_world()
	if not check(_w != null, "world loads"):
		return
	_monitor_on = true
	_last_pos = Vector3.INF
	# Watch the whole intro.
	var intro_done := await wait_until(func() -> bool: return _w.intro == null, 16.0)
	check(intro_done, "intro plays to the end")
	_last_pos = Vector3.INF
	# 1. Learn to move.
	await hold("move_forward", 1.6)
	var marker: Vector3 = _w.island.landmarks.move_marker
	check(_on_screen(get_viewport().get_camera_3d(), marker), "marker visible")
	await click_world(marker)
	check(await wait_until(func() -> bool: return QuestManager.index >= 1, 10.0), "Learn to move complete")
	# 2. Meet the instructor.
	var maelis: Npc = _w.director.npcs.maelis
	check(await walk_by_clicks(maelis.global_position, 7.0), "walked to the courtyard")
	check(await click_target(maelis, 1.0), "clicked Maelis")
	check(await wait_until(func() -> bool: return DialogueManager.active, 10.0), "talking to Maelis")
	await run_dialogue(_w, [1, 2, 3])
	check_eq(QuestManager.index, 2, "Meet the instructor complete")
	# 3. Gather logs.
	check(await walk_by_clicks(_w.island.landmarks.forest_clearing, 4.0), "walked to the forest clearing")
	var guard := 0
	while InventoryManager.count("logs") < 3 and guard < 12:
		guard += 1
		var best: ChoppableTree = null
		for tree in _w.island.choppable_trees:
			if not tree.is_stump and (best == null or flat_distance(tree.global_position, _w.player.global_position) < flat_distance(best.global_position, _w.player.global_position)):
				best = tree
		if best == null:
			await seconds(2.0)
			continue
		var had := InventoryManager.count("logs")
		if await click_target(best, 2.6):
			await wait_until(func() -> bool: return InventoryManager.count("logs") > had, 12.0)
	check_eq(QuestManager.index, 3, "Gather logs complete")
	# 4. Check your inventory.
	await tap("inventory")
	await frames(2)
	await click_control(_w.hud.inventory_panel.slot_buttons[InventoryManager.first_slot_of("logs")])
	check_eq(QuestManager.index, 4, "Check your inventory complete")
	await tap("inventory")
	# 5. Report back.
	check(await walk_by_clicks(maelis.global_position, 7.0), "walked back to Maelis")
	check(await click_target(maelis, 1.0), "clicked Maelis again")
	check(await wait_until(func() -> bool: return DialogueManager.active, 10.0), "talking to Maelis again")
	await run_dialogue(_w)
	check(QuestManager.is_tutorial_complete(), "tutorial complete")
	check_eq(InventoryManager.count("beginner_sword"), 1, "Beginner sword received")
	# Closing sequence, then back to the menu and Continue.
	var shown := await wait_until(func() -> bool: return top_modal() is TutorialCompletePanel, 9.0)
	check(shown, "Tutorial Complete after the gate sequence")
	_monitor_on = false
	var finish_pos := _w.player.global_position
	await click_control(find_named(top_modal(), "ReturnToMainMenu"))
	menu = await wait_for_scene("MainMenu") as MainMenu
	await click_control(menu.continue_button)
	var w2 := await wait_for_world()
	check(w2 != null and QuestManager.is_tutorial_complete(), "Continue restores the completed tutorial")
	check(w2.director.gate_sequence == null and top_modal() == null, "closing sequence not replayed")
	check_eq(InventoryManager.count("beginner_sword"), 1, "still one sword")
	check(flat_distance(w2.player.global_position, finish_pos) < 0.5, "position restored")
	check_eq(_jumps, 0, "no teleporting (max step %.3f m)" % _max_step)
	var total := 0.0
	for k in _time:
		total += _time[k]
	print("    pacing (game seconds): movement %.1f, dialogue %.1f, action %.1f, idle %.1f, cutscene %.1f, total %.1f; real %.1f s"
			% [_time.movement, _time.dialogue, _time.action, _time.idle, _time.cutscene, total, (Time.get_ticks_msec() - t0) / 1000.0])
	print("    (headless/accelerated timings are diagnostic only; human pacing target is 5-10 minutes)")
