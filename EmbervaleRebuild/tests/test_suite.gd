class_name TestSuite
extends Node
## Base class for headless test suites. Every method named `test_*` runs in declaration order and may
## await. Use the check helpers; a failed check records the failure and the test continues.

var suite_name := "suite"
var failures: Array[String] = []
var passed := 0
var current_test := ""
var world: World
var _test_failed := false
## Set by the runner: script errors during a test fail it.
var error_catcher: ErrorCatcher


## Runs every test_* method. Returns the number of failed tests.
func run_all(filter: String = "") -> int:
	var failed_tests := 0
	var seen := {}
	for m in get_method_list():
		var n: String = m.name
		if not n.begins_with("test_") or seen.has(n):
			continue
		seen[n] = true
		if filter != "" and not n.contains(filter):
			continue
		current_test = n
		_test_failed = false
		var t0 := Time.get_ticks_msec()
		if error_catcher:
			error_catcher.take()
		await before_each()
		await call(n)
		await after_each()
		if error_catcher:
			for e in error_catcher.take():
				check(false, "script error: " + e)
		var ms := Time.get_ticks_msec() - t0
		if _test_failed:
			failed_tests += 1
			print("  FAIL %s.%s (%d ms)" % [suite_name, n, ms])
		else:
			passed += 1
			print("  ok   %s.%s (%d ms)" % [suite_name, n, ms])
	return failed_tests


func before_each() -> void:
	pass


func after_each() -> void:
	pass


# --- checks -------------------------------------------------------------------------------------

func check(cond: bool, message: String = "") -> bool:
	if not cond:
		_test_failed = true
		var line := "%s.%s: %s" % [suite_name, current_test, message]
		failures.append(line)
		print("    check failed: " + message)
	return cond


func check_eq(a: Variant, b: Variant, message: String = "") -> bool:
	return check(a == b, "%s (got %s, expected %s)" % [message, str(a), str(b)])


func check_near(a: float, b: float, tolerance: float, message: String = "") -> bool:
	return check(absf(a - b) <= tolerance, "%s (got %.3f, expected %.3f ± %.3f)" % [message, a, b, tolerance])


func note(message: String) -> void:
	print("    note: " + message)


# --- helpers ------------------------------------------------------------------------------------

## Instantiates the world scene directly (no GameManager) and waits for navigation.
func load_world() -> World:
	world = load("res://scenes/world/world.tscn").instantiate()
	get_tree().root.add_child(world)
	if not world.island.is_navigation_ready:
		await world.island.navigation_ready
	await physics_frames(2)
	return world


func free_world() -> void:
	if is_instance_valid(world):
		world.queue_free()
		world = null
	await frames(2)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Waits `seconds` of game time (60 physics frames per second).
func seconds(s: float) -> void:
	await physics_frames(int(ceil(s * 60.0)))


## Holds an input action for `s` seconds of game time.
func hold(action: StringName, s: float) -> void:
	Input.action_press(action)
	await seconds(s)
	Input.action_release(action)


func release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "run", "camera_left",
			"camera_right", "camera_up", "camera_down"]:
		Input.action_release(a)


