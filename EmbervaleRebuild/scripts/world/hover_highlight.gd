class_name HoverHighlight
extends Node3D
## A soft pulsing ring on the ground under the hovered interactable. Presentation only: it listens to
## InteractionSystem.hover_changed and never touches gameplay.

var _ring: MeshInstance3D
var _mat: StandardMaterial3D
var _target: Node = null
var _t := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(1.0, 0.85, 0.4, 0.55)
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring = MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 1.0
	m.bottom_radius = 1.0
	m.height = 0.03
	m.radial_segments = 20
	m.rings = 0
	m.cap_top = false
	m.cap_bottom = false
	_ring.mesh = m
	_ring.material_override = _mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	visible = false


func connect_to(interaction: InteractionSystem) -> void:
	interaction.hover_changed.connect(_on_hover)


func _on_hover(target: Node) -> void:
	_target = target
	visible = target != null
	_t = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(_target) or not _target.is_inside_tree():
		visible = false
		return
	_t += delta
	var pos: Vector3 = _target.interaction_position()
	global_position = pos + Vector3(0, 0.05, 0)
	var r: float = clampf(float(_target.interaction_range()) * 0.42, 0.55, 1.1)
	var pulse := 1.0 + 0.08 * sin(_t * 5.0)
	_ring.scale = Vector3(r * pulse, 1.0, r * pulse)
	_mat.albedo_color.a = 0.45 + 0.15 * sin(_t * 5.0)
