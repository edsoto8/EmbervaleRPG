class_name SkillsDirector
extends Node
## Runs the skill activities (SPEC_SKILLS.md): woodcutting, fishing, firemaking, cooking, eating,
## Attack training, Marla's shop and Tobin's gear, plus level-up sparks. Every activity uses the
## shared cancellable action API and grants nothing for an interrupted attempt; every skill roll goes
## through SkillsManager.chance(); every inventory change that can fail is a preflighted transaction.

signal fire_lit(fire: Fire)

const FIRE_CLEARANCE := 0.45
const FIRE_SPACING := 2.0

var world: World
var island: TutorialIsland
var player: PlayerController
var fires: Array[Fire] = []
var fishing_spots: Array[FishingSpot] = []
var stall: MarketStall
var sparks: CPUParticles3D
var shop: ShopPanel
var _cooking_fire: Fire = null
var _connections: Array = []


func setup(w: World) -> void:
	world = w
	island = w.island
	player = w.player
	for tree in island.choppable_trees:
		tree.chop_handler = chop
	for d in island.dummies:
		d.attack_handler = train
	for k in 2:
		var a := PI * 0.5 + (k - 0.5) * 0.7
		var spot := FishingSpot.new()
		spot.name = "FishingSpot%d" % k
		w.add_child(spot)
		spot.global_position = Vector3(IslandLayout.POND.x + cos(a) * 5.4, IslandLayout.POND_LEVEL, IslandLayout.POND.y + sin(a) * 5.4)
		spot.fish_handler = fish
		fishing_spots.append(spot)
	stall = MarketStall.new()
	w.add_child(stall)
	stall.setup(island)
	stall.browse_handler = browse
	_build_sparks()
	_link(SkillsManager.level_up, _on_level_up)
	w.director.tobin_context_provider = tobin_context
	w.hud.inventory_panel.action_provider = item_actions
	# Level tasks follow current XP when a save (or an import) loads; pending rewards that now fit
	# are paid and logs already held count.
	QuestManager.check_level_tasks()
	QuestManager.catch_up()


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


# --- woodcutting ------------------------------------------------------------------------------------

func chop(tree: ChoppableTree, p: PlayerController) -> void:
	var data := tree.data()
	if SkillsManager.level("woodcutting") < data.level:
		_msg("You need a Woodcutting level of %d to chop this tree." % data.level)
		return
	if tree.is_stump:
		return
	_msg("You swing your axe at the %s." % tree.interaction_name().to_lower())
	while true:
		if not InventoryManager.can_add(data.log):
			_msg("Your inventory is too full to hold any more logs.")
			break
		world.director.chopping = tree
		var seconds := SkillData.chop_seconds(tree.tree_type, SkillsManager.level("woodcutting"), InventoryManager.has("steel_axe"))
		var ok: bool = await p.perform_action("chop", seconds, tree.global_position)
		if world.director.chopping == tree:
			world.director.chopping = null
		if not ok or not is_instance_valid(tree) or tree.is_stump:
			return
		GameManager.begin_transaction()
		if not InventoryManager.add_item(data.log):
			GameManager.end_transaction()
			_msg("Your inventory is too full to hold any more logs.")
			return
		SkillsManager.add_xp("woodcutting", data.xp)
		_msg("You get some %s." % ItemDB.display_name(data.log).to_lower())
		if tree.tree_type == "oak":
			QuestManager.report_task("chop_oak")
		elif tree.tree_type == "willow":
			QuestManager.report_task("chop_willow")
		# One log and its XP first, then the depletion roll.
		var falls := SkillsManager.chance(data.deplete)
		GameManager.end_transaction()
		if falls:
			tree.fell()
			if tree.tree_type != "normal":
				_msg("The %s falls." % tree.interaction_name().to_lower())
			return


# --- fishing ----------------------------------------------------------------------------------------

func has_rod() -> bool:
	return InventoryManager.has("fishing_rod") or InventoryManager.has("oak_fishing_rod")