## Sends a real mouse click at a viewport position through the input pipeline (window events are
## mapped back through the root's stretch transform, so pass viewport coordinates).
func click_screen(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var window_pos := get_tree().root.get_final_transform() * pos
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = window_pos
		e.global_position = window_pos
		Input.parse_input_event(e)
		await frames(1)


## Clicks the screen position of a world point (must be visible).
func click_world(point: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	await click_screen(cam.unproject_position(point))


## Waits until `cond` returns true or `timeout` game seconds pass. Returns whether it became true.
func wait_until(cond: Callable, timeout: float) -> bool:
	var frames_left := int(timeout * 60.0)
	while frames_left > 0:
		if cond.call():
			return true
		await get_tree().physics_frame
		frames_left -= 1
	return cond.call()


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- game flow helpers --------------------------------------------------------------------------

## Deletes save and settings files in the isolated data directory.
func wipe_saves() -> void:
	var dir := DirAccess.open(AppPaths.root())
	if dir == null:
		return
	for f in dir.get_files():
		if f.begins_with("savegame") or f == "settings.json":
			dir.remove(f)


## Returns the game to a clean main-menu-less state between tests.
func reset_game() -> void:
	release_all()
	get_tree().paused = false
	for m in get_tree().get_nodes_in_group("modal_panel"):
		m.queue_free()
	var cur := get_tree().current_scene
	if cur != null:
		cur.queue_free()
		get_tree().current_scene = null
	GameManager.end_adventure()
	GameManager.transitioning = false
	GameManager.state = GameManager.State.MAIN_MENU
	SaveManager.fail_next_write = ""
	await frames(3)


## Waits for a scene change to finish and returns the new current scene.
func wait_for_scene(script_class: String, timeout: float = 8.0) -> Node:
	var ok := await wait_until(func() -> bool:
		var cur := get_tree().current_scene
		return cur != null and not GameManager.transitioning and cur.get_script() != null \
				and cur.get_script().get_global_name() == script_class, timeout)
	if not ok:
		return null
	return get_tree().current_scene


## Waits for the gameplay world (from a GameManager scene change) to be ready.
func wait_for_world(timeout: float = 10.0) -> World:
	var w := await wait_for_scene("World", timeout) as World
	if w == null:
		return null
	if not w.is_ready:
		await w.world_ready
	world = w
	return w


## Sends an input action press and release through the input pipeline.
func tap(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await frames(1)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)
	await frames(1)


## Sends a key press and release (physical keycode) through the input pipeline.
func key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await frames(1)


## Clicks the centre of a Control through the input pipeline (after a frame, so new controls have
## been laid out, as they would be before a person could click them).
func click_control(c: Control) -> void:
	await frames(1)
	if not is_instance_valid(c):
		check(false, "control to click no longer exists")
		return
	await click_screen(c.get_global_rect().get_center())


func find_named(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)


func top_modal() -> ModalPanel:
	var modals := get_tree().get_nodes_in_group("modal_panel")
	return modals[modals.size() - 1] if modals.size() > 0 else null


func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


# --- adventure helpers ----------------------------------------------------------------------------

## Writes a save (stage island) with the given quest/inventory/skills and continues into it through
## the real Continue path. Returns the ready world.
func start_adventure(quest: Dictionary = {}, slots: Array = [], extra: Dictionary = {}) -> World:
	var data := GameManager.new_game_data("Tester", Appearance.defaults())
	data.stage = "island"
	for k in quest:
		data.quest[k] = quest[k]
	data.inventory.slots = slots
	for k in extra:
		data[k] = extra[k]
	if not SaveManager.write_save(data):
		push_error("could not write fixture save")
	var res := GameManager.continue_game()
	if not res.ok:
		push_error("continue failed: %s" % res.get("error", ""))
		return null
	var w := await wait_for_world()
	await physics_frames(2)
	return w


func saved_data() -> Dictionary:
	var d: Variant = read_json(AppPaths.save_path())
	return d if d is Dictionary else {}


## Plays through the current conversation with real keys: Space reveals/advances, number keys pick
## `picks` in order (1-based). Returns when the dialogue ends or after `limit` steps.
func run_dialogue(world_: World, picks: Array = [], limit: int = 40) -> void:
	var queue := picks.duplicate()
	for i in limit:
		if not DialogueManager.active:
			return
		var panel := world_.hud.dialogue_panel
		if panel.is_typing():
			await tap("dialogue_continue")
			continue
		if DialogueManager.has_choices():
			var n: int = queue.pop_front() if not queue.is_empty() else DialogueManager.choices().size()
			await tap("choice_%d" % n)
		else:
			await tap("dialogue_continue")
		await frames(1)


## Places the player near a point (teleport, for unit fixtures) and points the camera at it.
func place_player(world_: World, pos: Vector3, yaw: float = 0.0) -> void:
	world_.player.teleport(world_.island.closest_walkable(pos), yaw)
	world_.camera_rig.set_view(yaw, 50.0, 12.0)
	world_.camera_rig.snap()
	await physics_frames(3)
