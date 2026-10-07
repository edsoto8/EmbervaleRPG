extends Node
## Loads every GDScript in the project and reports any that fail to compile (exit code 1).
## godot --headless --path . res://tests/check_scripts.tscn


func _ready() -> void:
	var bad: Array[String] = []
	var count := 0
	for path in _scripts("res://"):
		count += 1
		var s: Script = load(path)
		if s == null or not s.can_instantiate():
			bad.append(path)
	print("checked %d scripts, %d failed" % [count, bad.size()])
	for b in bad:
		print("  FAILED: " + b)
	get_tree().quit(1 if bad.size() > 0 else 0)


func _scripts(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		if d.begins_with("."):
			continue
		out.append_array(_scripts(dir_path.path_join(d)))
	return out
