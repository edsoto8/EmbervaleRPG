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
	# Milestone 7: mining and smithing.
	"copper_ore": {"name": "Copper ore", "stack": true, "examine": "This needs refining.", "sell": 3,
		"icon": "ore", "color": Color("8a6a52"), "fleck": Color("d9824a")},
	"tin_ore": {"name": "Tin ore", "stack": true, "examine": "This needs refining.", "sell": 3,
		"icon": "ore", "color": Color("8a8780"), "fleck": Color("dcdcd2")},
	"iron_ore": {"name": "Iron ore", "stack": true, "examine": "A heavy lump of iron ore.", "sell": 8,
		"icon": "ore", "color": Color("6e5a50"), "fleck": Color("b0503a")},
	"bronze_bar": {"name": "Bronze bar", "stack": true, "examine": "It's a bar of bronze.", "sell": 8,
		"icon": "bar", "color": Color("b0743a")},
	"iron_bar": {"name": "Iron bar", "stack": true, "examine": "It's a bar of iron.", "sell": 20,
		"icon": "bar", "color": Color("8a8e92")},
	"bronze_dagger": {"name": "Bronze dagger", "stack": false, "sell": 12,
		"examine": "Short, but pointy. Brann wants to see one.", "icon": "dagger", "color": Color("c08848")},
	"bronze_helm": {"name": "Bronze helm", "stack": false, "sell": 25,
		"examine": "A medium helmet hammered from bronze.", "icon": "helm", "color": Color("b97f42")},
	"iron_dagger": {"name": "Iron dagger", "stack": false, "sell": 30,
		"examine": "A sharp iron dagger.", "icon": "dagger", "color": Color("a3a8ad")},
	"iron_helm": {"name": "Iron helm", "stack": false, "sell": 60,
		"examine": "A sturdy iron helmet.", "icon": "helm", "color": Color("8f9499")},
	"hammer": {"name": "Hammer", "stack": false, "sell": 1, "buy": 5,
		"examine": "Good for hitting things, like hot metal.", "icon": "hammer", "color": Color("7a7e82")},
	"bronze_pickaxe": {"name": "Bronze pickaxe", "stack": false, "sell": 10,
		"examine": "Used for mining.", "icon": "pickaxe", "color": Color("b0743a")},
	"steel_pickaxe": {"name": "Steel pickaxe", "stack": false, "buy": 50,
		"examine": "A keen steel pickaxe. Mines much faster.", "icon": "pickaxe", "color": Color("c8ced4")},
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
