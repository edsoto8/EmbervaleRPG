extends TestSuite
## Milestone 1: generation, movement, click pathfinding, camera and boundaries.

const LANDMARK_RANGES := {
	"npc_instructor": 2.0, "npc_merchant": 2.0, "npc_fisher": 2.0, "npc_wanderer": 2.0,
	"training_dummy": 1.9,
}


func before_each() -> void:
	await load_world()
	world.camera_rig.set_view(0.0, 48.0, 14.0)
	world.camera_rig.snap()


func after_each() -> void:
	release_all()
	await free_world()


func _player() -> PlayerController:
	return world.player


func _path_end(from: Vector3, to: Vector3) -> Vector3:
	var map := world.island.navigation_map()
	var target := NavigationServer3D.map_get_closest_point(map, to)
	var path := NavigationServer3D.map_get_path(map, from, target, true)
	return path[path.size() - 1] if path.size() > 0 else Vector3.INF


func test_landmarks_exist_on_ground() -> void:
	var island := world.island
	var required := ["dock", "move_marker", "village", "courtyard", "courtyard_entrance", "forest_clearing",
			"fishing_pond", "exit_gate", "npc_instructor", "npc_merchant", "npc_fisher", "npc_wanderer",
			"training_dummy"]
	for key in required:
		if not check(island.landmarks.has(key), "landmark %s exists" % key):
			continue
		var p: Vector3 = island.landmarks[key]
		check_near(p.y, island.ground_height(p.x, p.z), 0.01, "%s sits on generated ground" % key)
		check(p.y > 0.15, "%s is above water (y=%.2f)" % [key, p.y])
	check_near(island.landmarks.npc_instructor.x, 21.5, 0.01, "Maelis X")
	check_near(island.landmarks.npc_instructor.z, 4.0, 0.01, "Maelis Z")
	check_near(island.landmarks.training_dummy.x, 27.6, 0.01, "dummy X")
	check_near(island.landmarks.dock.x, 4.0, 0.01, "dock at X = 4")
	check_near(island.landmarks.dock.y, IslandLayout.DOCK_DECK, 0.01, "spawn on the dock deck")


func test_generation_is_deterministic() -> void:
	var first := _layout_signature(world.island)
	await free_world()
	await load_world()
	check_eq(_layout_signature(world.island), first, "same seeds give the same island")


func _layout_signature(island: TutorialIsland) -> String:
	var parts: Array[String] = []
	for body in island.find_children("*", "StaticBody3D", true, false):
		parts.append("%.2f,%.2f" % [body.global_position.x, body.global_position.z])
	var h := 0.0
	for i in range(0, island.terrain.heights.size(), 97):
		h += island.terrain.heights[i]
	return "%d|%.4f|%s" % [parts.size(), h, str(parts.hash())]


func test_navigation_ready_flag() -> void:
	check(world.island.is_navigation_ready, "navigation_ready flag set")
	var nm: NavigationMesh = world.island.nav_region.navigation_mesh
	check(nm != null and nm.get_polygon_count() > 50, "navmesh has polygons")
	check_near(nm.agent_max_climb, 0.25, 0.001, "max climb is one cell")
	check_near(nm.agent_radius, 0.5, 0.001, "agent radius")
	note("generation %.0f ms" % world.island.generation_time_ms)


func test_all_landmarks_reachable_from_dock() -> void:
	var start: Vector3 = world.island.landmarks.dock
	for key in world.island.landmarks:
		var target: Vector3 = world.island.landmarks[key]
		var end := _path_end(start, target)
		var allowed: float = LANDMARK_RANGES.get(key, 0.6)
		check(flat_distance(end, target) <= allowed,
				"%s reachable (path ends %.2f m away, allowed %.2f)" % [key, flat_distance(end, target), allowed])


func test_spawn_faces_north_on_dock() -> void:
	var p := _player()
	check(IslandLayout.on_dock(Vector2(p.global_position.x, p.global_position.z)), "player spawns on the dock")
	check_near(wrapf(p.facing_yaw(), -PI, PI), 0.0, 0.05, "player faces north")


