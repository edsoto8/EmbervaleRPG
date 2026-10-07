class_name ModalPanel
extends Control
## Base for modal panels: dims the screen, swallows input below it, works while paused, closes on Esc
## and frees itself. While any modal is open, world input is blocked (GameManager.is_modal_open()).

signal closed

var box: VBoxContainer
var frame: PanelContainer
var _closing := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("modal_panel")
	add_child(UITheme.dimmer())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	frame = UITheme.panel(22)
	center.add_child(frame)
	box = UITheme.vbox(12)
	frame.add_child(box)


## Adds the panel on the top-most UI layer.
func open(parent: Node = null) -> ModalPanel:
	var host := parent if parent != null else GameManager.ui_layer()
	host.add_child(self)
	_focus_first.call_deferred()
	return self


func _focus_first() -> void:
	for c in find_children("*", "Button", true, false):
		if c.visible and not c.disabled:
			(c as Button).grab_focus()
			return


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()


## Esc behaviour; subclasses may override.
func cancel() -> void:
	close()


func close() -> void:
	if _closing:
		return
	_closing = true
	remove_from_group("modal_panel")
	closed.emit()
	queue_free()
