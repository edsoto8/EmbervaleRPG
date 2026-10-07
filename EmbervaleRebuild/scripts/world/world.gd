class_name World
extends Node3D
## Root of the gameplay scene: wires the island, player, camera and presentation together, restores
## a loaded adventure (intro or saved position) and owns pause handling.

signal world_ready

@onready var island: TutorialIsland = $TutorialIsland
@onready var player: PlayerController = $Player
@onready var camera_rig: CameraController = $CameraRig
@onready var click_marker: ClickMarker = $ClickMarker

var gameplay_enabled := true
var intro: IntroCutscene
var is_ready := false
var interaction: InteractionSystem
var director: TutorialDirector
var hud: GameHUD


func _ready() -> void:
	add_to_group("world")
	player.camera = camera_rig
	player.nav.island = island
	player.nav.camera = camera_rig.camera
	click_marker.connect_to(player.nav)
	camera_rig.target = player
	SettingsManager.settings_changed.connect(_on_setting)
	camera_rig.sensitivity = SettingsManager.get_value("mouse_sensitivity")
	var loaded := GameManager.adventure_loaded
	if loaded:
		player.set_appearance(GameManager.character.appearance)
	player.teleport(island.landmarks["dock"], 0.0)
	camera_rig.snap()
	player.footstep.connect(_on_footstep)
	AudioManager.play_music("island_theme")
	AudioManager.start_ambience()
	var play_intro := loaded and GameManager.stage == "intro"
	if play_intro:
		set_gameplay_enabled(false)
		player.visible = false
	if not island.is_navigation_ready:
		await island.navigation_ready
	_build_systems(play_intro)
	if play_intro:
		intro = IntroCutscene.new()
		intro.name = "IntroCutscene"
		add_child(intro)
		intro.play(self)
	else:
		if loaded:
			restore_player(GameManager.pending_player)
		GameManager.set_state(GameManager.State.PLAYING)
		set_gameplay_enabled(true)
	is_ready = true
	world_ready.emit()


func _exit_tree() -> void:
	if SettingsManager.settings_changed.is_connected(_on_setting):
		SettingsManager.settings_changed.disconnect(_on_setting)


func _on_footstep(_foot: int) -> void:
	AudioManager.footstep(surface_at(player.global_position))


## Footstep surface under a point.
func surface_at(p: Vector3) -> String:
	if IslandLayout.on_dock(Vector2(p.x, p.z)):
		return "wood"
	match island.terrain.tile_at(p.x, p.z):
		IslandTerrain.Tile.PLAZA, IslandTerrain.Tile.COURTYARD:
			return "stone"
		IslandTerrain.Tile.SAND, IslandTerrain.Tile.PATH, IslandTerrain.Tile.MUD:
			return "sand"
	return "grass"


func _process(_delta: float) -> void:
	# Surf is louder near the shore, birdsong further inland.
	var p := player.global_position
	var inland := (IslandLayout.coast_radius(atan2(p.z, p.x)) - Vector2(p.x, p.z).length()) / 22.0
	AudioManager.set_shore_mix(inland)


func _on_setting(key: String, value: Variant) -> void:
	if key == "mouse_sensitivity":
		camera_rig.sensitivity = value


func _build_systems(hide_hud: bool) -> void:
	interaction = InteractionSystem.new()
	interaction.name = "InteractionSystem"
	add_child(interaction)
	interaction.setup(self)
	director = TutorialDirector.new()
	director.name = "TutorialDirector"
	add_child(director)
	hud = GameHUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(self, director, interaction)
	hud.visible = not hide_hud
	director.setup(self)


## True once the player stands in the world for real (navigation ready, intro over).
func player_ready() -> bool:
	return is_ready and intro == null


## Puts the player at a saved position, or back on the dock if it is not accessible.
func restore_player(data: Dictionary) -> void:
	var dock: Vector3 = island.landmarks["dock"]
	if not data.has("position"):
		player.teleport(dock, 0.0)
		camera_rig.snap()
		return
	var pos := Vector3(data.position[0], data.position[1], data.position[2])
	var yaw: float = data.get("yaw", 0.0)
	if not is_accessible(pos):
		GameManager.post_message("You find yourself back at the dock.")
		pos = dock
		yaw = 0.0
	player.teleport(pos, yaw)
	camera_rig.snap()


## A position is accessible if it is on (or right next to) the navmesh and reachable from the dock.
func is_accessible(pos: Vector3) -> bool:
	if not island.is_navigation_ready:
		return false
	var map := island.navigation_map()
	var closest := NavigationServer3D.map_get_closest_point(map, pos)
	if Vector2(closest.x - pos.x, closest.z - pos.z).length() > 0.8 or absf(closest.y - pos.y) > 1.5:
		return false
	var path := NavigationServer3D.map_get_path(map, island.landmarks["dock"], closest, true)
	if path.is_empty():
		return false
	var end := path[path.size() - 1]
	return Vector2(end.x - closest.x, end.z - closest.z).length() < 0.6


## Enables or disables player movement, clicks and camera input together (cutscenes, dialogue).
func set_gameplay_enabled(enabled: bool) -> void:
	gameplay_enabled = enabled
	player.set_input_enabled(enabled)
	camera_rig.input_enabled = enabled


func intro_finished() -> void:
	intro = null
	hud.visible = true
	set_gameplay_enabled(true)
	GameManager.intro_finished()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if GameManager.state == GameManager.State.PLAYING and not GameManager.is_modal_open():
			get_viewport().set_input_as_handled()
			open_pause_menu()


func open_pause_menu() -> PausePanel:
	if GameManager.state != GameManager.State.PLAYING:
		return null
	# Pausing freezes action and world timers (the tree pauses); it does not cancel them.
	return PausePanel.show_panel()
