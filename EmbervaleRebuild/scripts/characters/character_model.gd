class_name CharacterModel
extends Node3D
## Procedural low-poly humanoid built from an appearance dictionary (see Appearance). Faces local -Z.
## Each body part is merged into one vertex-coloured mesh; tools (axe, rod, sword) stay separate so
## they can be shown and hidden. Animation is procedural: idle, walk/run blending and timed actions.

signal footstep(foot: int)
signal action_finished(action_name: String)
## The moment a swing lands (axe on wood, sword on dummy).
signal action_impact(action_name: String)

const WALK_SPEED := 3.4
const RUN_SPEED := 6.2
## Overall scale of the rig (about 1.8 m tall).
const RIG_SCALE := 0.9

var appearance: Dictionary = Appearance.defaults()
## Number of primitive meshes before merging (merged parts keep draw calls low).
var part_count := 0
## Movement speed the model animates for (m/s); set by the controller each frame.
var locomotion_speed := 0.0
var current_action := ""
## Looks around now and then while idle (Milestone 4 polish).
var idle_glances := true

var rig: Node3D
var hips: Node3D
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var hand_r: Node3D
var tools := {}

var _phase := 0.0
var _last_step_sign := 0.0
var _action_time := 0.0
var _action_duration := 0.0
var _blend := 0.0
var _glance_timer := 3.0
var _glance_target := 0.0
var _head_yaw := 0.0
var _target_yaw := 0.0
var _turning := false
var _time := 0.0
var _last_cycle := 0.0
var _rng := RandomNumberGenerator.new()


func _init(look: Dictionary = {}) -> void:
	if not look.is_empty():
		appearance = Appearance.sanitize(look)


func _ready() -> void:
	_rng.seed = get_instance_id()
	build(appearance)


func set_appearance(look: Dictionary) -> void:
	appearance = Appearance.sanitize(look)
	if is_inside_tree():
		build(appearance)


