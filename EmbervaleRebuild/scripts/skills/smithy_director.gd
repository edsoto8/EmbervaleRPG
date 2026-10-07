class_name SmithyDirector
extends Node
## Milestone 7 (SPEC_SMITHING.md): mining in the quarry, smelting and smithing at Brann's forge, and
## Brann's quest "The Smith's Apprentice". Activities use the shared cancellable action API and grant
## nothing for an interrupted attempt; skill rolls go through SkillsManager.chance(); every inventory
## change that can fail is a preflighted transaction.

const QUEST := "smiths_apprentice"
const MAKE_ALL := 1000
const BRANN_LOOK := {"body_type": 2, "skin_tone": "c68e63", "hair_style": 0, "hair_color": "5a3a1e",
		"shirt_color": "8a6a2f", "pants_color": "3a3a3a"}

var world: World
var island: TutorialIsland
var player: PlayerController
var furnace: CraftStation
var anvil: CraftStation
var brann: Npc
var panel: CraftPanel
var chips: CPUParticles3D
var sparks: CPUParticles3D
var _mining: MiningRock = null
var _working_at: CraftStation = null
var _connections: Array = []


func setup(w: World) -> void:
	world = w
	island = w.island
	player = w.player
	for rock in island.mining_rocks:
		rock.mine_handler = mine
	furnace = CraftStation.new()
	w.add_child(furnace)
	furnace.setup(island, "furnace")
	furnace.use_handler = use_station
	anvil = CraftStation.new()
	w.add_child(anvil)
	anvil.setup(island, "anvil")
	anvil.use_handler = use_station
	brann = Npc.new().setup("brann", "Brann", BRANN_LOOK, island.landmarks.npc_smith,
			IslandLayout.yaw_towards(IslandLayout.SMITH, IslandLayout.PLAZA))
	w.director.register_npc(brann)
	w.director.graph_providers["brann"] = brann_graph
	w.director.quest_target_provider = quest_target
	w.director.arrow_npc_provider = arrow_npc
	chips = _particles("RockChips", Color("8b8a84"), Vector3(0.06, 0.05, 0.06), -9.8, 10)
	sparks = _particles("AnvilSparks", Color("ffc04a"), Vector3(0.04, 0.04, 0.04), -6.0, 14)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color("ffd36a")
	spark_mat.emission_enabled = true
	spark_mat.emission = Color("ffb030")
	spark_mat.emission_energy_multiplier = 2.5
	sparks.material_override = spark_mat
	_link(player.model.action_impact, _on_impact)
	w.director._refresh_markers()


