class_name TutorialIsland
extends Node3D
## Generates Driftwood Isle: terrain, collision, buildings, props, boundaries, water, batching and
## the runtime navmesh. Everything is deterministic (fixed seeds); quests and tests rely on
## `landmarks`, so layout changes must keep every landmark on reachable ground.

signal navigation_ready

const WATER_SHADER := preload("res://shaders/water.gdshader")
const WATER_LAND_OFFSET := 0.12
const SMALL_DECOR_FADE := 75.0

@export var generation_seed := IslandLayout.ISLAND_SEED

var terrain: IslandTerrain
var landmarks := {}
var nav_region: NavigationRegion3D
var is_navigation_ready := false
## Milliseconds from generation start to navigation readiness.
var generation_time_ms := 0.0
## Per-stage generation timings in milliseconds (perf report).
var stage_times := {}

var boat: Boat
var dummies: Array[TrainingDummy] = []
## Choppable tree slots (filled with ChoppableTree nodes from Milestone 3).
var choppable_trees: Array = []
var chimney_tops: Array[Vector3] = []
var lamp_positions: Array[Vector3] = []
var sea: MeshInstance3D
var pond: MeshInstance3D
var terrain_mesh: MeshInstance3D
var decor_chunks: Array = []
var ambient: AmbientLife

var _rng := RandomNumberGenerator.new()
var _cover_rng := RandomNumberGenerator.new()
var _props: Node3D
var _decor: Node3D
var _grass_core: Node3D
var _grass_extra: Node3D
var _lights: Node3D
## Grass chunks: core (always) and extra (hidden on Low, giving 40% density).
var grass_core_chunks: Array = []
var grass_extra_chunks: Array = []
var lantern_meshes: Array[MeshInstance3D] = []
## Ground cover counts by kind (graphics tests).
var cover_counts := {}
var sea_depth_image: Image
var pond_depth_image: Image
var graphics_quality := 1
var _boundary: StaticBody3D
var _keep: Array = []
var _reserved: Array[Vector3] = []   # (x, z, radius) circles no scattered prop may enter
var _occluders: Array[Vector3] = []  # (x, z, radius) with strength in _occluder_strength
var _occluder_strength: Array[float] = []
var _water_posts: Array[Vector2] = []
var _shoreline: PackedVector2Array


func _ready() -> void:
	generate()


func generate() -> void:
	var t0 := Time.get_ticks_usec()
	_rng.seed = generation_seed
	_cover_rng.seed = IslandLayout.COVER_SEED
	terrain = IslandTerrain.new()
	_stage("terrain", terrain.generate)

	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	add_child(nav_region)
	_props = Node3D.new()
	_props.name = "Props"
	nav_region.add_child(_props)
	_decor = Node3D.new()
	_decor.name = "_decor"
	add_child(_decor)
	_grass_core = Node3D.new()
	_grass_core.name = "_grass_core"
	add_child(_grass_core)
	_grass_extra = Node3D.new()
	_grass_extra.name = "_grass_extra"
	add_child(_grass_extra)
	_lights = Node3D.new()
	_lights.name = "Lanterns"
	add_child(_lights)

	_stage("ground", _build_ground)
	_stage("boundaries", _build_boundaries)
	_stage("dock", _build_dock)
	_stage("village", _build_village)
	_stage("courtyard", _build_courtyard)
	_stage("forest", _build_forest)
	_stage("pond", _build_pond)
	_stage("gate", _build_gate)
	_stage("scatter", _build_scatter)
	_stage("ground_cover", _build_ground_cover)
	_stage("ground_cover_m5", _build_extra_cover)
	_stage("mainland", _build_mainland)
	_stage("landmarks", _build_landmarks)
	_stage("terrain_mesh", _build_terrain_mesh)
	_stage("water", _build_water)
	_stage("water_depth", _bake_water_depth)
	_stage("merge_meshes", _merge_meshes)
	_stage("ambient_life", _build_ambient_life)
	_stage("bake_navigation", _bake_navigation)
	await _wait_for_map_sync()
	apply_graphics_quality(SettingsManager.get_value("graphics_quality"))
	if not SettingsManager.settings_changed.is_connected(_on_setting):
		SettingsManager.settings_changed.connect(_on_setting)
	generation_time_ms = (Time.get_ticks_usec() - t0) / 1000.0
	is_navigation_ready = true
	navigation_ready.emit()


func _stage(stage_name: String, fn: Callable) -> void:
	var t := Time.get_ticks_usec()
	fn.call()
	stage_times[stage_name] = (Time.get_ticks_usec() - t) / 1000.0


## Ground height including the dock deck.
func ground_height(x: float, z: float) -> float:
	if IslandLayout.on_dock(Vector2(x, z)):
		return IslandLayout.DOCK_DECK
	return terrain.height_at(x, z)


func ground_point(p: Vector2) -> Vector3:
	return Vector3(p.x, ground_height(p.x, p.y), p.y)


func navigation_map() -> RID:
	return get_world_3d().navigation_map


## Closest point on the navmesh, or the input if navigation is not ready.
func closest_walkable(p: Vector3) -> Vector3:
	if not is_navigation_ready:
		return p
	return NavigationServer3D.map_get_closest_point(navigation_map(), p)


# --- ground and boundaries ------------------------------------------------------------------------

func _build_ground() -> void:
	var body := PropFactory.solid(nav_region, "Ground", Vector3.ZERO, Layers.GROUND)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(terrain.build_collision_faces())
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


func _build_boundaries() -> void:
	_boundary = PropFactory.solid(nav_region, "Boundary", Vector3.ZERO, Layers.BOUNDARY)
	# Shoreline: one wall segment per angular step at the waterline, with a gap for the dock.
	var n := 180
	_shoreline = PackedVector2Array()
	for k in n:
		var a := TAU * k / n
		var dir := Vector2(cos(a), sin(a))
		var r := 30.0
		while r < 62.0 and terrain.height_at(dir.x * r, dir.y * r) > WATER_LAND_OFFSET:
			r += 0.25
		_shoreline.append(dir * (r - 0.35))
	var gap_west := Vector2.ZERO
	var gap_east := Vector2.ZERO
	for k in n:
		var p0 := _shoreline[k]
		var p1 := _shoreline[(k + 1) % n]
		var mid := (p0 + p1) * 0.5
		if mid.y > 30.0 and absf(mid.x - IslandLayout.DOCK_X) < 2.6:
			# Angles grow from +X towards +Z, so p1 is the western end of a skipped segment.
			if p0.x > IslandLayout.DOCK_X:
				gap_east = p0 if gap_east == Vector2.ZERO else gap_east
			gap_west = p1
			continue
		_wall(p0, p1)
	var rail_w := IslandLayout.DOCK_X - IslandLayout.DOCK_HALF_WIDTH - 0.1
	var rail_e := IslandLayout.DOCK_X + IslandLayout.DOCK_HALF_WIDTH + 0.1
	_wall(gap_west, Vector2(rail_w, gap_west.y))
	_wall(gap_east, Vector2(rail_e, gap_east.y))
	var z0 := IslandLayout.DOCK_START_Z + 2.5
	var z1 := IslandLayout.DOCK_END_Z + 0.1
	_wall(Vector2(rail_w, z0), Vector2(rail_w, z1), IslandLayout.DOCK_DECK)
	_wall(Vector2(rail_e, z0), Vector2(rail_e, z1), IslandLayout.DOCK_DECK)
	_wall(Vector2(rail_w, z1), Vector2(rail_e, z1), IslandLayout.DOCK_DECK)
	# Pond edge.
	var pn := 48
	var prev := Vector2.ZERO
	var first := Vector2.ZERO
	for k in pn + 1:
		var a := TAU * (k % pn) / pn
		var dir := Vector2(cos(a), sin(a))
		var r := 3.0
		while r < 9.0 and terrain.height_at(IslandLayout.POND.x + dir.x * r, IslandLayout.POND.y + dir.y * r) < 0.3:
			r += 0.1
		var p := IslandLayout.POND + dir * r
		if k == 0:
			first = p
		else:
			_wall(prev, p)
		prev = p


func _wall(a: Vector2, b: Vector2, base: float = NAN) -> void:
	var length := a.distance_to(b)
	if length < 0.01:
		return
	var mid := (a + b) * 0.5
	var y := base if not is_nan(base) else minf(terrain.height_at(a.x, a.y), terrain.height_at(b.x, b.y))
	var cs := PropFactory.box_shape(_boundary, Vector3(0.2, 4.0, length + 0.3),
			Vector3(mid.x, y + 1.5, mid.y), atan2(b.x - a.x, b.y - a.y))
	cs.name = "Wall"


