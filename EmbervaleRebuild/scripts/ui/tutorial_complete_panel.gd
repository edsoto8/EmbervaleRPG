class_name TutorialCompletePanel
extends ModalPanel
## Shown after the gate sequence: Continue Exploring (stay on the island) or Return to Main Menu.

var _world: World


static func show_panel(world: World) -> TutorialCompletePanel:
	var p := TutorialCompletePanel.new()
	p._world = world
	p._build()
	p.open()
	world.set_gameplay_enabled(false)
	return p


func _build() -> void:
	box.add_child(UITheme.title("Tutorial Complete", 44))
	var text := UITheme.wrapped("You've finished your training on Driftwood Isle, %s. The island is yours to explore: keep practising, earn coins and take on the island tasks." % GameManager.character.name, 18, UITheme.TEXT, 480)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(text)
	var row := UITheme.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var cont := UITheme.button("Continue Exploring", close, 220)
	cont.name = "ContinueExploring"
	var menu := UITheme.button("Return to Main Menu", _to_menu, 220)
	menu.name = "ReturnToMainMenu"
	row.add_child(cont)
	row.add_child(menu)
	box.add_child(row)


func close() -> void:
	super.close()
	if is_instance_valid(_world):
		_world.set_gameplay_enabled(true)


func _to_menu() -> void:
	if GameManager.save_and_return_to_menu():
		_closing = true
		queue_free()
		return
	ConfirmPanel.ask("Your progress could not be saved.\n%s" % GameManager.last_save_error, [
		["Retry", _to_menu],
		["Leave without saving", func() -> void: GameManager.leave_to_menu()],
		["Cancel", Callable()],
	], "Saving failed")