func fish(spot: FishingSpot, p: PlayerController) -> void:
	if not has_rod():
		_msg("You need a fishing rod. Old Tobin by the pond might lend you one.")
		return
	_msg("You cast out your line.")
	while true:
		if not has_rod():
			_msg("You need a fishing rod to keep fishing.")
			return
		var lvl := SkillsManager.level("fishing")
		var outputs := ["raw_shrimp"]
		if lvl >= SkillData.FISH.raw_trout.level:
			outputs.append("raw_trout")
		for o in outputs:
			if not InventoryManager.can_add(o):
				_msg("Your inventory is too full to hold any more fish.")
				return
		var ok: bool = await p.perform_action("fish", SkillData.FISH_CAST_SECONDS, spot.global_position)
		if not ok or not has_rod():
			return
		AudioManager.play("splash", -8.0)
		if not SkillsManager.chance(SkillData.catch_chance(lvl, InventoryManager.has("oak_fishing_rod"))):
			continue
		var caught := "raw_trout" if SkillsManager.chance(SkillData.trout_chance(lvl)) else "raw_shrimp"
		GameManager.begin_transaction()
		if not InventoryManager.add_item(caught):
			GameManager.end_transaction()
			_msg("Your inventory is too full to hold any more fish.")
			return
		SkillsManager.add_xp("fishing", SkillData.FISH[caught].xp)
		_msg("You catch some %s." % ItemDB.display_name(caught).to_lower().trim_prefix("raw "))
		if caught == "raw_shrimp":
			QuestManager.report_task("catch_shrimp")
		GameManager.end_transaction()


# --- firemaking -------------------------------------------------------------------------------------

## Where a fire would go: 1 m ahead of the player.
func fire_spot() -> Vector3:
	var yaw := player.facing_yaw()
	var p := player.global_position + Vector3(-sin(yaw), 0, -cos(yaw)) * 1.0
	p.y = island.ground_height(p.x, p.z)
	return p


## Empty when a fire may be lit at `p`, otherwise the reason it can't.
func placement_error(p: Vector3) -> String:
	var p2 := Vector2(p.x, p.z)
	if IslandLayout.on_dock(p2, 0.6) or (absf(p.x) < 2.2 and p.z < IslandLayout.GATE.y - 0.5):
		return "You can't light a fire on the dock or the bridge."
	var tile := island.terrain.tile_at(p.x, p.z)
	if tile == IslandTerrain.Tile.SEA or tile == IslandTerrain.Tile.POND_BED or p.y < 0.2 \
			or p2.distance_to(IslandLayout.POND) < 7.0:
		return "You can't light a fire in the water."
	if IslandLayout.in_plaza(p2, 0.5) or IslandLayout.in_courtyard(p2, 0.5):
		return "You can't light a fire here; find some open ground."
	for f in fires:
		if is_instance_valid(f) and Vector2(f.global_position.x, f.global_position.z).distance_to(p2) < FIRE_SPACING:
			return "There's already a fire here."
	var q := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = FIRE_CLEARANCE
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.55, 0))
	q.collision_mask = Layers.OBSTACLES | Layers.BOUNDARY
	if not player.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
		return "There's something in the way."
	var map := island.navigation_map()
	var c := NavigationServer3D.map_get_closest_point(map, p)
	if Vector2(c.x - p.x, c.z - p.z).length() > 0.6:
		return "You can't light a fire there."
	return ""


func light(log_id: String) -> void:
	if not InventoryManager.has("tinderbox"):
		_msg("You need a tinderbox to light a fire.")
		return
	var req: int = SkillData.FIRE_LOGS[log_id].level
	if SkillsManager.level("firemaking") < req:
		_msg("You need a Firemaking level of %d to light these logs." % req)
		return
	var spot := fire_spot()
	var err := placement_error(spot)
	if err != "":
		_msg(err)
		return
	player.nav.cancel("light")
	_msg("You attempt to light the logs.")
	while true:
		var ok: bool = await player.perform_action("light", SkillData.LIGHT_SECONDS, spot)
		if not ok:
			return
		# Revalidate the spot and the logs at completion.
		err = placement_error(spot)
		if err != "":
			_msg(err)
			return
		if not InventoryManager.has(log_id):
			_msg("You have no logs left to light.")
			return
		if not InventoryManager.has("tinderbox"):
			_msg("You need a tinderbox to light a fire.")
			return
		if not SkillsManager.chance(SkillData.light_chance(SkillsManager.level("firemaking"), req)):
			_msg("You fail to light a fire.")
			continue
		GameManager.begin_transaction()
		InventoryManager.remove_item(log_id)
		var fire := Fire.new()
		fire.name = "Fire"
		world.add_child(fire)
		fire.global_position = spot
		fire.cook_handler = cook
		fire.expired.connect(_on_fire_expired)
		fires.append(fire)
		SkillsManager.add_xp("firemaking", SkillData.FIRE_LOGS[log_id].xp)
		_msg("The fire catches and the logs begin to burn.")
		QuestManager.report_task("light_fire")
		GameManager.end_transaction()
		AudioManager.play("fire", -4.0)
		fire_lit.emit(fire)
		return


func _on_fire_expired(fire: Fire) -> void:
	fires.erase(fire)
	if _cooking_fire == fire:
		_cooking_fire = null
		if player.current_action() == "cook":
			player.cancel_action("fire_out")
			_msg("The fire has burned out.")


# --- cooking ----------------------------------------------------------------------------------------

