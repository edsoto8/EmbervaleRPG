class_name TutorialDirector
extends Node
## Turns world events into QuestManager/InventoryManager reports and owns NPC spawning, objective
## markers, conversations, the sword reward and the closing gate sequence. Autoload signals outlive
## the world, so every connection is undone in _exit_tree.

signal gate_sequence_finished(skipped: bool)
signal conversation_started(npc_id: String)
signal conversation_ended(npc_id: String)

const MARKER_RADIUS := 1.6
const NPC_LOOKS := {
	"maelis": {"body_type": 0, "skin_tone": "c68e63", "hair_style": 2, "hair_color": "2b2018",
			"shirt_color": "7a2e2e", "pants_color": "3a3a3a"},
	"marla": {"body_type": 2, "skin_tone": "f3d2b3", "hair_style": 3, "hair_color": "b8452c",
			"shirt_color": "3e6b35", "pants_color": "8a6a2f"},
	"tobin": {"body_type": 1, "skin_tone": "e0b48f", "hair_style": 1, "hair_color": "8c8c8c",
			"shirt_color": "2f4f7a", "pants_color": "5b3d6e"},
	"pip": {"body_type": 0, "skin_tone": "9c6a43", "hair_style": 4, "hair_color": "d8b45a",
			"shirt_color": "b5622a", "pants_color": "2f4f7a"},
}

var world: World
var island: TutorialIsland
var player: PlayerController
var npcs := {}
var marker: Node3D
var objective_arrow: Node3D
var gate_sequence: GateSequence
var talking_to: Npc = null
var chopping: ChoppableTree = null
var chips: CPUParticles3D
var _pending_completion := false
var _time := 0.0
var _connections: Array = []


func setup(w: World) -> void:
	world = w
	island = w.island
	player = w.player
	_spawn_npcs()
	_build_marker()
	_build_arrow()
	for tree in island.choppable_trees:
		tree.chop_handler = _chop
	_build_chips()
	_link(player.model.action_impact, _on_impact)
	_link(player.keyboard_moved, _on_keyboard_moved)
	_link(player.nav.destination_reached, _on_destination_reached)
	_link(QuestManager.objective_completed, _on_objective_completed)
	_link(QuestManager.progress_changed, _refresh_markers)
	_link(QuestManager.tutorial_completed, _on_tutorial_completed)
	_link(InventoryManager.item_examined, _on_item_examined)
	_link(InventoryManager.inventory_changed, _refresh_markers)
	_link(DialogueManager.dialogue_ended, _on_dialogue_ended)
	_refresh_markers()
	_repair_after_load()


func _link(sig: Signal, cb: Callable) -> void:
	sig.connect(cb)
	_connections.append([sig, cb])


func _exit_tree() -> void:
	for c in _connections:
		if c[0].is_connected(c[1]):
			c[0].disconnect(c[1])
	_connections.clear()
	if DialogueManager.active:
		DialogueManager.end()


# --- NPCs and markers -----------------------------------------------------------------------------

func _spawn_npcs() -> void:
	var lm := island.landmarks
	var maelis := Npc.new().setup("maelis", "Instructor Maelis", NPC_LOOKS.maelis, lm.npc_instructor, PI * 0.5)
	var marla_yaw := IslandLayout.yaw_towards(IslandLayout.MERCHANT, IslandLayout.PLAZA)
	var marla := Npc.new().setup("marla", "Marla", NPC_LOOKS.marla, lm.npc_merchant, marla_yaw)
	var stall_dir := (IslandLayout.PLAZA - IslandLayout.MARKET_STALL).normalized()
	marla.approach_point = island.ground_point(IslandLayout.MARKET_STALL + stall_dir * 0.55)
	var tobin := Npc.new().setup("tobin", "Old Tobin", NPC_LOOKS.tobin, lm.npc_fisher,
			IslandLayout.yaw_towards(IslandLayout.FISHER, IslandLayout.POND))
	var pip := Npc.new().setup("pip", "Pip", NPC_LOOKS.pip, lm.npc_wanderer, 0.3)
	pip.wanders = true
	pip.model_scale = 0.86
	for npc in [maelis, marla, tobin, pip]:
		register_npc(npc)


## Adds a villager to the world and routes their conversations here (later directors add theirs).
func register_npc(npc: Npc) -> void:
	npc.island = island
	world.add_child(npc)
	npc.talk_requested.connect(talk_to)
	npcs[npc.npc_id] = npc


func _build_marker() -> void:
	marker = Node3D.new()
	marker.name = "MoveMarker"
	world.add_child(marker)
	marker.global_position = island.landmarks.move_marker + Vector3(0, 0.02, 0)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(1.0, 0.85, 0.3, 0.45)
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ring := MeshInstance3D.new()
	ring.mesh = PropFactory.cylinder_mesh(0.75, 0.75, 0.04, 16)
	ring.material_override = glow
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(ring)
	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.55
	beam_mesh.bottom_radius = 0.7
	beam_mesh.height = 2.4
	beam_mesh.radial_segments = 12
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false
	beam.mesh = beam_mesh
	var beam_mat := glow.duplicate()
	beam_mat.albedo_color = Color(1.0, 0.9, 0.45, 0.18)
	beam.material_override = beam_mat
	beam.position.y = 1.2
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(beam)


