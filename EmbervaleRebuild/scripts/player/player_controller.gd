class_name PlayerController
extends CharacterBody3D
## The player: camera-relative WASD movement, click navigation steering, facing and timed actions.
## Moves in _physics_process (physics interpolation is on). Rotates the CharacterModel, not the body.

signal keyboard_moved(distance: float)
signal action_started(action_name: String)
signal action_cancelled(action_name: String, reason: String)
signal footstep(foot: int)

const WALK_SPEED := 3.4
const RUN_SPEED := 6.2
const ACCELERATION := 30.0
const GRAVITY := 20.0

## Keyboard and click movement are both blocked while false (cutscenes, dialogue, modals).
var input_enabled := true
var camera: CameraController
var model: CharacterModel
var nav: NavigationController
## Total horizontal distance moved by keyboard input.
var keyboard_distance := 0.0

var _action_token := 0
var _action_name := ""
var _release_frames := 0


func _ready() -> void:
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WALKABLE_SOURCES
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(46.0)
	safe_margin = 0.02
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.75
	shape.shape = capsule
	shape.position.y = 0.875
	add_child(shape)
	model = CharacterModel.new()
	model.name = "Model"
	add_child(model)
	model.footstep.connect(func(foot: int) -> void: footstep.emit(foot))
	nav = NavigationController.new()
	nav.name = "Navigation"
	nav.player = self
	add_child(nav)


func set_appearance(look: Dictionary) -> void:
	model.set_appearance(look)


## Places the player (e.g. at spawn or a loaded position) without interpolation artefacts.
func teleport(pos: Vector3, yaw: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	nav.cancel("teleport")
	cancel_action("teleport")
	model.face_yaw(yaw)
	reset_physics_interpolation()
	model.reset_physics_interpolation()


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	nav.input_enabled = enabled
	if not enabled:
		nav.cancel("input_disabled")


func facing_yaw() -> float:
	return model.global_rotation.y


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if input_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var keyboard := input.length() > 0.01
	var running := input_enabled and Input.is_action_pressed("run")
	var speed := RUN_SPEED if running else WALK_SPEED
	var desired := Vector3.ZERO
	if keyboard:
		# Keyboard input cancels click navigation, pending interactions and timed actions at once.
		if nav.is_active() or nav.has_pending():
			nav.cancel("keyboard")
		cancel_action("moved")
		var yaw := camera.yaw if camera else 0.0
		var forward := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		desired = (right * input.x - forward * input.y)
		if desired.length() > 1.0:
			desired = desired.normalized()
		desired *= speed
	elif nav.is_active():
		desired = nav.steer(global_position, speed, delta)
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	horizontal = horizontal.move_toward(desired, ACCELERATION * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	var before := global_position
	move_and_slide()
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if keyboard and moved > 0.0:
		keyboard_distance += moved
		keyboard_moved.emit(moved)
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	model.locomotion_speed = moved / delta if moved > 0.001 else 0.0
	if flat_speed > 0.3 and (keyboard or nav.is_active()):
		model.face_towards(global_position + Vector3(velocity.x, 0, velocity.z))
	if _action_name == "" and _release_frames > 0:
		_release_frames -= 1
		if _release_frames == 0:
			model.stop_action()


# --- timed actions -------------------------------------------------------------------------------

## Runs a timed action owned by the player. Returns false if it was cancelled (movement, a new click,
## another action or disabled input) before finishing. Paused time does not count.
func perform_action(action_name: String, seconds: float, face_point: Variant = null) -> bool:
	cancel_action("replaced")
	_action_token += 1
	var token := _action_token
	_action_name = action_name
	_release_frames = 0
	velocity.x = 0.0
	velocity.z = 0.0
	if face_point is Vector3:
		model.face_towards(face_point)
	model.play_action(action_name)
	action_started.emit(action_name)
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().physics_frame
		if token != _action_token:
			return false
		if not get_tree().paused:
			elapsed += get_physics_process_delta_time()
	if token != _action_token:
		return false
	_action_name = ""
	# Keep the pose for a moment so repeating actions don't flicker their tool.
	_release_frames = 3
	return true


func cancel_action(reason: String = "") -> void:
	if _action_name == "":
		return
	var was := _action_name
	_action_token += 1
	_action_name = ""
	model.stop_action()
	action_cancelled.emit(was, reason)


func is_busy() -> bool:
	return _action_name != ""


func current_action() -> String:
	return _action_name
