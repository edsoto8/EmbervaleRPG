class_name MiningRock
extends Node3D
## A rock in the quarry with ore veins (SPEC_SMITHING.md K2). Each completed swing yields one ore and
## depletes it to rubble, which respawns after the rock's delay. Merges its own full and rubble meshes
## and stays out of the island batches (it toggles). Collision is the same either way, so the navmesh holds.

signal depleted(rock: MiningRock)
signal respawned(rock: MiningRock)
signal struck(rock: MiningRock)

const VEIN_COLORS := {"copper": Color("d9824a"), "tin": Color("d8d8cc"), "iron": Color("a8452f")}

var rock_type := "copper"
var is_depleted := false
var respawn_left := 0.0
var full_visual: Node3D
var rubble_visual: Node3D
## Mining is run by SmithyDirector, which sets this callable.
var mine_handler := Callable()
var _shake := 0.0


func _init(kind: String = "copper") -> void:
	rock_type = kind


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("mining_rock")
	full_visual = Node3D.new()
	full_visual.name = "Full"
	add_child(full_visual)
	rubble_visual = Node3D.new()
	rubble_visual.name = "Rubble"
	add_child(rubble_visual)
	var h := IslandTerrain._hash01(int(position.x * 7.0), int(position.z * 7.0))
	var grey := Color("8b8a84").lerp(Color("6f6d66"), h)
	if rock_type == "iron":
		grey = grey.lerp(Color("6a5850"), 0.4)
	var vein: Color = VEIN_COLORS[rock_type]
	PropFactory.sphere(full_visual, 0.78, Vector3(0, 0.42, 0), grey, Vector3(1.15, 0.85, 1.0), 7, 4)
	PropFactory.sphere(full_visual, 0.5, Vector3(0.45, 0.85, 0.15), grey.lightened(0.06), Vector3(1, 0.8, 1), 6, 3)
	PropFactory.sphere(full_visual, 0.45, Vector3(-0.5, 0.3, 0.35), grey.darkened(0.08), Vector3(1.1, 0.7, 1), 6, 3)
	for k in 6:
		var a := k * 1.13 + h * 3.0
		var y := 0.4 + 0.35 * sin(k * 2.1)
		var r := 0.78 * sqrt(maxf(1.0 - pow((y - 0.42) / 0.68, 2.0), 0.15))
		var p := Vector3(cos(a) * r * 1.12, y, sin(a) * r * 0.98)
		PropFactory.sphere(full_visual, 0.13 + 0.03 * (k % 2), p, vein, Vector3(1.2, 0.7, 1.2), 5, 3)
	# Rubble: low, dull stones (no veins).
	var dull := grey.darkened(0.15)
	PropFactory.sphere(rubble_visual, 0.62, Vector3(0, 0.22, 0), dull, Vector3(1.2, 0.5, 1.05), 6, 3)
	PropFactory.sphere(rubble_visual, 0.32, Vector3(0.55, 0.15, -0.3), dull.lightened(0.05), Vector3(1, 0.6, 1), 5, 3)
	PropFactory.sphere(rubble_visual, 0.26, Vector3(-0.5, 0.12, 0.4), dull.darkened(0.05), Vector3(1, 0.6, 1), 5, 3)
	MeshMerger.merge(full_visual, [], 100.0, {"name": "RockMesh", "single": true})
	MeshMerger.merge(rubble_visual, [], 100.0, {"name": "RubbleMesh", "single": true})
	rubble_visual.visible = false
	# Collision at least 1 m tall so the navmesh carves around even the rubble.
	var body := PropFactory.solid(self, "Body", Vector3.ZERO)
	PropFactory.cylinder_shape(body, 0.85, 1.2, Vector3(0, 0.6, 0))
	var click := Area3D.new()
	click.name = "ClickArea"
	click.collision_layer = Layers.INTERACTABLES
	click.collision_mask = 0
	click.monitoring = false
	add_child(click)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.05
	shape.height = 1.6
	cs.shape = shape
	cs.position.y = 0.8
	click.add_child(cs)


func data() -> Dictionary:
	return SkillData.ROCKS[rock_type]


func interaction_verb() -> String:
	return "Mine"


func interaction_name() -> String:
	return data().name


func interaction_range() -> float:
	return 1.8


func interaction_position() -> Vector3:
	return global_position


func is_available() -> bool:
	return not is_depleted


func interact(player: Node) -> void:
	if is_depleted:
		GameManager.post_message("The rock has no ore left. It will refill soon.")
		return
	if mine_handler.is_valid():
		mine_handler.call(self, player)


## Called on every pickaxe impact (shake; chips and sound come from the director).
func strike() -> void:
	_shake = 1.0
	struck.emit(self)


func deplete() -> void:
	is_depleted = true
	respawn_left = data().respawn
	full_visual.visible = false
	rubble_visual.visible = true
	depleted.emit(self)


func respawn() -> void:
	is_depleted = false
	respawn_left = 0.0
	full_visual.visible = true
	rubble_visual.visible = false
	respawned.emit(self)


func _physics_process(delta: float) -> void:
	if is_depleted:
		respawn_left -= delta
		if respawn_left <= 0.0:
			respawn()
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 6.0, 0.0)
		full_visual.position = Vector3(sin(_shake * 50.0) * 0.025 * _shake, 0, cos(_shake * 41.0) * 0.02 * _shake)
