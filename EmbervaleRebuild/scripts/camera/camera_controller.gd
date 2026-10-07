class_name CameraController
extends Node3D
## Third-person orbit camera: smooth follow, wheel zoom, middle-drag/arrow orbit. Buildings and walls
## on the camera_blockers layer pull it inward. Moves per rendered frame, so physics interpolation is
## off for this node and it follows the player's interpolated transform.

const FOCUS_HEIGHT := 1.1
const MIN_DISTANCE := 5.0
const MAX_DISTANCE := 24.0
const ZOOM_STEP := 1.5
const SMOOTHING := 10.0
const MIN_PITCH := deg_to_rad(28.0)
const MAX_PITCH := deg_to_rad(72.0)
const DRAG_DEGREES_PER_PIXEL := 0.35
const KEY_DEGREES_PER_SECOND := 110.0

var target: Node3D
var yaw := 0.0
var pitch := deg_to_rad(48.0)
var distance := 14.0
var target_distance := 14.0
## User mouse sensitivity multiplier (Settings).
var sensitivity := 1.0
var input_enabled := true
## When false, an external driver (cutscene) positions `camera` directly.
var following := true
var camera: Camera3D
var focus := Vector3.ZERO
var _dragging := false
var _blocked_distance := INF


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 55.0
	camera.near = 0.1
	camera.far = 700.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.current = true


## Jumps to the target without smoothing.
func snap() -> void:
	if target == null:
		return
	focus = _target_point()
	distance = target_distance
	_blocked_distance = INF
	_place(1.0)


func set_view(new_yaw: float, new_pitch_degrees: float, new_distance: float) -> void:
	yaw = new_yaw
	pitch = clampf(deg_to_rad(new_pitch_degrees), MIN_PITCH, MAX_PITCH)
	target_distance = clampf(new_distance, MIN_DISTANCE, MAX_DISTANCE)


func _target_point() -> Vector3:
	var p := target.get_global_transform_interpolated().origin if target.is_inside_tree() else target.position
	return p + Vector3(0, FOCUS_HEIGHT, 0)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		_dragging = false
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			target_distance = clampf(target_distance - ZOOM_STEP, MIN_DISTANCE, MAX_DISTANCE)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			target_distance = clampf(target_distance + ZOOM_STEP, MIN_DISTANCE, MAX_DISTANCE)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		orbit(event.relative)
		get_viewport().set_input_as_handled()


## Applies a middle-drag mouse movement (pixels).
func orbit(relative: Vector2) -> void:
	var k := deg_to_rad(DRAG_DEGREES_PER_PIXEL) * sensitivity
	yaw -= relative.x * k
	pitch = clampf(pitch + relative.y * k, MIN_PITCH, MAX_PITCH)


func _process(delta: float) -> void:
	if input_enabled:
		var k := deg_to_rad(KEY_DEGREES_PER_SECOND) * delta
		yaw += (Input.get_action_strength("camera_left") - Input.get_action_strength("camera_right")) * k
		pitch = clampf(pitch + (Input.get_action_strength("camera_up") - Input.get_action_strength("camera_down")) * k,
				MIN_PITCH, MAX_PITCH)
	if not following or target == null:
		return
	_place(1.0 - exp(-SMOOTHING * delta))


func _place(t: float) -> void:
	focus = focus.lerp(_target_point(), t)
	distance = lerpf(distance, target_distance, t)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var d := distance
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(focus, focus + dir * distance, Layers.CAMERA_BLOCKERS)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var limit := maxf(focus.distance_to(hit.position) - 0.35, 1.2)
			# Pull in immediately; ease back out.
			_blocked_distance = limit if limit < _blocked_distance else lerpf(_blocked_distance, limit, t)
			d = minf(d, _blocked_distance)
		else:
			_blocked_distance = lerpf(minf(_blocked_distance, distance), distance, t) if _blocked_distance < distance else INF
			d = minf(d, _blocked_distance)
	global_position = focus
	camera.global_position = focus + dir * d
	camera.look_at(focus, Vector3.UP)
