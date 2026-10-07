class_name Fire
extends Node3D
## A campfire lit from logs. Burns for 60 s including a 3 s fade, then disappears. Clicking it with
## raw fish cooks (SkillsDirector sets cook_handler). Not saved: fires vanish on reload.

signal expired(fire: Fire)

var time_left := SkillData.FIRE_BURN_SECONDS
var cook_handler := Callable()
var _flames: Node3D
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("fire")
	var wood := Node3D.new()
	add_child(wood)
	for k in 4:
		var stick := MeshInstance3D.new()
		stick.mesh = PropFactory.cylinder_mesh(0.07, 0.08, 0.7, 6)
		stick.material_override = PropFactory.character_mat(Color("6b4a2b"))
		stick.rotation = Vector3(PI * 0.5, k * PI * 0.25, 0)
		stick.position.y = 0.08
		wood.add_child(stick)
	_flames = Node3D.new()
	add_child(_flames)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color("ff9a3a")
	flame_mat.emission_enabled = true
	flame_mat.emission = Color("ff7a1a")
	flame_mat.emission_energy_multiplier = 2.0
	var core_mat := flame_mat.duplicate()
	core_mat.albedo_color = Color("ffe08a")
	for k in 3:
		var f := MeshInstance3D.new()
		f.mesh = PropFactory.cylinder_mesh(0.0, 0.2 - k * 0.04, 0.55 + k * 0.12, 5)
		f.material_override = flame_mat if k < 2 else core_mat
		f.position = Vector3(cos(k * 2.1) * 0.06, 0.32 + k * 0.03, sin(k * 2.1) * 0.06)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flames.add_child(f)
	_light = OmniLight3D.new()
	_light.light_color = Color("ffa040")
	_light.light_energy = 1.4
	_light.omni_range = 4.0
	_light.position.y = 0.6
	add_child(_light)
	var click := Area3D.new()
	click.collision_layer = Layers.INTERACTABLES
	click.collision_mask = 0
	click.monitoring = false
	add_child(click)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.6
	shape.height = 1.2
	cs.shape = shape
	cs.position.y = 0.6
	click.add_child(cs)


func interaction_verb() -> String:
	return "Cook on"


func interaction_name() -> String:
	return "Fire"


func interaction_range() -> float:
	return 1.8


func interaction_position() -> Vector3:
	return global_position


func is_available() -> bool:
	return is_burning()


func is_burning() -> bool:
	return time_left > 0.0


func interact(player: Node) -> void:
	if cook_handler.is_valid():
		cook_handler.call(self, player)


func _physics_process(delta: float) -> void:
	time_left -= delta
	_t += delta
	var fade := clampf(time_left / SkillData.FIRE_FADE_SECONDS, 0.0, 1.0)
	var flicker := 1.0 + 0.12 * sin(_t * 13.0) + 0.08 * sin(_t * 7.3)
	_flames.scale = Vector3(fade, fade * flicker, fade)
	_light.light_energy = 1.4 * fade * flicker
	if time_left <= 0.0:
		expired.emit(self)
		queue_free()
