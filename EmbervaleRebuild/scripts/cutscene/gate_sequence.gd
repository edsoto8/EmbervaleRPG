class_name GateSequence
extends Node
## The closing camera pan to the exit gate (7.2 s, skippable with the intro controls). Ends with the
## gameplay camera restored; the director then shows Tutorial Complete.

signal finished(skipped: bool)

const DURATION := 7.2

var time := 0.0
var done := false
var _world: World
var _keys: Array = []
var _layer: CanvasLayer
var _caption: Label


func play(world: World) -> void:
	_world = world
	GameManager.set_state(GameManager.State.CUTSCENE)
	if world.hud:
		world.hud.visible = false
	var cam := world.camera_rig.camera
	world.camera_rig.following = false
	var gate: Vector3 = world.island.landmarks.exit_gate
	var gate_top := Vector3(IslandLayout.GATE.x, 3.5, IslandLayout.GATE.y)
	_keys = [
		[0.0, cam.global_position, world.camera_rig.focus],
		[2.6, Vector3(10, 26, -8), Vector3(0, 2, -30)],
		[5.0, gate + Vector3(5, 6, 9), gate_top],
		[DURATION, gate + Vector3(-3, 4, 7), gate_top],
	]
	_layer = CanvasLayer.new()
	_layer.layer = 40
	add_child(_layer)
	_caption = UITheme.label("The road beyond Driftwood Isle awaits.", 24, UITheme.ACCENT)
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.position.y -= 90
	_caption.modulate.a = 0.0
	_layer.add_child(_caption)
	var skip := UITheme.button("Skip  ▸", func() -> void: _finish(true), 120)
	skip.name = "SkipButton"
	skip.focus_mode = Control.FOCUS_NONE
	skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.position -= Vector2(24, 24)
	_layer.add_child(skip)
	_update(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not done and event.is_action_pressed("skip"):
		get_viewport().set_input_as_handled()
		_finish(true)


func _process(delta: float) -> void:
	if done:
		return
	time += delta
	if time >= DURATION:
		_finish(false)
		return
	_update(time)


func _update(t: float) -> void:
	var i := 0
	while i < _keys.size() - 2 and t > _keys[i + 1][0]:
		i += 1
	var a: Array = _keys[i]
	var b: Array = _keys[i + 1]
	var f := smoothstep(0.0, 1.0, clampf((t - a[0]) / (b[0] - a[0]), 0.0, 1.0))
	var cam := _world.camera_rig.camera
	cam.global_position = (a[1] as Vector3).lerp(b[1], f)
	cam.look_at((a[2] as Vector3).lerp(b[2], f), Vector3.UP)
	_caption.modulate.a = smoothstep(2.4, 3.2, t) * (1.0 - smoothstep(6.6, 7.1, t))


func _finish(skipped: bool) -> void:
	if done:
		return
	done = true
	var rig := _world.camera_rig
	rig.following = true
	rig.snap()
	if _world.hud:
		_world.hud.visible = true
	GameManager.set_state(GameManager.State.PLAYING)
	if is_instance_valid(_layer):
		_layer.queue_free()
	finished.emit(skipped)
	queue_free()
