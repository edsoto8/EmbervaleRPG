class_name InventoryPanel
extends PanelContainer
## 4 x 7 inventory grid. Clicking an item examines it and shows its actions (Drop; Milestone 6 adds
## Light and Eat through `action_provider`). Gameplay continues while it is open.

signal visibility_reported(open: bool)

const COLUMNS := 4
const SLOT_SIZE := Vector2(54, 50)

var slot_buttons: Array[Button] = []
var icons: Array[ItemIcon] = []
var qty_labels: Array[Label] = []
var selected := -1
var info_name: Label
var info_text: Label
var actions_row: HBoxContainer
## Callable(id: String, slot: int) -> Array of [text, Callable] extra actions (Light, Eat...).
var action_provider := Callable()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UITheme.vbox(8)
	add_child(v)
	var head := UITheme.hbox()
	var title := UITheme.label("Inventory", 22, UITheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := UITheme.button("✕", hide_panel, 36)
	close_btn.name = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	head.add_child(close_btn)
	v.add_child(head)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for i in InventoryManager.SLOTS:
		var b := Button.new()
		b.name = "Slot%d" % i
		b.custom_minimum_size = SLOT_SIZE
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.add_theme_stylebox_override("normal", UITheme.style(Color("1f1711"), Color("4a3a2a"), 1, 4, 2))
		b.add_theme_stylebox_override("hover", UITheme.style(Color("2c2118"), UITheme.BORDER, 1, 4, 2))
		b.add_theme_stylebox_override("pressed", UITheme.style(Color("3a2c1f"), UITheme.ACCENT, 2, 4, 2))
		b.add_theme_stylebox_override("hover_pressed", UITheme.style(Color("3a2c1f"), UITheme.ACCENT, 2, 4, 2))
		b.pressed.connect(select_slot.bind(i))
		var icon := ItemIcon.new()
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 4
		icon.offset_top = 3
		icon.offset_right = -4
		icon.offset_bottom = -3
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(icon)
		var q := UITheme.label("", 13, Color("ffe9a0"))
		q.add_theme_constant_override("outline_size", 4)
		q.add_theme_color_override("font_outline_color", Color.BLACK)
		q.position = Vector2(3, 0)
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(q)
		grid.add_child(b)
		slot_buttons.append(b)
		icons.append(icon)
		qty_labels.append(q)
	info_name = UITheme.label("", 17, UITheme.ACCENT)
	v.add_child(info_name)
	info_text = UITheme.wrapped("Click an item to examine it.", 14, UITheme.MUTED, 228)
	v.add_child(info_text)
	actions_row = UITheme.hbox(6)
	v.add_child(actions_row)
	InventoryManager.inventory_changed.connect(refresh)
	refresh()
	visible = false


func _exit_tree() -> void:
	if InventoryManager.inventory_changed.is_connected(refresh):
		InventoryManager.inventory_changed.disconnect(refresh)


func refresh() -> void:
	for i in InventoryManager.SLOTS:
		var s: Variant = InventoryManager.slot(i)
		icons[i].set_item("" if s == null else s.id)
		qty_labels[i].text = "" if s == null or (s.qty == 1 and not ItemDB.is_stackable(s.id)) else _short_qty(s.qty)
		slot_buttons[i].tooltip_text = "" if s == null else ItemDB.display_name(s.id)
		slot_buttons[i].set_pressed_no_signal(i == selected and s != null)
	if selected >= 0 and InventoryManager.slot(selected) == null:
		_clear_selection()
	elif selected >= 0:
		_show_info(selected)


static func _short_qty(q: int) -> String:
	if q >= 10000000:
		return "%dM" % (q / 1000000)
	if q >= 100000:
		return "%dK" % (q / 1000)
	return str(q)


func select_slot(i: int) -> void:
	var s: Variant = InventoryManager.slot(i)
	if s == null:
		_clear_selection()
		refresh()
		return
	selected = i
	InventoryManager.inspect(i)
	refresh()


func _show_info(i: int) -> void:
	var s: Variant = InventoryManager.slot(i)
	info_name.text = "%s%s" % [ItemDB.display_name(s.id), " × %d" % s.qty if s.qty > 1 else ""]
	info_text.text = ItemDB.examine_text(s.id)
	for c in actions_row.get_children():
		c.queue_free()
	var acts: Array = []
	if action_provider.is_valid():
		acts.append_array(action_provider.call(s.id, i))
	if not ItemDB.is_protected(s.id):
		acts.append(["Drop", _confirm_drop.bind(i)])
	for a in acts:
		var b := UITheme.button(a[0], a[1], 70)
		b.name = "Action" + str(a[0])
		b.focus_mode = Control.FOCUS_NONE
		actions_row.add_child(b)


func _clear_selection() -> void:
	selected = -1
	info_name.text = ""
	info_text.text = "Click an item to examine it."
	for c in actions_row.get_children():
		c.queue_free()


func _confirm_drop(i: int) -> void:
	var s: Variant = InventoryManager.slot(i)
	if s == null:
		return
	var what := ItemDB.display_name(s.id)
	var text := "Drop %s%s? It will be gone for good." % ["all %d " % s.qty if s.qty > 1 else "your ", what]
	ConfirmPanel.ask(text, [["Drop", func() -> void: _drop(i)], ["Keep", Callable()]], "Drop item")


func _drop(i: int) -> void:
	var res := InventoryManager.drop_slot(i)
	if res.ok:
		GameManager.post_message("You drop %s%s." % ["%d × " % res.qty if res.qty > 1 else "the ", ItemDB.display_name(res.id)])
	else:
		GameManager.post_message(res.error)
	_clear_selection()
	refresh()


func show_panel() -> void:
	visible = true
	refresh()
	visibility_reported.emit(true)


func hide_panel() -> void:
	if not visible:
		return
	visible = false
	_clear_selection()
	visibility_reported.emit(false)


func toggle() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()