func _build_arrow() -> void:
	objective_arrow = Node3D.new()
	objective_arrow.name = "ObjectiveArrow"
	world.add_child(objective_arrow)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("ffd36a")
	var cone := MeshInstance3D.new()
	cone.mesh = PropFactory.cylinder_mesh(0.22, 0.0, 0.45, 4)
	cone.material_override = mat
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	objective_arrow.add_child(cone)
	objective_arrow.visible = false


## Post-tutorial objective providers (Milestone 7): quest_target_provider returns a world position or
## INF; arrow_npc_provider returns the Npc to mark with the arrow, or null.
var quest_target_provider := Callable()
var arrow_npc_provider := Callable()
## Conversations for villagers added by later directors: npc_id -> Callable returning a graph.
var graph_providers := {}


## World position of the current objective (minimap star and arrow), or INF when there is none.
func objective_target() -> Vector3:
	if QuestManager.is_tutorial_complete() and quest_target_provider.is_valid():
		return quest_target_provider.call()
	match QuestManager.current_id():
		"learn_to_move":
			return island.landmarks.move_marker if not QuestManager.marker_reached else Vector3.INF
		"talk_to_instructor", "return_to_instructor":
			return npcs.maelis.global_position
		"collect_logs":
			return island.landmarks.forest_clearing
	return Vector3.INF


func _refresh_markers() -> void:
	if marker:
		marker.visible = QuestManager.current_id() == "learn_to_move" and not QuestManager.marker_reached
	if objective_arrow:
		_arrow_npc = arrow_npc()
		objective_arrow.visible = _arrow_npc != null


var _arrow_npc: Npc = null


func arrow_npc() -> Npc:
	var id := QuestManager.current_id()
	if id == "talk_to_instructor" or id == "return_to_instructor":
		return npcs.maelis
	if QuestManager.is_tutorial_complete() and arrow_npc_provider.is_valid():
		return arrow_npc_provider.call()
	return null


func _process(delta: float) -> void:
	_time += delta
	if marker and marker.visible:
		marker.rotation.y = _time * 0.8
		marker.scale = Vector3.ONE * (1.0 + 0.06 * sin(_time * 3.0))
	if objective_arrow and objective_arrow.visible and is_instance_valid(_arrow_npc):
		objective_arrow.global_position = _arrow_npc.global_position + Vector3(0, 2.55 + 0.12 * sin(_time * 3.0), 0)
		objective_arrow.rotation.y = _time * 1.5


# --- world events -> reports ----------------------------------------------------------------------

func _playing() -> bool:
	return GameManager.state == GameManager.State.PLAYING


func _on_keyboard_moved(distance: float) -> void:
	if _playing():
		QuestManager.report_keyboard_moved(distance)


func _on_destination_reached(point: Vector3, by_click: bool) -> void:
	if by_click and _near_marker(player.global_position):
		QuestManager.report_marker_reached()


func _physics_process(_delta: float) -> void:
	# Reaching the marker counts while walking there by click, even if the route continues past it.
	if player and player.nav.is_active() and player.nav.from_click and _near_marker(player.global_position):
		QuestManager.report_marker_reached()


func _near_marker(p: Vector3) -> bool:
	return QuestManager.current_id() == "learn_to_move" and not QuestManager.marker_reached \
			and Vector2(p.x - island.landmarks.move_marker.x, p.z - island.landmarks.move_marker.z).length() <= MARKER_RADIUS


func _on_item_examined(id: String, _slot: int) -> void:
	GameManager.post_message(ItemDB.examine_text(id))
	QuestManager.report_item_examined(id)


func _on_objective_completed(_id: String) -> void:
	player.model.play_action("cheer", 1.4)
	_refresh_markers()


# --- chopping (normal trees; Milestone 6 adds skills) ----------------------------------------------

func _build_chips() -> void:
	chips = CPUParticles3D.new()
	chips.name = "WoodChips"
	chips.emitting = false
	chips.one_shot = true
	chips.amount = 12
	chips.lifetime = 0.9
	chips.explosiveness = 1.0
	chips.direction = Vector3(0, 1, 0)
	chips.spread = 70.0
	chips.initial_velocity_min = 2.0
	chips.initial_velocity_max = 3.5
	chips.gravity = Vector3(0, -9.8, 0)
	chips.mesh = PropFactory.box_mesh(Vector3(0.07, 0.03, 0.05))
	chips.material_override = PropFactory.character_mat(Color("c9a774"))
	chips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(chips)


