class_name AmbientLife
extends Node3D
## Moving scenery, created after the island's batching so it stays independent: clouds circling the
## island (one merged mesh), gulls wheeling over the coast and smoke from the cottage chimneys.

const CLOUD_SPEED := 0.012
const GULL_COUNT := 3

var clouds: Node3D
var gulls: Array[Node3D] = []
var smoke: Array[CPUParticles3D] = []
var _time := 0.0
var _gull_params: Array = []


func setup(island: TutorialIsland) -> void:
	name = "AmbientLife"
	_build_clouds()
	_build_gulls()
	_build_smoke(island.chimney_tops)


func _build_clouds() -> void:
	clouds = Node3D.new()
	clouds.name = "Clouds"
	add_child(clouds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var parts := Node3D.new()
	clouds.add_child(parts)
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf() * 0.3
		var r := rng.randf_range(70.0, 110.0)
		var base := Vector3(cos(a) * r, rng.randf_range(34.0, 46.0), sin(a) * r)
		for q in rng.randi_range(3, 5):
			var off := Vector3(rng.randf_range(-6, 6), rng.randf_range(-1, 1.5), rng.randf_range(-3, 3))
			var size := rng.randf_range(3.0, 5.5)
			PropFactory.sphere(parts, size, base + off, Color("f4f6f8"), Vector3(1.4, 0.6, 1.0), 7, 4)
	var merged := MeshMerger.merge(parts, [], 1000.0, {"single": true, "name": "CloudMesh", "target": clouds, "cast_shadow": false})
	parts.queue_free()
	for m in merged:
		(m as MeshInstance3D).material_override = _cloud_material()


func _cloud_material() -> Material:
	var m := ShaderMaterial.new()
	m.shader = PropFactory.SHADER
	m.set_shader_parameter("use_vertex_color", true)
	return m


func _build_gulls() -> void:
	var mat := PropFactory.character_mat(Color("f2f2ee"))
	var tip := PropFactory.character_mat(Color("3a3a3a"))
	for k in GULL_COUNT:
		var g := Node3D.new()
		g.name = "Gull%d" % k
		add_child(g)
		var body := MeshInstance3D.new()
		body.mesh = PropFactory.box_mesh(Vector3(0.18, 0.14, 0.5))
		body.material_override = mat
		g.add_child(body)
		for side in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.name = "WingL" if side < 0 else "WingR"
			g.add_child(pivot)
			var wing := MeshInstance3D.new()
			wing.mesh = PropFactory.box_mesh(Vector3(0.65, 0.03, 0.24))
			wing.material_override = mat
			wing.position.x = side * 0.36
			pivot.add_child(wing)
			var wtip := MeshInstance3D.new()
			wtip.mesh = PropFactory.box_mesh(Vector3(0.2, 0.031, 0.2))
			wtip.material_override = tip
			wtip.position.x = side * 0.62
			pivot.add_child(wtip)
		for c in g.find_children("*", "MeshInstance3D", true, false):
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gulls.append(g)
		# Centre, radius, height, speed, phase.
		_gull_params.append([Vector2([-6.0, 10.0, 0.0][k], [38.0, -30.0, 6.0][k]), [16.0, 13.0, 30.0][k],
				[14.0, 17.0, 22.0][k], [0.32, -0.27, 0.18][k], k * 2.1])


func _build_smoke(tops: Array[Vector3]) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.7, 0.7)
	mesh.material = mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.85, 0.85, 0.55))
	ramp.set_color(1, Color(0.95, 0.95, 0.95, 0.0))
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 1.8))
	for t in tops:
		var p := CPUParticles3D.new()
		p.name = "ChimneySmoke"
		p.mesh = mesh
		p.amount = 10
		p.lifetime = 4.0
		p.preprocess = 4.0
		p.direction = Vector3(0.25, 1, 0.1)
		p.spread = 12.0
		p.initial_velocity_min = 0.5
		p.initial_velocity_max = 0.8
		p.gravity = Vector3(0.12, 0.08, 0.03)
		p.scale_amount_curve = grow
		p.color_ramp = ramp
		p.position = t
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		smoke.append(p)


func _physics_process(delta: float) -> void:
	_time += delta
	clouds.rotation.y = _time * CLOUD_SPEED
	for k in gulls.size():
		var prm: Array = _gull_params[k]
		var a: float = _time * prm[3] + prm[4]
		var c: Vector2 = prm[0]
		var r: float = prm[1]
		var g := gulls[k]
		var pos := Vector3(c.x + cos(a) * r, prm[2] + sin(_time * 0.7 + k) * 1.2, c.y + sin(a) * r)
		var dir := Vector3(-sin(a), 0, cos(a)) * signf(prm[3])
		g.position = pos
		g.look_at(pos + dir, Vector3.UP)
		g.rotation.z = -0.25 * signf(prm[3])
		var flap := sin(_time * 7.0 + k) * 0.5 if fmod(_time + k * 1.3, 5.0) < 2.2 else 0.08
		g.get_node("WingL").rotation.z = -flap
		g.get_node("WingR").rotation.z = flap
