class_name ClickMarker
extends Node3D
## Yellow cross shown at the click destination. Listens only to NavigationController signals.

var _time := 0.0
var _mesh: Node3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mesh = Node3D.new()
	add_child(_mesh)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("ffd23a")
	for a in [PI * 0.25, -PI * 0.25]:
		var mi := MeshInstance3D.new()
		mi.mesh = PropFactory.box_mesh(Vector3(0.12, 0.03, 0.7))
		mi.material_override = m
		mi.rotation.y = a
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh.add_child(mi)
	visible = false


func connect_to(nav: NavigationController) -> void:
	nav.destination_set.connect(_on_destination_set.bind(nav))
	nav.destination_reached.connect(func(_p: Vector3, _c: bool) -> void: visible = false)
	nav.navigation_cancelled.connect(func(_r: String) -> void: visible = false)


func _on_destination_set(point: Vector3, nav: NavigationController) -> void:
	# Only ground clicks show the cross (interaction approaches don't).
	await get_tree().process_frame
	if not nav.from_click:
		return
	global_position = point + Vector3(0, 0.06, 0)
	_time = 0.0
	visible = true


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	var s := 1.0 + 0.15 * sin(_time * 8.0)
	if _time < 0.15:
		s *= 1.6 - _time * 4.0
	_mesh.scale = Vector3(s, 1, s)
