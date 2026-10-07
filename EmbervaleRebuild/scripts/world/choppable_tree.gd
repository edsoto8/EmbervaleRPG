class_name ChoppableTree
extends Node3D
## A tree the player can chop. Merges its own canopy/trunk and stump meshes and stays out of the
## island batches (it shakes and toggles). Collision stays the same as a stump so the navmesh holds.

signal chopped(tree: ChoppableTree)
signal felled(tree: ChoppableTree)
signal regrown(tree: ChoppableTree)
signal struck(tree: ChoppableTree)

var tree_type := "normal"
var is_stump := false
var regrow_left := 0.0
var full_visual: Node3D
var stump_visual: Node3D
var _shake := 0.0


func _init(kind: String = "normal") -> void:
	tree_type = kind


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("choppable_tree")
	full_visual = Node3D.new()
	full_visual.name = "Full"
	add_child(full_visual)
	stump_visual = Node3D.new()
	stump_visual.name = "Stump"
	add_child(stump_visual)
	var trunk := Color("6b4a2b")
	match tree_type:
		"oak":
			PropFactory.cylinder(full_visual, 0.26, 0.42, 2.4, Vector3(0, 1.2, 0), Color("5e4126"), 7)
			for k in 3:
				var a := k * TAU / 3.0 + 0.4
				PropFactory.box(full_visual, Vector3(0.75, 0.26, 0.26), Vector3(cos(a) * 0.4, 0.02, sin(a) * 0.4),
						Color("4f3620"), Vector3(0, -a, -0.35))
			PropFactory.swaying(PropFactory.sphere(full_visual, 1.5, Vector3(0, 2.6, 0), Color("2f5f27"), Vector3(1.15, 0.55, 1.15)), 0.3)
			for c in [[Vector3(0, 3.1, 0), 1.65, Color("3f7a32")], [Vector3(0.9, 3.6, 0.3), 1.0, Color("4a8a38")],
					[Vector3(-0.8, 3.5, -0.4), 1.05, Color("447f35")], [Vector3(0.2, 4.2, -0.3), 0.7, Color("5a9a42")]]:
				PropFactory.swaying(PropFactory.sphere(full_visual, c[1], c[0], c[2], Vector3(1, 0.8, 1)), 0.35)
		"willow":
			PropFactory.cylinder(full_visual, 0.22, 0.32, 2.6, Vector3(0, 1.3, 0), Color("6f5a3e"), 7)
			PropFactory.swaying(PropFactory.sphere(full_visual, 1.5, Vector3(0, 3.2, 0), Color("7aa04a"), Vector3(1.1, 0.7, 1.1)), 0.35)
			for k in 8:
				var a := TAU * k / 8.0
				var strand := PropFactory.cylinder(full_visual, 0.1, 0.32, 2.2, Vector3(cos(a) * 1.25, 2.1, sin(a) * 1.25), Color("8ab055"), 5)
				PropFactory.swaying(strand, 0.7, true)
		_:
			PropFactory.cylinder(full_visual, 0.18, 0.3, 2.3, Vector3(0, 1.15, 0), trunk, 7)
			var g := Color("559640")
			PropFactory.swaying(PropFactory.sphere(full_visual, 1.15, Vector3(0, 2.35, 0), g.darkened(0.22), Vector3(1.1, 0.6, 1.1)), 0.3)
			PropFactory.swaying(PropFactory.sphere(full_visual, 1.3, Vector3(0, 2.85, 0), g, Vector3(1, 0.8, 1)), 0.35)
			PropFactory.swaying(PropFactory.sphere(full_visual, 0.8, Vector3(0.7, 3.4, 0.2), g.lightened(0.1)), 0.5)
			PropFactory.swaying(PropFactory.sphere(full_visual, 0.65, Vector3(-0.55, 3.15, -0.5), g.lightened(0.16)), 0.55)
			PropFactory.swaying(PropFactory.sphere(full_visual, 0.5, Vector3(0, 3.85, 0), g.lightened(0.22)), 0.6)
	PropFactory.cylinder(stump_visual, 0.3, 0.38, 0.45, Vector3(0, 0.22, 0), trunk, 7)
	PropFactory.cylinder(stump_visual, 0.28, 0.28, 0.02, Vector3(0, 0.455, 0), Color("c9a774"), 7)
	MeshMerger.merge(full_visual, [], 100.0, {"name": "TreeMesh", "single": true})
	MeshMerger.merge(stump_visual, [], 100.0, {"name": "StumpMesh", "single": true})
	stump_visual.visible = false
	var body := PropFactory.solid(self, "Trunk", Vector3.ZERO)
	PropFactory.cylinder_shape(body, 0.4, 2.2, Vector3(0, 1.1, 0))
	var click := Area3D.new()
	click.name = "ClickArea"
	click.collision_layer = Layers.INTERACTABLES
	click.collision_mask = 0
	click.monitoring = false
	add_child(click)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 1.3
	cap.height = 4.2
	cs.shape = cap
	cs.position.y = 2.1
	click.add_child(cs)


func data() -> Dictionary:
	return SkillData.TREES[tree_type]


func interaction_verb() -> String:
	return "Chop down"


func interaction_name() -> String:
	return {"normal": "Tree", "oak": "Oak tree", "willow": "Willow tree"}[tree_type]


func interaction_range() -> float:
	return 1.7


func interaction_position() -> Vector3:
	return global_position


func is_available() -> bool:
	return not is_stump


## Chopping is run by whoever owns the activity (TutorialDirector, later SkillsDirector), which sets
## this callable; the tree itself only knows how to look chopped.
var chop_handler := Callable()


func interact(player: Node) -> void:
	if is_stump:
		GameManager.post_message("This tree has been cut down. It will grow back soon.")
		return
	if chop_handler.is_valid():
		chop_handler.call(self, player)


## Called on every axe impact (shake and wood chips).
func strike() -> void:
	_shake = 1.0
	struck.emit(self)


## Turns the tree into a stump that regrows after its regrow time.
func fell() -> void:
	is_stump = true
	regrow_left = data().regrow
	full_visual.visible = false
	stump_visual.visible = true
	felled.emit(self)


func regrow() -> void:
	is_stump = false
	regrow_left = 0.0
	full_visual.visible = true
	stump_visual.visible = false
	regrown.emit(self)


func _physics_process(delta: float) -> void:
	if is_stump:
		regrow_left -= delta
		if regrow_left <= 0.0:
			regrow()
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 4.0, 0.0)
		full_visual.rotation = Vector3(sin(_shake * 40.0) * 0.03 * _shake, 0, cos(_shake * 33.0) * 0.03 * _shake)
