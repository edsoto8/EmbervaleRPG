class_name CharacterCreation
extends Node3D
## Name, body type, skin, hair style/colour, shirt/pants colour on a rotating, draggable preview.
## Create Character saves first; the old adventure is only replaced once that succeeds.

const AUTO_ROTATE := 0.6          ## rad/s
const DRAG_RATE := 0.012          ## rad per pixel
const DRAG_PAUSE := 2.0           ## seconds of no auto-rotation after a drag

var appearance := Appearance.defaults()
var preview: CharacterModel
var turntable: Node3D
var name_edit: LineEdit
var name_error: Label
var create_button: Button
var status: Label
var body_selector: HBoxContainer
var hair_selector: HBoxContainer
var swatch_rows := {}
var rng := RandomNumberGenerator.new()
var _dragging := false
var _pause_left := 0.0
var _ui_root: Control


func _ready() -> void:
	GameManager.set_state(GameManager.State.CHARACTER_CREATION)
	rng.randomize()
	_build_stage()
	_build_ui()
	_refresh_preview()
	_validate()


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2a3b4c")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("d4dbe3")
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-30), 0)
	sun.light_color = Color("fff1d6")
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.5, 2.2, 2.0)
	fill.light_color = Color("9fb8ff")
	fill.light_energy = 0.4
	fill.omni_range = 8.0
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PropFactory.cylinder_mesh(1.4, 1.5, 0.3, 12)
	floor_mesh.material_override = PropFactory.mat(Color("8a7a5e"))
	floor_mesh.position.y = -0.15
	add_child(floor_mesh)
	var ground := MeshInstance3D.new()
	ground.mesh = PropFactory.cylinder_mesh(9.0, 9.0, 0.1, 24)
	ground.material_override = PropFactory.mat(Color("4f7a35"))
	ground.position.y = -0.32
	add_child(ground)
	turntable = Node3D.new()
	turntable.name = "Turntable"
	turntable.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(turntable)
	preview = CharacterModel.new(appearance)
	preview.name = "Preview"
	turntable.add_child(preview)
	turntable.rotation.y = 0.5
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.position = Vector3(-1.05, 1.35, 4.4)
	add_child(cam)
	cam.look_at(Vector3(-1.05, 0.95, 0), Vector3.UP)
	cam.current = true


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui_root = Control.new()
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui_root)
	var panel := UITheme.panel(14)
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 24
	panel.offset_top = 16
	panel.offset_bottom = -16
	panel.offset_right = 24 + 470
	_ui_root.add_child(panel)
	var v := UITheme.vbox(4)
	panel.add_child(v)
	var heading := UITheme.label("Create your character", 26, UITheme.ACCENT)
	v.add_child(heading)
	v.add_child(UITheme.label("Name", 17, UITheme.MUTED))
	name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.placeholder_text = "Letters, numbers and spaces"
	name_edit.max_length = Appearance.NAME_MAX + 4
	name_edit.text_changed.connect(func(_t: String) -> void: _validate())
	name_edit.text_submitted.connect(func(_t: String) -> void: _on_create())
	v.add_child(name_edit)
	name_error = UITheme.label("", 14, UITheme.DANGER)
	name_error.custom_minimum_size.y = 18
	v.add_child(name_error)
	body_selector = _selector_row(v, "Body type", Appearance.BODY_TYPES, "body_type")
	_swatch_row(v, "Skin tone", Appearance.SKIN, "skin_tone")
	hair_selector = _selector_row(v, "Hair style", Appearance.HAIR_STYLES, "hair_style")
	_swatch_row(v, "Hair colour", Appearance.HAIR, "hair_color")
	_swatch_row(v, "Shirt colour", Appearance.CLOTH, "shirt_color")
	_swatch_row(v, "Pants colour", Appearance.CLOTH, "pants_color")
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6
	v.add_child(spacer)
	var randomize_button := UITheme.button("Randomize", _on_randomize, 440)
	randomize_button.name = "Randomize"
	v.add_child(randomize_button)
	status = UITheme.wrapped("", 14, UITheme.DANGER, 440)
	v.add_child(status)
	var row := UITheme.hbox(12)
	var back := UITheme.button("Back", _on_back, 140)
	back.name = "Back"
	create_button = UITheme.button("Create Character", _on_create, 288)
	create_button.name = "Create"
	row.add_child(back)
	row.add_child(create_button)
	v.add_child(row)
	var hint := UITheme.label("Drag to rotate", 15, UITheme.MUTED)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position.x += 220
	hint.position.y -= 40
	_ui_root.add_child(hint)
	name_edit.grab_focus.call_deferred()


func _selector_row(parent: Control, text: String, options: Array, key: String) -> HBoxContainer:
	var row := UITheme.hbox(12)
	var l := UITheme.label(text, 15, UITheme.MUTED)
	l.custom_minimum_size.x = 120
	row.add_child(l)
	var sel := UITheme.selector(options, appearance[key], func(i: int) -> void:
		appearance[key] = i
		_refresh_preview())
	sel.name = key
	row.add_child(sel)
	parent.add_child(row)
	return sel


func _swatch_row(parent: Control, text: String, palette: Array, key: String) -> void:
	parent.add_child(UITheme.label(text, 15, UITheme.MUTED))
	var row := UITheme.hbox(6)
	row.name = key
	var group := ButtonGroup.new()
	for hex in palette:
		var b := UITheme.swatch(Color(hex), func() -> void:
			appearance[key] = hex
			_refresh_preview())
		b.button_group = group
		b.name = hex
		b.button_pressed = hex == appearance[key]
		row.add_child(b)
	swatch_rows[key] = row
	parent.add_child(row)


func _sync_controls() -> void:
	UITheme.set_selector(body_selector, Appearance.BODY_TYPES, appearance.body_type)
	UITheme.set_selector(hair_selector, Appearance.HAIR_STYLES, appearance.hair_style)
	for key in swatch_rows:
		for b in swatch_rows[key].get_children():
			b.set_pressed_no_signal(b.name == appearance[key])


func _refresh_preview() -> void:
	preview.set_appearance(appearance)


## Name validation: shows the reason and disables Create while invalid.
func _validate() -> bool:
	var err := Appearance.name_error(Appearance.clean_name(name_edit.text))
	name_error.text = err if name_edit.text != "" else "Enter a name."
	create_button.disabled = err != ""
	return err == ""


func _on_randomize() -> void:
	var old := appearance.duplicate()
	var fresh := Appearance.randomized(rng)
	# Every field changes.
	for key in fresh:
		var tries := 0
		while fresh[key] == old[key] and tries < 20:
			fresh[key] = Appearance.randomized(rng)[key]
			tries += 1
	appearance = fresh
	if name_edit.text.strip_edges() == "":
		name_edit.text = Appearance.SUGGESTED_NAMES[rng.randi_range(0, Appearance.SUGGESTED_NAMES.size() - 1)]
	_sync_controls()
	_refresh_preview()
	_validate()


func _on_create() -> void:
	if not _validate() or GameManager.transitioning:
		return
	status.text = ""
	if not GameManager.create_character(Appearance.clean_name(name_edit.text), appearance):
		status.text = GameManager.last_save_error


func _on_back() -> void:
	if GameManager.transitioning:
		return
	GameManager.go_to_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		rotate_preview(event.relative.x)
	elif event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_on_back()


## Drag rotation (pixels); pauses auto-rotation for 2 s.
func rotate_preview(pixels: float) -> void:
	turntable.rotation.y += pixels * DRAG_RATE
	_pause_left = DRAG_PAUSE


func _process(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left -= delta
	else:
		turntable.rotation.y += AUTO_ROTATE * delta
