extends Node
## Runs dialogue graphs (content lives in TutorialDialogues). A graph is
## {"start": id, "nodes": {id: node}}; a node has "speaker", "text" and either "next" (an id, or a
## Callable returning an id), "choices" ([{text, next}], up to three) or "end": true. An optional
## "action" Callable runs when the node is entered and may set flags in `outcome`.

signal dialogue_started(npc_id: String)
signal line_shown(node: Dictionary)
signal dialogue_ended(npc_id: String, outcome: Dictionary)

var active := false
var npc_id := ""
var speakers := {}
var outcome := {}
var current := {}
var _graph := {}
var _current_id := ""


func reset() -> void:
	if active:
		end()


## Starts a conversation. `speaker_info` maps speaker ids to {name, appearance}.
func start(id: String, graph: Dictionary, speaker_info: Dictionary = {}) -> bool:
	if active:
		return false
	active = true
	npc_id = id
	speakers = speaker_info
	outcome = {}
	_graph = graph
	dialogue_started.emit(id)
	_enter(graph.start)
	return true


func speaker_name(speaker_id: String) -> String:
	return speakers.get(speaker_id, {}).get("name", speaker_id.capitalize())


func _enter(node_id: Variant) -> void:
	if not active:
		return
	if node_id is Callable:
		node_id = node_id.call()
	if node_id == null or node_id == "" or not _graph.nodes.has(node_id):
		end()
		return
	_current_id = node_id
	current = _graph.nodes[node_id]
	if current.has("action"):
		current.action.call(outcome)
		if not active:
			return
	if current.get("text", "") == "":
		# Pure branch/action node.
		_enter(current.get("next", ""))
		return
	line_shown.emit(current)


func has_choices() -> bool:
	return active and current.has("choices")


func choices() -> Array:
	return current.get("choices", []) if active else []


## Continues past a line without choices.
func advance() -> void:
	if not active or has_choices():
		return
	if current.get("end", false):
		end()
		return
	_enter(current.get("next", ""))


## Picks a displayed choice (0-based).
func choose(i: int) -> void:
	if not has_choices():
		return
	var list: Array = current.choices
	if i < 0 or i >= list.size():
		return
	var c: Dictionary = list[i]
	if c.has("action"):
		c.action.call(outcome)
	_enter(c.get("next", ""))


func end() -> void:
	if not active:
		return
	active = false
	var id := npc_id
	var result := outcome
	current = {}
	_graph = {}
	npc_id = ""
	dialogue_ended.emit(id, result)
