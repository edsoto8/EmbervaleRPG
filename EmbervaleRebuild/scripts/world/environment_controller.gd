class_name EnvironmentController
extends Node3D
## Sky, sun, fog and post-processing for the island (root of environment.tscn). Milestone 5 extends it
## with graphics quality presets.

var world_env: WorldEnvironment
var sun: DirectionalLight3D
var env: Environment


func _ready() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("5d8fc9")
	sky_mat.sky_horizon_color = Color("bcd3e6")
	sky_mat.ground_horizon_color = Color("bcd3e6")
	sky_mat.ground_bottom_color = Color("4a6a80")
	sky_mat.sun_angle_max = 20.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d4dbe3")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("c9d6e0")
	env.fog_depth_begin = 70.0
	env.fog_depth_end = 420.0
	env.fog_depth_curve = 1.4
	env.fog_density = 0.85
	env.fog_sky_affect = 0.0
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(-35.0), 0)
	sun.light_color = Color("fff1d6")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 50.0
	add_child(sun)
