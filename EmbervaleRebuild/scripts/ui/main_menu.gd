class_name MainMenu
extends Node3D
## Main menu over a slowly orbiting view of the island: New Game, Continue, Settings, Import Save, Exit.

const ORBIT_SPEED := 0.045
const ORBIT_RADIUS := 78.0
const ORBIT_HEIGHT := 36.0

var island: TutorialIsland
var camera: Camera3D
var continue_button: Button
var new_game_button: Button
var notice: Label
var _angle := 0.6
var _status := {}


func _ready() -> void:
	GameManager.set_state(GameManager.State.MAIN_MENU)
	add_child(load("res://scenes/world/environment.tscn").instantiate())
	island = TutorialIsland.new()
	island.name = "TutorialIsland"
	add_child(island)
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.far = 800.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.current = true
	_place_camera()
	_build_ui()
	refresh()
	AudioManager.stop_ambience()
	AudioManager.play_music("menu_theme")


func _process(delta: float) -> void:
	_angle += ORBIT_SPEED * delta
	_place_camera()


func _place_camera() -> void:
	camera.global_position = Vector3(sin(_angle) * ORBIT_RADIUS, ORBIT_HEIGHT, cos(_angle) * ORBIT_RADIUS + 4.0)
	camera.look_at(Vector3(0, 0, 4), Vector3.UP)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.03, 0.02, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 470
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var column := UITheme.vbox(14)
	column.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	column.offset_left = 60
	column.offset_right = 420
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(column)
	var mark := EmberMark.new()
	mark.custom_minimum_size = Vector2(300, 74)
	column.add_child(mark)
	column.add_child(UITheme.title("EMBERVALE", 64))
	var sub := UITheme.label("Driftwood Isle", 24, UITheme.TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	column.add_child(gap)
	new_game_button = _menu_button(column, "New Game", _on_new_game)
	continue_button = _menu_button(column, "Continue", _on_continue)
	_menu_button(column, "Settings", func() -> void: SettingsPanel.show_panel())
	_menu_button(column, "Import Save…", _on_import)
	_menu_button(column, "Exit", func() -> void: GameManager.quit_game())
	notice = UITheme.wrapped("", 16, UITheme.MUTED, 340)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(notice)
	var version := UITheme.label("v%s · Godot %s" % [ProjectSettings.get_setting("application/config/version"),
			Engine.get_version_info().string], 14, UITheme.MUTED)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.position -= Vector2(16, 12)
	root.add_child(version)
	new_game_button.grab_focus.call_deferred()


func _menu_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := UITheme.button(text, cb, 300)
	b.name = text.replace(" ", "").replace("…", "")
	b.custom_minimum_size.y = 48
	parent.add_child(b)
	return b


## Re-reads the save state: Continue is enabled only for a valid supported save (or a usable backup).
func refresh() -> void:
	_status = SaveManager.save_status()
	continue_button.disabled = not _status.can_continue
	notice.text = _status.message
	notice.add_theme_color_override("font_color", UITheme.DANGER if _status.primary in ["corrupt", "unsupported"] else UITheme.MUTED)


func _on_new_game() -> void:
	if GameManager.transitioning:
		return
	if _status.primary != "missing" or _status.backup == "valid":
		ConfirmPanel.ask("Starting a new game will replace your saved adventure once your new character is created.",
				[["Start new game", GameManager.start_new_game], ["Cancel", Callable()]], "Replace your adventure?")
	else:
		GameManager.start_new_game()


func _on_continue() -> void:
	if GameManager.transitioning:
		return
	refresh()
	if not _status.can_continue:
		return
	if _status.get("needs_recovery", false):
		ConfirmPanel.ask(_status.message + "\nThe damaged file will be kept for inspection.",
				[["Restore backup", _recover], ["Cancel", Callable()]], "Save problem")
		return
	var res := GameManager.continue_game()
	if not res.ok:
		GameManager.toast(res.error, UITheme.DANGER)
		refresh()


func _recover() -> void:
	var res := GameManager.recover_and_continue()
	if not res.ok:
		GameManager.toast(res.error, UITheme.DANGER)
		refresh()


func _on_import() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; Embervale saves"])
	dialog.title = "Import an Embervale save"
	dialog.use_native_dialog = true
	dialog.file_selected.connect(_confirm_import)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func _confirm_import(path: String) -> void:
	var check := SaveManager.import_save(path)
	if not check.ok:
		GameManager.toast(check.error, UITheme.DANGER, 6.0)
		return
	if _status.primary != "missing":
		ConfirmPanel.ask("Import %s's adventure? It will replace your current save (the original file is not changed)." % check.data.character.name,
				[["Import", _do_import.bind(path)], ["Cancel", Callable()]], "Import save")
	else:
		_do_import(path)


func _do_import(path: String) -> void:
	var res := GameManager.import_save(path)
	if res.ok:
		GameManager.toast("Imported %s's adventure. Choose Continue to play." % res.data.character.name, UITheme.GOOD)
	else:
		GameManager.toast(res.error, UITheme.DANGER, 6.0)
	refresh()
