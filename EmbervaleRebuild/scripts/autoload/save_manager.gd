extends Node
## Reads, writes and validates the JSON adventure save (SPEC_SAVE.md). It never decides *when* to
## save (GameManager does) and never touches runtime state: validate() returns normalised data and
## everything is checked before anything changes.
##
## Writes are atomic: write a temporary file, read it back and validate it, keep the previous valid
## save as the backup, then replace the destination. A corrupt primary is preserved for inspection.

signal save_written(path: String)
signal save_failed(message: String)

const VERSION := 2
const SLOT_COUNT := 28
const STAGES := ["intro", "island"]

## Test hook: the next write fails at this step ("open", "verify" or "replace"); cleared after use.
var fail_next_write := ""
var last_error := ""


func save_path() -> String:
	return AppPaths.save_path()


func backup_path() -> String:
	return save_path().get_basename() + ".backup.json"


func temp_path() -> String:
	return save_path().get_basename() + ".tmp"


# --- reading ------------------------------------------------------------------------------------

## Status of one file: "missing", "valid", "corrupt" (unreadable/invalid) or "unsupported" (newer).
func file_status(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": "missing"}
	var text := FileAccess.get_file_as_string(path)
	if text == "" and FileAccess.get_open_error() != OK:
		return {"status": "corrupt", "error": "The save file could not be read."}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"status": "corrupt", "error": "The save file is damaged (line %d: %s)." % [json.get_error_line(), json.get_error_message()]}
	var result := validate(json.data)
	if not result.ok:
		return {"status": "unsupported" if result.get("unsupported", false) else "corrupt", "error": result.error}
	return {"status": "valid", "data": result.data, "saved_at": result.data.get("saved_at", "")}


## Summary for the main menu: whether Continue is possible and what to tell the player.
func save_status() -> Dictionary:
	var primary := file_status(save_path())
	var backup := file_status(backup_path())
	var out := {"primary": primary.status, "backup": backup.status, "can_continue": false, "message": ""}
	match primary.status:
		"valid":
			out.can_continue = true
		"missing":
			if backup.status == "valid":
				out.can_continue = true
				out.needs_recovery = true
				out.message = "Your save file is missing, but a backup was found."
		"corrupt":
			out.message = primary.error
			if backup.status == "valid":
				out.can_continue = true
				out.needs_recovery = true
				out.message += " A backup from %s can be restored." % _pretty_time(backup.saved_at)
		"unsupported":
			out.message = primary.error
	return out


func has_valid_save() -> bool:
	return save_status().can_continue


## Loads the primary save. Returns {ok, data, error}.
func load_save() -> Dictionary:
	var st := file_status(save_path())
	if st.status == "valid":
		return {"ok": true, "data": st.data}
	return {"ok": false, "error": st.get("error", "There is no saved adventure.")}


## Restores the backup over a damaged or missing primary, keeping the damaged file for inspection.
func recover_from_backup() -> Dictionary:
	var backup := file_status(backup_path())
	if backup.status != "valid":
		return {"ok": false, "error": "The backup save is not usable."}
	if FileAccess.file_exists(save_path()):
		if not _preserve_corrupt():
			return {"ok": false, "error": "The damaged save could not be moved aside."}
	if DirAccess.copy_absolute(backup_path(), save_path()) != OK:
		return {"ok": false, "error": "The backup could not be restored."}
	return {"ok": true, "data": backup.data}


# --- writing ------------------------------------------------------------------------------------

## Moves the primary save aside as savegame.corrupt-<time>.json. Returns false if it can't.
func _preserve_corrupt() -> bool:
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "-")
	var keep := save_path().get_basename() + ".corrupt-%s.json" % stamp
	var n := 1
	while FileAccess.file_exists(keep):
		keep = save_path().get_basename() + ".corrupt-%s-%d.json" % [stamp, n]
		n += 1
	return DirAccess.rename_absolute(save_path(), keep) == OK


