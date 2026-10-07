class_name FishingSpot
extends Node3D
## Rippling water near the pond's south bank. Clicking it walks to the bank and casts.

var fish_handler := Callable()
var _rings: Array[MeshInstance3D] = []
var _t := 0.0


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("fishing_spot")
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.5)
	for k in 2:
		var ring := MeshInstance3D.new()
		var m := CylinderMesh.new()
		m.top_radius = 0.5
		m.bottom_radius = 0.5
		m.height = 0.01
		m.radial_segments = 14
		m.rings = 0
		ring.mesh = m
		ring.material_override = mat.duplicate()
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position.y = 0.03
		add_child(ring)
		_rings.append(ring)
	var click := Area3D.new()
	click.collision_layer = Layers.INTERACTABLES
	click.collision_mask = 0
	click.monitoring = false
	add_child(click)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.9
	shape.height = 0.8
	cs.shape = shape
	click.add_child(cs)


func interaction_verb() -> String:
	return "Fish at"


func interaction_name() -> String:
	return "Fishing spot"


func interaction_range() -> float:
	return 3.0


func interaction_position() -> Vector3:
	return global_position


func is_available() -> bool:
	return true


func interact(player: Node) -> void:
	if fish_handler.is_valid():
		fish_handler.call(self, player)


func _process(delta: float) -> void:
	_t += delta
	for k in _rings.size():
		var phase := fmod(_t * 0.6 + k * 0.5, 1.0)
		_rings[k].scale = Vector3(0.4 + phase * 1.4, 1, 0.4 + phase * 1.4)
		(_rings[k].material_override as StandardMaterial3D).albedo_color.a = 0.55 * (1.0 - phase)
