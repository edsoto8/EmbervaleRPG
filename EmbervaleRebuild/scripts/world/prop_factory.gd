class_name PropFactory
extends RefCounted
## Builds low-poly props from cached primitive meshes and cached flat-shaded materials.
##
## Every static prop should use `mat(color)`: TutorialIsland._merge_meshes() later bakes all meshes
## using these shared materials into vertex-coloured chunks (see MeshMerger).

const SHADER := preload("res://shaders/lowpoly.gdshader")

static var _mats := {}
static var _meshes := {}
static var _vertex_mat: ShaderMaterial
static var _character_vertex_mat: ShaderMaterial


## Shared material for a colour. `sway` is the wind weight (0 = rigid, 1 = leaf tips).
static func mat(color: Color, sway: float = 0.0) -> ShaderMaterial:
	var key := "%s|%.2f" % [color.to_html(false), sway]
	var m: ShaderMaterial = _mats.get(key)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("albedo", color)
		m.set_shader_parameter("sway", sway)
		m.set_meta("pf_color", color)
		m.set_meta("pf_sway", sway)
		_mats[key] = m
	return m


static func is_shared(m: Material) -> bool:
	return m != null and m.has_meta("pf_color")


## The material used by batched (vertex-coloured) chunks.
static func vertex_mat() -> ShaderMaterial:
	if _vertex_mat == null:
		_vertex_mat = ShaderMaterial.new()
		_vertex_mat.shader = SHADER
		_vertex_mat.set_shader_parameter("use_vertex_color", true)
	return _vertex_mat


## Character body material: vertex-coloured with rim light. Not a shared mat(), so characters never
## end up in the island's batches.
static func character_vertex_mat() -> ShaderMaterial:
	if _character_vertex_mat == null:
		_character_vertex_mat = ShaderMaterial.new()
		_character_vertex_mat.shader = SHADER
		_character_vertex_mat.set_shader_parameter("use_vertex_color", true)
		_character_vertex_mat.set_shader_parameter("rim_strength", 0.35)
	return _character_vertex_mat


## Unshared rim-lit material for character props (tools), also excluded from batching.
static func character_mat(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("rim_strength", 0.35)
	return m


# --- meshes -------------------------------------------------------------------------------------

static func box_mesh(size: Vector3) -> BoxMesh:
	var key := "box%s" % size
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func cylinder_mesh(top: float, bottom: float, height: float, sides: int = 8) -> CylinderMesh:
	var key := "cyl%.3f|%.3f|%.3f|%d" % [top, bottom, height, sides]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = sides
		m.rings = 0
		m.cap_top = top > 0.0
		_meshes[key] = m
	return _meshes[key]


static func sphere_mesh(radius: float, segments: int = 8, rings: int = 5) -> SphereMesh:
	var key := "sph%.3f|%d|%d" % [radius, segments, rings]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = segments
		m.rings = rings
		_meshes[key] = m
	return _meshes[key]


static func prism_mesh(size: Vector3) -> PrismMesh:
	var key := "prism%s" % size
	if not _meshes.has(key):
		var m := PrismMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


# --- placement ----------------------------------------------------------------------------------

static func add(parent: Node, mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO,
		scl: Vector3 = Vector3.ONE, sway: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, sway)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func box(parent: Node, size: Vector3, pos: Vector3, color: Color,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return add(parent, box_mesh(size), color, pos, rot)


static func cylinder(parent: Node, top: float, bottom: float, height: float, pos: Vector3,
		color: Color, sides: int = 8, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return add(parent, cylinder_mesh(top, bottom, height, sides), color, pos, rot)


static func cone(parent: Node, radius: float, height: float, pos: Vector3, color: Color,
		sides: int = 7, sway: float = 0.0) -> MeshInstance3D:
	return add(parent, cylinder_mesh(0.0, radius, height, sides), color, pos, Vector3.ZERO,
			Vector3.ONE, sway)


static func sphere(parent: Node, radius: float, pos: Vector3, color: Color,
		scl: Vector3 = Vector3.ONE, segments: int = 7, rings: int = 4, sway: float = 0.0) -> MeshInstance3D:
	return add(parent, sphere_mesh(radius, segments, rings), color, pos, Vector3.ZERO, scl, sway)


static func prism(parent: Node, size: Vector3, pos: Vector3, color: Color,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return add(parent, prism_mesh(size), color, pos, rot)


## Marks a mesh as a plant part for wind. Anchored meshes sway more towards the tip.
static func swaying(mi: MeshInstance3D, weight: float, anchored: bool = false) -> MeshInstance3D:
	var c: Color = mi.material_override.get_meta("pf_color")
	mi.material_override = mat(c, weight)
	mi.set_meta("pf_anchored", anchored)
	return mi


# --- collision ----------------------------------------------------------------------------------

static func solid(parent: Node, node_name: String, pos: Vector3, layer: int = Layers.OBSTACLES) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = pos
	parent.add_child(body)
	return body


static func box_shape(body: CollisionObject3D, size: Vector3, offset: Vector3 = Vector3.ZERO,
		yaw: float = 0.0) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.position = offset
	cs.rotation.y = yaw
	body.add_child(cs)
	return cs


static func cylinder_shape(body: CollisionObject3D, radius: float, height: float,
		offset: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	cs.shape = s
	cs.position = offset
	body.add_child(cs)
	return cs