func test_keyboard_walk_speed_and_direction() -> void:
	var p := _player()
	var start := p.global_position
	await hold("move_forward", 1.0)
	await physics_frames(2)
	var moved := p.global_position - start
	check(moved.z < -2.6, "W moves north with the default camera (dz=%.2f)" % moved.z)
	check(absf(moved.x) < 0.3, "no sideways drift (dx=%.2f)" % moved.x)
	var dist := flat_distance(start, p.global_position)
	check(dist > 2.8 and dist < 3.6, "walk speed about 3.4 m/s (moved %.2f m in 1 s)" % dist)
	check(p.keyboard_distance > 2.5, "keyboard distance is tracked")


func test_diagonal_is_normalised_and_run_is_faster() -> void:
	var p := _player()
	# Walk up the dock first so there is room.
	var start := p.global_position
	Input.action_press("move_forward")
	Input.action_press("move_left")
	await seconds(0.8)
	release_all()
	var diag := flat_distance(start, p.global_position)
	check(diag < 3.4 * 0.8 + 0.3, "diagonal speed normalised (%.2f m in 0.8 s)" % diag)
	await seconds(0.5)
	p.teleport(world.island.landmarks.village, 0.0)
	await physics_frames(2)
	start = p.global_position
	Input.action_press("run")
	Input.action_press("move_back")
	await seconds(1.0)
	release_all()
	var ran := flat_distance(start, p.global_position)
	check(ran > 4.8, "Shift runs at about 6.2 m/s (%.2f m in 1 s)" % ran)


func test_movement_is_camera_relative() -> void:
	var p := _player()
	p.teleport(world.island.landmarks.village + Vector3(0, 0, 3.5), 0.0)
	world.camera_rig.yaw = PI * 0.5   # camera east of the player, looking west
	await physics_frames(2)
	var start := p.global_position
	await hold("move_forward", 0.7)
	var moved := p.global_position - start
	check(moved.x < -1.5 and absf(moved.z) < 0.5, "W follows the camera forward (moved %s)" % moved)


func test_click_to_walk_and_marker() -> void:
	var p := _player()
	var target: Vector3 = world.island.landmarks.move_marker
	await click_world(target)
	check(p.nav.is_active(), "click starts navigation")
	await frames(2)
	check(world.click_marker.visible, "destination marker shown")
	var arrived := await wait_until(func() -> bool: return not p.nav.is_active(), 8.0)
	check(arrived, "route finishes")
	check(flat_distance(p.global_position, target) <= 0.45, "arrives at the click (%.2f m)" % flat_distance(p.global_position, target))
	check(not world.click_marker.visible, "marker hidden on arrival")


func test_keyboard_cancels_click_navigation() -> void:
	var p := _player()
	await click_world(world.island.landmarks.move_marker)
	check(p.nav.is_active(), "navigating")
	await seconds(0.3)
	Input.action_press("move_back")
	await physics_frames(2)
	check(not p.nav.is_active(), "keyboard cancels click navigation immediately")
	release_all()


func test_path_goes_around_obstacles() -> void:
	var p := _player()
	var cottage: Vector2 = IslandLayout.COTTAGES[4]   # (12, 14.5)
	var a := world.island.ground_point(cottage + Vector2(-4.0, 0.0))
	var b := world.island.ground_point(cottage + Vector2(4.2, 0.0))
	p.teleport(a, 0.0)
	await physics_frames(2)
	check(p.nav.walk_to(b), "route found")
	var arrived := await wait_until(func() -> bool: return not p.nav.is_active(), 10.0)
	check(arrived and flat_distance(p.global_position, b) < 0.5, "walked around the cottage (%.2f m left)" % flat_distance(p.global_position, b))


func test_far_water_click_rejected() -> void:
	var p := _player()
	var rejected := [false]
	p.nav.click_rejected.connect(func(_pt: Vector3, _r: String) -> void: rejected[0] = true)
	check(not p.nav.walk_to(Vector3(30, 0, 70)), "point far out at sea is not walkable")
	check(rejected[0], "rejection reported")
	check(not p.nav.is_active(), "no route started")


