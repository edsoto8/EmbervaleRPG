extends Node
## Visual check: drives the real game flow and saves screenshots of each stage.
## godot --path . --rendering-driver opengl3 --fixed-fps 60 res://tests/capture_screenshots.tscn -- <out_dir>

var out_dir := "user://screenshots"
var shots: Array[String] = []


func _ready() -> void:
	get_tree().current_scene = null
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	GameManager.quit_handler = func() -> void: pass
	await run()
	print("saved %d screenshots to %s" % [shots.size(), out_dir])
	get_tree().quit()


func run() -> void:
	GameManager.go_to_main_menu()
	await _wait_scene("MainMenu")
	await _frames(40)
	await shot("01_main_menu")
	SettingsPanel.show_panel()
	await _frames(5)
	await shot("02_settings")
	get_tree().get_first_node_in_group("modal_panel").close()
	GameManager.start_new_game()
	var cc: CharacterCreation = await _wait_scene("CharacterCreation")
	cc.name_edit.text = "Rowan"
	cc.name_edit.text_changed.emit("Rowan")
	await _frames(30)
	await shot("03_character_creation")
	cc.appearance = {"body_type": 2, "skin_tone": "9c6a43", "hair_style": 3, "hair_color": "b8452c",
			"shirt_color": "7a2e2e", "pants_color": "3a3a3a"}
	cc._sync_controls()
	cc._refresh_preview()
	await _frames(20)
	await shot("04_character_creation_custom")
	cc._on_create()
	var w: World = await _wait_scene("World")
	await _seconds(2.0)
	await shot("05_intro_boat")
	await _seconds(4.5)
	await shot("06_intro_flyover")
	await _seconds(4.8)
	await shot("07_intro_dock")
	await _seconds(4.0)
	await shot("08_gameplay")
	await post_intro(w)
	w.open_pause_menu()
	await _frames(5)
	await shot("99_pause")
	get_tree().paused = false


## Tutorial HUD, dialogue, inventory and the closing screens.
func post_intro(w: World) -> void:
	w.player.teleport(w.island.landmarks.npc_instructor + Vector3(-1.6, 0, 0.4), PI * 0.5)
	w.camera_rig.set_view(-0.9, 40.0, 9.0)
	w.camera_rig.snap()
	QuestManager.report_keyboard_moved(4.0)
	QuestManager.report_marker_reached()
	await _frames(10)
	await shot("09_tutorial_hud")
	w.director.talk_to(w.director.npcs.maelis)
	await _seconds(2.5)
	await shot("10_dialogue")
	DialogueManager.end()
	await _frames(5)
	InventoryManager.add_item("logs", 3)
	InventoryManager.add_item("coins", 125)
	InventoryManager.add_item("tinderbox")
	w.hud.inventory_panel.show_panel()
	w.hud.inventory_panel.select_slot(0)
	await _frames(10)
	await shot("11_inventory")
	w.hud.inventory_panel.hide_panel()
	var q := QuestManager.to_dict()
	q.index = 4
	QuestManager.from_dict(q)
	w.director.talk_to(w.director.npcs.maelis)
	for i in 16:
		await _seconds(0.3)
		if not DialogueManager.active:
			break
		if DialogueManager.has_choices() and not w.hud.dialogue_panel.is_typing():
			DialogueManager.choose(DialogueManager.choices().size() - 1)
		else:
			w.hud.dialogue_panel._on_continue()
	await _seconds(3.0)
	await shot("12_gate_sequence")
	await _seconds(5.0)
	await shot("13_tutorial_complete")
	var panel := get_tree().get_first_node_in_group("modal_panel")
	if panel:
		panel.close()
	await _frames(5)


func shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	shots.append(path)
	print("shot " + path)


func _wait_scene(cls: String) -> Node:
	while true:
		await get_tree().process_frame
		var cur := get_tree().current_scene
		if cur != null and not GameManager.transitioning and cur.get_script() and cur.get_script().get_global_name() == cls:
			return cur
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	for i in int(s * 60.0):
		await get_tree().physics_frame