## Raw fish the player can cook now, trout first.
func cookable() -> Array[String]:
	var out: Array[String] = []
	for raw in SkillData.COOKING:
		if InventoryManager.has(raw) and SkillsManager.level("cooking") >= SkillData.COOKING[raw].level:
			out.append(raw)
	return out


func cook(fire: Fire, p: PlayerController) -> void:
	if cookable().is_empty():
		if InventoryManager.has("raw_trout"):
			_msg("You need a Cooking level of %d to cook trout." % SkillData.COOKING.raw_trout.level)
		else:
			_msg("You have no raw fish to cook.")
		return
	_cooking_fire = fire
	while is_instance_valid(fire) and fire.is_burning():
		var list := cookable()
		if list.is_empty():
			_msg("You have nothing left to cook.")
			break
		var raw: String = list[0]
		var data: Dictionary = SkillData.COOKING[raw]
		# Reserve room for either outcome before starting.
		if not InventoryManager.preflight({raw: 1}, {data.cooked: 1}).ok or not InventoryManager.preflight({raw: 1}, {data.burnt: 1}).ok:
			_msg("Your inventory is too full to cook. Drop or sell something first.")
			break
		var ok: bool = await p.perform_action("cook", SkillData.COOK_SECONDS, fire.global_position)
		if not ok or not is_instance_valid(fire) or not fire.is_burning():
			break
		var lvl := SkillsManager.level("cooking")
		GameManager.begin_transaction()
		if SkillsManager.chance(SkillData.burn_chance(raw, lvl)):
			if InventoryManager.transact({raw: 1}, {data.burnt: 1}).ok:
				_msg("You accidentally burn the %s." % ItemDB.display_name(data.cooked).to_lower())
				if SkillsManager.chance(SkillData.SINGE_CHANCE):
					SkillsManager.damage(1)
					_msg("You singe your fingers.")
		else:
			if InventoryManager.transact({raw: 1}, {data.cooked: 1}).ok:
				SkillsManager.add_xp("cooking", data.xp)
				_msg("You cook the %s." % ItemDB.display_name(data.cooked).to_lower())
				QuestManager.report_task("cook_fish")
		GameManager.end_transaction()
	if _cooking_fire == fire:
		_cooking_fire = null


# --- eating -----------------------------------------------------------------------------------------

func eat(id: String) -> void:
	if not ItemDB.is_food(id) or not InventoryManager.has(id):
		return
	player.nav.cancel("eat")
	var ok: bool = await player.perform_action("eat", SkillData.EAT_SECONDS)
	if not ok:
		return
	GameManager.begin_transaction()
	if not InventoryManager.remove_item(id):
		GameManager.end_transaction()
		return
	var healed := SkillsManager.heal(ItemDB.heal_amount(id))
	AudioManager.play("eat", -4.0)
	_msg("You eat the %s.%s" % [ItemDB.display_name(id).to_lower(), " It heals some health." if healed > 0 else ""])
	# Fish stacks have no provenance: cooked shrimp/trout counts once the player has cooked a fish.
	if (id == "shrimp" or id == "trout") and QuestManager.is_task_done("cook_fish"):
		QuestManager.report_task("eat_cooked")
	GameManager.end_transaction()


## Inventory actions for an item (Light, Eat); Drop is added by the panel.
func item_actions(id: String, _slot: int) -> Array:
	var out: Array = []
	if SkillData.FIRE_LOGS.has(id):
		out.append(["Light", func() -> void: light(id)])
	if ItemDB.is_food(id):
		out.append(["Eat", func() -> void: eat(id)])
	return out


# --- attack training ----------------------------------------------------------------------------------

func train(dummy: TrainingDummy, p: PlayerController) -> void:
	if not QuestManager.is_tutorial_complete() or not InventoryManager.has("beginner_sword"):
		_msg("You need the Beginner sword from Maelis before you can train here.")
		return
	if SkillsManager.level("attack") >= SkillData.DUMMY_MAX_LEVEL:
		_msg("You can learn nothing more from this dummy.")
		return
	while SkillsManager.level("attack") < SkillData.DUMMY_MAX_LEVEL:
		var ok: bool = await p.perform_action("attack", SkillData.ATTACK_SECONDS, dummy.global_position)
		if not ok:
			return
		dummy.wobble()
		AudioManager.play("hit", -6.0)
		SkillsManager.add_xp("attack", SkillData.ATTACK_XP)
	_msg("You can learn nothing more from this dummy.")


# --- shop ---------------------------------------------------------------------------------------------

const SHOP_STOCK := ["steel_axe", "oak_fishing_rod", "tinderbox", "bread"]
const UNIQUE_TOOLS := ["steel_axe", "oak_fishing_rod"]


