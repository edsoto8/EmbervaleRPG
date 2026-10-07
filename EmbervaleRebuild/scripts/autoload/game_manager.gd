extends Node
## Owns the game flow (menu, character creation, intro, playing, paused), the current character, the
## save snapshot (build_save_data) and when to save. Nothing is saved until `adventure_loaded` is true,
## so menu-only sessions and direct world-scene runs (F6) never write a save.

enum State { MAIN_MENU, CHARACTER_CREATION, CUTSCENE, PLAYING, PAUSED }

signal state_changed(state: State)
signal message_posted(text: String)
signal saved
signal save_failed(message: String)
signal scene_ready(scene: Node)

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const CREATION_SCENE := "res://scenes/ui/character_creation.tscn"
const WORLD_SCENE := "res://scenes/world/world.tscn"
const FADE_TIME := 0.35
const QUIT_WAIT := 0.25

var state: State = State.MAIN_MENU
var character := {"name": Appearance.DEFAULT_NAME, "appearance": Appearance.defaults()}
## "intro" until the intro finishes or is skipped, then "island".
var stage := "intro"
var adventure_loaded := false
## Player position/yaw from the loaded save, restored by the world after navigation is ready.
var pending_player := {}
## True while a scene change (with fades) is running.
var transitioning := false
var last_save_error := ""
## Test hook: when set, quit_game() calls this instead of quitting the tree.
var quit_handler := Callable()

var _ui: CanvasLayer
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _toast_box: VBoxContainer
var _suppress_saves := 0
var _save_pending := false
var _quitting := false
## Save sections kept verbatim for managers that are not present (so nothing is lost on re-save).
var _extra_sections := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UITheme.install()
	get_tree().set_auto_accept_quit(false)
	_ui = CanvasLayer.new()
	_ui.name = "UILayer"
	_ui.layer = 80
	add_child(_ui)
	_toast_box = UITheme.vbox(6)
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_box.position.y = 24
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_toast_box)
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "FadeLayer"
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade)
	_connect_managers()


func _connect_managers() -> void:
	var quest := get_node_or_null("/root/QuestManager")
	if quest:
		quest.objective_completed.connect(func(_id: String) -> void: request_save())
		quest.tutorial_completed.connect(func() -> void: request_save())
		if quest.has_signal("task_completed"):
			quest.task_completed.connect(func(_id: String) -> void: request_save())
		if quest.has_signal("reward_paid"):
			quest.reward_paid.connect(func(_id: String) -> void: request_save())
		if quest.has_signal("quest_started"):
			quest.quest_started.connect(func(_id: String) -> void: request_save())
			quest.quest_progress.connect(func(_id: String, _f: String) -> void: request_save())
			quest.quest_completed.connect(func(_id: String) -> void: request_save())


func ui_layer() -> CanvasLayer:
	return _ui


func is_modal_open() -> bool:
	return get_tree().get_node_count_in_group("modal_panel") > 0


func set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)


func post_message(text: String) -> void:
	message_posted.emit(text)


## A short notice at the top of the screen (errors, confirmations).
func toast(text: String, color: Color = UITheme.TEXT, seconds: float = 4.0) -> void:
	var p := UITheme.panel(10)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UITheme.wrapped(text, 17, color, 520)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	_toast_box.add_child(p)
	var t := p.create_tween()
	t.tween_interval(seconds)
	t.tween_property(p, "modulate:a", 0.0, 0.4)
	t.tween_callback(p.queue_free)


## The current gameplay world, if one is loaded.
func world() -> World:
	var nodes := get_tree().get_nodes_in_group("world")
	return nodes[0] if nodes.size() > 0 else null


# --- scenes ---------------------------------------------------------------------------------------

func change_scene(path: String) -> void:
	if transitioning:
		return
	transitioning = true
	get_tree().paused = false
	await _fade_to(1.0)
	for m in get_tree().get_nodes_in_group("modal_panel"):
		m.queue_free()
	get_tree().change_scene_to_file(path)
	await get_tree().scene_changed
	await get_tree().process_frame
	transitioning = false
	scene_ready.emit(get_tree().current_scene)
	await _fade_to(0.0)


