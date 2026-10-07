class_name InteractionSystem
extends Node
## Hover text and hand cursor over interactables, click-to-walk-then-interact, and E for the nearest
## object in reach (no auto-walk). Interactables implement interaction_verb/name/range/position() and
## interact(player), and join the "interactable" group. Results are Variants, so type them explicitly.

signal hover_changed(target: Node)
signal interaction_started(target: Node)

const E_EXTRA_RANGE := 1.0
const REACH_SLACK := 0.35

var world: World
var player: PlayerController
var hovered: Node = null
## Last mouse position seen in a motion/button event (viewport coordinates).
var mouse_position := Vector2(-1, -1)


func setup(w: World) -> void:
	world = w
	player = w.player
	player.nav.object_clicked.connect(_on_object_clicked)


## The interactable owning a collider (an Area3D or body child resolves to its parent).
static func interactable_from(node: Object) -> Node:
	var n := node as Node
	while n != null:
		if n.is_in_group("interactable"):
			return n
		n = n.get_parent()
	return null


func _input_allowed() -> bool:
	return world != null and world.gameplay_enabled and not GameManager.is_modal_open() \
			and GameManager.state == GameManager.State.PLAYING


func _process(_delta: float) -> void:
	var target: Node = null
	if _input_allowed() and get_viewport().gui_get_hovered_control() == null and mouse_position.x >= 0.0:
		var hit := player.nav.pick(mouse_position)
		if not hit.is_empty():
			target = interactable_from(hit.collider)
			if target != null and not target.is_available():
				target = null
	if target != hovered:
		hovered = target
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if target else Input.CURSOR_ARROW)
		hover_changed.emit(target)


func hover_text(target: Node) -> String:
	if target == null:
		return ""
	return "%s %s" % [target.interaction_verb(), target.interaction_name()]


func _on_object_clicked(collider: Object, point: Vector3) -> void:
	var target := interactable_from(collider)
	if target == null:
		player.cancel_action("clicked")
		player.nav.walk_to(point)
		return
	use_target(target)


## Walks within range of a target, then uses it once. Returns false if it can't be reached.
func use_target(target: Node) -> bool:
	player.cancel_action("new_interaction")
	player.nav.cancel("new_interaction")
	var pos: Vector3 = target.interaction_position()
	var reach: float = target.interaction_range()
	if _flat(player.global_position, pos) <= reach:
		_interact(target)
		return true
	var goal: Vector3 = target.approach_position() if target.has_method("approach_position") else pos
	var ok := player.nav.approach(pos, maxf(reach - 0.15, 0.3), func() -> void: _arrive(target), goal)
	if not ok:
		GameManager.post_message("You can't reach that.")
	return ok


func _arrive(target: Node) -> void:
	if not is_instance_valid(target):
		return
	var pos: Vector3 = target.interaction_position()
	var reach: float = target.interaction_range()
	if _flat(player.global_position, pos) > reach + REACH_SLACK:
		GameManager.post_message("You can't reach that.")
		return
	_interact(target)


func _interact(target: Node) -> void:
	if not target.is_available():
		target.interact(player)
		return
	var pos: Vector3 = target.interaction_position()
	player.model.face_towards(pos)
	interaction_started.emit(target)
	target.interact(player)


## The nearest available interactable within its range + 1 m.
func nearest() -> Node:
	var best: Node = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("interactable"):
		if not n.is_available():
			continue
		var pos: Vector3 = n.interaction_position()
		var reach: float = n.interaction_range()
		var d := _flat(player.global_position, pos)
		if d <= reach + E_EXTRA_RANGE and d < best_d:
			best = n
			best_d = d
	return best


func interact_nearest() -> bool:
	var target := nearest()
	if target == null:
		GameManager.post_message("There's nothing to use nearby.")
		return false
	player.nav.cancel("interact")
	player.cancel_action("new_interaction")
	_interact(target)
	return true


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		mouse_position = event.position


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not event.is_echo() and _input_allowed():
		get_viewport().set_input_as_handled()
		interact_nearest()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