func build(look: Dictionary) -> void:
	for c in get_children():
		remove_child(c)
		c.free()
	tools.clear()
	part_count = 0
	var skin := Color(look.skin_tone)
	var hair := Color(look.hair_color)
	var shirt := Color(look.shirt_color)
	var pants := Color(look.pants_color)
	var bw: float = [0.86, 1.0, 1.2][look.body_type]
	var boot := Color("3d2b1f")

	rig = _pivot(self, "Rig", Vector3.ZERO)
	rig.scale = Vector3.ONE * RIG_SCALE
	hips = _pivot(rig, "Hips", Vector3(0, 0.92, 0))
	torso = _pivot(hips, "Torso", Vector3(0, 0.08, 0))
	_mesh(torso, PropFactory.box_mesh(Vector3(0.44 * bw, 0.2, 0.24)), pants, Vector3(0, -0.05, 0))
	_mesh(torso, PropFactory.box_mesh(Vector3(0.48 * bw, 0.56, 0.27)), shirt, Vector3(0, 0.3, 0))
	_mesh(torso, PropFactory.box_mesh(Vector3(0.5 * bw, 0.08, 0.29)), Color("4a3424"), Vector3(0, 0.06, 0))
	_mesh(torso, PropFactory.box_mesh(Vector3(0.09, 0.07, 0.03)), Color("c9a34a"), Vector3(0, 0.06, -0.15))
	_mesh(torso, PropFactory.box_mesh(Vector3(0.3 * bw, 0.06, 0.29)), shirt.darkened(0.15), Vector3(0, 0.57, 0))
	_mesh(torso, PropFactory.cylinder_mesh(0.07, 0.08, 0.12, 6), skin, Vector3(0, 0.64, 0))

	head = _pivot(torso, "Head", Vector3(0, 0.7, 0))
	_mesh(head, PropFactory.box_mesh(Vector3(0.3, 0.32, 0.3)), skin, Vector3(0, 0.16, 0))
	for sx in [-0.075, 0.075]:
		_mesh(head, PropFactory.box_mesh(Vector3(0.06, 0.06, 0.02)), Color("f4f1ea"), Vector3(sx, 0.19, -0.151))
		_mesh(head, PropFactory.box_mesh(Vector3(0.035, 0.045, 0.02)), Color("2a2420"), Vector3(sx, 0.185, -0.158))
		_mesh(head, PropFactory.box_mesh(Vector3(0.012, 0.012, 0.01)), Color("ffffff"), Vector3(sx + 0.008, 0.197, -0.169))
		_mesh(head, PropFactory.box_mesh(Vector3(0.08, 0.02, 0.02)), hair.darkened(0.2), Vector3(sx, 0.245, -0.155))
		_mesh(head, PropFactory.box_mesh(Vector3(0.03, 0.07, 0.06)), skin.darkened(0.05), Vector3(sx * 2.1, 0.16, 0))
	_mesh(head, PropFactory.box_mesh(Vector3(0.05, 0.07, 0.05)), skin.darkened(0.08), Vector3(0, 0.14, -0.165))
	_mesh(head, PropFactory.box_mesh(Vector3(0.1, 0.02, 0.02)), Color("8a4a3a"), Vector3(0, 0.075, -0.152))
	_build_hair(head, look.hair_style, hair)

	var shoulder_x := 0.24 * bw + 0.075
	arm_l = _pivot(torso, "ArmL", Vector3(-shoulder_x, 0.52, 0))
	arm_r = _pivot(torso, "ArmR", Vector3(shoulder_x, 0.52, 0))
	for arm in [arm_l, arm_r]:
		_mesh(arm, PropFactory.box_mesh(Vector3(0.14 * bw, 0.32, 0.15)), shirt, Vector3(0, -0.14, 0))
		_mesh(arm, PropFactory.box_mesh(Vector3(0.11, 0.28, 0.12)), skin, Vector3(0, -0.43, 0))
		_mesh(arm, PropFactory.box_mesh(Vector3(0.12, 0.11, 0.13)), skin.darkened(0.06), Vector3(0, -0.62, 0))
		_mesh(arm, PropFactory.box_mesh(Vector3(0.04, 0.07, 0.04)), skin.darkened(0.1), Vector3(0, -0.6, -0.08))
		_mesh(arm, PropFactory.box_mesh(Vector3(0.15 * bw, 0.05, 0.16)), shirt.darkened(0.12), Vector3(0, -0.29, 0))
	hand_r = _pivot(arm_r, "HandR", Vector3(0, -0.62, 0))

	leg_l = _pivot(hips, "LegL", Vector3(-0.12 * bw, 0.0, 0))
	leg_r = _pivot(hips, "LegR", Vector3(0.12 * bw, 0.0, 0))
	for leg in [leg_l, leg_r]:
		_mesh(leg, PropFactory.box_mesh(Vector3(0.17 * bw, 0.78, 0.2)), pants, Vector3(0, -0.4, 0))
		_mesh(leg, PropFactory.box_mesh(Vector3(0.19 * bw, 0.14, 0.3)), boot, Vector3(0, -0.84, -0.04))
		_mesh(leg, PropFactory.box_mesh(Vector3(0.2 * bw, 0.03, 0.31)), Color("1f1712"), Vector3(0, -0.905, -0.04))
		_mesh(leg, PropFactory.box_mesh(Vector3(0.2 * bw, 0.05, 0.22)), boot.lightened(0.12), Vector3(0, -0.76, 0))
		_mesh(leg, PropFactory.box_mesh(Vector3(0.18 * bw, 0.06, 0.06)), boot.darkened(0.15), Vector3(0, -0.86, -0.18))

	for part in [torso, head, arm_l, arm_r, leg_l, leg_r]:
		_merge_part(part)
	_build_tools()
	_apply_rim()


