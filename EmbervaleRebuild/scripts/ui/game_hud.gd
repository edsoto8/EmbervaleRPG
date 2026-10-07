class_name GameHUD
extends CanvasLayer
## Hitpoints, minimap, quest tracker (with substep checklist), message log, Inventory button and
## panel, hover text and the dialogue panel. Presentation only: it listens to autoload signals and
## never drives gameplay directly.

const LOG_LINES := 6

var world: World
var director: TutorialDirector
var interaction: InteractionSystem
var root: Control
var minimap: Minimap
var hp_label: Label
var tracker_title: Label
var tracker_objective: Label
var tracker_steps: VBoxContainer
var tracker_list: VBoxContainer
var log_box: VBoxContainer
var log_panel: PanelContainer
var inventory_button: Button
var inventory_panel: InventoryPanel
var dialogue_panel: DialoguePanel
var hover_label: Label
var bottom_right: HBoxContainer
var messages: Array[String] = []
var _connections: Array = []


func setup(w: World, d: TutorialDirector, i: InteractionSystem) -> void:
	world = w
	director = d
	interaction = i
	layer = 10
	root = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_minimap()
	_build_tracker()
	_build_log()
	_build_buttons()
	inventory_panel = InventoryPanel.new()
	inventory_panel.name = "InventoryPanel"
	inventory_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	inventory_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	inventory_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	inventory_panel.offset_right = -16
	inventory_panel.offset_bottom = -70
	root.add_child(inventory_panel)
	inventory_panel.visibility_reported.connect(func(open: bool) -> void: QuestManager.report_inventory_visibility(open))
	dialogue_panel = DialoguePanel.new()
	dialogue_panel.name = "DialoguePanel"
	root.add_child(dialogue_panel)
	hover_label = UITheme.label("", 17, UITheme.ACCENT)
	hover_label.add_theme_constant_override("outline_size", 5)
	hover_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hover_label)
	_link(GameManager.message_posted, post)
	_link(QuestManager.progress_changed, refresh_tracker)
	_link(QuestManager.objective_completed, func(_id: String) -> void: refresh_tracker())
	_link(InventoryManager.inventory_changed, refresh_tracker)
	_link(DialogueManager.dialogue_started, func(_id: String) -> void: _on_dialogue(true))
	_link(DialogueManager.dialogue_ended, func(_id: String, _o: Dictionary) -> void: _on_dialogue(false))
	_link(interaction.hover_changed, _on_hover)
	refresh_tracker()
	refresh_hitpoints()


func _link(sig: Signal, cb: Callable) -> void:
	sig.connect(cb)
	_connections.append([sig, cb])


func _exit_tree() -> void:
	for c in _connections:
		if c[0].is_connected(c[1]):
			c[0].disconnect(c[1])
	_connections.clear()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _build_minimap() -> void:
	var box := UITheme.vbox(6)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.offset_right = -16
	box.offset_top = 16
	box.name = "MapColumn"
	root.add_child(box)
	minimap = Minimap.new()
	minimap.name = "Minimap"
	minimap.custom_minimum_size = Vector2(180, 180)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(minimap)
	minimap.setup(world.island, world.player, director)
	var hp := UITheme.panel(6)
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_label = UITheme.label("", 16, Color("ff8a7a"))
	hp_label.name = "Hitpoints"
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.add_child(hp_label)
	box.add_child(hp)


func _build_tracker() -> void:
	var panel := UITheme.panel(12)
	panel.name = "QuestTracker"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -212
	panel.offset_top = 16
	panel.custom_minimum_size.x = 300
	root.add_child(panel)
	var v := UITheme.vbox(4)
	panel.add_child(v)
	tracker_title = UITheme.label("Tutorial", 19, UITheme.ACCENT)
	v.add_child(tracker_title)
	tracker_objective = UITheme.wrapped("", 15, UITheme.TEXT, 276)
	v.add_child(tracker_objective)
	tracker_steps = UITheme.vbox(2)
	v.add_child(tracker_steps)
	var sep := HSeparator.new()
	v.add_child(sep)
	tracker_list = UITheme.vbox(1)
	v.add_child(tracker_list)


func _build_log() -> void:
	log_panel = UITheme.panel(10)
	log_panel.name = "MessageLog"
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	log_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	log_panel.offset_left = 16
	log_panel.offset_bottom = -16
	log_panel.custom_minimum_size = Vector2(470, 0)
	log_panel.self_modulate = Color(1, 1, 1, 0.85)
	root.add_child(log_panel)
	log_box = UITheme.vbox(1)
	log_panel.add_child(log_box)
	log_panel.visible = false


func _build_buttons() -> void:
	bottom_right = UITheme.hbox(8)
	bottom_right.name = "Buttons"
	bottom_right.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bottom_right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_right.offset_right = -16
	bottom_right.offset_bottom = -16
	root.add_child(bottom_right)
	inventory_button = UITheme.button("Inventory (I)", toggle_inventory, 150)
	inventory_button.name = "InventoryButton"
	inventory_button.focus_mode = Control.FOCUS_NONE
	bottom_right.add_child(inventory_button)