## Atomically writes a snapshot. Returns true on success; on failure the previous save is untouched,
## `last_error` explains why and save_failed is emitted.
func write_save(data: Dictionary) -> bool:
	var snapshot := data.duplicate(true)
	snapshot["version"] = VERSION
	snapshot["saved_at"] = Time.get_datetime_string_from_system(true) + "Z"
	var check := validate(snapshot)
	if not check.ok:
		return _fail("The game could not be saved: %s" % check.error)
	var text := JSON.stringify(snapshot, "\t")
	DirAccess.make_dir_recursive_absolute(save_path().get_base_dir())
	var f: FileAccess = null if _consume_failure("open") else FileAccess.open(temp_path(), FileAccess.WRITE)
	if f == null:
		return _fail("The game could not be saved (could not write %s)." % temp_path().get_file())
	f.store_string(text)
	f.close()
	var back := file_status(temp_path())
	if back.status != "valid" or _consume_failure("verify"):
		DirAccess.remove_absolute(temp_path())
		return _fail("The game could not be saved (the written file did not verify).")
	# Keep the current save as the known-good backup before replacing it.
	if file_status(save_path()).status == "valid":
		if DirAccess.copy_absolute(save_path(), backup_path()) != OK:
			DirAccess.remove_absolute(temp_path())
			return _fail("The game could not be saved (could not back up the previous save).")
	if _consume_failure("replace"):
		DirAccess.remove_absolute(temp_path())
		return _fail("The game could not be saved (could not replace the save file).")
	# Never overwrite a damaged primary: keep it for inspection.
	if file_status(save_path()).status == "corrupt":
		_preserve_corrupt()
	var err := DirAccess.rename_absolute(temp_path(), save_path())
	if err != OK and FileAccess.file_exists(save_path()) and file_status(backup_path()).status == "valid":
		# Some platforms refuse to rename over an existing file; the backup now holds the old save.
		DirAccess.remove_absolute(save_path())
		err = DirAccess.rename_absolute(temp_path(), save_path())
	if err != OK:
		DirAccess.remove_absolute(temp_path())
		return _fail("The game could not be saved (could not replace the save file).")
	last_error = ""
	save_written.emit(save_path())
	return true


func _consume_failure(step: String) -> bool:
	if fail_next_write == step:
		fail_next_write = ""
		return true
	return false


func _fail(message: String) -> bool:
	last_error = message
	push_warning(message)
	save_failed.emit(message)
	return false


## Explicitly imports a reference-game (version 1) or rebuild save from another location. The source
## file is only read; the result is validated, migrated and written as version 2 in the rebuild
## directory. Returns {ok, data, error}.
func import_save(source_path: String) -> Dictionary:
	if not FileAccess.file_exists(source_path):
		return {"ok": false, "error": "That file does not exist."}
	var text := FileAccess.get_file_as_string(source_path)
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "error": "That file is not a readable save (line %d: %s)." % [json.get_error_line(), json.get_error_message()]}
	var result := validate(json.data)
	if not result.ok:
		return {"ok": false, "error": result.error}
	result.data["imported_from_version"] = result.source_version
	return {"ok": true, "data": result.data}


# --- validation ---------------------------------------------------------------------------------