func test_boundaries_hold() -> void:
	var p := _player()
	# Off the end of the dock.
	await hold("move_back", 3.5)
	check(p.global_position.z < IslandLayout.DOCK_END_Z + 0.1, "dock end rail holds (z=%.2f)" % p.global_position.z)
	check(p.global_position.y > 0.3, "still on the deck")
	# Sideways off the dock.
	await hold("move_left", 1.5)
	check(p.global_position.x > IslandLayout.DOCK_X - IslandLayout.DOCK_HALF_WIDTH, "dock side rail holds")
	# Into the pond.
	p.teleport(world.island.landmarks.fishing_pond, 0.0)
	await physics_frames(2)
	await hold("move_forward", 3.0)
	var d := Vector2(p.global_position.x, p.global_position.z).distance_to(IslandLayout.POND)
	check(d > 6.0, "pond edge holds (%.2f m from centre)" % d)
	# Into the sea from the east beach.
	p.teleport(world.island.ground_point(Vector2(38, 4)), 0.0)
	world.camera_rig.yaw = PI * 0.5
	await physics_frames(2)
	await hold("move_back", 4.0)
	check(world.island.terrain.height_at(p.global_position.x, p.global_position.z) > 0.0, "shoreline holds")


func test_camera_zoom_clamped_and_orbit() -> void:
	var rig := world.camera_rig
	check_near(rig.target_distance, 14.0, 0.01, "initial distance")
	check_near(rad_to_deg(rig.pitch), 48.0, 0.01, "initial pitch")
	for i in 20:
		await click_screen(Vector2(640, 360), MOUSE_BUTTON_WHEEL_UP)
	check_near(rig.target_distance, 5.0, 0.01, "zoom clamps at 5 m")
	for i in 30:
		await click_screen(Vector2(640, 360), MOUSE_BUTTON_WHEEL_DOWN)
	check_near(rig.target_distance, 24.0, 0.01, "zoom clamps at 24 m")
	rig.orbit(Vector2(0, -10000))
	check_near(rad_to_deg(rig.pitch), 28.0, 0.01, "pitch clamps at 28°")
	rig.orbit(Vector2(0, 10000))
	check_near(rad_to_deg(rig.pitch), 72.0, 0.01, "pitch clamps at 72°")


func test_camera_orbit_does_not_cancel_movement() -> void:
	var p := _player()
	await click_world(world.island.landmarks.move_marker)
	Input.action_press("camera_left")
	await seconds(0.5)
	Input.action_release("camera_left")
	check(p.nav.is_active(), "orbiting keeps the route")
	var yaw_before := world.camera_rig.yaw
	world.camera_rig.orbit(Vector2(40, 0))
	check(world.camera_rig.yaw != yaw_before and p.nav.is_active(), "drag orbit keeps the route")


func test_camera_pulls_in_behind_buildings() -> void:
	var p := _player()
	var c: Vector2 = IslandLayout.COTTAGES[3]   # (-7, 33), door faces the plaza (north)
	p.teleport(world.island.ground_point(c + Vector2(0, -4.2)), 0.0)
	world.camera_rig.set_view(0.0, 30.0, 20.0)
	world.camera_rig.snap()
	await frames(5)
	var cam_d := world.camera_rig.camera.global_position.distance_to(world.camera_rig.focus)
	check(cam_d < 8.0, "camera pulled in front of the cottage (%.2f m)" % cam_d)


func test_obstacles_are_tall_enough() -> void:
	var short := 0
	for body in world.island.find_children("*", "StaticBody3D", true, false):
		if (body.collision_layer & Layers.OBSTACLES) == 0:
			continue
		for cs in body.get_children():
			if not cs is CollisionShape3D:
				continue
			var h := 0.0
			if cs.shape is BoxShape3D:
				h = cs.shape.size.y
			elif cs.shape is CylinderShape3D:
				h = cs.shape.height
			else:
				continue
			if h < 0.99:
				short += 1
	check_eq(short, 0, "every obstacle collision shape is at least ~1 m tall")
