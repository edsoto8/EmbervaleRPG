extends Node
## The five tutorial objectives (completed in order) and the island tasks. Gameplay reports events
## here (`report_*`); this turns them into progress. GameManager saves after each completed objective,
## task and reward payment (after the triggering transaction finishes).

signal objective_started(id: String)
signal objective_completed(id: String)
signal progress_changed
signal tutorial_completed
signal task_completed(id: String)
signal reward_paid(id: String)
signal all_tasks_completed

const WASD_GOAL := 4.0
const LOGS_GOAL := 3
const OBJECTIVES := [
	{"id": "learn_to_move", "title": "Learn to move",
		"hint": "Walk with WASD, then click the glowing marker by the dock."},
	{"id": "talk_to_instructor", "title": "Meet the instructor",
		"hint": "Talk to Instructor Maelis in the training courtyard east of the village."},
	{"id": "collect_logs", "title": "Gather logs",
		"hint": "Chop trees in the forest clearing west of the village until you have 3 logs."},
	{"id": "inspect_inventory", "title": "Check your inventory",
		"hint": "Open your inventory with I and examine the logs."},
	{"id": "return_to_instructor", "title": "Report back",
		"hint": "Return to Instructor Maelis for your reward."},
]

var index := 0
var wasd_distance := 0.0
var marker_reached := false
var inventory_opened := false
var logs_inspected := false
var tasks: Array[String] = []
var pending_task_rewards: Array[String] = []
## Runtime only: whether the inventory panel is currently open (reported by the HUD).
var inventory_open := false

var _loading := false
var _retrying := false


func _ready() -> void:
	InventoryManager.inventory_changed.connect(_on_inventory_changed)
	SkillsManager.level_up.connect(func(_s: String, _l: int) -> void: check_level_tasks())


func reset() -> void:
	index = 0
	wasd_distance = 0.0
	marker_reached = false
	inventory_opened = false
	logs_inspected = false
	tasks = []
	pending_task_rewards = []
	inventory_open = false
	progress_changed.emit()


func to_dict() -> Dictionary:
	return {
		"index": index,
		"wasd_distance": wasd_distance,
		"marker_reached": marker_reached,
		"inventory_opened": inventory_opened,
		"logs_inspected": logs_inspected,
		"tasks": tasks.duplicate(),
		"pending_task_rewards": pending_task_rewards.duplicate(),
	}


## Loads validated data without emitting completion events (no rewards or fanfares replay).
func from_dict(data: Dictionary) -> void:
	_loading = true
	index = clampi(int(data.get("index", 0)), 0, OBJECTIVES.size())
	wasd_distance = clampf(float(data.get("wasd_distance", 0.0)), 0.0, WASD_GOAL)
	marker_reached = data.get("marker_reached", false)
	inventory_opened = data.get("inventory_opened", false)
	logs_inspected = data.get("logs_inspected", false)
	tasks.assign(data.get("tasks", []))
	pending_task_rewards.assign(data.get("pending_task_rewards", []))
	inventory_open = false
	_loading = false
	progress_changed.emit()


# --- tutorial -------------------------------------------------------------------------------------

func current_id() -> String:
	return OBJECTIVES[index].id if index < OBJECTIVES.size() else ""


func current_objective() -> Dictionary:
	return OBJECTIVES[index] if index < OBJECTIVES.size() else {}


func is_tutorial_complete() -> bool:
	return index >= OBJECTIVES.size()


func is_completed(id: String) -> bool:
	for i in OBJECTIVES.size():
		if OBJECTIVES[i].id == id:
			return i < index
	return false


## Substep checklist for the tracker: [[text, done], ...].
func substeps() -> Array:
	match current_id():
		"learn_to_move":
			return [["Walk 4 m with WASD (%.1f / 4)" % wasd_distance, wasd_distance >= WASD_GOAL],
					["Click the glowing marker by the dock", marker_reached]]
		"talk_to_instructor":
			return [["Talk to Instructor Maelis", false]]
		"collect_logs":
			return [["Logs: %d / %d" % [mini(InventoryManager.count("logs"), LOGS_GOAL), LOGS_GOAL], false]]
		"inspect_inventory":
			return [["Open your inventory (I)", inventory_opened], ["Examine the logs", logs_inspected]]
		"return_to_instructor":
			return [["Talk to Instructor Maelis", false]]
	return []


func report_keyboard_moved(distance: float) -> void:
	if current_id() != "learn_to_move" or wasd_distance >= WASD_GOAL:
		return
	wasd_distance = minf(wasd_distance + distance, WASD_GOAL)
	progress_changed.emit()
	_check_movement()