func _particles(node_name: String, color: Color, size: Vector3, gravity: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = node_name
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 65.0
	p.initial_velocity_min = 1.8
	p.initial_velocity_max = 3.2
	p.gravity = Vector3(0, gravity, 0)
	p.mesh = PropFactory.box_mesh(size)
	p.material_override = PropFactory.character_mat(color)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(p)
	return p


func _link(sig: Signal, cb: Callable) -> void:
	sig.connect(cb)
	_connections.append([sig, cb])


func _exit_tree() -> void:
	for c in _connections:
		if c[0].is_connected(c[1]):
			c[0].disconnect(c[1])
	_connections.clear()


static func _msg(text: String) -> void:
	GameManager.post_message(text)


## Pickaxe impacts chip the rock; hammer impacts ring the anvil (world events, forwarded to audio).
func _on_impact(action_name: String) -> void:
	if action_name == "mine" and _mining != null and is_instance_valid(_mining):
		_mining.strike()
		var to_player := player.global_position - _mining.global_position
		to_player.y = 0
		chips.global_position = _mining.global_position + to_player.normalized() * 0.6 + Vector3(0, 0.7, 0)
		chips.restart()
		AudioManager.play("mine", -4.0, randf_range(0.94, 1.06))
	elif action_name == "smith" and _working_at == anvil:
		sparks.global_position = anvil.global_position + Vector3(0, 1.05, 0)
		sparks.restart()
		AudioManager.play("anvil", -8.0, randf_range(0.97, 1.03))


# --- tools --------------------------------------------------------------------------------------------

func has_pickaxe() -> bool:
	for id in SkillData.PICKAXES:
		if InventoryManager.has(id):
			return true
	return false


func has_hammer() -> bool:
	return InventoryManager.has("hammer")


## Gives Brann's missing tools (bronze pickaxe and/or hammer), all or nothing. True when nothing is
## missing afterwards.
func give_tools() -> bool:
	var add := {}
	if not has_pickaxe():
		add["bronze_pickaxe"] = 1
	if not has_hammer():
		add["hammer"] = 1
	if add.is_empty():
		return true
	var res := InventoryManager.transact({}, add)
	if not res.ok:
		_msg("Your inventory is too full for Brann's tools. Make some room and ask again.")
		return false
	_msg("Brann hands you %s." % " and ".join(add.keys().map(func(k: String) -> String: return "a " + ItemDB.display_name(k).to_lower())))
	return true


# --- mining -------------------------------------------------------------------------------------------

func mine(rock: MiningRock, p: PlayerController) -> void:
	var data := rock.data()
	if rock.is_depleted:
		return
	if not has_pickaxe():
		_msg("You need a pickaxe to mine this rock. Brann the blacksmith might lend you one.")
		return
	if SkillsManager.level("mining") < data.level:
		_msg("You need a Mining level of %d to mine this rock." % data.level)
		return
	if not InventoryManager.can_add(data.ore):
		_msg("Your inventory is too full to hold any more ore.")
		return
	_msg("You swing your pickaxe at the rock.")
	_mining = rock
	var seconds := SkillData.mine_seconds(rock.rock_type, SkillsManager.level("mining"), InventoryManager.has("steel_pickaxe"))
	var ok: bool = await p.perform_action("mine", seconds, rock.global_position)
	if _mining == rock:
		_mining = null
	if not ok or not is_instance_valid(rock) or rock.is_depleted:
		return
	# Revalidate at completion: the pickaxe may have been dropped meanwhile.
	if not has_pickaxe():
		_msg("You need a pickaxe to mine this rock.")
		return
	GameManager.begin_transaction()
	if not InventoryManager.add_item(data.ore):
		GameManager.end_transaction()
		_msg("Your inventory is too full to hold any more ore.")
		return
	SkillsManager.add_xp("mining", data.xp)
	_msg("You manage to mine some %s." % rock.rock_type)
	if rock.rock_type == "copper":
		QuestManager.report_quest_flag(QUEST, "mined_copper")
	elif rock.rock_type == "tin":
		QuestManager.report_quest_flag(QUEST, "mined_tin")
	GameManager.end_transaction()
	rock.deplete()


# --- smelting and smithing ----------------------------------------------------------------------------

func use_station(station: CraftStation, _p: PlayerController) -> void:
	if station.station == "anvil" and not has_hammer():
		_msg("You need a hammer to work the metal. Brann keeps spares, and Marla sells them.")
		return
	player.cancel_action("craft_menu")
	panel = CraftPanel.show_panel(self, station)


## Empty when one of `id` can be made now, otherwise the reason it can't.
func craft_error(id: String) -> String:
	var r: Dictionary = SkillData.RECIPES[id]
	if r.station == "anvil" and not has_hammer():
		return "You need a hammer."
	if SkillsManager.level("smithing") < r.level:
		return "You need a Smithing level of %d." % r.level
	for input in r.inputs:
		if InventoryManager.count(input) < r.inputs[input]:
			if r.station == "furnace":
				return "You don't have the ore."
			return "You need %d %s." % [r.inputs[input], ItemDB.display_name(input).to_lower()]
	return ""


## How many of `id` the current ingredients allow.
func makeable(id: String) -> int:
	var r: Dictionary = SkillData.RECIPES[id]
	var n := MAKE_ALL
	for input in r.inputs:
		n = mini(n, InventoryManager.count(input) / int(r.inputs[input]))
	return n


## Makes up to `count` of a recipe at its station, one timed step at a time.
func craft(id: String, count: int, station: CraftStation) -> void:
	var r: Dictionary = SkillData.RECIPES[id]
	var smelting: bool = r.station == "furnace"
	var made := 0
	_working_at = station
	station.set_active(true)
	while made < count:
		var err := craft_error(id)
		if err != "":
			if made == 0:
				_msg(err)
			else:
				_msg("You have nothing left to %s." % ("smelt" if smelting else "smith"))
			break
		if not InventoryManager.preflight(r.inputs, {id: 1}).ok:
			_msg("Your inventory is too full. Drop or sell something first.")
			break
		var ok: bool = await player.perform_action("smelt" if smelting else "smith",
				SkillData.SMELT_SECONDS if smelting else SkillData.SMITH_SECONDS, station.global_position)
		if not ok:
			break
		# Recheck ingredients, level and the hammer at completion.
		err = craft_error(id)
		if err != "":
			_msg(err)
			break
		GameManager.begin_transaction()
		if smelting and not SkillsManager.chance(SkillData.smelt_chance(id, SkillsManager.level("smithing"))):
			if InventoryManager.transact(r.inputs, {}).ok:
				_msg("The iron ore is too impure and crumbles away.")
		else:
			var res := InventoryManager.transact(r.inputs, {id: 1})
			if res.ok:
				SkillsManager.add_xp("smithing", r.xp)
				if smelting:
					_msg("You retrieve a %s." % ItemDB.display_name(id).to_lower())
				else:
					_msg("You hammer the metal into a %s." % ItemDB.display_name(id).to_lower())
				if id == "bronze_bar":
					QuestManager.report_quest_flag(QUEST, "smelted_bronze")
				elif id == "bronze_dagger":
					QuestManager.report_quest_flag(QUEST, "smithed_dagger")
			else:
				GameManager.end_transaction()
				_msg("Your inventory is too full. Drop or sell something first.")
				break
		GameManager.end_transaction()
		if smelting:
			AudioManager.play("fire", -6.0, 1.2)
		made += 1
	if is_instance_valid(station):
		station.set_active(false)
	if _working_at == station:
		_working_at = null


# --- Brann and the quest ------------------------------------------------------------------------------

func needs_tools() -> bool:
	return not has_pickaxe() or not has_hammer()


func brann_graph() -> Dictionary:
	return TutorialDialogues.brann({
		"name": GameManager.character.name,
		"tutorial_complete": QuestManager.is_tutorial_complete(),
		"stage": QuestManager.quest_stage(QUEST),
		"needs_tools": needs_tools(),
		"has_dagger": InventoryManager.has("bronze_dagger"),
		"next_step": next_step_text(),
		"accept": accept_quest,
		"give_tools": give_tools,
		"hand_in": hand_in,
	})


## Starts the quest (once) and hands over the tools; true when the tools were delivered.
func accept_quest() -> bool:
	QuestManager.start_quest(QUEST)
	return give_tools()


## The dagger for 60 coins plus Smithing and Mining XP, completing the quest, as one transaction.
func hand_in() -> bool:
	if QuestManager.quest_stage(QUEST) != 1 or not InventoryManager.has("bronze_dagger"):
		return false
	var info: Dictionary = QuestData.QUESTS[QUEST]
	GameManager.begin_transaction()
	var res := InventoryManager.transact({"bronze_dagger": 1}, {"coins": info.coins})
	if res.ok:
		_msg("You hand Brann the bronze dagger. He pays you %d coins." % info.coins)
		for skill in info.xp:
			SkillsManager.add_xp(skill, info.xp[skill])
		QuestManager.complete_quest(QUEST)
	GameManager.end_transaction()
	return res.ok


## What the tracker and Brann suggest next while the quest is active.
func next_step_text() -> String:
	if InventoryManager.has("bronze_dagger"):
		return "Bring the dagger back to me."
	if InventoryManager.has("bronze_bar"):
		return "Hammer that bar into a dagger on my anvil."
	if InventoryManager.has("copper_ore") and InventoryManager.has("tin_ore"):
		return "Smelt your copper and tin into a bronze bar at my furnace."
	if InventoryManager.has("copper_ore"):
		return "You'll want tin ore as well as copper."
	if InventoryManager.has("tin_ore"):
		return "You'll want copper ore as well as tin."
	return "Mine copper and tin in the quarry, north-east of the gate path."


## Minimap star after the tutorial: Brann to start or hand in, otherwise the next station.
func quest_target() -> Vector3:
	var stage := QuestManager.quest_stage(QUEST)
	if stage == 0:
		return brann.global_position
	if stage >= QuestData.final_stage(QUEST):
		return Vector3.INF
	if InventoryManager.has("bronze_dagger"):
		return brann.global_position
	if InventoryManager.has("bronze_bar"):
		return anvil.front
	if InventoryManager.has("copper_ore") and InventoryManager.has("tin_ore"):
		return furnace.front
	return island.landmarks.quarry


func arrow_npc() -> Npc:
	var stage := QuestManager.quest_stage(QUEST)
	if stage == 0 or (stage == 1 and InventoryManager.has("bronze_dagger")):
		return brann
	return null