# --- regions ------------------------------------------------------------------------------------

func _reserve(p: Vector2, radius: float) -> void:
	_reserved.append(Vector3(p.x, p.y, radius))


func _occlude(pos: Vector2, radius: float, strength: float) -> void:
	_occluders.append(Vector3(pos.x, pos.y, radius))
	_occluder_strength.append(strength)


func _node_at(parent: Node, node_name: String, p: Vector2, yaw: float = 0.0, y_offset: float = 0.0) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = Vector3(p.x, ground_height(p.x, p.y) + y_offset, p.y)
	n.rotation.y = yaw
	parent.add_child(n)
	return n


func _build_dock() -> void:
	var dock := Node3D.new()
	dock.name = "Dock"
	_props.add_child(dock)
	var plank := Color("8a6440")
	var dark := Color("5e4229")
	var length := IslandLayout.DOCK_END_Z - IslandLayout.DOCK_START_Z
	var cz := (IslandLayout.DOCK_START_Z + IslandLayout.DOCK_END_Z) * 0.5
	var deck := PropFactory.solid(dock, "Deck", Vector3(IslandLayout.DOCK_X, IslandLayout.DOCK_DECK - 0.15, cz), Layers.GROUND)
	PropFactory.box_shape(deck, Vector3(IslandLayout.DOCK_HALF_WIDTH * 2.0, 0.3, length))
	PropFactory.box(dock, Vector3(3.0, 0.16, length), Vector3(IslandLayout.DOCK_X, IslandLayout.DOCK_DECK - 0.08, cz), plank)
	var z := IslandLayout.DOCK_START_Z + 0.5
	while z < IslandLayout.DOCK_END_Z:
		PropFactory.box(dock, Vector3(3.04, 0.03, 0.06), Vector3(IslandLayout.DOCK_X, IslandLayout.DOCK_DECK + 0.005, z), dark)
		z += 0.75
	z = IslandLayout.DOCK_START_Z + 3.0
	while z <= IslandLayout.DOCK_END_Z + 0.01:
		for side in [-1.0, 1.0]:
			var x: float = IslandLayout.DOCK_X + side * 1.55
			PropFactory.cylinder(dock, 0.12, 0.14, 2.6, Vector3(x, -0.6, z), dark, 6)
			PropFactory.cylinder(dock, 0.12, 0.12, 0.08, Vector3(x, 0.72, z), Color("4d3520"), 6)
			if terrain.height_at(x, z) < 0.0:
				_water_posts.append(Vector2(x, z))
		z += 3.5
	# Rope rail along both sides.
	for side in [-1.0, 1.0]:
		PropFactory.box(dock, Vector3(0.05, 0.05, length - 3.0), Vector3(IslandLayout.DOCK_X + side * 1.55, 0.65, cz + 1.5), Color("c9b48a"))
	# Crates and barrels on the beach beside the landing.
	for c in [Vector2(-0.4, 39.5), Vector2(8.6, 38.6)]:
		var crate := PropFactory.solid(_props, "Crate", Vector3(c.x, ground_height(c.x, c.y), c.y))
		PropFactory.box_shape(crate, Vector3(1.0, 1.2, 1.0), Vector3(0, 0.6, 0))
		PropFactory.box(crate, Vector3(0.9, 0.8, 0.9), Vector3(0, 0.4, 0), Color("9a7448"), Vector3(0, 0.3, 0))
		PropFactory.box(crate, Vector3(0.6, 0.55, 0.6), Vector3(0.2, 1.07, 0.1), Color("a88052"), Vector3(0, -0.2, 0))
		_reserve(c, 1.5)
	var barrel := PropFactory.solid(_props, "Barrel", ground_point(Vector2(9.6, 40.1)))
	PropFactory.cylinder_shape(barrel, 0.45, 1.2, Vector3(0, 0.6, 0))
	PropFactory.cylinder(barrel, 0.38, 0.38, 0.9, Vector3(0, 0.45, 0), Color("7d5634"), 8)
	PropFactory.cylinder(barrel, 0.4, 0.4, 0.08, Vector3(0, 0.25, 0), Color("4a4a48"), 8)
	PropFactory.cylinder(barrel, 0.4, 0.4, 0.08, Vector3(0, 0.7, 0), Color("4a4a48"), 8)
	_reserve(Vector2(9.6, 40.1), 1.2)
	_reserve(Vector2(IslandLayout.DOCK_X, 38.0), 4.0)
	# The moored boat: separate so the intro can sail it in.
	boat = Boat.new()
	boat.name = "Boat"
	boat.position = Vector3(IslandLayout.BOAT.x, 0.0, IslandLayout.BOAT.y)
	add_child(boat)
	_keep.append(boat)


func _build_village() -> void:
	var village := Node3D.new()
	village.name = "Village"
	_props.add_child(village)
	_reserve(IslandLayout.PLAZA, IslandLayout.PLAZA_RADIUS + 1.0)
	for c in IslandLayout.COTTAGES:
		_build_cottage(village, c)
	# Well.
	var well := PropFactory.solid(village, "Well", ground_point(IslandLayout.WELL))
	PropFactory.cylinder_shape(well, 1.05, 1.4, Vector3(0, 0.7, 0))
	var stone := Color("8d8a82")
	PropFactory.cylinder(well, 0.95, 1.0, 0.8, Vector3(0, 0.4, 0), stone, 10)
	PropFactory.cylinder(well, 0.75, 0.75, 0.05, Vector3(0, 0.78, 0), Color("2f4a5a"), 10)
	for s in [-1.0, 1.0]:
		PropFactory.box(well, Vector3(0.14, 1.9, 0.14), Vector3(s * 0.85, 1.15, 0), Color("6b4a2b"))
	PropFactory.prism(well, Vector3(2.2, 0.7, 1.4), Vector3(0, 2.35, 0), Color("8a4b33"))
	PropFactory.cylinder(well, 0.06, 0.06, 1.6, Vector3(0, 1.75, 0), Color("6b4a2b"), 6, Vector3(0, 0, PI * 0.5))
	PropFactory.cylinder(well, 0.16, 0.13, 0.25, Vector3(0, 1.3, 0), Color("7d5634"), 7)
	_occlude(IslandLayout.WELL, 1.6, 0.35)
	# Market stalls face the plaza centre.
	_build_stall(village, IslandLayout.MARKET_STALL, Color("b8452c"), Color("efe6cf"), true)
	_build_stall(village, IslandLayout.SECOND_STALL, Color("2f6a7a"), Color("efe6cf"), false)
	# Lamp posts around the plaza, clear of path entrances.
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		var p: Vector2 = IslandLayout.PLAZA + Vector2(cos(a), sin(a)) * (IslandLayout.PLAZA_RADIUS + 0.6)
		if IslandLayout.distance_to_paths(p) < 2.2 or p.distance_to(IslandLayout.MARKET_STALL) < 2.5 \
				or p.distance_to(IslandLayout.SECOND_STALL) < 2.5:
			continue
		_build_lamp(village, p)
	# Signpost by the dock path.
	var sign_node := PropFactory.solid(village, "Signpost", ground_point(IslandLayout.SIGNPOST))
	PropFactory.cylinder_shape(sign_node, 0.2, 2.4, Vector3(0, 1.2, 0))
	PropFactory.cylinder(sign_node, 0.07, 0.08, 2.3, Vector3(0, 1.15, 0), Color("6b4a2b"), 6)
	var boards := [[0.6, 2.0, Color("a88052")], [-0.9, 1.7, Color("9a7448")], [2.2, 1.4, Color("a88052")]]
	for b in boards:
		var arm := Node3D.new()
		arm.rotation.y = b[0]
		arm.position.y = b[1]
		sign_node.add_child(arm)
		PropFactory.box(arm, Vector3(0.9, 0.22, 0.05), Vector3(0.45, 0, 0), b[2])
		PropFactory.prism(arm, Vector3(0.22, 0.2, 0.05), Vector3(0.98, 0, 0), b[2], Vector3(0, 0, -PI * 0.5))
	_reserve(IslandLayout.SIGNPOST, 1.0)
	_build_garden(village)