## Every axe impact shakes the tree, sprays chips and sounds the chop (world event, forwarded).
func _on_impact(action_name: String) -> void:
	if action_name != "chop" or chopping == null or not is_instance_valid(chopping):
		return
	chopping.strike()
	var to_player := (player.global_position - chopping.global_position)
	to_player.y = 0
	chips.global_position = chopping.global_position + to_player.normalized() * 0.35 + Vector3(0, 1.0, 0)
	chips.restart()
	AudioManager.play("chop", -3.0, randf_range(0.92, 1.08))


func _chop(tree: ChoppableTree, p: PlayerController) -> void:
	if tree.is_stump:
		return
	if not InventoryManager.can_add("logs"):
		GameManager.post_message("Your inventory is too full to hold any more logs.")
		return
	GameManager.post_message("You swing your axe at the tree.")
	chopping = tree
	var ok: bool = await p.perform_action("chop", SkillData.TREES.normal.seconds, tree.global_position)
	if chopping == tree:
		chopping = null
	if not ok or tree.is_stump:
		return
	if not InventoryManager.add_item("logs"):
		GameManager.post_message("Your inventory is too full to hold any more logs.")
		return
	GameManager.post_message("You get some logs.")
	tree.fell()


# --- conversations --------------------------------------------------------------------------------

func talk_to(npc: Npc) -> void:
	if DialogueManager.active or not _playing():
		return
	var graph := _graph_for(npc)
	player.nav.cancel("dialogue")
	player.cancel_action("dialogue")
	world.set_gameplay_enabled(false)
	talking_to = npc
	npc.begin_talk(player.global_position)
	player.model.face_towards(npc.global_position)
	var info := {
		"player": {"name": GameManager.character.name, "appearance": GameManager.character.appearance},
		npc.npc_id: {"name": npc.display_name, "appearance": npc.appearance},
	}
	conversation_started.emit(npc.npc_id)
	DialogueManager.start(npc.npc_id, graph, info)


func _graph_for(npc: Npc) -> Dictionary:
	if graph_providers.has(npc.npc_id):
		return graph_providers[npc.npc_id].call()
	var ctx := {"name": GameManager.character.name, "logs": InventoryManager.count("logs"), "give_sword": _give_sword}
	match npc.npc_id:
		"maelis":
			var stage := QuestManager.current_id()
			if stage == "":
				stage = "afterward"
				ctx["needs_sword"] = not InventoryManager.has("beginner_sword")
			return TutorialDialogues.maelis(stage, ctx)
		"marla":
			return TutorialDialogues.marla(QuestManager.is_tutorial_complete())
		"tobin":
			return TutorialDialogues.tobin(tobin_context())
		_:
			return TutorialDialogues.pip()


## Tobin's context; SkillsDirector (Milestone 6) extends it with fishing gear.
var tobin_context_provider := Callable()


func tobin_context() -> Dictionary:
	if tobin_context_provider.is_valid():
		return tobin_context_provider.call()
	return {"fishing_enabled": false}


## Gives the Beginner sword once. Already owning one counts as delivered (no duplicates).
func _give_sword() -> bool:
	if InventoryManager.has("beginner_sword"):
		return true
	if InventoryManager.add_item("beginner_sword"):
		GameManager.post_message("Maelis hands you a Beginner sword.")
		return true
	GameManager.post_message("Your inventory is too full for the sword. Drop or use something, then talk to Maelis again.")
	return false


func _on_dialogue_ended(_npc_id: String, outcome: Dictionary) -> void:
	var npc := talking_to
	talking_to = null
	if npc:
		npc.end_talk()
	if outcome.get("accepted", false):
		QuestManager.report_assignment_accepted()
	if outcome.get("sword_given", false):
		QuestManager.report_sword_delivered()
	conversation_ended.emit(_npc_id)
	if _pending_completion:
		_pending_completion = false
		start_gate_sequence()
	elif GameManager.state == GameManager.State.PLAYING:
		world.set_gameplay_enabled(true)


func _on_tutorial_completed() -> void:
	if DialogueManager.active:
		_pending_completion = true
	else:
		start_gate_sequence()


# --- closing sequence -----------------------------------------------------------------------------

func start_gate_sequence() -> void:
	world.set_gameplay_enabled(false)
	gate_sequence = GateSequence.new()
	gate_sequence.name = "GateSequence"
	world.add_child(gate_sequence)
	gate_sequence.finished.connect(_on_gate_finished)
	gate_sequence.play(world)


func _on_gate_finished(skipped: bool) -> void:
	gate_sequence = null
	gate_sequence_finished.emit(skipped)
	TutorialCompletePanel.show_panel(world)


## Imported or older saves: a completed tutorial without the sword gets one replacement if it fits;
## otherwise Maelis offers it again (retryable) when talked to.
func _repair_after_load() -> void:
	if QuestManager.is_tutorial_complete() and not InventoryManager.has("beginner_sword"):
		if InventoryManager.add_item("beginner_sword"):
			GameManager.post_message("A replacement Beginner sword has been placed in your pack.")
			GameManager.request_save()
		else:
			GameManager.post_message("Your pack is full; talk to Maelis to collect a replacement Beginner sword.")
