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


## Runs every test_* method. Returns the number of failed tests.
func run_all(filter: String = "") -> int:
	var failed_tests := 0
	for m in get_method_list():
		var n: String = m.name
		if not n.begins_with("test_"):
			continue
		if filter != "" and not n.contains(filter):
			continue
		current_test = n
		_test_failed = false
		var t0 := Time.get_ticks_msec()
		await before_each()
		await call(n)
		await after_each()
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