func _build_cottage(parent: Node, c: Vector2) -> void:
	var yaw := IslandLayout.yaw_towards(c, IslandLayout.PLAZA)
	var cot := _node_at(parent, "Cottage", c, yaw)
	var size := IslandLayout.COTTAGE_SIZE
	var wall := Color("e6d9bb")
	var timber := Color("6b4a2b")
	var roof := Color("9a4a32") if int(c.x + c.y) % 2 == 0 else Color("7d5a3a")
	PropFactory.box(cot, Vector3(size.x + 0.3, 0.4, size.y + 0.3), Vector3(0, 0.0, 0), Color("8d8a82"))
	PropFactory.box(cot, Vector3(size.x, 2.6, size.y), Vector3(0, 1.3, 0), wall)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			PropFactory.box(cot, Vector3(0.22, 2.7, 0.22), Vector3(sx * size.x * 0.5, 1.35, sz * size.y * 0.5), timber)
	PropFactory.box(cot, Vector3(size.x + 0.05, 0.18, size.y + 0.05), Vector3(0, 2.55, 0), timber)
	PropFactory.prism(cot, Vector3(size.y + 0.7, 1.8, size.x + 0.7), Vector3(0, 3.5, 0), roof, Vector3(0, PI * 0.5, 0))
	PropFactory.box(cot, Vector3(0.95, 1.8, 0.12), Vector3(0, 0.9, -size.y * 0.5 - 0.04), Color("5a3b22"))
	PropFactory.box(cot, Vector3(0.08, 0.08, 0.06), Vector3(0.3, 0.95, -size.y * 0.5 - 0.12), Color("c9a34a"))
	for wx in [-1.6, 1.6]:
		PropFactory.box(cot, Vector3(0.8, 0.7, 0.1), Vector3(wx, 1.5, -size.y * 0.5 - 0.02), Color("3e5a6e"))
		PropFactory.box(cot, Vector3(0.95, 0.1, 0.16), Vector3(wx, 1.12, -size.y * 0.5 - 0.05), timber)
	for wz in [-0.8, 0.9]:
		for sx in [-1.0, 1.0]:
			PropFactory.box(cot, Vector3(0.1, 0.7, 0.75), Vector3(sx * (size.x * 0.5 + 0.02), 1.5, wz), Color("3e5a6e"))
	var chimney := Vector3(size.x * 0.28, 3.8, size.y * 0.25)
	PropFactory.box(cot, Vector3(0.6, 1.8, 0.6), chimney, Color("7f7b73"))
	chimney_tops.append(cot.position + Basis(Vector3.UP, yaw) * (chimney + Vector3(0, 0.95, 0)))
	var body := PropFactory.solid(cot, "Body", Vector3.ZERO, Layers.OBSTACLES | Layers.CAMERA_BLOCKERS)
	PropFactory.box_shape(body, Vector3(size.x + 0.2, 4.4, size.y + 0.2), Vector3(0, 2.2, 0))
	_reserve(c, 4.2)
	_occlude(c, 3.8, 0.55)


func _build_stall(parent: Node, p: Vector2, cloth_a: Color, cloth_b: Color, goods: bool) -> void:
	var yaw := IslandLayout.yaw_towards(p, IslandLayout.PLAZA)
	var stall := _node_at(parent, "MarketStall", p, yaw)
	var wood := Color("7d5634")
	PropFactory.box(stall, Vector3(2.4, 0.95, 0.8), Vector3(0, 0.475, 0), Color("9a7448"))
	PropFactory.box(stall, Vector3(2.5, 0.08, 0.9), Vector3(0, 0.98, 0), wood)
	for sx in [-1.15, 1.15]:
		for sz in [-0.4, 0.95]:
			PropFactory.box(stall, Vector3(0.1, 2.5, 0.1), Vector3(sx, 1.25, sz), wood)
	for k in 5:
		var col := cloth_a if k % 2 == 0 else cloth_b
		PropFactory.box(stall, Vector3(0.52, 0.06, 1.9), Vector3(-1.04 + k * 0.52, 2.55, 0.28), col, Vector3(-0.18, 0, 0))
	if goods:
		for k in 4:
			PropFactory.sphere(stall, 0.12, Vector3(-0.8 + k * 0.22, 1.1, -0.1), Color("c84a32"))
		PropFactory.box(stall, Vector3(0.5, 0.25, 0.35), Vector3(0.6, 1.14, 0.0), Color("a88052"))
		PropFactory.cylinder(stall, 0.08, 0.08, 0.5, Vector3(0.2, 1.06, 0.05), Color("8a6440"), 6, Vector3(0, 0, PI * 0.5))
	else:
		for k in 3:
			PropFactory.box(stall, Vector3(0.3, 0.2, 0.3), Vector3(-0.6 + k * 0.45, 1.12, 0), Color("d8b45a").darkened(k * 0.1))
	var body := PropFactory.solid(stall, "Body", Vector3.ZERO)
	PropFactory.box_shape(body, Vector3(2.6, 1.2, 1.0), Vector3(0, 0.6, 0))
	_reserve(p, 2.2)


func _build_lamp(parent: Node, p: Vector2) -> void:
	var lamp := PropFactory.solid(parent, "Lamp", ground_point(p))
	PropFactory.cylinder_shape(lamp, 0.18, 3.0, Vector3(0, 1.5, 0))
	PropFactory.cylinder(lamp, 0.07, 0.09, 2.6, Vector3(0, 1.3, 0), Color("3a3a3a"), 6)
	PropFactory.prism(lamp, Vector3(0.45, 0.25, 0.45), Vector3(0, 3.07, 0), Color("3a3a3a"))
	lamp_positions.append(lamp.position + Vector3(0, 2.75, 0))
	# The glowing lantern stays out of the batches (emissive, catches the bloom).
	var glass := MeshInstance3D.new()
	glass.mesh = PropFactory.box_mesh(Vector3(0.32, 0.4, 0.32))
	glass.material_override = _lantern_material()
	glass.position = lamp.position + Vector3(0, 2.75, 0)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lights.add_child(glass)
	lantern_meshes.append(glass)
	_reserve(p, 0.8)


static var _lantern_mat: StandardMaterial3D


static func _lantern_material() -> StandardMaterial3D:
	if _lantern_mat == null:
		_lantern_mat = StandardMaterial3D.new()
		_lantern_mat.albedo_color = Color("ffd27a")
		_lantern_mat.emission_enabled = true
		_lantern_mat.emission = Color("ffc35a")
		_lantern_mat.emission_energy_multiplier = 1.6
	return _lantern_mat


func _build_garden(parent: Node) -> void:
	var g := _node_at(parent, "Garden", IslandLayout.GARDEN)
	var half := IslandLayout.GARDEN_SIZE * 0.5
	var wood := Color("8a6a45")
	var body := PropFactory.solid(g, "Fence", Vector3.ZERO)
	for side in 4:
		var horizontal := side < 2
		var sgn := -1.0 if side % 2 == 0 else 1.0
		var length := half.x * 2.0 if horizontal else half.y * 2.0
		var off := Vector3(0, 0, sgn * half.y) if horizontal else Vector3(sgn * half.x, 0, 0)
		var size := Vector3(length, 1.1, 0.15) if horizontal else Vector3(0.15, 1.1, length)
		PropFactory.box_shape(body, size, off + Vector3(0, 0.55, 0))
		var steps := int(length)
		for k in steps + 1:
			var t := -length * 0.5 + k * length / steps
			var pp := off + (Vector3(t, 0.45, 0) if horizontal else Vector3(0, 0.45, t))
			PropFactory.box(g, Vector3(0.1, 0.9, 0.1), pp, wood)
		PropFactory.box(g, Vector3(size.x, 0.06, size.z), off + Vector3(0, 0.7, 0), wood)
		PropFactory.box(g, Vector3(size.x, 0.06, size.z), off + Vector3(0, 0.35, 0), wood)
	for row in 3:
		var z := -1.1 + row * 1.1
		PropFactory.box(g, Vector3(4.2, 0.1, 0.6), Vector3(0, 0.03, z), Color("6e4f33"))
		for k in 6:
			var x := -1.8 + k * 0.72
			if row == 1:
				PropFactory.sphere(g, 0.2, Vector3(x, 0.2, z), Color("5f9a3a"))
			elif row == 0:
				PropFactory.cone(g, 0.12, 0.35, Vector3(x, 0.25, z), Color("4f8a35"))
				PropFactory.sphere(g, 0.07, Vector3(x, 0.07, z), Color("d87a2a"))
			else:
				PropFactory.sphere(g, 0.16, Vector3(x, 0.16, z), Color("7fb04a"), Vector3(1, 0.7, 1))
	_reserve(IslandLayout.GARDEN, 3.6)
	_occlude(IslandLayout.GARDEN, 2.8, 0.15)