## Adds a HUD button next to Inventory (Milestone 6: Skills).
func add_button(text: String, cb: Callable, button_name: String) -> Button:
	var b := UITheme.button(text, cb, 130)
	b.name = button_name
	b.focus_mode = Control.FOCUS_NONE
	bottom_right.add_child(b)
	bottom_right.move_child(b, 0)
	return b


# --- updates ----------------------------------------------------------------------------------------

func post(text: String) -> void:
	if text == "":
		return
	messages.append(text)
	while messages.size() > 40:
		messages.pop_front()
	for c in log_box.get_children():
		c.queue_free()
	var start := maxi(messages.size() - LOG_LINES, 0)
	for k in range(start, messages.size()):
		var l := UITheme.wrapped(messages[k], 15, UITheme.TEXT if k == messages.size() - 1 else UITheme.MUTED, 448)
		log_box.add_child(l)
	log_panel.visible = not DialogueManager.active


func refresh_hitpoints(current: int = 10, maximum: int = 10) -> void:
	hp_label.text = "Hitpoints  %d / %d" % [current, maximum]


func refresh_tracker() -> void:
	for c in tracker_steps.get_children():
		c.queue_free()
	for c in tracker_list.get_children():
		c.queue_free()
	if QuestManager.is_tutorial_complete():
		tracker_title.text = "Ready for adventure"
		tracker_objective.text = "Your training is complete. Explore the island and keep practising."
		_fill_tasks()
		return
	var obj := QuestManager.current_objective()
	tracker_title.text = "Tutorial: %s" % obj.title
	tracker_objective.text = obj.hint
	for step in QuestManager.substeps():
		tracker_steps.add_child(_check_line(step[0], step[1], 15))
	for i in QuestManager.OBJECTIVES.size():
		var o: Dictionary = QuestManager.OBJECTIVES[i]
		var done := i < QuestManager.index
		var l := _check_line("%d. %s" % [i + 1, o.title], done, 14)
		if i == QuestManager.index:
			l.get_child(1).add_theme_color_override("font_color", UITheme.ACCENT)
		tracker_list.add_child(l)


## Island tasks below "Ready for adventure" (populated from Milestone 6).
func _fill_tasks() -> void:
	if not TaskData.TASKS.size():
		return
	var heading := UITheme.label("Island tasks (%d / %d)" % [QuestManager.tasks.size(), TaskData.TASKS.size()], 15, UITheme.ACCENT)
	tracker_list.add_child(heading)
	var next := QuestManager.next_tasks(3)
	if next.is_empty():
		tracker_list.add_child(UITheme.label("Driftwood Isle mastered!", 15, UITheme.GOOD))
	for t in next:
		tracker_list.add_child(_check_line("%s  (%d coins)" % [TaskData.text(t), TaskData.reward(t)], false, 14))
	if not QuestManager.pending_task_rewards.is_empty():
		tracker_list.add_child(UITheme.wrapped("Rewards waiting: make room for %d coins." % _pending_coins(), 13, UITheme.DANGER, 276))


func _pending_coins() -> int:
	var n := 0
	for t in QuestManager.pending_task_rewards:
		n += TaskData.reward(t)
	return n


func _check_line(text: String, done: bool, size: int) -> HBoxContainer:
	var row := UITheme.hbox(6)
	row.add_child(UITheme.label("✔" if done else "•", size, UITheme.GOOD if done else UITheme.MUTED))
	var l := UITheme.label(text, size, UITheme.MUTED if done else UITheme.TEXT)
	row.add_child(l)
	return row


func toggle_inventory() -> void:
	inventory_panel.toggle()


func _on_dialogue(active: bool) -> void:
	log_panel.visible = not active and not messages.is_empty()
	if active:
		hover_label.text = ""


func _on_hover(target: Node) -> void:
	hover_label.text = interaction.hover_text(target)


func _process(_delta: float) -> void:
	if hover_label.text != "":
		hover_label.position = root.get_local_mouse_position() + Vector2(18, 12)


func _unhandled_input(event: InputEvent) -> void:
	if DialogueManager.active or GameManager.is_modal_open():
		return
	if event.is_action_pressed("inventory") and not event.is_echo():
		if GameManager.state == GameManager.State.PLAYING and world.gameplay_enabled:
			get_viewport().set_input_as_handled()
			toggle_inventory()
	elif event.is_action_pressed("pause") and close_top_panel():
		get_viewport().set_input_as_handled()


## Esc closes the topmost HUD panel first. Returns true if one was closed.
func close_top_panel() -> bool:
	if inventory_panel.visible:
		inventory_panel.hide_panel()
		return true
	return false
