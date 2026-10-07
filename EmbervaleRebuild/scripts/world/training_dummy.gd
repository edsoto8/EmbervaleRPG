class_name TrainingDummy
extends Node3D
## A straw training dummy on a post. Builds and merges its own mesh (one draw call) and stays out of
## the island batches so it can wobble when hit.

var body: StaticBody3D
## Set by SkillsDirector: Callable(dummy, player) runs Attack training.
var attack_handler := Callable()
var _visual: Node3D
var _wobble := 0.0


func _ready() -> void:
	add_to_group("interactable")
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var wood := Color("6b4a2b")
	var straw := Color("cdb36a")
	var sack := Color("a68a55")
	PropFactory.cylinder(_visual, 0.08, 0.1, 1.9, Vector3(0, 0.95, 0), wood, 6)
	PropFactory.cylinder(_visual, 0.3, 0.32, 0.8, Vector3(0, 1.25, 0), sack, 8)
	PropFactory.cylinder(_visual, 0.31, 0.31, 0.08, Vector3(0, 1.0, 0), Color("7a5a33"), 8)
	PropFactory.box(_visual, Vector3(1.2, 0.12, 0.12), Vector3(0, 1.45, 0), wood)
	PropFactory.sphere(_visual, 0.22, Vector3(0, 1.85, 0), straw)
	PropFactory.box(_visual, Vector3(0.5, 0.06, 0.5), Vector3(0, 0.03, 0), wood)
	MeshMerger.merge(_visual, [], 100.0, {"name": "DummyMesh", "single": true})
	body = PropFactory.solid(self, "Body", Vector3.ZERO)
	PropFactory.cylinder_shape(body, 0.35, 2.0, Vector3(0, 1.0, 0))


func interaction_verb() -> String:
	return "Attack"


func interaction_name() -> String:
	return "Training dummy"


func interaction_range() -> float:
	return 1.9


func interaction_position() -> Vector3:
	return global_position


func is_available() -> bool:
	return true


func interact(player: Node) -> void:
	if attack_handler.is_valid():
		attack_handler.call(self, player)
	else:
		GameManager.post_message("Finish your training with Maelis before using the dummies.")


## Makes the dummy rock back and forth briefly (used by training in Milestone 6).
func wobble() -> void:
	_wobble = 1.0


func _physics_process(delta: float) -> void:
	if _wobble <= 0.0:
		return
	_wobble = maxf(_wobble - delta * 1.6, 0.0)
	_visual.rotation.z = sin(_wobble * 18.0) * 0.12 * _wobble
