class_name QuestData
extends RefCounted
## Island quests (SPEC_SMITHING.md K4): stages, checklist flags and rewards. Progress lives in
## QuestManager.quests as {id: {stage, flags}}; stage 0 is "not started" and the last stage is "complete".

const QUESTS := {
	"smiths_apprentice": {
		"title": "The Smith's Apprentice",
		"giver": "brann",
		"stages": 3,
		"start_hint": "New quest: talk to Brann at the smithy east of the plaza.",
		"hint": "Brann wants proof you can work metal: make a bronze dagger and bring it to him.",
		"flags": [
			{"id": "mined_copper", "text": "Mine some copper ore in the quarry"},
			{"id": "mined_tin", "text": "Mine some tin ore in the quarry"},
			{"id": "smelted_bronze", "text": "Smelt a bronze bar at the furnace"},
			{"id": "smithed_dagger", "text": "Smith a bronze dagger on the anvil"},
		],
		"hand_in": "bronze_dagger",
		"hand_in_text": "Bring the bronze dagger to Brann",
		"coins": 60,
		"xp": {"smithing": 250.0, "mining": 100.0},
	},
}


static func is_known(id: String) -> bool:
	return QUESTS.has(id)


static func title(id: String) -> String:
	return QUESTS[id].title if QUESTS.has(id) else id


static func final_stage(id: String) -> int:
	return QUESTS[id].stages - 1 if QUESTS.has(id) else 0


static func flag_ids(id: String) -> Array[String]:
	var out: Array[String] = []
	if QUESTS.has(id):
		for f in QUESTS[id].flags:
			out.append(f.id)
	return out


static func ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(QUESTS.keys())
	return out
