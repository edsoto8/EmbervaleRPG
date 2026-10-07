class_name ItemDB
extends RefCounted
## Every item: display name, stacking, examine text, prices, healing and icon recipe (icons are drawn
## in code by ItemIcon). Don't name static functions after Object methods (hence display_name()).

const MAX_QTY := 9007199254740991  ## Largest exact integer in JSON (2^53 - 1).

const ITEMS := {
	"logs": {"name": "Logs", "stack": true, "examine": "A number of wooden logs.", "sell": 2,
		"icon": "log", "color": Color("8a6440")},
	"oak_logs": {"name": "Oak logs", "stack": true, "examine": "Logs cut from an oak tree.", "sell": 5,
		"icon": "log", "color": Color("a07a45")},
	"willow_logs": {"name": "Willow logs", "stack": true, "examine": "Pale logs cut from a willow tree.", "sell": 8,
		"icon": "log", "color": Color("b9a274")},
	"raw_shrimp": {"name": "Raw shrimp", "stack": true, "examine": "I should cook this before eating it.", "sell": 1,
		"icon": "shrimp", "color": Color("d98a8a")},
	"shrimp": {"name": "Shrimp", "stack": true, "examine": "Some nicely cooked shrimp.", "sell": 4, "heal": 3,
		"icon": "shrimp", "color": Color("e0753a")},
	"burnt_shrimp": {"name": "Burnt shrimp", "stack": true, "examine": "Oops. These are ruined.",
		"icon": "shrimp", "color": Color("3a2f28")},
	"raw_trout": {"name": "Raw trout", "stack": true, "examine": "A fresh trout from the pond.", "sell": 5,
		"icon": "fish", "color": Color("8fa6b8")},
	"trout": {"name": "Trout", "stack": true, "examine": "A nicely cooked trout.", "sell": 12, "heal": 7,
		"icon": "fish", "color": Color("c9874a")},
	"burnt_trout": {"name": "Burnt trout", "stack": true, "examine": "A blackened, inedible trout.",
		"icon": "fish", "color": Color("3a2f28")},
	"bread": {"name": "Bread", "stack": true, "examine": "A crusty loaf from Marla's stall.", "sell": 2, "heal": 2,
		"buy": 6, "icon": "bread", "color": Color("d8a55a")},
	"coins": {"name": "Coins", "stack": true, "examine": "Shiny gold coins.", "icon": "coins",
		"color": Color("e8c24a")},
	"beginner_sword": {"name": "Beginner sword", "stack": false, "protected": true,
		"examine": "A light training sword from Instructor Maelis.", "icon": "sword", "color": Color("b9c0c6")},
	"fishing_rod": {"name": "Fishing rod", "stack": false, "examine": "A simple rod for catching fish.",
		"icon": "rod", "color": Color("8a6440")},
	"oak_fishing_rod": {"name": "Oak fishing rod", "stack": false, "buy": 45,
		"examine": "A sturdy oak rod. Fish seem to bite more often.", "icon": "rod", "color": Color("b07a3a")},
	"tinderbox": {"name": "Tinderbox", "stack": false, "buy": 5, "examine": "Useful for lighting fires.",
		"icon": "tinderbox", "color": Color("7a7268")},
	"steel_axe": {"name": "Steel axe", "stack": false, "buy": 60,
		"examine": "A well-balanced steel axe. Chops much faster.", "icon": "axe", "color": Color("c8ced4")},
}


static func exists(id: String) -> bool:
	return ITEMS.has(id)


static func display_name(id: String) -> String:
	return ITEMS[id].name if ITEMS.has(id) else id


static func is_stackable(id: String) -> bool:
	return ITEMS.has(id) and ITEMS[id].stack


static func examine_text(id: String) -> String:
	return ITEMS[id].examine if ITEMS.has(id) else ""


static func info(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func sell_price(id: String) -> int:
	return ITEMS.get(id, {}).get("sell", 0)


static func buy_price(id: String) -> int:
	return ITEMS.get(id, {}).get("buy", 0)


static func heal_amount(id: String) -> int:
	return ITEMS.get(id, {}).get("heal", 0)


static func is_protected(id: String) -> bool:
	return ITEMS.get(id, {}).get("protected", false)


static func is_food(id: String) -> bool:
	return heal_amount(id) > 0
