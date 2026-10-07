class_name DialoguePanel
extends Control
## Dialogue box: live 3D portrait of the speaker, typed text, Continue and up to three numbered
## choices. Space/E/Enter first reveals unfinished text, then advances; 1-3 picks a choice. While it
## is open it swallows mouse input so clicks never reach the world.

const CHARS_PER_SECOND := 55.0

var portrait_viewport: SubViewport
var portrait_model: CharacterModel
var speaker_label: Label
var text_label: Label
var choice_box: VBoxContainer
var continue_button: Button
var _speaker := ""
var _typing := false
var _shown := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var frame := UITheme.panel(14)
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	frame.custom_minimum_size = Vector2(780, 196)
	frame.offset_left = -390
	frame.offset_right = 390
	frame.offset_top = -216
	frame.offset_bottom = -20
	add_child(frame)
	var row := UITheme.hbox(16)
	frame.add_child(row)
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(150, 160)
	holder.stretch = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(holder)
	portrait_viewport = SubViewport.new()
	portrait_viewport.own_world_3d = true
	portrait_viewport.transparent_bg = true
	portrait_viewport.size = Vector2i(150, 160)
	holder.add_child(portrait_viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("3b2d20")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("d4dbe3")
	e.ambient_light_energy = 0.55
	env.environment = e
	portrait_viewport.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-25), deg_to_rad(-30), 0)
	light.light_energy = 0.9
	portrait_viewport.add_child(light)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.68, -1.15)
	portrait_viewport.add_child(cam)
	cam.look_at(Vector3(0, 1.6, 0), Vector3.UP)
	cam.current = true
	var col := UITheme.vbox(6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	speaker_label = UITheme.label("", 21, UITheme.ACCENT)
	col.add_child(speaker_label)
	text_label = UITheme.wrapped("", 18, UITheme.TEXT, 560)
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(text_label)
	choice_box = UITheme.vbox(4)
	col.add_child(choice_box)
	continue_button = UITheme.button("Continue  ▸", _on_continue, 160)
	continue_button.name = "Continue"
	continue_button.focus_mode = Control.FOCUS_NONE
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	col.add_child(continue_button)
	visible = false
	DialogueManager.line_shown.connect(_on_line)
	DialogueManager.dialogue_ended.connect(_on_ended)


func _exit_tree() -> void:
	if DialogueManager.line_shown.is_connected(_on_line):
		DialogueManager.line_shown.disconnect(_on_line)
	if DialogueManager.dialogue_ended.is_connected(_on_ended):
		DialogueManager.dialogue_ended.disconnect(_on_ended)


func _on_line(node: Dictionary) -> void:
	visible = true
	var sid: String = node.get("speaker", "")
	speaker_label.text = DialogueManager.speaker_name(sid)
	if sid != _speaker:
		_speaker = sid
		_set_portrait(DialogueManager.speakers.get(sid, {}).get("appearance", Appearance.defaults()))
	text_label.text = node.get("text", "")
	text_label.visible_characters = 0
	_shown = 0.0
	_typing = true
	for c in choice_box.get_children():
		c.queue_free()
	var list: Array = node.get("choices", [])
	for i in list.size():
		var b := UITheme.button("%d. %s" % [i + 1, list[i].text], _choose.bind(i), 300)
		b.name = "Choice%d" % (i + 1)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.visible = false
		choice_box.add_child(b)
	continue_button.visible = false


func _set_portrait(look: Dictionary) -> void:
	if is_instance_valid(portrait_model):
		portrait_model.queue_free()
	portrait_model = CharacterModel.new(look)
	portrait_model.idle_glances = false
	portrait_viewport.add_child(portrait_model)
	portrait_model.rotation.y = 0.35


func _process(delta: float) -> void:
	if not visible:
		return
	if _typing:
		_shown += delta * CHARS_PER_SECOND
		text_label.visible_characters = int(_shown)
		if _shown >= text_label.get_total_character_count():
			_finish_typing()
	if is_instance_valid(portrait_model):
		if _typing and portrait_model.current_action == "":
			portrait_model.play_action("talk")
		elif not _typing and portrait_model.current_action == "talk":
			portrait_model.stop_action()


func _finish_typing() -> void:
	_typing = false
	text_label.visible_characters = -1
	var has_choices := choice_box.get_child_count() > 0
	for c in choice_box.get_children():
		c.visible = true
	continue_button.visible = not has_choices


func is_typing() -> bool:
	return _typing


func _on_continue() -> void:
	if _typing:
		_finish_typing()
	elif not DialogueManager.has_choices():
		DialogueManager.advance()


func _choose(i: int) -> void:
	if _typing:
		_finish_typing()
		return
	DialogueManager.choose(i)


func _on_ended(_npc: String, _outcome: Dictionary) -> void:
	visible = false
	_speaker = ""


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not DialogueManager.active:
		return
	if event.is_action_pressed("dialogue_continue") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_on_continue()
	elif event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		DialogueManager.end()
	else:
		for i in 3:
			if event.is_action_pressed("choice_%d" % (i + 1)) and DialogueManager.has_choices():
				get_viewport().set_input_as_handled()
				if i < DialogueManager.choices().size():
					_choose(i)
				return
