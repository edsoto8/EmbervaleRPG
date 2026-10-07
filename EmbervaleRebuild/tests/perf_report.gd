extends Node
## Performance report: peak draw calls per measured view (and graphics preset when available), plus
## generation time (cold and the median of five warm loads, world instantiation -> navigation_ready).
## Usage: godot --path . --rendering-driver opengl3 res://tests/perf_report.tscn [-- out_file]

const VIEWS := [
	# name, focus, yaw, distance, pitch degrees (SPEC_GAME.md measurement contract)
	["dock", null, 0.0, 14.0, 48.0],
	["village", Vector3(0, 0, 18), 0.6, 16.0, 45.0],
	["forest", Vector3(-24, 0, -12), 0.8, 18.0, 50.0],
	["overview", Vector3(0, 0, 4), 0.0, 95.0, 72.0],
]
const WARMUP := 30
const SAMPLES := 120
const HARD_LIMIT := 450
const TARGET := 260

var _lines: PackedStringArray = []


func _ready() -> void:
	await get_tree().process_frame
	get_window().size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_out("Embervale perf report — %s, %s" % [Engine.get_version_info().string, RenderingServer.get_video_adapter_name()])
	_out("Viewport %s, renderer %s" % [get_viewport().get_visible_rect().size, RenderingServer.get_current_rendering_method()])
	var times: Array[float] = []
	var world: World
	for i in 6:
		var t0 := Time.get_ticks_usec()
		world = load("res://scenes/world/world.tscn").instantiate()
		add_child(world)
		if not world.island.is_navigation_ready:
			await world.island.navigation_ready
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		times.append(ms)
		if i < 5:
			world.queue_free()
			await get_tree().process_frame
	var warm := times.slice(1, 6)
	warm.sort()
	_out("Generation: cold %.0f ms, warm median %.0f ms (limit 1500) %s" % [times[0], warm[2], "PASS" if warm[2] < 1500.0 else "FAIL"])
	_out("Stages (last load): %s" % str(world.island.stage_times))
	var presets := [-1]
	if Engine.has_singleton("SettingsManager") or get_tree().root.has_node("SettingsManager"):
		presets = [0, 1, 2]
	var worst := 0
	for preset in presets:
		if preset >= 0:
			get_tree().root.get_node("SettingsManager").set_value("graphics_quality", preset)
		for v in VIEWS:
			var peak := await _measure(world, v)
			worst = maxi(worst, peak)
			_out("%-8s %-9s peak draw calls %3d  %s" % [["low", "medium", "high"][preset] if preset >= 0 else "-", v[0], peak,
					"PASS" if peak <= HARD_LIMIT else "FAIL"])
	_out("Worst view %d draw calls (hard limit %d, target %d) %s" % [worst, HARD_LIMIT, TARGET, "PASS" if worst <= HARD_LIMIT else "FAIL"])
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var f := FileAccess.open(args[0], FileAccess.WRITE)
		if f:
			f.store_string("\n".join(_lines) + "\n")
	get_tree().quit()


func _measure(world: World, v: Array) -> int:
	var rig := world.camera_rig
	if v[1] == null:
		rig.following = true
		rig.set_view(v[2], v[4], v[3])
		rig.snap()
	else:
		rig.following = false
		var focus: Vector3 = v[1]
		focus.y = world.island.ground_height(focus.x, focus.z)
		var pitch := deg_to_rad(v[4])
		var dir := Vector3(sin(v[2]) * cos(pitch), sin(pitch), cos(v[2]) * cos(pitch))
		rig.camera.global_position = focus + dir * v[3]
		rig.camera.look_at(focus, Vector3.UP)
	for i in WARMUP:
		await get_tree().process_frame
	var peak := 0
	for i in SAMPLES:
		await get_tree().process_frame
		peak = maxi(peak, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	return peak


func _out(line: String) -> void:
	print(line)
	_lines.append(line)
