class_name CraftStation
extends Node3D
## Click target for the smithy's furnace or anvil ("Use Furnace"). The static meshes are batched with
## the island; this node adds the interaction and, for the furnace, the flickering glow and smoke
## (animated, so created after batching).

var station := "furnace"
var use_handler := Callable()
## Where the player stands to work (range is measured from here).
var front := Vector3.ZERO
var glow: MeshInstance3D
var smoke: CPUParticles3D
var active := false
var _t := 0.0


func setup(island: TutorialIsland, kind: String) -> void:
	station = kind
	name = "Furnace" if kind == "furnace" else "Anvil"
	add_to_group("interactable")
	add_to_group("craft_station")
	var p: Vector2 = IslandLayout.FURNACE if kind == "furnace" else IslandLayout.ANVIL
	global_position = island.ground_point(p)
	front = island.ground_point(p + (Vector2(-1.65, 0.0) if kind == "furnace" else Vector2(-1.0, 0.0)))
	var click := Area3D.new()
	click.collision_layer = Layers.INTERACTABLES
	click.collision_mask = 0
	click.monitoring = false
	add_child(click)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.1, 2.1, 2.1) if kind == "furnace" else Vector3(1.3, 1.3, 1.3)
	cs.shape = shape
	cs.position.y = shape.size.y * 0.5
	click.add_child(cs)
	if kind == "furnace":
		_build_fire()


func _build_fire() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("ff8a2a")
	mat.emission_enabled = true
	mat.emission = Color("ff6a1a")
	mat.emission_energy_multiplier = 1.8
	glow = MeshInstance3D.new()
	glow.name = "Glow"
	glow.mesh = PropFactory.box_mesh(Vector3(0.06, 0.55, 0.8))
	glow.material_override = mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.position = Vector3(-0.9, 0.55, 0)
	add_child(glow)
	smoke = CPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.amount = 10
	smoke.lifetime = 3.5
	smoke.direction = Vector3(0.2, 1, 0)
	smoke.spread = 12.0
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 0.9
	smoke.gravity = Vector3(0.12, 0.1, 0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.45, 0.43, 0.42, 0.45))
	ramp.set_color(1, Color(0.6, 0.6, 0.6, 0.0))
	smoke.color_ramp = ramp
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.6))
	grow.add_point(Vector2(1, 2.4))
	smoke.scale_amount_curve = grow
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	quad.material = smat
	smoke.mesh = quad
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.position = Vector3(0.3, 5.0, 0)
	add_child(smoke)


func interaction_verb() -> String:
	return "Use"


func interaction_name() -> String:
	return "Furnace" if station == "furnace" else "Anvil"


func interaction_range() -> float:
	return 1.4


func interaction_position() -> Vector3:
	return front


func is_available() -> bool:
	return true


func interact(player: Node) -> void:
	if use_handler.is_valid():
		use_handler.call(self, player)


## Brightens the furnace while smelting.
func set_active(on: bool) -> void:
	active = on


func _process(delta: float) -> void:
	if glow == null:
		return
	_t += delta
	var base := 2.6 if active else 1.5
	var flicker := 0.25 * sin(_t * 11.0) + 0.15 * sin(_t * 23.0 + 1.3)
	(glow.material_override as StandardMaterial3D).emission_energy_multiplier = base + flicker
