class_name World
extends Node3D
## Root of the gameplay scene: wires the island, player, camera and presentation together.

signal world_ready

@onready var island: TutorialIsland = $TutorialIsland
@onready var player: PlayerController = $Player
@onready var camera_rig: CameraController = $CameraRig
@onready var click_marker: ClickMarker = $ClickMarker

var gameplay_enabled := true


func _ready() -> void:
	player.camera = camera_rig
	player.nav.island = island
	player.nav.camera = camera_rig.camera
	click_marker.connect_to(player.nav)
	camera_rig.target = player
	player.teleport(island.landmarks["dock"], 0.0)
	camera_rig.snap()
	if not island.is_navigation_ready:
		await island.navigation_ready
	world_ready.emit()


## Enables or disables player movement, clicks and camera input together (cutscenes, dialogue).
func set_gameplay_enabled(enabled: bool) -> void:
	gameplay_enabled = enabled
	player.set_input_enabled(enabled)
	camera_rig.input_enabled = enabled
