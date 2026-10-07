extends Node
## Plays the procedurally synthesised music, ambience and sound effects. Gameplay never calls this for
## game events: it listens to autoload signals (inventory, quest, dialogue, skills) and to button
## presses (SceneTree.node_added). Scenes only start/stop music and ambience and forward a few world
## events (footsteps, axe impacts, inventory toggle). Under the headless display server one-shots are
## counted but not started.

const BUSES := ["Music", "Ambience", "SFX"]
const SFX_VOICES := 10
## Slow recipes rendered once on worker threads (each with its own RNG).
const PRERENDERED := {
	"menu_theme": [1101, "menu_theme"],
	"island_theme": [1102, "island_theme"],
	"surf": [1103, "surf_loop"],
	"birds": [1104, "birds_loop"],
}

var headless := false
var music: AudioStreamPlayer
var surf: AudioStreamPlayer
var birds: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _cache := {}
var _counts := {}
var _tasks := {}
var _rendered := {}
var _mutex := Mutex.new()
var _wanted_music := ""
var _ambience_on := false
var _rng := RandomNumberGenerator.new()
var _shut_down := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	headless = DisplayServer.get_name() == "headless"
	_rng.seed = 2024
	_setup_buses()
	music = _player("Music", -8.0)
	surf = _player("Ambience", -14.0)
	birds = _player("Ambience", -20.0)
	for i in SFX_VOICES:
		_voices.append(_player("SFX", 0.0))
	for key in PRERENDERED:
		var entry: Array = PRERENDERED[key]
		_tasks[key] = WorkerThreadPool.add_task(_render.bind(key, entry[0], entry[1]), true, "synth " + key)
	InventoryManager.item_added.connect(_on_item_added)
	QuestManager.objective_completed.connect(func(_id: String) -> void: play("jingle"))
	QuestManager.tutorial_completed.connect(func() -> void: play("fanfare"))
	QuestManager.all_tasks_completed.connect(func() -> void: play("fanfare"))
	QuestManager.reward_paid.connect(func(_id: String) -> void: play("coins"))
	DialogueManager.line_shown.connect(func(_n: Dictionary) -> void: play("dialogue", -6.0))
	var skills := get_node_or_null("/root/SkillsManager")
	if skills:
		skills.level_up.connect(func(_s: String, _l: int) -> void: play("level_up"))
	get_tree().node_added.connect(_on_node_added)


func _setup_buses() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")


func _player(bus: String, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = volume_db
	add_child(p)
	return p


## Worker-thread render; uses only its own RNG.
func _render(sound: String, seed_value: int, recipe: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var stream := Synth.render(recipe, rng)
	_mutex.lock()
	_rendered[sound] = stream
	_mutex.unlock()


func is_rendered(sound: String) -> bool:
	_mutex.lock()
	var ok := _rendered.has(sound)
	_mutex.unlock()
	return ok


func _process(_delta: float) -> void:
	for key in _tasks.keys():
		if WorkerThreadPool.is_task_completed(_tasks[key]):
			WorkerThreadPool.wait_for_task_completion(_tasks[key])
			_tasks.erase(key)
	if _wanted_music != "" and music.stream == null and is_rendered(_wanted_music):
		_start_music()
	if _ambience_on and surf.stream == null and is_rendered("surf") and is_rendered("birds"):
		_start_ambience()


# --- public API ---------------------------------------------------------------------------------------

## Plays a one-shot by name. Returns the voice (null when headless or shut down).
func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	_counts[sound] = _counts.get(sound, 0) + 1
	if headless or _shut_down:
		return null
	var stream := _stream(sound)
	if stream == null:
		return null
	var v := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	v.stream = stream
	v.volume_db = volume_db
	v.pitch_scale = pitch
	v.play()
	return v


## How many times a one-shot has been requested (works headless; used by tests).
func count(sound: String) -> int:
	return _counts.get(sound, 0)


func reset_counts() -> void:
	_counts.clear()


func _stream(sound: String) -> AudioStreamWAV:
	if _cache.has(sound):
		return _cache[sound]
	var s: AudioStreamWAV = null
	match sound:
		"click": s = Synth.click()
		"pickup": s = Synth.pickup()
		"dialogue": s = Synth.dialogue_blip()
		"inventory": s = Synth.inventory(_rng)
		"jingle": s = Synth.jingle()
		"fanfare": s = Synth.fanfare()
		"level_up": s = Synth.level_up()
		"chop": s = Synth.chop(_rng)
		"splash": s = Synth.splash(_rng)
		"fire": s = Synth.fire(_rng)
		"eat": s = Synth.eat(_rng)
		"coins": s = Synth.coins()
		"swing": s = Synth.swing(_rng)
		"hit": s = Synth.hit(_rng)
		_:
			if sound.begins_with("step_"):
				s = Synth.footstep(sound.trim_prefix("step_").get_slice("_", 0), _rng)
	if s != null:
		_cache[sound] = s
	return s


## Footstep on a surface ("grass", "wood", "stone", "sand"), with a little variation.
func footstep(surface: String) -> void:
	play("step_%s_%d" % [surface, _rng.randi_range(0, 2)], -10.0, _rng.randf_range(0.92, 1.08))


func play_music(sound: String) -> void:
	if _wanted_music == sound and music.playing:
		return
	_wanted_music = sound
	music.stop()
	music.stream = null
	if not headless and not _shut_down and is_rendered(sound):
		_start_music()


func _start_music() -> void:
	_mutex.lock()
	music.stream = _rendered.get(_wanted_music)
	_mutex.unlock()
	if headless or _shut_down:
		return
	music.volume_db = -40.0
	music.play()
	var t := create_tween()
	t.tween_property(music, "volume_db", -10.0, 1.5)


func stop_music() -> void:
	_wanted_music = ""
	music.stop()
	music.stream = null


func current_music() -> String:
	return _wanted_music


func start_ambience() -> void:
	_ambience_on = true
	if is_rendered("surf") and is_rendered("birds"):
		_start_ambience()


func _start_ambience() -> void:
	_mutex.lock()
	surf.stream = _rendered.get("surf")
	birds.stream = _rendered.get("birds")
	_mutex.unlock()
	if headless or _shut_down:
		return
	surf.play()
	birds.play()


func stop_ambience() -> void:
	_ambience_on = false
	surf.stop()
	birds.stop()
	surf.stream = null
	birds.stream = null


func ambience_active() -> bool:
	return _ambience_on


## Surf gets louder near the shore (0 = on the beach, 1 = far inland); birds the other way.
func set_shore_mix(inland: float) -> void:
	surf.volume_db = lerpf(-8.0, -26.0, clampf(inland, 0.0, 1.0))
	birds.volume_db = lerpf(-24.0, -14.0, clampf(inland, 0.0, 1.0))


# --- listeners --------------------------------------------------------------------------------------

func _on_item_added(id: String, _qty: int) -> void:
	if id == "coins":
		play("coins", -4.0)
	else:
		play("pickup", -4.0)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(func() -> void: play("click", -8.0))


## Test hook: undo shutdown() so later tests can keep using audio.
func resume_after_shutdown() -> void:
	_shut_down = false


func _exit_tree() -> void:
	# Worker renders reference this node; let them finish before it is freed.
	_wait_for_renders()


func _wait_for_renders() -> void:
	for key in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key])
	_tasks.clear()


## Stops everything and waits for worker renders (graceful quit).
func shutdown() -> void:
	_shut_down = true
	music.stop()
	surf.stop()
	birds.stop()
	for v in _voices:
		v.stop()
		v.stream = null
	music.stream = null
	surf.stream = null
	birds.stream = null
	_wait_for_renders()
