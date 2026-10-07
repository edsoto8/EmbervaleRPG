class_name TaskData
extends RefCounted
## Island tasks (SPEC_SKILLS.md S8), in display order, with coin rewards.

const TASKS := [
	{"id": "catch_shrimp", "text": "Catch a shrimp", "coins": 10},
	{"id": "light_fire", "text": "Light a fire", "coins": 10},
	{"id": "cook_fish", "text": "Cook a fish", "coins": 10},
	{"id": "eat_cooked", "text": "Eat some food you cooked", "coins": 10},
	{"id": "chop_oak", "text": "Chop an oak tree", "coins": 15},
	{"id": "sell_item", "text": "Sell something to Marla", "coins": 10},
	{"id": "buy_steel_axe", "text": "Buy the steel axe", "coins": 20},
	{"id": "attack_5", "text": "Reach Attack level 5", "coins": 20},
	{"id": "chop_willow", "text": "Chop a willow tree", "coins": 25},
	{"id": "level_10", "text": "Reach level 10 in any skill", "coins": 50},
]


static func ids() -> Array[String]:
	var out: Array[String] = []
	for t in TASKS:
		out.append(t.id)
	return out


static func is_known(id: String) -> bool:
	for t in TASKS:
		if t.id == id:
			return true
	return false


static func reward(id: String) -> int:
	for t in TASKS:
		if t.id == id:
			return t.coins
	return 0


static func text(id: String) -> String:
	for t in TASKS:
		if t.id == id:
			return t.text
	return id