func _build_courtyard() -> void:
	var court := Node3D.new()
	court.name = "Courtyard"
	_props.add_child(court)
	var lo := IslandLayout.COURTYARD_MIN
	var hi := IslandLayout.COURTYARD_MAX
	var wood := Color("7a5a3a")
	var fence := PropFactory.solid(court, "Fence", Vector3.ZERO)
	var gap_lo := IslandLayout.COURTYARD_ENTRANCE.y - IslandLayout.COURTYARD_GAP * 0.5
	var gap_hi := IslandLayout.COURTYARD_ENTRANCE.y + IslandLayout.COURTYARD_GAP * 0.5
	var runs := [
		[Vector2(lo.x, lo.y), Vector2(hi.x, lo.y)],
		[Vector2(lo.x, hi.y), Vector2(hi.x, hi.y)],
		[Vector2(hi.x, lo.y), Vector2(hi.x, hi.y)],
		[Vector2(lo.x, lo.y), Vector2(lo.x, gap_lo)],
		[Vector2(lo.x, gap_hi), Vector2(lo.x, hi.y)],
	]
	for run in runs:
		_fence_run(court, fence, run[0], run[1], wood)
	for gp in [Vector2(lo.x, gap_lo), Vector2(lo.x, gap_hi)]:
		var y := terrain.height_at(gp.x, gp.y)
		PropFactory.box(court, Vector3(0.3, 1.8, 0.3), Vector3(gp.x, y + 0.9, gp.y), Color("5e4229"))
		PropFactory.sphere(court, 0.18, Vector3(gp.x, y + 1.9, gp.y), Color("5e4229"))
	for d in IslandLayout.DUMMIES:
		var dummy := TrainingDummy.new()
		dummy.name = "TrainingDummy"
		dummy.position = ground_point(d)
		dummy.rotation.y = PI * 0.5  # faces west, towards the entrance
		_props.add_child(dummy)
		dummies.append(dummy)
		_keep.append(dummy)
		_occlude(d, 0.8, 0.2)
	var rack := _node_at(court, "WeaponRack", IslandLayout.WEAPON_RACK, PI * 0.5)
	PropFactory.box(rack, Vector3(2.0, 0.1, 0.1), Vector3(0, 1.3, 0), wood)
	PropFactory.box(rack, Vector3(2.0, 0.1, 0.1), Vector3(0, 0.45, 0), wood)
	for sx in [-0.95, 0.95]:
		PropFactory.box(rack, Vector3(0.12, 1.5, 0.4), Vector3(sx, 0.75, 0), wood)
	for k in 4:
		var x := -0.6 + k * 0.4
		PropFactory.box(rack, Vector3(0.06, 1.1, 0.02), Vector3(x, 0.95, 0.06), Color("b9c0c6"))
		PropFactory.box(rack, Vector3(0.22, 0.05, 0.06), Vector3(x, 0.42, 0.06), Color("6b4a2b"))
	var rb := PropFactory.solid(rack, "Body", Vector3.ZERO)
	PropFactory.box_shape(rb, Vector3(2.2, 1.6, 0.6), Vector3(0, 0.8, 0))
	_reserve(Vector2((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5), 10.5)


func _fence_run(parent: Node, body: StaticBody3D, a: Vector2, b: Vector2, wood: Color) -> void:
	var length := a.distance_to(b)
	var mid := (a + b) * 0.5
	var yaw := atan2(b.x - a.x, b.y - a.y)
	var base := terrain.height_at(mid.x, mid.y)
	PropFactory.box_shape(body, Vector3(0.2, 1.2, length), Vector3(mid.x, base + 0.6, mid.y), yaw)
	var steps := maxi(int(length / 1.6), 1)
	for k in steps + 1:
		var p := a.lerp(b, float(k) / steps)
		var y := terrain.height_at(p.x, p.y)
		PropFactory.box(parent, Vector3(0.14, 1.1, 0.14), Vector3(p.x, y + 0.5, p.y), wood)
	for h in [0.4, 0.85]:
		PropFactory.box(parent, Vector3(0.07, 0.09, length), Vector3(mid.x, base + h, mid.y), wood, Vector3(0, yaw, 0))


func _build_forest() -> void:
	var forest := Node3D.new()
	forest.name = "Forest"
	_props.add_child(forest)
	_reserve(IslandLayout.FOREST, IslandLayout.FOREST_RADIUS + 0.5)
	for p in IslandLayout.CHOPPABLE_TREES:
		_reserve(p, 1.2)
		var tree := ChoppableTree.new("normal")
		tree.name = "ChoppableTree"
		tree.position = ground_point(p)
		tree.rotation.y = p.x * 1.7
		_props.add_child(tree)
		choppable_trees.append(tree)
		_keep.append(tree)
		_occlude(p, 2.0, 0.4)
	# A ring of woodland around the clearing.
	var placed := 0
	var attempts := 0
	while placed < 46 and attempts < 600:
		attempts += 1
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(IslandLayout.FOREST_RADIUS + 1.8, 17.0)
		var p: Vector2 = IslandLayout.FOREST + Vector2(cos(a), sin(a)) * r
		if not _can_place(p, 1.6):
			continue
		_build_tree(forest, p, _rng.randf() < 0.55)
		placed += 1
	# Stumps and a log pile at the clearing's edge (stumps have tall collision so they stay obstacles).
	for s in [Vector2(-29.6, -10.6), Vector2(-25.8, -17.8), Vector2(-18.9, -14.8)]:
		var stump := PropFactory.solid(forest, "Stump", ground_point(s))
		PropFactory.cylinder_shape(stump, 0.45, 1.0, Vector3(0, 0.5, 0))
		PropFactory.cylinder(stump, 0.32, 0.4, 0.45, Vector3(0, 0.22, 0), Color("6b4a2b"), 7)
		PropFactory.cylinder(stump, 0.3, 0.3, 0.02, Vector3(0, 0.455, 0), Color("c9a774"), 7)
		_reserve(s, 1.0)
	var pile := _node_at(forest, "LogPile", Vector2(-29.0, -15.2), 0.6)
	for k in 5:
		var row := 0 if k < 3 else 1
		var x := (k - 1) * 0.42 if row == 0 else (k - 3.5) * 0.42
		var log := PropFactory.cylinder(pile, 0.2, 0.2, 1.8, Vector3(x, 0.2 + row * 0.36, 0), Color("7d5634"), 7, Vector3(PI * 0.5, 0, 0))
		log.name = "Log"
	var pb := PropFactory.solid(pile, "Body", Vector3.ZERO)
	PropFactory.box_shape(pb, Vector3(1.6, 1.0, 2.0), Vector3(0, 0.5, 0))
	_reserve(Vector2(-29.0, -15.2), 1.6)


func _build_tree(parent: Node, p: Vector2, pine: bool, scale: float = -1.0) -> Node3D:
	var s := scale if scale > 0.0 else _rng.randf_range(0.85, 1.25)
	var tree := _node_at(parent, "Tree", p, _rng.randf() * TAU)
	var trunk := Color("6b4a2b")
	if pine:
		PropFactory.cylinder(tree, 0.16 * s, 0.24 * s, 1.6 * s, Vector3(0, 0.8 * s, 0), trunk, 6)
		var greens := [Color("2f5e2e"), Color("3a6b33"), Color("447a3a")]
		for k in 3:
			var cone := PropFactory.cone(tree, (1.5 - k * 0.38) * s, 1.6 * s, Vector3(0, (1.7 + k * 0.85) * s, 0), greens[k], 7)
			PropFactory.swaying(cone, 0.3 + k * 0.15, true)
	else:
		PropFactory.cylinder(tree, 0.18 * s, 0.26 * s, 2.2 * s, Vector3(0, 1.1 * s, 0), trunk, 6)
		var g := Color("4f8a3a").lerp(Color("6a9a3e"), _rng.randf())
		var c1 := PropFactory.sphere(tree, 1.25 * s, Vector3(0, 2.7 * s, 0), g, Vector3(1, 0.85, 1))
		var c2 := PropFactory.sphere(tree, 0.85 * s, Vector3(0.55 * s, 3.25 * s, 0.25 * s), g.lightened(0.08))
		PropFactory.swaying(c1, 0.35)
		PropFactory.swaying(c2, 0.5)
	var body := PropFactory.solid(tree, "Trunk", Vector3.ZERO)
	PropFactory.cylinder_shape(body, 0.35 * s, 2.2, Vector3(0, 1.1, 0))
	_reserve(p, 1.6 * s)
	_occlude(p, 2.0 * s, 0.4)
	return tree


func _build_pond() -> void:
	var pond_node := Node3D.new()
	pond_node.name = "Pond"
	_props.add_child(pond_node)
	_reserve(IslandLayout.POND, 9.5)
	for k in 9:
		var a := TAU * k / 9.0 + 0.3
		if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.75:
			continue  # keep the south bank (towards the village) open for Tobin and fishing
		var r := 6.8 + (k % 3) * 0.35
		var p: Vector2 = IslandLayout.POND + Vector2(cos(a), sin(a)) * r
		_build_rock(pond_node, p, 0.45 + (k % 3) * 0.15, true)
	for k in 16:
		var a := TAU * k / 16.0
		if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.6:
			continue
		var p: Vector2 = IslandLayout.POND + Vector2(cos(a), sin(a)) * (6.1 + (k % 2) * 0.3)
		var clump := _node_at(_decor, "Reeds", p)
		for q in 4:
			var off := Vector3(cos(q * 1.7) * 0.18, 0, sin(q * 1.7) * 0.18)
			var reed := PropFactory.cylinder(clump, 0.0, 0.04, 1.1 + q * 0.12, off + Vector3(0, 0.55, 0), Color("6f8f3a"), 4)
			PropFactory.swaying(reed, 0.7, true)


func _build_rock(parent: Node, p: Vector2, size: float, solid: bool) -> void:
	var rock := _node_at(parent, "Rock", p, _rng.randf() * TAU, -0.1)
	var grey := Color("8b8a84").lerp(Color("74726b"), _rng.randf())
	PropFactory.sphere(rock, size, Vector3(0, size * 0.45, 0), grey, Vector3(1.2, 0.75, 1.0), 6, 3)
	PropFactory.sphere(rock, size * 0.6, Vector3(size * 0.6, size * 0.3, size * 0.2), grey.darkened(0.08), Vector3(1, 0.7, 1), 5, 3)
	if solid:
		var body := PropFactory.solid(rock, "Body", Vector3.ZERO)
		PropFactory.cylinder_shape(body, size * 1.1, maxf(1.0, size * 1.6), Vector3(0, 0.5, 0))
	_reserve(p, size * 1.4 + 0.3)


func _build_gate() -> void:
	var gate := _node_at(_props, "ExitGate", IslandLayout.GATE)
	var stone := Color("8d8a82")
	var dark := Color("6f6c66")
	for sx in [-2.6, 2.6]:
		PropFactory.box(gate, Vector3(2.3, 6.0, 2.3), Vector3(sx, 3.0, 0), stone)
		PropFactory.box(gate, Vector3(2.6, 0.5, 2.6), Vector3(sx, 6.2, 0), dark)
		for cx in [-0.8, 0.0, 0.8]:
			PropFactory.box(gate, Vector3(0.5, 0.5, 2.6), Vector3(sx + cx, 6.7, 0), stone)
		PropFactory.prism(gate, Vector3(2.4, 1.6, 2.4), Vector3(sx, 7.6, 0), Color("6a4a3a"))
	PropFactory.box(gate, Vector3(3.0, 1.4, 1.8), Vector3(0, 5.0, 0), stone)
	PropFactory.box(gate, Vector3(2.9, 3.8, 0.3), Vector3(0, 1.9, 0), Color("5e4229"))
	for k in 5:
		PropFactory.box(gate, Vector3(0.06, 3.8, 0.34), Vector3(-1.2 + k * 0.6, 1.9, 0), Color("4a3420"))
	PropFactory.box(gate, Vector3(2.9, 0.15, 0.36), Vector3(0, 2.6, 0), Color("4a4a48"))
	PropFactory.box(gate, Vector3(2.9, 0.15, 0.36), Vector3(0, 1.0, 0), Color("4a4a48"))
	var body := PropFactory.solid(gate, "Body", Vector3.ZERO, Layers.OBSTACLES | Layers.CAMERA_BLOCKERS)
	PropFactory.box_shape(body, Vector3(7.5, 6.0, 2.4), Vector3(0, 3.0, 0))
	# Walls either side, following the ground.
	for side in [-1.0, 1.0]:
		var x0: float = side * 3.75
		var x1: float = side * IslandLayout.GATE_WALL_HALF
		var steps := 4
		for k in steps:
			var xa: float = lerpf(x0, x1, float(k) / steps)
			var xb: float = lerpf(x0, x1, float(k + 1) / steps)
			var xm := (xa + xb) * 0.5
			var y := terrain.height_at(xm, IslandLayout.GATE.y) - ground_height(IslandLayout.GATE.x, IslandLayout.GATE.y)
			PropFactory.box(gate, Vector3(absf(xb - xa) + 0.05, 3.6, 1.0), Vector3(xm, y + 1.5, 0), stone)
			PropFactory.box(gate, Vector3(0.45, 0.45, 1.1), Vector3(xm - 0.4, y + 3.5, 0), dark)
			PropFactory.box(gate, Vector3(0.45, 0.45, 1.1), Vector3(xm + 0.4, y + 3.5, 0), dark)
		var wb := PropFactory.solid(gate, "Wall", Vector3.ZERO, Layers.OBSTACLES | Layers.CAMERA_BLOCKERS)
		PropFactory.box_shape(wb, Vector3(absf(x1 - x0), 5.0, 1.2), Vector3((x0 + x1) * 0.5, 1.5, 0))
	# Bridge towards the mainland (scenery: the gate stays shut and the shoreline boundary holds).
	var bridge := Node3D.new()
	bridge.name = "Bridge"
	_props.add_child(bridge)
	var deck_y := 0.9
	var z0 := IslandLayout.GATE.y - 1.6
	var z1 := -70.0
	var cz := (z0 + z1) * 0.5
	PropFactory.box(bridge, Vector3(3.0, 0.2, absf(z1 - z0)), Vector3(0, deck_y, cz), Color("8a6440"))
	for side in [-1.0, 1.0]:
		PropFactory.box(bridge, Vector3(0.1, 0.1, absf(z1 - z0)), Vector3(side * 1.45, deck_y + 0.75, cz), Color("6b4a2b"))
	var z := z0 - 2.0
	while z > z1:
		for side in [-1.0, 1.0]:
			PropFactory.cylinder(bridge, 0.14, 0.16, 3.6, Vector3(side * 1.5, deck_y - 1.2, z), Color("5e4229"), 6)
			if terrain.height_at(side * 1.5, z) < 0.0:
				_water_posts.append(Vector2(side * 1.5, z))
		z -= 4.0
	_reserve(IslandLayout.GATE, 6.0)
	for x in range(-10, 12, 3):
		_reserve(Vector2(x, IslandLayout.GATE.y), 2.0)


## Free placement test for scattered props: on land, off paths and out of every reserved area.
func _can_place(p: Vector2, radius: float) -> bool:
	if not terrain.is_land(p.x, p.y):
		return false
	var t := terrain.tile_at(p.x, p.y)
	if t == IslandTerrain.Tile.SAND or t == IslandTerrain.Tile.PATH or t == IslandTerrain.Tile.PLAZA \
			or t == IslandTerrain.Tile.COURTYARD or t == IslandTerrain.Tile.MUD:
		return false
	if IslandLayout.distance_to_paths(p) < IslandLayout.PATH_HALF_WIDTH + radius + 0.6:
		return false
	if IslandLayout.in_courtyard(p, radius + 1.0) or IslandLayout.in_plaza(p, radius + 1.0):
		return false
	if p.distance_to(IslandLayout.POND) < 9.5 + radius:
		return false
	for r in _reserved:
		if p.distance_to(Vector2(r.x, r.y)) < r.z + radius:
			return false
	# Stay clear of the shoreline boundary.
	if sqrt(p.x * p.x + p.y * p.y) > IslandLayout.coast_radius(atan2(p.y, p.x)) - 7.0:
		return false
	return true


func _build_scatter() -> void:
	var scatter := Node3D.new()
	scatter.name = "Scatter"
	_props.add_child(scatter)
	var trees := 0
	var attempts := 0
	while trees < 58 and attempts < 2500:
		attempts += 1
		var p := Vector2(_rng.randf_range(-44, 44), _rng.randf_range(-44, 44))
		if not _can_place(p, 1.4):
			continue
		_build_tree(scatter, p, _rng.randf() < 0.4)
		trees += 1
	var rocks := 0
	attempts = 0
	while rocks < 16 and attempts < 800:
		attempts += 1
		var p := Vector2(_rng.randf_range(-44, 44), _rng.randf_range(-44, 44))
		if not _can_place(p, 0.9):
			continue
		_build_rock(scatter, p, _rng.randf_range(0.4, 0.8), true)
		rocks += 1
	var bushes := 0
	attempts = 0
	while bushes < 30 and attempts < 1200:
		attempts += 1
		var p := Vector2(_rng.randf_range(-44, 44), _rng.randf_range(-44, 44))
		if not _can_place(p, 0.8):
			continue
		var bush := _node_at(scatter, "Bush", p)
		var g := Color("4b8236").lerp(Color("5f9440"), _rng.randf())
		var b1 := PropFactory.sphere(bush, 0.6, Vector3(0, 0.45, 0), g, Vector3(1.2, 0.8, 1.0))
		var b2 := PropFactory.sphere(bush, 0.42, Vector3(0.45, 0.35, 0.2), g.lightened(0.07))
		PropFactory.swaying(b1, 0.25)
		PropFactory.swaying(b2, 0.3)
		var body := PropFactory.solid(bush, "Body", Vector3.ZERO)
		PropFactory.cylinder_shape(body, 0.7, 1.1, Vector3(0, 0.55, 0))
		_reserve(p, 1.0)
		bushes += 1


var _grass_count := 0


## Small, collision-free decoration. Uses `_cover_rng` so adding cover never moves other props.
func _build_ground_cover() -> void:
	var flowers := [Color("e8d34a"), Color("e86a6a"), Color("f0f0f0"), Color("b07ad8"), Color("6aa8e8")]
	for k in 260:
		var p := Vector2(_cover_rng.randf_range(-45, 45), _cover_rng.randf_range(-45, 45))
		var kind := _cover_rng.randi() % 3
		if not terrain.is_land(p.x, p.y):
			continue
		var t := terrain.tile_at(p.x, p.y)
		if t != IslandTerrain.Tile.GRASS and t != IslandTerrain.Tile.FOREST:
			continue
		if IslandLayout.distance_to_paths(p) < 1.5 or IslandLayout.in_courtyard(p, 0.5):
			continue
		var tuft := _node_at(_decor, "Cover", p)
		if kind == 0:
			var col: Color = flowers[_cover_rng.randi() % flowers.size()]
			for q in 3:
				var off := Vector3(cos(q * 2.1) * 0.22, 0, sin(q * 2.1) * 0.22)
				var stem := PropFactory.cylinder(tuft, 0.015, 0.015, 0.3, off + Vector3(0, 0.15, 0), Color("5f8f3a"), 3)
				PropFactory.swaying(stem, 0.8, true)
				var bloom := PropFactory.sphere(tuft, 0.07, off + Vector3(0, 0.32, 0), col, Vector3.ONE, 5, 2)
				PropFactory.swaying(bloom, 0.9)
		else:
			# 40% of the grass is core; the rest only shows on Medium and High.
			_grass_count += 1
			tuft.reparent(_grass_core if _grass_count % 5 < 2 else _grass_extra, false)
			var g := Color("6fa344").lerp(Color("88b850"), _cover_rng.randf())
			for q in 4:
				var off := Vector3(cos(q * 1.6) * 0.12, 0, sin(q * 1.6) * 0.12)
				var blade := PropFactory.cylinder(tuft, 0.0, 0.05, 0.4, off + Vector3(0, 0.2, 0), g, 3)
				PropFactory.swaying(blade, 1.0, true)


## Milestone 5 ground cover, drawn after the original cover from `_cover_rng` so nothing earlier
## moves: ferns and mushrooms in the forest, tall grass clumps, more flower types, lily pads and
## cattails on the pond, border stones along the paths, wood piles and a bucket. All collision-free.
func _build_extra_cover() -> void:
	cover_counts = {"fern": 0, "mushroom": 0, "tall_grass": 0, "flower": 0, "lily_pad": 0, "cattail": 0,
			"border_stone": 0, "wood_pile": 0, "bucket": 0}
	for k in 520:
		var p := Vector2(_cover_rng.randf_range(-45, 45), _cover_rng.randf_range(-45, 45))
		var roll := _cover_rng.randf()
		if not terrain.is_land(p.x, p.y) or IslandLayout.in_courtyard(p, 0.8) or IslandLayout.in_plaza(p, 0.5):
			continue
		var t := terrain.tile_at(p.x, p.y)
		if t != IslandTerrain.Tile.GRASS and t != IslandTerrain.Tile.FOREST:
			continue
		if IslandLayout.distance_to_paths(p) < 1.6 or _near_reserved_solid(p):
			continue
		if t == IslandTerrain.Tile.FOREST and roll < 0.45:
			_fern(p)
		elif t == IslandTerrain.Tile.FOREST and roll < 0.7:
			_mushrooms(p)
		elif roll < 0.75:
			_tall_grass(p)
		else:
			_flower_clump(p, roll)
	# Lily pads and cattails on the pond (cattails stay off the south fishing bank).
	for k in 14:
		var a := _cover_rng.randf() * TAU
		var r := _cover_rng.randf_range(2.6, 5.2)
		var lp := IslandLayout.POND + Vector2(cos(a), sin(a)) * r
		var pad := _node_at(_decor, "LilyPad", lp)
		pad.position.y = IslandLayout.POND_LEVEL + 0.012
		PropFactory.cylinder(pad, 0.32, 0.32, 0.02, Vector3.ZERO, Color("4f8f3a"), 7)
		if k % 4 == 0:
			PropFactory.sphere(pad, 0.07, Vector3(0.08, 0.05, 0), Color("f2c9e0"), Vector3(1, 0.6, 1), 5, 2)
		cover_counts.lily_pad += 1
	for k in 10:
		var a := TAU * (k + 0.5) / 10.0
		if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.8:
			continue
		var cp := IslandLayout.POND + Vector2(cos(a), sin(a)) * 6.0
		var clump := _node_at(_decor, "Cattails", cp)
		for q in 3:
			var off := Vector3(cos(q * 2.3) * 0.15, 0, sin(q * 2.3) * 0.15)
			PropFactory.swaying(PropFactory.cylinder(clump, 0.015, 0.025, 1.4, off + Vector3(0, 0.7, 0), Color("6f8f3a"), 4), 0.6, true)
			PropFactory.swaying(PropFactory.cylinder(clump, 0.045, 0.045, 0.22, off + Vector3(0, 1.32, 0), Color("6b4326"), 5), 0.6)
		cover_counts.cattail += 1
	# Border stones along the main paths.
	for path in IslandLayout.PATHS:
		for i in path.size() - 1:
			var a: Vector2 = path[i]
			var b: Vector2 = path[i + 1]
			var length := a.distance_to(b)
			var dir := (b - a) / length
			var side := Vector2(-dir.y, dir.x)
			var d := 1.0
			while d < length - 0.5:
				for sgn in [-1.0, 1.0]:
					var sp: Vector2 = a + dir * d + side * sgn * (IslandLayout.PATH_HALF_WIDTH + 0.25)
					if IslandLayout.in_plaza(sp, 0.6) or IslandLayout.in_courtyard(sp, 0.6) or not terrain.is_land(sp.x, sp.y) \
							or IslandLayout.on_dock(sp, 1.0) or _near_reserved_solid(sp):
						continue
					var stone := _node_at(_decor, "BorderStone", sp, _cover_rng.randf() * TAU, -0.05)
					var sz := _cover_rng.randf_range(0.12, 0.2)
					PropFactory.sphere(stone, sz, Vector3(0, sz * 0.4, 0), Color("9a978f").lerp(Color("7f7c75"), _cover_rng.randf()), Vector3(1.3, 0.6, 1.0), 5, 3)
					cover_counts.border_stone += 1
				d += 2.2
	# Wood piles beside two cottages and a bucket by the well.
	for c in [IslandLayout.COTTAGES[0], IslandLayout.COTTAGES[2]]:
		var yaw := IslandLayout.yaw_towards(c, IslandLayout.PLAZA)
		var wp: Vector2 = c + Vector2(cos(yaw), -sin(yaw)) * 3.0
		var pile := _node_at(_decor, "WoodPile", wp, yaw)
		for q in 4:
			PropFactory.cylinder(pile, 0.1, 0.1, 0.9, Vector3((q % 2) * 0.22 - 0.11, 0.1 + (q / 2) * 0.19, 0), Color("8a6440"), 6, Vector3(PI * 0.5, 0, 0))
		cover_counts.wood_pile += 1
	var bucket := _node_at(_decor, "Bucket", IslandLayout.WELL + Vector2(1.35, 0.4))
	PropFactory.cylinder(bucket, 0.2, 0.16, 0.3, Vector3(0, 0.15, 0), Color("7d5634"), 8)
	PropFactory.cylinder(bucket, 0.205, 0.205, 0.03, Vector3(0, 0.24, 0), Color("4a4a48"), 8)
	PropFactory.cylinder(bucket, 0.17, 0.17, 0.01, Vector3(0, 0.27, 0), Color("3f6e8e"), 8)
	cover_counts.bucket += 1


func _near_reserved_solid(p: Vector2) -> bool:
	for r in _reserved:
		if p.distance_to(Vector2(r.x, r.y)) < r.z * 0.8:
			return true
	return false


func _fern(p: Vector2) -> void:
	var fern := _node_at(_decor, "Fern", p, _cover_rng.randf() * TAU)
	var g := Color("3f7a32").lerp(Color("5a8f3a"), _cover_rng.randf())
	for q in 5:
		var a := TAU * q / 5.0
		var frond := PropFactory.box(fern, Vector3(0.12, 0.02, 0.55), Vector3(cos(a) * 0.22, 0.18, sin(a) * 0.22), g, Vector3(0.5, -a + PI * 0.5, 0))
		PropFactory.swaying(frond, 0.6)
	cover_counts.fern += 1


func _mushrooms(p: Vector2) -> void:
	var m := _node_at(_decor, "Mushrooms", p)
	for q in 3:
		var off := Vector3(cos(q * 2.2) * 0.14, 0, sin(q * 2.2) * 0.14)
		var h := 0.08 + q * 0.03
		PropFactory.cylinder(m, 0.025, 0.03, h, off + Vector3(0, h * 0.5, 0), Color("efe6cf"), 5)
		PropFactory.sphere(m, 0.06 + q * 0.01, off + Vector3(0, h, 0), Color("c84a32") if q != 1 else Color("b07a4a"), Vector3(1, 0.55, 1), 6, 3)
	cover_counts.mushroom += 1


func _tall_grass(p: Vector2) -> void:
	_grass_count += 1
	var host := _grass_core if _grass_count % 5 < 2 else _grass_extra
	var clump := _node_at(host, "TallGrass", p)
	var g := Color("7aa84a").lerp(Color("9dbf5a"), _cover_rng.randf())
	for q in 6:
		var off := Vector3(cos(q * 1.05) * 0.16, 0, sin(q * 1.05) * 0.16)
		var blade := PropFactory.cylinder(clump, 0.0, 0.05, 0.75, off + Vector3(0, 0.37, 0), g, 3)
		blade.rotation = Vector3(off.z * 1.5, 0, -off.x * 1.5)
		PropFactory.swaying(blade, 1.0, true)
	cover_counts.tall_grass += 1


func _flower_clump(p: Vector2, roll: float) -> void:
	var f := _node_at(_decor, "Flowers", p)
	var kinds := [[Color("f4f1ea"), Color("f0c43a")], [Color("e86a9a"), Color("f7d0e0")], [Color("6a8ae8"), Color("f0f0f0")]]
	var kind: Array = kinds[int(roll * 100.0) % kinds.size()]
	for q in 4:
		var off := Vector3(cos(q * 1.6) * 0.18, 0, sin(q * 1.6) * 0.18)
		PropFactory.swaying(PropFactory.cylinder(f, 0.012, 0.012, 0.34, off + Vector3(0, 0.17, 0), Color("5f8f3a"), 3), 0.8, true)
		PropFactory.swaying(PropFactory.sphere(f, 0.065, off + Vector3(0, 0.36, 0), kind[0], Vector3(1, 0.5, 1), 6, 2), 0.9)
		PropFactory.swaying(PropFactory.sphere(f, 0.03, off + Vector3(0, 0.385, 0), kind[1], Vector3.ONE, 4, 2), 0.9)
	cover_counts.flower += 1


func _build_mainland() -> void:
	# A distant, unreachable landmass to the north, built as one vertex-coloured mesh.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 40
	var nz := 12
	var x0 := -260.0
	var x1 := 260.0
	var z0 := -128.0
	var z1 := -260.0
	var n := FastNoiseLite.new()
	n.seed = IslandLayout.NOISE_SEED + 1
	n.frequency = 0.012
	var hgt := func(x: float, z: float) -> float:
		var t := clampf((z0 - z) / 30.0, 0.0, 1.0)
		return -1.5 + t * (6.0 + 18.0 * (n.get_noise_2d(x, z) * 0.5 + 0.5))
	for j in nz:
		for i in nx:
			var xa := lerpf(x0, x1, float(i) / nx)
			var xb := lerpf(x0, x1, float(i + 1) / nx)
			var za := lerpf(z0, z1, float(j) / nz)
			var zb := lerpf(z0, z1, float(j + 1) / nz)
			var a := Vector3(xa, hgt.call(xa, za), za)
			var b := Vector3(xb, hgt.call(xb, za), za)
			var c := Vector3(xb, hgt.call(xb, zb), zb)
			var d := Vector3(xa, hgt.call(xa, zb), zb)
			# One colour per quad, so the far beach reads as a clean strip.
			var avg: float = (a.y + b.y + c.y + d.y) / 4.0
			var col := Color("d9c48f") if j == 0 else (Color("5f8a45") if avg < 12.0 else Color("7d7f72"))
			for tri in [[a, c, b], [a, d, c]]:
				for v in tri:
					st.set_color(col)
					st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Mainland"
	mi.mesh = st.commit()
	mi.material_override = PropFactory.vertex_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# A tower on the far shore hints at the road beyond the gate.
	var far := Node3D.new()
	far.name = "MainlandProps"
	add_child(far)
	for k in 14:
		var x := -90.0 + k * 14.0 + sin(k * 3.1) * 4.0
		var z := -142.0 - absf(sin(k * 1.7)) * 20.0
		var y: float = hgt.call(x, z)
		PropFactory.cone(far, 3.0, 7.0, Vector3(x, y + 4.5, z), Color("2f5e2e"), 6)
		PropFactory.cylinder(far, 0.5, 0.6, 2.0, Vector3(x, y + 1.0, z), Color("6b4a2b"), 5)
	var ty: float = hgt.call(8.0, -140.0)
	PropFactory.box(far, Vector3(5, 14, 5), Vector3(8, ty + 7, -140), Color("8d8a82"))
	PropFactory.prism(far, Vector3(6, 4, 6), Vector3(8, ty + 16, -140), Color("8a4b33"))


# --- landmarks, terrain mesh, water --------------------------------------------------------------

func _build_landmarks() -> void:
	landmarks = {
		"dock": ground_point(IslandLayout.SPAWN),
		"move_marker": ground_point(IslandLayout.MOVE_MARKER),
		"village": ground_point(Vector2(1.6, 19.8)),
		"courtyard": ground_point(Vector2(24.5, 1.2)),
		"courtyard_entrance": ground_point(Vector2(15.8, IslandLayout.COURTYARD_ENTRANCE.y)),
		"forest_clearing": ground_point(IslandLayout.FOREST),
		"fishing_pond": ground_point(Vector2(22.6, -14.6)),
		"exit_gate": ground_point(IslandLayout.EXIT_GATE_POINT),
		"npc_instructor": ground_point(IslandLayout.INSTRUCTOR),
		"npc_merchant": ground_point(IslandLayout.MERCHANT),
		"npc_fisher": ground_point(IslandLayout.FISHER),
		"npc_wanderer": ground_point(IslandLayout.WANDERER_HOME),
		"training_dummy": ground_point(IslandLayout.DUMMIES[0]),
	}


func _build_terrain_mesh() -> void:
	# Fake ambient occlusion under trees and along buildings, baked into the tile colours.
	for k in _occluders.size():
		var o := _occluders[k]
		var s := _occluder_strength[k]
		var r := o.z
		for j in range(int(floor(o.y - r)) + IslandTerrain.HALF, int(ceil(o.y + r)) + IslandTerrain.HALF + 1):
			for i in range(int(floor(o.x - r)) + IslandTerrain.HALF, int(ceil(o.x + r)) + IslandTerrain.HALF + 1):
				if i < 0 or j < 0 or i >= IslandTerrain.SIZE or j >= IslandTerrain.SIZE:
					continue
				var d := Vector2(i - IslandTerrain.HALF + 0.5, j - IslandTerrain.HALF + 0.5).distance_to(Vector2(o.x, o.y))
				if d < r:
					var idx := j * IslandTerrain.SIZE + i
					terrain.occlusion[idx] = maxf(terrain.occlusion[idx], s * (1.0 - d / r))
	terrain_mesh = MeshInstance3D.new()
	terrain_mesh.name = "TerrainMesh"
	terrain_mesh.mesh = terrain.build_mesh()
	terrain_mesh.material_override = PropFactory.vertex_mat()
	terrain_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(terrain_mesh)


func _build_water() -> void:
	var sea_mat := ShaderMaterial.new()
	sea_mat.shader = WATER_SHADER
	sea_mat.set_shader_parameter("level", IslandLayout.SEA_LEVEL)
	sea = MeshInstance3D.new()
	sea.name = "Sea"
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	plane.subdivide_width = 60
	plane.subdivide_depth = 60
	sea.mesh = plane
	sea.material_override = sea_mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	var pond_mat := ShaderMaterial.new()
	pond_mat.shader = WATER_SHADER
	pond_mat.set_shader_parameter("level", IslandLayout.POND_LEVEL)
	pond_mat.set_shader_parameter("wave_height", 0.01)
	pond = MeshInstance3D.new()
	pond.name = "PondWater"
	var disc := PlaneMesh.new()
	disc.size = Vector2(16, 16)
	disc.subdivide_width = 8
	disc.subdivide_depth = 8
	pond.mesh = disc
	pond.material_override = pond_mat
	pond.position = Vector3(IslandLayout.POND.x, IslandLayout.POND_LEVEL, IslandLayout.POND.y)
	pond.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pond)


