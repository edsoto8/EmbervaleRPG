class_name TutorialDialogues
extends RefCounted
## Every line of dialogue in the game. Graph builders take a context dictionary:
## name (player), logs (normal logs held), give_sword (Callable -> bool), and for later milestones
## fishing_level, has_rod, has_tinderbox, give_gear (Callable -> Dictionary).


static func _line(speaker: String, text: String, next: Variant = "", extra: Dictionary = {}) -> Dictionary:
	var n := {"speaker": speaker, "text": text}
	if next is String and next == "":
		n["end"] = true
	else:
		n["next"] = next
	n.merge(extra)
	return n


static func maelis(stage: String, ctx: Dictionary) -> Dictionary:
	var name: String = ctx.get("name", "adventurer")
	match stage:
		"learn_to_move":
			return {"start": "a", "nodes": {
				"a": _line("maelis", "Ah, a new arrival! Before we talk, find your feet. Walk with W, A, S and D, or click the ground where you want to go.", "b"),
				"b": _line("maelis", "Then head down to the glowing marker by the dock, and come back to me."),
			}}
		"talk_to_instructor":
			return {"start": "greet", "nodes": {
				"greet": _line("maelis", "Welcome to Driftwood Isle, %s. I am Maelis, and I train every adventurer who lands here." % name, "train"),
				"train": _line("maelis", "Here you'll learn to gather what you need and look after your pack. When you're done, the north gate awaits.", "ask"),
				"ask": {"speaker": "maelis", "text": "What would you like to know?", "choices": [
					{"text": "Tell me about the island.", "next": "island"},
					{"text": "Who lives here?", "next": "residents"},
					{"text": "I'm ready to begin.", "next": "assign"},
				]},
				"island": _line("maelis", "Driftwood Isle is small but generous. The village is at its heart, the forest lies west, the pond north-east, and the gate stands on the north shore.", "ask"),
				"residents": _line("maelis", "Marla keeps the market stall in the plaza, Old Tobin fishes by the pond, and young Pip arrived only days before you.", "ask"),
				"assign": _line("maelis", "Good. Go to the forest clearing west of the village and chop three logs. Bring them back to me.", "accept",
						{"action": func(o: Dictionary) -> void: o["accepted"] = true}),
				"accept": {"speaker": "player", "text": "Three logs. I'll be back soon.", "end": true},
			}}
		"collect_logs":
			var logs: int = mini(ctx.get("logs", 0), 3)
			return {"start": "a", "nodes": {
				"a": _line("maelis", "You have %d of the 3 logs I asked for." % logs, "b"),
				"b": _line("maelis", "Click a tree in the forest clearing west of the village to walk over and chop it, or press E when you're standing beside one."),
			}}
		"inspect_inventory":
			return {"start": "a", "nodes": {
				"a": _line("maelis", "Before you hand them over, check your pack. Press I to open your inventory, then click the logs to examine them."),
			}}
		"return_to_instructor":
			var give: Callable = ctx.get("give_sword", Callable())
			return {"start": "well_done", "nodes": {
				"well_done": _line("maelis", "Well done, %s! You've gathered your logs and know your way around your pack." % name, "give"),
				"give": {"speaker": "maelis", "text": "", "next": func() -> String: return "given" if give.call() else "full"},
				"given": _line("maelis", "Take this Beginner sword. Keep the logs; you'll find a use for them.", "gate",
						{"action": func(o: Dictionary) -> void: o["sword_given"] = true}),
				"gate": _line("maelis", "The gate on the north shore marks the end of your training. Beyond it lies the wider world, when you are ready for it.", "thanks"),
				"thanks": {"speaker": "maelis", "text": "Is there anything else?", "choices": [
					{"text": "Thank you, Maelis.", "next": "farewell"},
				]},
				"farewell": _line("maelis", "Go well, %s." % name),
				"full": _line("maelis", "I have a sword for you, but your pack is full. Make some room and talk to me again."),
			}}
		_:
			var nodes := {
				"a": _line("maelis", "Safe travels, %s. You're always welcome to keep practising here." % name, "b"),
				"b": _line("maelis", "Chop, fish, cook and train on the dummies in this courtyard; every bit of practice makes you stronger."),
			}
			if ctx.get("needs_sword", false):
				var give_again: Callable = ctx.get("give_sword", Callable())
				nodes = {
					"a": _line("maelis", "You've lost your Beginner sword? Here, let me find you another.", "give"),
					"give": {"speaker": "maelis", "text": "", "next": func() -> String: return "given" if give_again.call() else "full"},
					"given": _line("maelis", "There you are. Look after this one, %s." % name),
					"full": _line("maelis", "Your pack is full. Make some room and talk to me again."),
				}
			return {"start": "a", "nodes": nodes}


static func marla(tutorial_complete: bool) -> Dictionary:
	if tutorial_complete:
		return {"start": "a", "nodes": {
			"a": _line("marla", "Browse my stall when you like: I buy logs and fish, and I've a fine steel axe for sale."),
		}}
	return {"start": "a", "nodes": {
		"a": _line("marla", "Welcome, dear! My stall opens to adventurers once Maelis has finished your training.", "b"),
		"b": _line("marla", "Come back when she's done with you."),
	}}


static func pip() -> Dictionary:
	return {"start": "a", "nodes": {
		"a": _line("pip", "Hi! I only arrived a few days ago. Someday I want to be a real adventurer!", "b"),
		"b": _line("player", "Keep practising and you will, Pip."),
	}}


## Old Tobin by the pond (fishing arrives in Milestone 6).
static func tobin(ctx: Dictionary) -> Dictionary:
	if not ctx.get("fishing_enabled", false):
		return {"start": "a", "nodes": {
			"a": _line("tobin", "The fish are biting today. Finish your training with Maelis and come back to see me."),
		}}
	var give: Callable = ctx.get("give_gear", Callable())
	if not ctx.get("has_rod", false) or not ctx.get("has_tinderbox", false):
		return {"start": "a", "nodes": {
			"a": {"speaker": "tobin", "text": "Morning! You look like you could use a rod and a tinderbox. Want to borrow some of mine?", "choices": [
				{"text": "Yes please, Tobin.", "next": "give"},
				{"text": "Not right now.", "next": "later"},
			]},
			"give": {"speaker": "tobin", "text": "", "next": func() -> String: return "given" if give.call() else "full"},
			"given": _line("tobin", "There you go. Click a ripple near the bank to fish. Light a fire with your tinderbox by selecting logs in your pack, then click the fire with raw fish to cook it.", "eat"),
			"eat": _line("tobin", "Cooked fish keeps you healthy. Eat it from your pack when you're hurt."),
			"full": _line("tobin", "Your pack's too full to carry them. Make some room and ask me again."),
			"later": _line("tobin", "Suit yourself. I'll be here."),
		}}
	var tip := "Fish keep biting while you stand still; move and you'll stop casting. Cook your catch on a fire before it spoils."
	var nodes := {"a": _line("tobin", tip, "")}
	if ctx.get("fishing_level", 1) >= 5:
		nodes["a"] = _line("tobin", tip, "trout")
		nodes["trout"] = _line("tobin", "With your skill, you'll start pulling trout from these waters now and then. They cook up lovely.")
	return {"start": "a", "nodes": nodes}