func report_marker_reached() -> void:
	if current_id() != "learn_to_move" or marker_reached:
		return
	marker_reached = true
	progress_changed.emit()
	_check_movement()


func _check_movement() -> void:
	if wasd_distance >= WASD_GOAL and marker_reached:
		_complete()


## Maelis's introduction finished with the player accepting the three-log assignment.
func report_assignment_accepted() -> void:
	if current_id() == "talk_to_instructor":
		_complete()


func report_inventory_visibility(open: bool) -> void:
	inventory_open = open
	if open and current_id() == "inspect_inventory" and not inventory_opened:
		inventory_opened = true
		progress_changed.emit()


func report_item_examined(id: String) -> void:
	if current_id() != "inspect_inventory" or not inventory_open or not inventory_opened:
		return
	if id == "logs" and InventoryManager.has("logs"):
		logs_inspected = true
		_complete()


## The Beginner sword was successfully delivered by Maelis's reward conversation.
func report_sword_delivered() -> void:
	if current_id() == "return_to_instructor":
		_complete()


func _on_inventory_changed() -> void:
	if _loading:
		return
	if current_id() == "collect_logs":
		progress_changed.emit()
		if InventoryManager.count("logs") >= LOGS_GOAL:
			_complete()
	retry_pending_rewards()


func _complete() -> void:
	var id := current_id()
	if id == "":
		return
	index += 1
	objective_completed.emit(id)
	GameManager.post_message("Objective complete: %s." % OBJECTIVES[index - 1].title)
	if is_tutorial_complete():
		progress_changed.emit()
		tutorial_completed.emit()
		return
	_activate()


func _activate() -> void:
	match current_id():
		"collect_logs":
			# Logs obtained early count as soon as this objective starts.
			if InventoryManager.count("logs") >= LOGS_GOAL:
				objective_started.emit(current_id())
				_complete()
				return
		"inspect_inventory":
			# Earlier inspections don't count; an already open panel counts as opened now.
			logs_inspected = false
			inventory_opened = inventory_open
	objective_started.emit(current_id())
	progress_changed.emit()


# --- island tasks ---------------------------------------------------------------------------------

func is_task_done(id: String) -> bool:
	return id in tasks


## The next tasks not yet done (for the tracker).
func next_tasks(count: int = 3) -> Array[String]:
	var out: Array[String] = []
	for t in TaskData.ids():
		if not t in tasks:
			out.append(t)
			if out.size() >= count:
				break
	return out


## Completes an island task once and pays its coins (or keeps them pending until there is room).
func report_task(id: String) -> void:
	if not TaskData.is_known(id) or id in tasks:
		return
	tasks.append(id)
	task_completed.emit(id)
	GameManager.post_message("Task complete: %s." % TaskData.text(id))
	_pay(id)
	progress_changed.emit()
	if tasks.size() == TaskData.TASKS.size():
		GameManager.post_message("Driftwood Isle mastered!")
		all_tasks_completed.emit()


func _pay(id: String) -> bool:
	var coins := TaskData.reward(id)
	var was_pending := id in pending_task_rewards
	# Taken off the pending list first so the inventory change this causes can't pay it twice.
	pending_task_rewards.erase(id)
	if InventoryManager.add_item("coins", coins):
		GameManager.post_message("You receive %d coins." % coins)
		reward_paid.emit(id)
		return true
	pending_task_rewards.append(id)
	if not was_pending:
		GameManager.post_message("Your reward of %d coins is waiting. Make room in your inventory to receive it." % coins)
	return false


## Level tasks follow current XP: on level-ups and when a save (including an import) loads.
func check_level_tasks() -> void:
	if SkillsManager.level("attack") >= 5:
		report_task("attack_5")
	if SkillsManager.highest_level() >= 10:
		report_task("level_10")


## Pays any pending task rewards that now fit (called whenever the inventory changes).
func retry_pending_rewards() -> void:
	if pending_task_rewards.is_empty() or _loading or _retrying:
		return
	# Paying adds coins, which re-enters this through inventory_changed; guard against that and
	# skip rewards already paid meanwhile, so each is paid exactly once.
	_retrying = true
	for id in pending_task_rewards.duplicate():
		if id in pending_task_rewards and InventoryManager.can_add("coins", TaskData.reward(id)):
			_pay(id)
	_retrying = false


## After a load: pay rewards that now fit and count logs already held (no events replay).
func catch_up() -> void:
	retry_pending_rewards()
	if current_id() == "collect_logs" and InventoryManager.count("logs") >= LOGS_GOAL:
		_complete()