func _pivot(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n


func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	part_count += 1
	return PropFactory.add(parent, mesh, color, pos, rot)


func _build_hair(h: Node3D, style: int, c: Color) -> void:
	var shade := c.darkened(0.12)
	match style:
		1:
			_mesh(h, PropFactory.box_mesh(Vector3(0.34, 0.11, 0.34)), c, Vector3(0, 0.335, 0.0))
			_mesh(h, PropFactory.box_mesh(Vector3(0.34, 0.2, 0.09)), c, Vector3(0, 0.23, 0.13))
			_mesh(h, PropFactory.box_mesh(Vector3(0.3, 0.06, 0.06)), c, Vector3(0, 0.3, -0.15))
			for sx in [-0.16, 0.16]:
				_mesh(h, PropFactory.box_mesh(Vector3(0.04, 0.12, 0.2)), shade, Vector3(sx, 0.26, 0.04))
			_mesh(h, PropFactory.box_mesh(Vector3(0.2, 0.05, 0.2)), shade, Vector3(0.03, 0.4, 0.02))
		2:
			_mesh(h, PropFactory.box_mesh(Vector3(0.35, 0.12, 0.35)), c, Vector3(0, 0.335, 0.0))
			_mesh(h, PropFactory.box_mesh(Vector3(0.36, 0.5, 0.11)), c, Vector3(0, 0.1, 0.145))
			_mesh(h, PropFactory.box_mesh(Vector3(0.3, 0.2, 0.06)), shade, Vector3(0, -0.14, 0.17))
			for sx in [-0.165, 0.165]:
				_mesh(h, PropFactory.box_mesh(Vector3(0.05, 0.36, 0.26)), c, Vector3(sx, 0.16, 0.04))
			_mesh(h, PropFactory.box_mesh(Vector3(0.3, 0.06, 0.06)), shade, Vector3(0, 0.3, -0.155))
		3:
			_mesh(h, PropFactory.box_mesh(Vector3(0.34, 0.11, 0.34)), c, Vector3(0, 0.335, 0.0))
			_mesh(h, PropFactory.box_mesh(Vector3(0.34, 0.18, 0.09)), c, Vector3(0, 0.24, 0.13))
			_mesh(h, PropFactory.box_mesh(Vector3(0.06, 0.06, 0.06)), shade, Vector3(0, 0.26, 0.19))
			_mesh(h, PropFactory.box_mesh(Vector3(0.1, 0.34, 0.1)), c, Vector3(0, 0.08, 0.23), Vector3(0.35, 0, 0))
			for sx in [-0.16, 0.16]:
				_mesh(h, PropFactory.box_mesh(Vector3(0.04, 0.12, 0.18)), shade, Vector3(sx, 0.27, 0.05))
		4:
			_mesh(h, PropFactory.box_mesh(Vector3(0.09, 0.16, 0.34)), c, Vector3(0, 0.38, 0.0))
			for k in 3:
				_mesh(h, PropFactory.box_mesh(Vector3(0.07, 0.08, 0.08)), shade, Vector3(0, 0.48, -0.1 + k * 0.1))


func _merge_part(part: Node3D) -> void:
	# Merge only this part's own meshes (not child pivots).
	var holder := Node3D.new()
	holder.name = "Parts"
	part.add_child(holder)
	for c in part.get_children():
		if c is MeshInstance3D:
			c.reparent(holder, false)
	MeshMerger.merge(holder, [], 100.0, {"single": true, "name": "Mesh", "target": part})
	holder.queue_free()


func _build_tools() -> void:
	var wood := Color("7d5634")
	var steel := Color("b9c0c6")
	var axe := Node3D.new()
	axe.name = "Axe"
	hand_r.add_child(axe)
	_tool_mesh(axe, PropFactory.box_mesh(Vector3(0.05, 0.62, 0.05)), wood, Vector3(0, -0.2, 0))
	_tool_mesh(axe, PropFactory.box_mesh(Vector3(0.04, 0.16, 0.2)), steel, Vector3(0, -0.46, -0.1))
	axe.rotation.x = -PI * 0.5
	tools["axe"] = axe
	var rod := Node3D.new()
	rod.name = "Rod"
	hand_r.add_child(rod)
	_tool_mesh(rod, PropFactory.cylinder_mesh(0.012, 0.025, 1.8, 5), wood, Vector3(0, 0.8, 0))
	rod.rotation.x = -1.0
	tools["rod"] = rod
	var sword := Node3D.new()
	sword.name = "Sword"
	hand_r.add_child(sword)
	_tool_mesh(sword, PropFactory.box_mesh(Vector3(0.05, 0.7, 0.015)), steel, Vector3(0, 0.43, 0))
	_tool_mesh(sword, PropFactory.box_mesh(Vector3(0.22, 0.04, 0.05)), Color("c9a34a"), Vector3(0, 0.07, 0))
	_tool_mesh(sword, PropFactory.box_mesh(Vector3(0.04, 0.14, 0.04)), Color("4a3424"), Vector3(0, -0.02, 0))
	sword.rotation.x = -PI * 0.5
	tools["sword"] = sword
	var tinder := Node3D.new()
	tinder.name = "Tinderbox"
	_tool_mesh(tinder, PropFactory.box_mesh(Vector3(0.1, 0.06, 0.07)), Color("6e6a62"), Vector3.ZERO)
	hand_r.add_child(tinder)
	tools["tinderbox"] = tinder
	var food := Node3D.new()
	food.name = "Food"
	_tool_mesh(food, PropFactory.sphere_mesh(0.07, 6, 3), Color("d8955a"), Vector3.ZERO)
	hand_r.add_child(food)
	tools["food"] = food
	for t in tools.values():
		t.visible = false


func _tool_mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = PropFactory.character_mat(color)
	mi.position = pos
	parent.add_child(mi)


## Rim-lit materials: the merged body parts use the character vertex material.
func _apply_rim() -> void:
	for part in [torso, head, arm_l, arm_r, leg_l, leg_r]:
		for c in part.get_children():
			if c is MeshInstance3D:
				c.material_override = PropFactory.character_vertex_mat()


func show_tool(tool_name: String) -> void:
	for k in tools:
		tools[k].visible = k == tool_name


# --- facing --------------------------------------------------------------------------------------

## Turns smoothly towards a world point (yaw only).
func face_towards(point: Vector3) -> void:
	var d := point - global_position
	if Vector2(d.x, d.z).length() < 0.01:
		return
	_target_yaw = atan2(-d.x, -d.z)
	_turning = true


## Snaps to a yaw immediately.
func face_yaw(yaw: float) -> void:
	_turning = false
	_target_yaw = yaw
	global_rotation.y = yaw


func is_turning() -> bool:
	return _turning


# --- actions -------------------------------------------------------------------------------------

## Plays a timed animation ("chop", "fish", "attack", "light", "cook", "eat", "talk", "cheer").
## A positive duration stops it automatically; zero keeps it running until stop_action().
func play_action(action_name: String, duration: float = 0.0) -> void:
	current_action = action_name
	_action_time = 0.0
	_last_cycle = 0.0
	_action_duration = duration
	match action_name:
		"chop":
			show_tool("axe")
		"fish":
			show_tool("rod")
		"attack":
			show_tool("sword")
		"light":
			show_tool("tinderbox")
		"eat":
			show_tool("food")
		_:
			show_tool("")


func stop_action() -> void:
	if current_action == "":
		return
	var was := current_action
	current_action = ""
	show_tool("")
	action_finished.emit(was)


func _physics_process(delta: float) -> void:
	_time += delta
	if _turning:
		var cur := global_rotation.y
		var diff := wrapf(_target_yaw - cur, -PI, PI)
		if absf(diff) < 0.01:
			global_rotation.y = _target_yaw
			_turning = false
		else:
			global_rotation.y = cur + diff * minf(12.0 * delta, 1.0)
	if current_action != "":
		_action_time += delta
		if _action_duration > 0.0 and _action_time >= _action_duration:
			stop_action()
	_animate(delta)


func _animate(delta: float) -> void:
	var speed := locomotion_speed
	var target_blend := clampf(speed / WALK_SPEED, 0.0, 1.0)
	_blend = lerpf(_blend, target_blend, minf(10.0 * delta, 1.0))
	var run := clampf((speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)
	_phase += delta * (speed * 2.15 if speed > 0.05 else 0.0)
	var swing := sin(_phase)
	var amp := lerpf(0.55, 0.85, run) * _blend
	leg_l.rotation.x = swing * amp
	leg_r.rotation.x = -swing * amp
	var arm_amp := lerpf(0.45, 0.8, run) * _blend
	arm_l.rotation = Vector3(-swing * arm_amp, 0, -0.06)
	arm_r.rotation = Vector3(swing * arm_amp, 0, 0.06)
	hips.position.y = 0.92 + absf(cos(_phase)) * 0.04 * _blend - 0.02 * _blend
	torso.rotation.x = -0.12 * run * _blend
	var breathe := sin(_time * 1.9) * 0.012 * (1.0 - _blend)
	torso.scale = Vector3(1.0 + breathe * 0.5, 1.0 + breathe, 1.0)
	# Footsteps when a foot passes the bottom of its stride.
	var s := signf(swing)
	if _blend > 0.3 and s != _last_step_sign and s != 0.0:
		footstep.emit(0 if s > 0.0 else 1)
	_last_step_sign = s
	# Idle head glances.
	if idle_glances and _blend < 0.1 and current_action == "":
		_glance_timer -= delta
		if _glance_timer <= 0.0:
			# Alternate between a glance to one side and looking ahead again.
			_glance_timer = _rng.randf_range(2.0, 4.5)
			if absf(_glance_target) > 0.01:
				_glance_target = 0.0
			else:
				_glance_target = _rng.randf_range(0.25, 0.6) * (1.0 if _rng.randf() < 0.5 else -1.0)
	else:
		_glance_target = 0.0
	_head_yaw = lerpf(_head_yaw, _glance_target, minf(4.0 * delta, 1.0))
	head.rotation = Vector3(0, _head_yaw, 0)
	if current_action != "":
		_animate_action()


func _impact_at(cycle: float, at: float) -> void:
	if _last_cycle < at and cycle >= at:
		action_impact.emit(current_action)
	_last_cycle = cycle


func _animate_action() -> void:
	var t := _action_time
	match current_action:
		"chop":
			var cyc := fmod(t, 1.0)
			_impact_at(cyc, 0.62)
			var raise := sin(cyc * TAU * 0.5)
			arm_r.rotation = Vector3(-2.4 + 1.9 * (1.0 - raise) if cyc > 0.55 else -0.6 - 1.8 * smoothstep(0.0, 0.55, cyc), 0, 0.15)
			arm_l.rotation = Vector3(arm_r.rotation.x * 0.8, 0, -0.25)
			torso.rotation.y = -0.2
		"attack":
			var cyc := fmod(t, 1.2) / 1.2
			_impact_at(cyc, 0.55)
			arm_r.rotation = Vector3(-2.2 + 2.6 * smoothstep(0.45, 0.65, cyc) if cyc > 0.45 else -0.4 - 1.8 * smoothstep(0.0, 0.45, cyc), 0, 0.2)
			arm_l.rotation = Vector3(-0.4, 0, -0.2)
			torso.rotation.y = -0.25 + 0.4 * smoothstep(0.45, 0.65, cyc)
		"fish":
			arm_r.rotation = Vector3(-0.9 + sin(t * 1.3) * 0.08, 0, 0.1)
			arm_l.rotation = Vector3(-0.7, 0, -0.1)
		"light", "cook":
			hips.position.y = 0.62
			leg_l.rotation.x = -1.2
			leg_r.rotation.x = 0.4
			arm_r.rotation = Vector3(-0.9 + sin(t * 9.0) * 0.15, 0, 0.1)
			arm_l.rotation = Vector3(-0.8, 0, -0.1)
			torso.rotation.x = 0.25
		"eat":
			arm_r.rotation = Vector3(-2.0 + sin(t * 8.0) * 0.12, 0, 0.35)
		"talk":
			arm_r.rotation = Vector3(-0.5 + sin(t * 3.1) * 0.25, 0, 0.25 + sin(t * 2.3) * 0.1)
			arm_l.rotation = Vector3(-0.2 + sin(t * 2.6 + 1.0) * 0.15, 0, -0.15)
			head.rotation.x = sin(t * 4.0) * 0.06
		"cheer":
			var bounce := absf(sin(t * 7.0))
			arm_r.rotation = Vector3(-2.8 + bounce * 0.3, 0, 0.3)
			arm_l.rotation = Vector3(-2.8 + bounce * 0.3, 0, -0.3)
			hips.position.y = 0.92 + bounce * 0.08
