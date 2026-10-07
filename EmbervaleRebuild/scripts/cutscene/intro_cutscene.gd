class_name IntroCutscene
extends Node
## The 14.6 s intro: the boat sails up to the dock with the player aboard (10.5 s), the player steps
## onto the dock at 11 s, the camera sweeps over the island and settles into the gameplay camera.
## Skip (button, Space, Esc, Enter) produces exactly the same final state as watching.

signal finished(skipped: bool)

const DURATION := 14.6
const BOAT_ARRIVAL := 10.5
const PLAYER_APPEARS := 11.0
const BOAT_START_Z := 118.0
const MESSAGES := [
	[0.6, 4.6, "Welcome, {name}.", "Every legend of Embervale began with a single voyage. Yours begins today."],
	[5.0, 9.3, "Driftwood Isle.", "A small island where new adventurers learn to find their way, speak with the locals and gather what they need."],
	[9.7, 14.2, "Your journey begins.", "Step onto the dock and explore. Move with WASD, or click where you want to go."],
]

var time := 0.0
var done := false
var shown_messages: Array[String] = []

var _world: World
var _boat: Boat
var _passenger: CharacterModel
var _layer: CanvasLayer
var _top_bar: ColorRect
var _bottom_bar: ColorRect
var _msg_panel: PanelContainer
var _msg_title: Label
var _msg_body: Label
var _skip_button: Button
var _flyover: Array = []
var _final_pos := Vector3.ZERO
var _final_focus := Vector3.ZERO


func play(world: World) -> void:
	_world = world
	_boat = world.island.boat
	GameManager.set_state(GameManager.State.CUTSCENE)
	world.camera_rig.following = false
	world.player.visible = false
	_boat.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_boat.bobbing = false
	_passenger = CharacterModel.new(GameManager.character.appearance)
	_passenger.name = "Passenger"
	_passenger.idle_glances = false
	_boat.add_child(_passenger)
	_passenger.position = Vector3(0, 0.48, 0.9)
	# Final gameplay camera (what CameraController.snap() will produce at the dock).
	_final_focus = world.island.landmarks["dock"] + Vector3(0, CameraController.FOCUS_HEIGHT, 0)
	var pitch := deg_to_rad(48.0)
	_final_pos = _final_focus + Vector3(0, sin(pitch), cos(pitch)) * 14.0
	_flyover = [
		[Vector3(-18, 20, 42), Vector3(0, 0, 20)],
		[Vector3(-34, 26, 4), Vector3(-20, 0, -10)],
		[Vector3(6, 30, -30), Vector3(18, 0, -8)],
		[Vector3(36, 22, 26), Vector3(10, 0, 30)],
	]
	_build_overlay()
	_update(0.0)


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 40
	add_child(_layer)
	_top_bar = ColorRect.new()
	_top_bar.color = Color.BLACK
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_layer.add_child(_top_bar)
	_bottom_bar = ColorRect.new()
	_bottom_bar.color = Color.BLACK
	_bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_layer.add_child(_bottom_bar)
	_msg_panel = UITheme.panel(16)
	_msg_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_msg_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_msg_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_msg_panel.position.y -= 110
	_msg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UITheme.vbox(6)
	_msg_panel.add_child(v)
	_msg_title = UITheme.label("", 30, UITheme.ACCENT)
	_msg_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_body = UITheme.wrapped("", 19, UITheme.TEXT, 560)
	_msg_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_msg_title)
	v.add_child(_msg_body)
	_msg_panel.modulate.a = 0.0
	_layer.add_child(_msg_panel)
	_skip_button = UITheme.button("Skip  ▸", skip, 120)
	_skip_button.name = "SkipButton"
	_skip_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_button.position -= Vector2(24, 24)
	_skip_button.focus_mode = Control.FOCUS_NONE
	_layer.add_child(_skip_button)


func _unhandled_input(event: InputEvent) -> void:
	if done:
		return
	if event.is_action_pressed("skip"):
		get_viewport().set_input_as_handled()
		skip()


func _process(delta: float) -> void:
	if done:
		return
	time += delta
	if time >= DURATION:
		_finish(false)
		return
	_update(time)