func browse(_stall: MarketStall, _p: PlayerController) -> void:
	if not QuestManager.is_tutorial_complete():
		_msg("Marla's stall opens to adventurers once Maelis has finished your training.")
		return
	player.cancel_action("shop")
	shop = ShopPanel.show_panel(self)


## Buys one item. Returns {ok, error}.
func buy(id: String) -> Dictionary:
	var price := ItemDB.buy_price(id)
	if not id in SHOP_STOCK or price <= 0:
		return {"ok": false, "error": "Marla doesn't sell that."}
	if id in UNIQUE_TOOLS and InventoryManager.has(id):
		return {"ok": false, "error": "You already have a %s." % ItemDB.display_name(id).to_lower()}
	if InventoryManager.count("coins") < price:
		return {"ok": false, "error": "You need %d coins for the %s." % [price, ItemDB.display_name(id).to_lower()]}
	GameManager.begin_transaction()
	var res := InventoryManager.transact({"coins": price}, {id: 1})
	if res.ok:
		_msg("You buy a %s for %d coins." % [ItemDB.display_name(id).to_lower(), price])
		if id == "steel_axe":
			QuestManager.report_task("buy_steel_axe")
	GameManager.end_transaction()
	if not res.ok:
		return {"ok": false, "error": res.get("error", "That won't fit.")}
	return {"ok": true}


## Sells one or all of an item. Returns {ok, error, coins}.
func sell(id: String, all: bool) -> Dictionary:
	var price := ItemDB.sell_price(id)
	if price <= 0 or ItemDB.is_protected(id):
		return {"ok": false, "error": "Marla won't buy that."}
	var qty := InventoryManager.count(id) if all else 1
	if qty <= 0:
		return {"ok": false, "error": "You don't have any."}
	if price * qty > ItemDB.MAX_QTY or InventoryManager.count("coins") + price * qty > ItemDB.MAX_QTY:
		return {"ok": false, "error": "That's more coins than you can carry."}
	GameManager.begin_transaction()
	var res := InventoryManager.transact({id: qty}, {"coins": price * qty})
	if res.ok:
		_msg("You sell %s for %d coins." % [("%d %s" % [qty, ItemDB.display_name(id).to_lower()]) if qty > 1 else "the " + ItemDB.display_name(id).to_lower(), price * qty])
		QuestManager.report_task("sell_item")
	GameManager.end_transaction()
	if not res.ok:
		return {"ok": false, "error": res.get("error", "That won't fit.")}
	return {"ok": true, "coins": price * qty}


# --- Tobin's gear -------------------------------------------------------------------------------------

func tobin_context() -> Dictionary:
	return {
		"fishing_enabled": true,
		"has_rod": has_rod(),
		"has_tinderbox": InventoryManager.has("tinderbox"),
		"fishing_level": SkillsManager.level("fishing"),
		"give_gear": give_gear,
	}


## Lends the missing basic rod and/or tinderbox, all or nothing (repeatable when there's no room).
func give_gear() -> bool:
	var add := {}
	if not has_rod():
		add["fishing_rod"] = 1
	if not InventoryManager.has("tinderbox"):
		add["tinderbox"] = 1
	if add.is_empty():
		return true
	var res := InventoryManager.transact({}, add)
	if not res.ok:
		_msg("Your inventory is too full for Tobin's gear. Make some room and ask again.")
		return false
	_msg("Old Tobin hands you %s." % " and ".join(add.keys().map(func(k: String) -> String: return "a " + ItemDB.display_name(k).to_lower())))
	return true


# --- level-up sparks ----------------------------------------------------------------------------------

func _build_sparks() -> void:
	sparks = CPUParticles3D.new()
	sparks.name = "LevelUpSparks"
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = 40
	sparks.lifetime = 1.4
	sparks.explosiveness = 0.9
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	sparks.emission_ring_radius = 0.9
	sparks.emission_ring_inner_radius = 0.6
	sparks.emission_ring_height = 0.2
	sparks.emission_ring_axis = Vector3.UP
	sparks.direction = Vector3.UP
	sparks.spread = 25.0
	sparks.initial_velocity_min = 1.5
	sparks.initial_velocity_max = 3.0
	sparks.gravity = Vector3(0, -1.0, 0)
	var mesh := PropFactory.box_mesh(Vector3(0.06, 0.06, 0.06))
	sparks.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("ffd36a")
	mat.emission_enabled = true
	mat.emission = Color("ffc040")
	mat.emission_energy_multiplier = 2.0
	sparks.material_override = mat
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(sparks)


func _on_level_up(_skill: String, _level: int) -> void:
	sparks.global_position = player.global_position + Vector3(0, 0.3, 0)
	sparks.restart()
