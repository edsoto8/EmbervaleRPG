class_name AppPaths
extends RefCounted
## Resolves where saves and settings live.
##
## The directory is chosen from the command line the first time anything asks, which happens in the
## first autoload's _init, before any file is read or written. Test, capture and perf entry scenes
## (anything under res://tests/) and runs given the `--isolated` user argument get a private directory,
## so tools never touch the production user://savegame.json or user://settings.json.

const ENV_OVERRIDE := "EMBERVALE_DATA_DIR"

static var _root := ""


static func root() -> String:
	if _root == "":
		_root = _resolve()
		if _root != "user://":
			DirAccess.make_dir_recursive_absolute(_root)
	return _root


static func is_isolated() -> bool:
	return root() != "user://"


static func save_path() -> String:
	return root().path_join("savegame.json")


static func settings_path() -> String:
	return root().path_join("settings.json")


## Tests may move the data directory (for example to simulate write failures). Never points at user://.
static func override_root(path: String) -> void:
	assert(path != "user://")
	_root = path
	DirAccess.make_dir_recursive_absolute(_root)


static func _resolve() -> String:
	var env := OS.get_environment(ENV_OVERRIDE)
	if env != "":
		return env
	var isolated := false
	for arg in OS.get_cmdline_args():
		if arg.begins_with("res://tests/") or arg.begins_with("tests/"):
			isolated = true
	if "--isolated" in OS.get_cmdline_user_args():
		isolated = true
	if isolated:
		return "user://test_runs/%d" % OS.get_process_id()
	return "user://"
