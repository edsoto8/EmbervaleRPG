class_name NavigationController
extends Node
## Click-to-move: projects a click onto walkable ground, queries a navmesh path and steers the player
## along it. Also carries the "walk there, then interact" pending target used by InteractionSystem.
## Presentation (ClickMarker) only listens to these signals.

signal destination_set(point: Vector3)
signal destination_reached(point: Vector3, by_click: bool)
signal navigation_cancelled(reason: String)
signal click_rejected(point: Vector3, reason: String)
## A click landed on something interactable (resolved by InteractionSystem).
signal object_clicked(collider: Object, point: Vector3)

const WAYPOINT_TOLERANCE := 0.35
const ARRIVAL_TOLERANCE := 0.3
const MAX_PROJECTION := 3.0
const STUCK_TIMEOUT := 1.25
const RAY_LENGTH := 400.0

var player: PlayerController
var island: TutorialIsland
var camera: Camera3D
var input_enabled := true
## True while the active route was started by a ground click (not an interaction approach).
var from_click := false

var _path := PackedVector3Array()
var _index := 0
var _active := false
var _arrival := ARRIVAL_TOLERANCE
var _destination := Vector3.ZERO
var _best := INF
var _stuck := 0.0
## Callable invoked when the route ends at its destination (pending interaction), else empty.
var _on_arrive := Callable()
## For interaction approaches: arrive as soon as the player is within `_reach` of this point.
var _reach_target := Vector3.INF
var _reach := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		handle_click(event.position)


## Ray-casts a screen point against ground, obstacles and interactables.
func pick(screen_pos: Vector2) -> Dictionary:
	if camera == null:
		return {}
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * RAY_LENGTH
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.CLICKABLE)
	q.collide_with_areas = true
	return player.get_world_3d().direct_space_state.intersect_ray(q)


func handle_click(screen_pos: Vector2) -> void:
	var hit := pick(screen_pos)
	if hit.is_empty():
		click_rejected.emit(Vector3.INF, "nothing")
		return
	var collider: Object = hit.collider
	if collider is CollisionObject3D and (collider.collision_layer & Layers.INTERACTABLES) != 0:
		object_clicked.emit(collider, hit.position)
		return
	if object_clicked.get_connections().size() > 0 and collider is Node and _interactable_ancestor(collider):
		object_clicked.emit(collider, hit.position)
		return
	player.cancel_action("clicked")
	if walk_to(hit.position):
		from_click = true


func _interactable_ancestor(n: Node) -> bool:
	while n != null:
		if n.is_in_group("interactable"):
			return true
		n = n.get_parent()
	return false


## Starts walking to the closest walkable point. Returns false (and posts click_rejected) when the
## point is too far from walkable ground or unreachable.
func walk_to(point: Vector3, arrival: float = ARRIVAL_TOLERANCE, on_arrive: Callable = Callable()) -> bool:
	if island == null or not island.is_navigation_ready:
		click_rejected.emit(point, "not_ready")
		return false
	var map := island.navigation_map()
	var closest := NavigationServer3D.map_get_closest_point(map, point)
	if closest.distance_to(point) > MAX_PROJECTION:
		click_rejected.emit(point, "unwalkable")
		return false
	var path := NavigationServer3D.map_get_path(map, player.global_position, closest, true)
	if path.size() < 2:
		if path.size() == 1 or player.global_position.distance_to(closest) <= arrival:
			_finish_immediately(closest, on_arrive)
			return true
		click_rejected.emit(point, "unreachable")
		return false
	if _flat(path[path.size() - 1], closest) > maxf(arrival, 0.6) + 0.4:
		click_rejected.emit(point, "unreachable")
		return false
	cancel("replaced")
	_path = path
	_index = 1
	_active = true
	from_click = false
	_reach_target = Vector3.INF
	_arrival = arrival
	_destination = closest
	_best = INF
	_stuck = 0.0
	_on_arrive = on_arrive
	destination_set.emit(closest)
	return true


func _finish_immediately(point: Vector3, on_arrive: Callable) -> void:
	cancel("replaced")
	_destination = point
	destination_reached.emit(point, false)
	if on_arrive.is_valid():
		on_arrive.call()


## Approaches a point and calls `on_arrive` once within `reach` metres of it (pending interaction).
## The route heads for the closest walkable point; arrival is measured to the target itself.
func approach(point: Vector3, reach: float, on_arrive: Callable, goal: Vector3 = Vector3.INF) -> bool:
	if _flat(player.global_position, point) <= reach:
		_finish_immediately(point, on_arrive)
		return true
	var dest := goal if goal != Vector3.INF else point
	if not walk_to(dest, ARRIVAL_TOLERANCE, on_arrive):
		return false
	_reach_target = point
	_reach = reach
	return true


func cancel(reason: String = "") -> void:
	var was_active := _active or _on_arrive.is_valid()
	_active = false
	_path = PackedVector3Array()
	_on_arrive = Callable()
	from_click = false
	_reach_target = Vector3.INF
	if was_active:
		navigation_cancelled.emit(reason)


func is_active() -> bool:
	return _active


func has_pending() -> bool:
	return _on_arrive.is_valid()


func destination() -> Vector3:
	return _destination


## Desired velocity towards the next waypoint; finishes the route on arrival.
func steer(pos: Vector3, speed: float, delta: float) -> Vector3:
	while _index < _path.size():
		var last := _index == _path.size() - 1
		var tol := _arrival if last else WAYPOINT_TOLERANCE
		if _flat(pos, _path[_index]) <= tol:
			_index += 1
			_best = INF
			_stuck = 0.0
		else:
			break
	if _index >= _path.size() or _flat(pos, _destination) <= _arrival \
			or (_reach_target != Vector3.INF and _flat(pos, _reach_target) <= _reach):
		_arrive()
		return Vector3.ZERO
	var wp := _path[_index]
	var d := _flat(pos, wp)
	if d < _best - 0.03:
		_best = d
		_stuck = 0.0
	else:
		_stuck += delta
		if _stuck > STUCK_TIMEOUT:
			if _on_arrive.is_valid():
				GameManager.post_message("You can't reach that.")
			cancel("stuck")
			return Vector3.ZERO
	var dir := Vector3(wp.x - pos.x, 0, wp.z - pos.z).normalized()
	var remaining := _flat(pos, _destination)
	var brake := sqrt(2.0 * PlayerController.ACCELERATION * maxf(remaining - _arrival * 0.5, 0.0))
	return dir * minf(speed, maxf(brake, 1.2))


func _arrive() -> void:
	_active = false
	_reach_target = Vector3.INF
	var cb := _on_arrive
	_on_arrive = Callable()
	var by_click := from_click
	from_click = false
	destination_reached.emit(_destination, by_click)
	if cb.is_valid():
		cb.call()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