## Bakes signed water depth (metres below the still surface; negative over land) for the sea and the
## pond into textures the water shader samples, so no depth-buffer reads are needed.
func _bake_water_depth() -> void:
	var sea_rect := Rect2(-64, -64, 128, 128)
	sea_depth_image = _depth_image(sea_rect, 256, IslandLayout.SEA_LEVEL)
	_apply_depth(sea, sea_depth_image, sea_rect, 3.0)
	var pond_rect := Rect2(IslandLayout.POND.x - 8.0, IslandLayout.POND.y - 8.0, 16.0, 16.0)
	pond_depth_image = _depth_image(pond_rect, 64, IslandLayout.POND_LEVEL)
	_apply_depth(pond, pond_depth_image, pond_rect, 0.9)
	var posts := PackedVector4Array()
	for wp in _water_posts.slice(0, 24):
		posts.append(Vector4(wp.x, wp.y, 0, 0))
	var sea_mat: ShaderMaterial = sea.material_override
	sea_mat.set_shader_parameter("posts", posts)
	sea_mat.set_shader_parameter("post_count", posts.size())


func _depth_image(rect: Rect2, res: int, level: float) -> Image:
	var img := Image.create(res, res, false, Image.FORMAT_R8)
	for j in res:
		for i in res:
			var x := rect.position.x + (i + 0.5) / res * rect.size.x
			var z := rect.position.y + (j + 0.5) / res * rect.size.y
			var depth := level - terrain.height_at(x, z)
			img.set_pixel(i, j, Color(clampf((depth + 2.0) / 8.0, 0.0, 1.0), 0, 0))
	return img


