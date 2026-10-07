class_name Boat
extends Node3D
## The small sailing boat moored at the dock. It moves during the intro, so it stays out of the
## island batches; it merges its own parts into one mesh.

var deck_height := 0.55  ## Where a passenger stands, in local space.
var _bob_time := 0.0
var bobbing := true
var base_y := 0.0


func _ready() -> void:
	var hull := Color("7a5332")
	var trim := Color("5a3b22")
	var sail := Color("efe6cf")
	var v := Node3D.new()
	v.name = "Visual"
	add_child(v)
	PropFactory.box(v, Vector3(1.9, 0.6, 4.6), Vector3(0, 0.1, 0), hull)
	PropFactory.prism(v, Vector3(1.9, 1.2, 0.6), Vector3(0, 0.1, -2.6), hull, Vector3(PI * 0.5, 0, 0))
	PropFactory.box(v, Vector3(2.0, 0.12, 4.7), Vector3(0, 0.42, 0), trim)
	PropFactory.box(v, Vector3(1.6, 0.06, 4.0), Vector3(0, 0.36, 0.1), Color("9c7a4e"))
	PropFactory.cylinder(v, 0.07, 0.08, 4.2, Vector3(0, 2.4, -0.4), trim, 6)
	PropFactory.box(v, Vector3(0.06, 2.6, 1.8), Vector3(0, 2.6, 0.5), sail)
	PropFactory.box(v, Vector3(0.9, 0.3, 0.12), Vector3(0, 0.5, -1.2), trim)
	MeshMerger.merge(v, [], 100.0, {"name": "BoatMesh", "single": true})
	base_y = position.y


func _physics_process(delta: float) -> void:
	if not bobbing:
		return
	_bob_time += delta
	position.y = base_y + sin(_bob_time * 1.3) * 0.04
	rotation.z = sin(_bob_time * 0.9) * 0.025
