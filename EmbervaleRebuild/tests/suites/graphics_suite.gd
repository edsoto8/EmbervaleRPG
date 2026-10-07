extends TestSuite
## Milestone 5: quality presets (live and persisted), water depth bake, wind weights after batching,
## terrain shading, the richer character model and the new ground cover.


func before_each() -> void:
	await reset_game()
	wipe_saves()
	SettingsManager.load_settings()


func after_each() -> void:
	SettingsManager.set_value("graphics_quality", 1)
	await reset_game()


func _env(w: World) -> EnvironmentController:
	return w.get_node("Environment") as EnvironmentController


func test_presets_apply_live() -> void:
	var w := await load_world()
	var env := _env(w)
	var expect := [
		[30.0, Viewport.MSAA_DISABLED, false, false, 45.0, 0.4, 1.0],
		[50.0, Viewport.MSAA_2X, true, true, 75.0, 1.0, 0.0],
		[70.0, Viewport.MSAA_4X, true, true, 100.0, 1.0, 0.0],
	]
	for q in 3:
		SettingsManager.set_value("graphics_quality", q)
		await frames(1)
		var e: Array = expect[q]
		var label: String = SettingsManager.QUALITY_NAMES[q]
		check_near(env.sun.directional_shadow_max_distance, e[0], 0.01, "%s shadow distance" % label)
		check(env.sun.shadow_enabled, "%s keeps sun shadows" % label)
		check_eq(get_viewport().msaa_3d, e[1], "%s MSAA" % label)
		check_eq(env.env.glow_enabled, e[2], "%s bloom" % label)
		check_eq(env.env.adjustment_enabled, e[2], "%s grading" % label)
		check_eq(env.vignette.visible, e[3], "%s vignette" % label)
		check_near(w.island.decor_chunks[0].visibility_range_end, e[4], 0.01, "%s small decor fade" % label)
		check_near(w.island.grass_density(), e[5], 0.08, "%s grass density" % label)
		check_near(env.wind_grass_only, e[6], 0.01, "%s wind scope" % label)
		check(env.wind_strength > 0.0, "%s wind on" % label)
	await free_world()


func test_preset_persists_and_panel() -> void:
	SettingsManager.set_value("graphics_quality", 2)
	var data: Variant = read_json(AppPaths.settings_path())
	check(data is Dictionary and data.graphics_quality == 2, "quality saved with the other settings")
	SettingsManager.values.graphics_quality = 0
	SettingsManager.load_settings()
	check_eq(SettingsManager.get_value("graphics_quality"), 2, "quality restored on restart")
	var panel := SettingsPanel.show_panel()
	await frames(2)
	check_eq(panel.quality.selected, 2, "panel shows the current preset")
	panel.quality.select(0)
	panel.quality.item_selected.emit(0)
	check_eq(SettingsManager.get_value("graphics_quality"), 0, "choosing Low in Settings applies it")
	panel.close()
	SettingsManager.reset_to_defaults()
	check_eq(SettingsManager.get_value("graphics_quality"), 1, "default is Medium")


func test_water_depth_bake() -> void:
	var w := await load_world()
	var isl := w.island
	var sea_rect := Rect2(-64, -64, 128, 128)
	var shore := isl.baked_depth(isl.sea_depth_image, sea_rect, 4.0, 47.5)
	var offshore := isl.baked_depth(isl.sea_depth_image, sea_rect, 4.0, 62.0)
	var land := isl.baked_depth(isl.sea_depth_image, sea_rect, 0.0, 18.0)
	check(shore >= -0.1 and shore < 1.0, "shallow near the shore (%.2f m)" % shore)
	check(offshore > 2.0, "deep offshore (%.2f m)" % offshore)
	check(land < 0.0, "negative over land (%.2f m)" % land)
	var pond_rect := Rect2(IslandLayout.POND.x - 8, IslandLayout.POND.y - 8, 16, 16)
	var centre := isl.baked_depth(isl.pond_depth_image, pond_rect, IslandLayout.POND.x, IslandLayout.POND.y)
	var edge := isl.baked_depth(isl.pond_depth_image, pond_rect, IslandLayout.POND.x, IslandLayout.POND.y + 6.3)
	check(centre > 0.6 and edge < centre, "pond deep in the middle (%.2f), shallow at the edge (%.2f)" % [centre, edge])
	var mat: ShaderMaterial = isl.sea.material_override
	check(mat.get_shader_parameter("has_depth") and mat.get_shader_parameter("post_count") > 0, "depth and post foam wired")
	await free_world()


