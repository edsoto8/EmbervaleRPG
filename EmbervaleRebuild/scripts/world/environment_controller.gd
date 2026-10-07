class_name EnvironmentController
extends Node3D
## Sky, sun, fill light, fog, post-processing and vignette for the island (root of environment.tscn).
## Applies the graphics quality preset (sun shadows, MSAA, bloom and grading, vignette and the wind
## shader globals) live whenever SettingsManager changes it. The Compatibility renderer has no
## screen-space AA, and turning sun shadows off darkens the scene, so Low keeps short shadows.

## Per-preset values (SPEC_GRAPHICS.md G8).
const PRESETS := [
	{"name": "Low", "shadow_distance": 30.0, "shadow_atlas": 2048, "shadow_blur": 0.0, "soft_quality": 0,
		"msaa": Viewport.MSAA_DISABLED, "bloom": false, "vignette": false, "wind": 1.0, "grass_only": 1.0},
	{"name": "Medium", "shadow_distance": 50.0, "shadow_atlas": 4096, "shadow_blur": 1.0, "soft_quality": 2,
		"msaa": Viewport.MSAA_2X, "bloom": true, "vignette": true, "wind": 1.0, "grass_only": 0.0},
	{"name": "High", "shadow_distance": 70.0, "shadow_atlas": 8192, "shadow_blur": 1.6, "soft_quality": 3,
		"msaa": Viewport.MSAA_4X, "bloom": true, "vignette": true, "wind": 1.0, "grass_only": 0.0},
]
const SUN_ELEVATION := 38.0
const SUN_AZIMUTH := -35.0
const HORIZON := Color("cfdbe2")

var world_env: WorldEnvironment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var env: Environment
var vignette: ColorRect
var quality := 1
## Current wind globals (mirrors the shader globals for inspection).
var wind_strength := 1.0
var wind_grass_only := 0.0


func _ready() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("4f86c6")
	sky_mat.sky_horizon_color = HORIZON
	sky_mat.ground_horizon_color = HORIZON
	sky_mat.ground_bottom_color = Color("3f6680")
	sky_mat.sun_angle_max = 18.0
	sky_mat.sky_curve = 0.12
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Cool sky/ground ambient fill so shadowed faces read clearly against warm lit ones.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c9d6e6")
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# Horizon haze in the sky's horizon colour, so sea and sky blend instead of meeting at a line.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = HORIZON
	env.fog_depth_begin = 60.0
	env.fog_depth_end = 380.0
	env.fog_depth_curve = 1.3
	env.fog_density = 0.9
	env.fog_sky_affect = 0.35
	env.glow_hdr_threshold = 0.95
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	env.adjustment_brightness = 1.0
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	# Warm late-afternoon key light.
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-SUN_ELEVATION), deg_to_rad(SUN_AZIMUTH), 0)
	sun.light_color = Color("ffe2b0")
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	# Cool fill from the opposite side, no shadows.
	fill = DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation = Vector3(deg_to_rad(-30.0), deg_to_rad(SUN_AZIMUTH + 180.0), 0)
	fill.light_color = Color("9fb6d8")
	fill.light_energy = 0.18
	fill.shadow_enabled = false
	add_child(fill)
	_build_vignette()
	SettingsManager.settings_changed.connect(_on_setting)
	apply_quality(SettingsManager.get_value("graphics_quality"))


func _exit_tree() -> void:
	if SettingsManager.settings_changed.is_connected(_on_setting):
		SettingsManager.settings_changed.disconnect(_on_setting)


func _build_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Vignette"
	layer.layer = 1
	add_child(layer)
	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/vignette.gdshader")
	vignette.material = mat
	layer.add_child(vignette)


func _on_setting(key: String, value: Variant) -> void:
	if key == "graphics_quality":
		apply_quality(value)


func apply_quality(level: int) -> void:
	quality = clampi(level, 0, PRESETS.size() - 1)
	var p: Dictionary = PRESETS[quality]
	sun.directional_shadow_max_distance = p.shadow_distance
	sun.shadow_blur = p.shadow_blur
	RenderingServer.directional_shadow_atlas_set_size(p.shadow_atlas, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(p.soft_quality)
	get_viewport().msaa_3d = p.msaa
	env.glow_enabled = p.bloom
	env.adjustment_enabled = p.bloom
	vignette.visible = p.vignette
	wind_strength = p.wind
	wind_grass_only = p.grass_only
	RenderingServer.global_shader_parameter_set("wind_strength", wind_strength)
	RenderingServer.global_shader_parameter_set("wind_grass_only", wind_grass_only)


func preset() -> Dictionary:
	return PRESETS[quality]
