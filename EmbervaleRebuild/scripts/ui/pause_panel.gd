class_name PausePanel
extends ModalPanel
## Pause menu: Resume, Settings, Save & Main Menu, Save & Exit. Opening it pauses the tree (freezing
## actions and world timers); closing it resumes. A failed save offers Retry or leaving without saving.


static func show_panel() -> PausePanel:
	var p := PausePanel.new()
	p._build()
	p.open()
	GameManager.pause_game()
	return p


func _build() -> void:
	var heading := UITheme.label("Paused", 32, UITheme.ACCENT)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	for entry in [["Resume", close], ["Settings", _settings], ["Save & Main Menu", _save_menu], ["Save & Exit", _save_exit]]:
		var b := UITheme.button(entry[0], entry[1], 260)
		b.name = str(entry[0]).replace(" ", "").replace("&", "And")
		box.add_child(b)


func close() -> void:
	super.close()
	GameManager.resume_game()


func _settings() -> void:
	SettingsPanel.show_panel()


func _save_menu() -> void:
	if GameManager.save_and_return_to_menu():
		_closing = true
		queue_free()
		return
	ConfirmPanel.ask("Your progress could not be saved.\n%s" % GameManager.last_save_error, [
		["Retry", _save_menu],
		["Leave without saving", func() -> void: GameManager.leave_to_menu()],
		["Cancel", Callable()],
	], "Saving failed")


func _save_exit() -> void:
	if GameManager.save_and_quit():
		return
	ConfirmPanel.ask("Your progress could not be saved.\n%s" % GameManager.last_save_error, [
		["Retry", _save_exit],
		["Exit without saving", func() -> void: GameManager.quit_game()],
		["Cancel", Callable()],
	], "Saving failed")