func _fade_to(alpha: float) -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP if alpha > 0.0 else Control.MOUSE_FILTER_IGNORE
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(_fade, "color:a", alpha, FADE_TIME)
	await t.finished


func go_to_main_menu() -> void:
	set_state(State.MAIN_MENU)
	await change_scene(MAIN_MENU_SCENE)


## New Game: go to character creation. The old save stays until a character is created and saved.
func start_new_game() -> void:
	set_state(State.CHARACTER_CREATION)
	await change_scene(CREATION_SCENE)


## Creates the character and writes the first save. Only after that succeeds does the new adventure
## replace the old one. Returns false (and leaves everything unchanged) if saving fails.
func create_character(char_name: String, appearance: Dictionary) -> bool:
	var clean := Appearance.clean_name(char_name)
	if not Appearance.is_valid_name(clean):
		last_save_error = Appearance.name_error(clean)
		return false
	var data := new_game_data(clean, appearance)
	if not SaveManager.write_save(data):
		last_save_error = SaveManager.last_error
		save_failed.emit(last_save_error)
		return false
	apply_save_data(data)
	set_state(State.CUTSCENE)
	change_scene(WORLD_SCENE)
	return true


func new_game_data(char_name: String, appearance: Dictionary) -> Dictionary:
	var xp := {}
	for s in SkillData.SKILLS:
		xp[s] = 0
	return {
		"version": SaveManager.VERSION,
		"character": {"name": char_name, "appearance": Appearance.sanitize(appearance)},
		"stage": "intro",
		"quest": {"index": 0, "wasd_distance": 0, "marker_reached": false, "inventory_opened": false,
				"logs_inspected": false, "tasks": [], "pending_task_rewards": [], "quests": {}},
		"inventory": {"slots": []},
		"skills": {"xp": xp, "hitpoints": SkillData.MAX_HITPOINTS},
	}


## Loads the save and enters the world. Returns {ok, error}.
func continue_game() -> Dictionary:
	var res := SaveManager.load_save()
	if not res.ok:
		return res
	return _enter_with(res.data)


## Restores the backup over a damaged primary save, then continues.
func recover_and_continue() -> Dictionary:
	var res := SaveManager.recover_from_backup()
	if not res.ok:
		return res
	toast("Your adventure was restored from the backup save.", UITheme.GOOD)
	return _enter_with(res.data)


func _enter_with(data: Dictionary) -> Dictionary:
	apply_save_data(data)
	set_state(State.CUTSCENE if stage == "intro" else State.PLAYING)
	change_scene(WORLD_SCENE)
	return {"ok": true}


## Explicitly imports a reference (version 1) or rebuild save from `source_path`, writing it as the
## rebuild's version 2 save. The source file is never modified. Returns {ok, error}.
func import_save(source_path: String) -> Dictionary:
	var res := SaveManager.import_save(source_path)
	if not res.ok:
		return res
	if not SaveManager.write_save(res.data):
		return {"ok": false, "error": SaveManager.last_error}
	return {"ok": true, "data": res.data}


## Applies validated save data to every manager. Inventory loads before skills and quest (quest checks
## read item counts); progression/reward/save listeners are suppressed meanwhile.
func apply_save_data(data: Dictionary) -> void:
	_suppress_saves += 1
	character = {"name": data.character.name, "appearance": Appearance.sanitize(data.character.appearance)}
	stage = data.get("stage", "island")
	pending_player = data.get("player", {}) if stage == "island" else {}
	var inv := get_node_or_null("/root/InventoryManager")
	var skills := get_node_or_null("/root/SkillsManager")
	var quest := get_node_or_null("/root/QuestManager")
	if inv:
		inv.from_dict(data.get("inventory", {}))
	if skills:
		skills.from_dict(data.get("skills", {}))
	if quest:
		quest.from_dict(data.get("quest", {}))
	_extra_sections = {}
	for key in ["inventory", "skills", "quest"]:
		if data.has(key):
			_extra_sections[key] = data[key]
	adventure_loaded = true
	_suppress_saves -= 1
	_save_pending = false



