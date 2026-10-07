class_name Boat
extends Node3D
## The small sailing boat moored at the dock. It moves during the intro, so it stays out of the
## island batches; it merges its own parts into one mesh.

var deck_height := 0.48  ## Where a passenger stands, in local space.
var bobbing := true
var base_y := 0.0
var _bob_time := 0.0


func _ready() -> void:
	var hull := Color("7a5332")
	var trim := Color("5a3b22")
	var sail := Color("efe6cf")
	var v := Node3D.new()
	v.name = "Visual"
	add_child(v)
	var mi := MeshInstance3D.new()
	mi.mesh = _hull_mesh()
	mi.material_override = PropFactory.mat(hull)
	v.add_child(mi)
	PropFactory.box(v, Vector3(1.3, 0.06, 3.0), Vector3(0, 0.42, 0.6), Color("9c7a4e"))
	PropFactory.box(v, Vector3(1.6, 0.08, 0.3), Vector3(0, 0.5, -0.6), trim)
	PropFactory.box(v, Vector3(1.6, 0.08, 0.3), Vector3(0, 0.5, 1.4), trim)
	PropFactory.cylinder(v, 0.07, 0.08, 4.2, Vector3(0, 2.5, -0.5), trim, 6)
	PropFactory.box(v, Vector3(0.05, 0.05, 1.9), Vector3(0, 1.25, 0.45), trim)
	PropFactory.box(v, Vector3(0.04, 2.6, 1.8), Vector3(0, 2.6, 0.45), sail)
	MeshMerger.merge(v, [], 100.0, {"name": "BoatMesh", "single": true})
	base_y = position.y


## A tapered, flat-shaded hull: bow at -Z, transom at +Z.
func _hull_mesh() -> ArrayMesh:
	var sections := [[-2.7, 0.0], [-2.1, 0.55], [-1.2, 0.88], [0.0, 1.0], [1.3, 0.95], [2.3, 0.82]]
	var top := 0.55
	var keel := -0.35
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in sections.size() - 1:
		var za: float = sections[i][0]
		var zb: float = sections[i + 1][0]
		var wa: float = sections[i][1]
		var wb: float = sections[i + 1][1]
		for side in [-1.0, 1.0]:
			var a := Vector3(side * wa, top, za)
			var b := Vector3(side * wb, top, zb)
			var c := Vector3(side * wb * 0.35, keel, zb)
			var d := Vector3(side * wa * 0.35, keel, za)
			_quad(st, a, b, c, d, Vector3(side, -0.3, 0))
		# Bottom strip.
		_quad(st, Vector3(-wa * 0.35, keel, za), Vector3(wa * 0.35, keel, za), Vector3(wb * 0.35, keel, zb),
				Vector3(-wb * 0.35, keel, zb), Vector3.DOWN)
	# Transom.
	var w: float = sections[sections.size() - 1][1]
	var z: float = sections[sections.size() - 1][0]
	_quad(st, Vector3(-w, top, z), Vector3(w, top, z), Vector3(w * 0.35, keel, z), Vector3(-w * 0.35, keel, z), Vector3.BACK)
	st.generate_normals()
	return st.commit()


## Adds a quad whose front face looks along `outward` (Godot treats clockwise triangles as front).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	var pts := [a, b, c, a, c, d]
	if (b - a).cross(c - a).dot(outward) > 0.0:
		pts = [a, c, b, a, d, c]
	for p in pts:
		st.add_vertex(p)


func _physics_process(delta: float) -> void:
	if not bobbing:
		return
	_bob_time += delta
	position.y = base_y + sin(_bob_time * 1.3) * 0.04
	rotation.z = sin(_bob_time * 0.9) * 0.025