## Validates and normalises raw parsed JSON. Returns {ok, data, error, source_version, unsupported}.
## Version 1 data is migrated to version 2 in memory. Never coerces malformed values into items.
func validate(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return _invalid("The save file does not contain a save.")
	var d: Dictionary = raw
	if not d.has("version"):
		return _invalid("The save file has no version number.")
	var version: Variant = d.version
	if not _is_integer(version):
		return _invalid("The save file's version number is invalid.")
	var v := int(version)
	if v > VERSION:
		var r := _invalid("This save was made by a newer version of Embervale (save version %d). This version can load saves up to version %d." % [v, VERSION])
		r.unsupported = true
		return r
	if v < 1:
		return _invalid("The save file's version number (%d) is not supported." % v)
	var out := {"version": VERSION}
	if d.get("saved_at") is String:
		out.saved_at = d.saved_at
	# Character (required).
	if not d.has("character") or not d.character is Dictionary:
		return _invalid("The save file has no character.")
	var ch: Dictionary = d.character
	var char_name := ""
	if ch.get("name") is String:
		char_name = Appearance.clean_name(ch.name)
	if not Appearance.is_valid_name(char_name):
		char_name = Appearance.DEFAULT_NAME
	out.character = {"name": char_name, "appearance": Appearance.sanitize(ch.get("appearance"))}
	# Stage.
	if d.has("stage"):
		if not d.stage is String or not d.stage in STAGES:
			return _invalid("The save file's stage (%s) is not recognised." % str(d.stage))
		out.stage = d.stage
	else:
		out.stage = "island"
	# Player position (optional; invalid -> dock spawn).
	var pl: Variant = d.get("player")
	if pl is Dictionary and _is_vec3(pl.get("position")) and _is_finite_number(pl.get("yaw")):
		out.player = {"position": [float(pl.position[0]), float(pl.position[1]), float(pl.position[2])],
				"yaw": float(pl.yaw)}
	# Quest.
	var quest := _validate_quest(d.get("quest"))
	if quest.has("error"):
		return _invalid(quest.error)
	out.quest = quest.data
	# Inventory.
	var inv := _validate_inventory(d.get("inventory"))
	if inv.has("error"):
		return _invalid(inv.error)
	out.inventory = inv.data
	# Skills (legacy top-level hitpoints moves inside; nested wins).
	var sk := _validate_skills(d.get("skills"), d.get("hitpoints"))
	if sk.has("error"):
		return _invalid(sk.error)
	out.skills = sk.data
	if v == 1:
		# Legacy completed tasks are treated as already paid.
		out.quest.pending_task_rewards = []
	return {"ok": true, "data": out, "source_version": v}


func _invalid(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _validate_quest(q: Variant) -> Dictionary:
	var out := {"index": 0, "wasd_distance": 0.0, "marker_reached": false, "inventory_opened": false,
			"logs_inspected": false, "tasks": [], "pending_task_rewards": [], "quests": {}}
	if q == null:
		return {"data": out}
	if not q is Dictionary:
		return {"error": "The save file's quest progress is malformed."}
	var qd: Dictionary = q
	if _is_finite_number(qd.get("index")):
		out.index = clampi(int(floor(float(qd.index))), 0, 5)
	if _is_finite_number(qd.get("wasd_distance")):
		out.wasd_distance = clampf(float(qd.wasd_distance), 0.0, 4.0)
	for flag in ["marker_reached", "inventory_opened", "logs_inspected"]:
		out[flag] = qd.get(flag) is bool and qd[flag]
	if qd.has("tasks"):
		if not qd.tasks is Array:
			return {"error": "The save file's task list is malformed."}
		for t in qd.tasks:
			if t is String and TaskData.is_known(t) and not t in out.tasks:
				out.tasks.append(t)
	if qd.has("pending_task_rewards"):
		if not qd.pending_task_rewards is Array:
			return {"error": "The save file's pending rewards are malformed."}
		for t in qd.pending_task_rewards:
			if t is String and t in out.tasks and not t in out.pending_task_rewards:
				out.pending_task_rewards.append(t)
	# Quests (Milestone 7): unknown ids ignored, stage clamped, only known flags kept once.
	if qd.has("quests"):
		if not qd.quests is Dictionary:
			return {"error": "The save file's quest list is malformed."}
		for id in qd.quests:
			var e: Variant = qd.quests[id]
			if not id is String or not QuestData.is_known(id) or not e is Dictionary:
				continue
			var entry := {"stage": 0, "flags": []}
			if _is_finite_number(e.get("stage")):
				entry.stage = clampi(int(floor(float(e.stage))), 0, QuestData.final_stage(id))
			if e.get("flags") is Array:
				var known := QuestData.flag_ids(id)
				for f in e.flags:
					if f is String and f in known and not f in entry.flags:
						entry.flags.append(f)
			out.quests[id] = entry
	return {"data": out}


func _validate_inventory(inv: Variant) -> Dictionary:
	var slots: Array = []
	slots.resize(SLOT_COUNT)
	if inv == null:
		return {"data": {"slots": slots}}
	if not inv is Dictionary:
		return {"error": "The save file's inventory is malformed."}
	var raw: Variant = inv.get("slots", [])
	if not raw is Array:
		return {"error": "The save file's inventory slots are malformed."}
	if raw.size() > SLOT_COUNT:
		return {"error": "The save file's inventory has %d slots (at most %d)." % [raw.size(), SLOT_COUNT]}
	var first_slot := {}
	for i in raw.size():
		var e: Variant = raw[i]
		if e == null:
			continue
		if not e is Dictionary or not e.get("id") is String:
			return {"error": "Inventory slot %d is malformed." % (i + 1)}
		var id: String = e.id
		if not ItemDB.exists(id):
			return {"error": "Inventory slot %d holds an unknown item (%s)." % [i + 1, id]}
		var qty: Variant = e.get("qty")
		if not _is_integer(qty) or float(qty) < 1.0 or float(qty) > ItemDB.MAX_QTY:
			return {"error": "Inventory slot %d has an invalid quantity." % (i + 1)}
		var n := int(qty)
		if not ItemDB.is_stackable(id):
			if n != 1:
				return {"error": "Inventory slot %d has %d of an item that can't stack." % [i + 1, n]}
			slots[i] = {"id": id, "qty": 1}
			continue
		if first_slot.has(id):
			var j: int = first_slot[id]
			if slots[j].qty + n > ItemDB.MAX_QTY:
				return {"error": "The inventory holds too many %s." % ItemDB.display_name(id)}
			slots[j].qty += n
		else:
			first_slot[id] = i
			slots[i] = {"id": id, "qty": n}
	return {"data": {"slots": slots}}


func _validate_skills(sk: Variant, legacy_hp: Variant) -> Dictionary:
	var xp := {}
	for s in SkillData.SKILLS:
		xp[s] = 0.0
	var hp := SkillData.MAX_HITPOINTS
	var hp_source: Variant = legacy_hp
	if sk != null:
		if not sk is Dictionary:
			return {"error": "The save file's skills are malformed."}
		if sk.has("xp"):
			if not sk.xp is Dictionary:
				return {"error": "The save file's skill experience is malformed."}
			for s in SkillData.SKILLS:
				var v: Variant = sk.xp.get(s)
				if _is_finite_number(v) and float(v) >= 0.0:
					xp[s] = minf(float(v), SkillData.xp_cap())
		if sk.has("hitpoints"):
			hp_source = sk.hitpoints
	if _is_finite_number(hp_source):
		hp = clampi(int(floor(float(hp_source))), 1, SkillData.MAX_HITPOINTS)
	return {"data": {"xp": xp, "hitpoints": hp}}


static func _is_finite_number(v: Variant) -> bool:
	return (v is int) or (v is float and is_finite(v))


static func _is_integer(v: Variant) -> bool:
	if v is int:
		return true
	return v is float and is_finite(v) and v == floor(v) and absf(v) <= ItemDB.MAX_QTY


static func _is_vec3(v: Variant) -> bool:
	if not v is Array or v.size() != 3:
		return false
	for c in v:
		if not _is_finite_number(c):
			return false
	return true


static func _pretty_time(stamp: String) -> String:
	if stamp == "":
		return "an earlier session"
	return stamp.replace("T", " ").trim_suffix("Z") + " UTC"