func _alphas(mi: MeshInstance3D) -> Array:
	var arr := mi.mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var lo := 1.0
	var hi := 0.0
	var distinct := {}
	for c in colors:
		lo = minf(lo, c.a)
		hi = maxf(hi, c.a)
		distinct[snappedf(c.a, 0.05)] = true
	return [lo, hi, distinct.size()]


func test_wind_weights_survive_batching() -> void:
	var w := await load_world()
	var props_sway := false
	var props_rigid := false
	for c in w.island.get_node("Batches").get_children():
		if c.name.begins_with("Props"):
			var a := _alphas(c)
			props_sway = props_sway or a[0] < 0.9
			props_rigid = props_rigid or a[1] >= 0.999
	check(props_sway and props_rigid, "batched props keep plant sway weights and rigid trunks")
	var grass := _alphas(w.island.grass_core_chunks[0])
	check(grass[0] < 0.1 and grass[1] > 0.9, "grass blades are anchored: still at the root, full sway at the tip")
	var grass_mat: ShaderMaterial = w.island.grass_core_chunks[0].material_override
	check(grass_mat.get_shader_parameter("is_grass"), "grass chunks flagged for grass-only wind")
	await free_world()


func test_terrain_shading() -> void:
	var w := await load_world()
	var t := w.island.terrain
	var wet := Color.BLACK
	var dry := Color.BLACK
	for j in range(100, 120):
		var i := 68
		if t.tiles[j * IslandTerrain.SIZE + i] == IslandTerrain.Tile.SAND:
			var h := t.height_at(i - 64 + 0.5, j - 64 + 0.5)
			if h < 0.18 and wet == Color.BLACK:
				wet = t.tile_color(i, j)
			elif h > 0.25 and dry == Color.BLACK:
				dry = t.tile_color(i, j)
	check(wet != Color.BLACK and dry != Color.BLACK, "found wet and dry sand")
	check(wet.get_luminance() < dry.get_luminance(), "wet sand band is darker")
	var soft := t.soft_colors()
	var softened := 0
	for idx in soft.size():
		var i := idx % IslandTerrain.SIZE
		var j := idx / IslandTerrain.SIZE
		if t._tile_in_mesh(i, j) and not soft[idx].is_equal_approx(t.tile_color(i, j)):
			softened += 1
	check(softened > 200, "transitions softened (%d tiles)" % softened)
	await free_world()


func test_richer_character_model() -> void:
	var m := CharacterModel.new(Appearance.defaults())
	get_tree().root.add_child(m)
	await frames(1)
	check(m.part_count >= 42, "detailed model (%d parts before merging)" % m.part_count)
	var mesh_count := 0
	for part in [m.torso, m.head, m.arm_l, m.arm_r, m.leg_l, m.leg_r]:
		for c in part.get_children():
			if c is MeshInstance3D:
				mesh_count += 1
				var mat: ShaderMaterial = c.material_override
				check(mat.get_shader_parameter("rim_strength") > 0.0, "rim light on %s" % part.name)
	check_eq(mesh_count, 6, "body parts still merged to one mesh each")
	for style in 5:
		var look := Appearance.defaults()
		look.hair_style = style
		m.set_appearance(look)
		await frames(1)
		check(m.head.get_child_count() > 0, "hair style %d builds" % style)
	m.queue_free()


func test_new_ground_cover() -> void:
	var w := await load_world()
	var c := w.island.cover_counts
	for kind in ["fern", "mushroom", "tall_grass", "flower"]:
		check(c[kind] >= 5, "%s placed (%d)" % [kind, c[kind]])
	check(c.lily_pad >= 10 and c.cattail >= 5, "lily pads (%d) and cattails (%d) on the pond" % [c.lily_pad, c.cattail])
	check(c.border_stone >= 40, "border stones along the paths (%d)" % c.border_stone)
	check(c.wood_pile == 2 and c.bucket == 1, "wood piles and a bucket")
	check(w.island.get_node_or_null("_decor") == null, "all cover batched (source nodes freed)")
	await free_world()


func test_lanterns_glow() -> void:
	var w := await load_world()
	check_eq(w.island.lantern_meshes.size(), w.island.lamp_positions.size(), "every lamp has a lantern")
	var mat: StandardMaterial3D = w.island.lantern_meshes[0].material_override
	check(mat.emission_enabled and mat.emission_energy_multiplier > 1.0, "lanterns are emissive for bloom")
	await free_world()
