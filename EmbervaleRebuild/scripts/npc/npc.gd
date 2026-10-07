class_name Npc
extends Node3D
## A villager: a CharacterModel with a click area on the interactables layer. NPCs don't block the
## player (like the classic game) and never change the navmesh. Pip wanders near their home.

signal talk_requested(npc: Npc)

const WANDER_SPEED := 1.3
const WANDER_RADIUS := 5.0

var npc_id := ""
var display_name := ""
var appearance := {}
var home := Vector3.ZERO
var home_yaw := 0.0
var wanders := false
var model_scale := 1.0
## Where the player talks from (defaults to the NPC; Marla is reached across her counter).
var approach_point := Vector3.INF
var island: TutorialIsland
var model: CharacterModel
var talking := false

var _path := PackedVector3Array()
var _path_index := 0
var _wait := 2.0
var _rng := RandomNumberGenerator.new()


func setup(id: String, nice_name: String, look: Dictionary, pos: Vector3, yaw: float) -> Npc:
	npc_id = id
	display_name = nice_name
	appearance = look
	home = pos
	home_yaw = yaw
	name = id.capitalize().replace(" ", "")
	return self


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("npc")
	_rng.seed = hash(npc_id)
	global_position = home
	model = CharacterModel.new(appearance)
	model.name = "Model"
	model.scale = Vector3.ONE * model_scale
	add_child(model)
	model.face_yaw(home_yaw)
	var area := StaticBody3D.new()
	area.name = "ClickBody"
	area.collision_layer = Layers.INTERACTABLES
	area.collision_mask = 0
	add_child(area)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.9 * model_scale
	cs.shape = cap
	cs.position.y = 0.95 * model_scale
	area.add_child(cs)


func interaction_verb() -> String:
	return "Talk-to"


func interaction_name() -> String:
	return display_name


func interaction_range() -> float:
	return 2.0


## Where range is measured from: the NPC, or (for Marla) the front of her counter.
func interaction_position() -> Vector3:
	return approach_point if approach_point != Vector3.INF else global_position


func approach_position() -> Vector3:
	return approach_point if approach_point != Vector3.INF else global_position


func is_available() -> bool:
	return true


func interact(_player: Node) -> void:
	talk_requested.emit(self)


func begin_talk(towards: Vector3) -> void:
	talking = true
	_path = PackedVector3Array()
	model.locomotion_speed = 0.0
	model.face_towards(towards)
	model.play_action("talk")


func end_talk() -> void:
	talking = false
	model.stop_action()
	if not wanders:
		model.face_towards(global_position + Basis(Vector3.UP, home_yaw) * Vector3.FORWARD)
	_wait = 2.0


func cheer() -> void:
	model.play_action("cheer", 1.6)


func _physics_process(delta: float) -> void:
	if not wanders or talking or island == null or not island.is_navigation_ready:
		model.locomotion_speed = 0.0
		return
	if _path_index >= _path.size():
		model.locomotion_speed = 0.0
		_wait -= delta
		if _wait <= 0.0:
			_pick_destination()
		return
	var target := _path[_path_index]
	var to := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if to.length() < 0.2:
		_path_index += 1
		if _path_index >= _path.size():
			_wait = _rng.randf_range(2.0, 5.0)
		return
	var step := to.normalized() * WANDER_SPEED * delta
	global_position += step
	global_position.y = island.ground_height(global_position.x, global_position.z)
	model.locomotion_speed = WANDER_SPEED
	model.face_towards(target)


func _pick_destination() -> void:
	var map := island.navigation_map()
	for attempt in 6:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(1.0, WANDER_RADIUS)
		var p := home + Vector3(cos(a) * r, 0, sin(a) * r)
		var c := NavigationServer3D.map_get_closest_point(map, p)
		if Vector2(c.x - home.x, c.z - home.z).length() > WANDER_RADIUS:
			continue
		var path := NavigationServer3D.map_get_path(map, global_position, c, true)
		if path.size() >= 2:
			_path = path
			_path_index = 1
			return
	_wait = 1.5
