class_name ConfirmPanel
extends ModalPanel
## A message with buttons. `choices` is an array of [text, callable]; the last choice is also what
## Esc does. Each choice closes the panel before running its callable.

var _choices: Array = []


static func ask(message: String, choices: Array, heading: String = "") -> ConfirmPanel:
	var p := ConfirmPanel.new()
	p._build(message, choices, heading)
	p.open()
	return p


func _build(message: String, choices: Array, heading: String) -> void:
	_choices = choices
	if heading != "":
		var h := UITheme.label(heading, 26, UITheme.ACCENT)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(h)
	var msg := UITheme.wrapped(message, 18, UITheme.TEXT, 460)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(msg)
	var row := UITheme.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	for c in choices:
		var b := UITheme.button(c[0], _choose.bind(c[1]), 150)
		b.name = "Choice_" + str(c[0]).replace(" ", "_").replace("&", "and")
		row.add_child(b)


func _choose(cb: Callable) -> void:
	close()
	if cb.is_valid():
		cb.call()


func cancel() -> void:
	if _choices.is_empty():
		close()
		return
	_choose(_choices[_choices.size() - 1][1])


func press(text: String) -> void:
	for c in _choices:
		if c[0] == text:
			_choose(c[1])
			return
	push_error("No choice named %s" % text)
