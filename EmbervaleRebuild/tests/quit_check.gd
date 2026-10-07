extends Node
## Graceful-shutdown check: opens the main menu (music playing), then quits through
## GameManager.quit_game(). Run with a renderer and look for "leaked" warnings in the output.


func _ready() -> void:
	get_tree().current_scene = null
	await get_tree().process_frame
	GameManager.go_to_main_menu()
	for i in 240:
		await get_tree().process_frame
	print("music playing: %s" % AudioManager.music.playing)
	GameManager.quit_game()
