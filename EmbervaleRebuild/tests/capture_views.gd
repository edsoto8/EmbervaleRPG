extends Node
## Captures fixed camera views of the island as PNGs (and reports draw calls per view).
## Usage: godot --path . --rendering-driver opengl3 --fixed-fps 60 res://tests/capture_views.tscn -- <out_dir> [low|medium|high]

const VIEWS := [
	# name, focus (x, y, z), yaw, distance, pitch degrees
	["dock", null, 0.0, 14.0, 48.0],
	["village", Vector3(0, 1, 18), 0.6, 16.0, 45.0],
	["forest", Vector3(-24, 1, -12), 0.8, 18.0, 50.0],
	["courtyard", Vector3(25, 1, 4), -0.9, 16.0, 42.0],
	["pond", Vector3(20, 1, -20), 2.6, 16.0, 40.0],
	["gate", Vector3(0, 1, -38), 0.2, 18.0, 30.0],
	["overview", Vector3(0, 0, 4), 0.0, 95.0, 72.0],
]

var out_dir := "user://captures"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	var world: World = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	if not world.island.is_navigation_ready:
		await world.island.navigation_ready
	print("generation_ms=%.1f stages=%s" % [world.island.generation_time_ms, world.island.stage_times])
	var rig := world.camera_rig
	for v in VIEWS:
		if v[1] != null:
			rig.following = false
			var focus: Vector3 = v[1]
			focus.y = world.island.ground_height(focus.x, focus.z) + 1.1
			var pitch := deg_to_rad(v[4])
			var dir := Vector3(sin(v[2]) * cos(pitch), sin(pitch), cos(v[2]) * cos(pitch))
			rig.camera.global_position = focus + dir * v[3]
			rig.camera.look_at(focus, Vector3.UP)
		else:
			rig.following = true
			rig.set_view(v[2], v[4], v[3])
			rig.snap()
		for i in 30:
			await get_tree().process_frame
		var peak := 0
		for i in 10:
			await get_tree().process_frame
			peak = maxi(peak, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		var img := get_viewport().get_texture().get_image()
		var path: String = out_dir.path_join("%s.png" % v[0])
		img.save_png(path)
		print("view=%s draw_calls=%d -> %s" % [v[0], peak, path])
	get_tree().quit()