func _update(t: float) -> void:
	# Boat: decelerating approach to the mooring.
	var k := clampf(t / BOAT_ARRIVAL, 0.0, 1.0)
	var ease_k := 1.0 - pow(1.0 - k, 2.4)
	var z := lerpf(BOAT_START_Z, IslandLayout.BOAT.y, ease_k)
	_boat.position = Vector3(IslandLayout.BOAT.x, sin(t * 1.3) * 0.05, z)
	_boat.rotation.z = sin(t * 0.9) * 0.03
	if t >= PLAYER_APPEARS and _passenger.visible:
		_passenger.visible = false
		_world.player.visible = true
	_passenger.locomotion_speed = 0.0
	_update_camera(t)
	_update_overlay(t)


func _boat_focus(t: float) -> Vector3:
	var k := clampf(t / BOAT_ARRIVAL, 0.0, 1.0)
	var z := lerpf(BOAT_START_Z, IslandLayout.BOAT.y, 1.0 - pow(1.0 - k, 2.4))
	return Vector3(IslandLayout.BOAT.x, 1.4, z)


func _update_camera(t: float) -> void:
	var cam := _world.camera_rig.camera
	var pos: Vector3
	var look: Vector3
	if t < 4.5:
		var b := _boat_focus(t)
		var a := -0.9 + t * 0.12
		pos = b + Vector3(sin(a) * 13.0, 4.5 + t * 0.4, cos(a) * 13.0)
		look = b
	elif t < 10.5:
		var b0 := _boat_focus(4.5)
		var a0 := -0.9 + 4.5 * 0.12
		var points := [b0 + Vector3(sin(a0) * 13.0, 6.3, cos(a0) * 13.0)]
		var looks := [b0]
		for f in _flyover:
			points.append(f[0])
			looks.append(f[1])
		var u := (t - 4.5) / 6.0 * (points.size() - 1)
		var i := mini(int(u), points.size() - 2)
		var f := smoothstep(0.0, 1.0, u - i)
		pos = _catmull(points, i, f)
		look = (looks[i] as Vector3).lerp(looks[i + 1], f)
	else:
		var last: Array = _flyover[_flyover.size() - 1]
		var f := smoothstep(0.0, 1.0, (t - 10.5) / (DURATION - 10.5 - 0.4))
		pos = (last[0] as Vector3).lerp(_final_pos, f)
		look = (last[1] as Vector3).lerp(_final_focus, f)
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)


static func _catmull(p: Array, i: int, t: float) -> Vector3:
	var p0: Vector3 = p[maxi(i - 1, 0)]
	var p1: Vector3 = p[i]
	var p2: Vector3 = p[i + 1]
	var p3: Vector3 = p[mini(i + 2, p.size() - 1)]
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _update_overlay(t: float) -> void:
	var bar := 72.0 * smoothstep(0.0, 0.7, t) * (1.0 - smoothstep(DURATION - 0.8, DURATION - 0.1, t))
	_top_bar.offset_top = 0.0
	_top_bar.offset_bottom = bar
	_bottom_bar.offset_top = -bar
	_bottom_bar.offset_bottom = 0.0
	var alpha := 0.0
	for m in MESSAGES:
		if t >= m[0] and t < m[1]:
			var title: String = m[2].format({"name": GameManager.character.name})
			if _msg_title.text != title:
				_msg_title.text = title
				_msg_body.text = m[3]
				shown_messages.append(title)
			alpha = smoothstep(m[0], m[0] + 0.4, t) * (1.0 - smoothstep(m[1] - 0.4, m[1], t))
	_msg_panel.modulate.a = alpha


func skip() -> void:
	_finish(true)


## Puts everything in its final state exactly once: moored boat, player on the dock, gameplay camera,
## controls enabled, stage "island", saved once.
func _finish(skipped: bool) -> void:
	if done:
		return
	done = true
	_boat.position = Vector3(IslandLayout.BOAT.x, 0.0, IslandLayout.BOAT.y)
	_boat.rotation = Vector3.ZERO
	_boat.base_y = 0.0
	_boat.bobbing = true
	_boat.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	_boat.reset_physics_interpolation()
	if is_instance_valid(_passenger):
		_passenger.queue_free()
	var player := _world.player
	player.visible = true
	player.teleport(_world.island.landmarks["dock"], 0.0)
	var rig := _world.camera_rig
	rig.following = true
	rig.set_view(0.0, 48.0, 14.0)
	rig.snap()
	if is_instance_valid(_layer):
		_layer.queue_free()
	finished.emit(skipped)
	_world.intro_finished()
	queue_free()