## The complete save snapshot.
func build_save_data() -> Dictionary:
	var data := {
		"version": SaveManager.VERSION,
		"character": character.duplicate(true),
		"stage": stage,
	}
	var w := world()
	if stage == "island" and w != null and w.player_ready():
		var p := w.player.global_position
		data["player"] = {"position": [p.x, p.y, p.z], "yaw": w.player.facing_yaw()}
	elif stage == "island" and not pending_player.is_empty():
		data["player"] = pending_player.duplicate(true)
	var inv := get_node_or_null("/root/InventoryManager")
	var skills := get_node_or_null("/root/SkillsManager")
	var quest := get_node_or_null("/root/QuestManager")
	data["inventory"] = inv.to_dict() if inv else _extra_sections.get("inventory", {"slots": []})
	data["skills"] = skills.to_dict() if skills else _extra_sections.get("skills", {})
	data["quest"] = quest.to_dict() if quest else _extra_sections.get("quest", {})
	return data


# --- saving ---------------------------------------------------------------------------------------

## Saves now if an adventure is loaded. Returns false (with a visible error) if writing failed.
func save_game() -> bool:
	if not adventure_loaded:
		return true
	if _suppress_saves > 0:
		_save_pending = true
		return true
	var ok := SaveManager.write_save(build_save_data())
	if ok:
		last_save_error = ""
		saved.emit()
	else:
		last_save_error = SaveManager.last_error
		toast(last_save_error, UITheme.DANGER, 6.0)
		save_failed.emit(last_save_error)
	return ok


## Checkpoint save after the current gameplay transaction and all its reports finish (deferred to
## the end of the frame), so state, rewards and XP land in the same snapshot.
func request_save() -> void:
	if not adventure_loaded or _save_pending:
		return
	_save_pending = true
	_flush_save.call_deferred()


func _flush_save() -> void:
	if not _save_pending:
		return
	_save_pending = false
	save_game()


## Blocks checkpoint saves while a multi-step transaction runs; end with end_transaction().
func begin_transaction() -> void:
	_suppress_saves += 1


func end_transaction() -> void:
	_suppress_saves = maxi(_suppress_saves - 1, 0)
	if _suppress_saves == 0 and _save_pending:
		_save_pending = false
		request_save()


func intro_finished() -> void:
	stage = "island"
	set_state(State.PLAYING)
	save_game()


# --- pause, menu and quitting ---------------------------------------------------------------------

func pause_game() -> void:
	if state != State.PLAYING:
		return
	set_state(State.PAUSED)
	get_tree().paused = true


func resume_game() -> void:
	if state != State.PAUSED:
		return
	get_tree().paused = false
	set_state(State.PLAYING)


## Save & Main Menu. Returns false if saving failed (the caller offers retry or leaving without saving).
func save_and_return_to_menu() -> bool:
	if adventure_loaded and not save_game():
		return false
	leave_to_menu()
	return true


## Ends the adventure without saving and returns to the main menu.
func leave_to_menu() -> void:
	end_adventure()
	go_to_main_menu()


func end_adventure() -> void:
	adventure_loaded = false
	pending_player = {}
	_extra_sections = {}
	for n in ["InventoryManager", "SkillsManager", "QuestManager", "DialogueManager"]:
		var m := get_node_or_null("/root/" + n)
		if m and m.has_method("reset"):
			m.reset()


## Save & Exit / window close. Returns false if saving failed (nothing is discarded silently).
func save_and_quit() -> bool:
	if adventure_loaded and not save_game():
		return false
	quit_game()
	return true


## Graceful shutdown: stop audio, wait briefly in real time, then quit. Does not save (callers do).
func quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	get_tree().paused = false
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("shutdown"):
		audio.shutdown()
	await get_tree().create_timer(QUIT_WAIT, true, false, true).timeout
	if quit_handler.is_valid():
		_quitting = false
		quit_handler.call()
		return
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_close()


## Window close: save if an adventure is loaded; if that fails, ask instead of discarding progress.
func request_close() -> void:
	if not adventure_loaded:
		quit_game()
		return
	if save_game():
		quit_game()
		return
	ConfirmPanel.ask("Your progress could not be saved.\n%s" % last_save_error, [
		["Retry", request_close],
		["Quit without saving", quit_game],
		["Cancel", Callable()],
	], "Saving failed")