## Decoded depth (metres) from a baked image at a world point (tests).
func baked_depth(img: Image, rect: Rect2, x: float, z: float) -> float:
	var i := clampi(int((x - rect.position.x) / rect.size.x * img.get_width()), 0, img.get_width() - 1)
	var j := clampi(int((z - rect.position.y) / rect.size.y * img.get_height()), 0, img.get_height() - 1)
	return img.get_pixel(i, j).r * 8.0 - 2.0


func _apply_depth(mi: MeshInstance3D, img: Image, rect: Rect2, max_depth: float) -> void:
	var mat: ShaderMaterial = mi.material_override
	mat.set_shader_parameter("depth_tex", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("has_depth", true)
	mat.set_shader_parameter("depth_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	mat.set_shader_parameter("max_depth", max_depth)


# --- batching and navigation ----------------------------------------------------------------------

## Replaces every static mesh using a shared PropFactory material with vertex-coloured chunks.
## Anything that moves, animates or toggles visibility is in `_keep` (boat, dummies, choppable trees).
func _merge_meshes() -> void:
	var batches := Node3D.new()
	batches.name = "Batches"
	add_child(batches)
	MeshMerger.merge(_props, _keep, 32.0, {"target": batches, "name": "Props"})
	decor_chunks = MeshMerger.merge(_decor, _keep, 16.0, {"target": batches, "name": "Decor",
			"cast_shadow": false, "visibility_end": SMALL_DECOR_FADE})
	var grass_mat := _grass_material()
	grass_core_chunks = MeshMerger.merge(_grass_core, [], 16.0, {"target": batches, "name": "GrassCore",
			"cast_shadow": false, "visibility_end": SMALL_DECOR_FADE, "material": grass_mat})
	grass_extra_chunks = MeshMerger.merge(_grass_extra, [], 16.0, {"target": batches, "name": "GrassExtra",
			"cast_shadow": false, "visibility_end": SMALL_DECOR_FADE, "material": grass_mat})
	decor_chunks.append_array(grass_core_chunks)
	decor_chunks.append_array(grass_extra_chunks)
	# The merged sources are now empty holders.
	for holder in [_decor, _grass_core, _grass_extra]:
		holder.queue_free()
	var far := get_node_or_null("MainlandProps")
	if far:
		MeshMerger.merge(far, [], 200.0, {"target": batches, "name": "Far", "cast_shadow": false})


## Clouds, gulls and chimney smoke: created after batching so they stay animated and independent.
func _build_ambient_life() -> void:
	ambient = AmbientLife.new()
	add_child(ambient)
	ambient.setup(self)


static var _grass_mat: ShaderMaterial


## Vertex-coloured material for grass chunks; flagged so grass keeps moving on the Low preset.
static func _grass_material() -> ShaderMaterial:
	if _grass_mat == null:
		_grass_mat = ShaderMaterial.new()
		_grass_mat.shader = PropFactory.SHADER
		_grass_mat.set_shader_parameter("use_vertex_color", true)
		_grass_mat.set_shader_parameter("is_grass", true)
	return _grass_mat


## Sets how far small decoration stays visible (graphics presets).
func set_decor_fade(distance: float) -> void:
	for c in decor_chunks:
		if is_instance_valid(c):
			c.visibility_range_end = distance


const DECOR_FADE := [45.0, 75.0, 100.0]


## Grass density and small-decor fade for a preset (Low 40% grass / 45 m, Medium 100% / 75 m,
## High 100% / 100 m). Called on generation and whenever the setting changes.
func apply_graphics_quality(level: int) -> void:
	graphics_quality = clampi(level, 0, 2)
	set_decor_fade(DECOR_FADE[graphics_quality])
	for c in grass_extra_chunks:
		if is_instance_valid(c):
			c.visible = graphics_quality > 0


func _on_setting(key: String, value: Variant) -> void:
	if key == "graphics_quality":
		apply_graphics_quality(value)


func _exit_tree() -> void:
	if SettingsManager.settings_changed.is_connected(_on_setting):
		SettingsManager.settings_changed.disconnect(_on_setting)


## Visible grass tufts as a fraction of all grass (for tests): 0.4 on Low, 1.0 otherwise.
func grass_density() -> float:
	var total := 0
	var shown := 0
	for c in grass_core_chunks + grass_extra_chunks:
		var n: int = (c as MeshInstance3D).mesh.get_faces().size()
		total += n
		if c.visible:
			shown += n
	return float(shown) / maxf(total, 1.0)


func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 40.0
	nm.region_min_size = 4.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Layers.WALKABLE_SOURCES
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.filter_baking_aabb = AABB(Vector3(-56, -2, -56), Vector3(112, 12, 116))
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, source, nav_region)
	NavigationServer3D.bake_from_source_geometry_data(nm, source)
	nav_region.navigation_mesh = nm


## Waits until the map has synchronised the baked region (the dock answers path queries).
func _wait_for_map_sync() -> void:
	var map := navigation_map()
	var probe: Vector3 = landmarks["dock"]
	for i in 120:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) == 0:
			continue
		if NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 1.0:
			return
	push_error("Navigation map did not synchronise")
