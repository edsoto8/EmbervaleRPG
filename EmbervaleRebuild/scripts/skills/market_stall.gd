class_name MarketStall
extends Node3D
## Click target for Marla's stall ("Browse Market stall"). The stall's meshes are batched with the
## island; this node only adds the interaction.

var browse_handler := Callable()
var front := Vector3.ZERO


func setup(island: TutorialIsland) -> void:
	add_to_group("interactable")
	name = "MarketStallInteraction"
	var p := IslandLayout.MARKET_STALL
	global_position = island.ground_point(p)
	rotation.y = IslandLayout.yaw_towards(p, IslandLayout.PLAZA)
	var dir := (IslandLayout.PLAZA - p).normalized()
	front = island.ground_point(p + dir * 0.6)
	var click := Area3D.new()
	click.collision_layer = Layers.INTERACTABLES
	click.collision_mask = 0
	click.monitoring = false
	add_child(click)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.6, 1.3, 1.1)
	cs.shape = shape
	cs.position.y = 0.65
	click.add_child(cs)


func interaction_verb() -> String:
	return "Browse"


func interaction_name() -> String:
	return "Market stall"


func interaction_range() -> float:
	return 3.2


func interaction_position() -> Vector3:
	return front


func is_available() -> bool:
	return true


func interact(player: Node) -> void:
	if browse_handler.is_valid():
		browse_handler.call(self, player)
