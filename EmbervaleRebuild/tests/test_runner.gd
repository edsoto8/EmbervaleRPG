extends Node
## Headless test runner. Usage:
##   godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn [-- suite [test_filter]]
## Exit code 0 means every test passed.

const SUITES := {
	"world": "res://tests/suites/world_suite.gd",
	"flow": "res://tests/suites/flow_suite.gd",
	"tutorial": "res://tests/suites/tutorial_suite.gd",
	"polish": "res://tests/suites/polish_suite.gd",
	"playthrough": "res://tests/suites/playthrough_suite.gd",
}


func _ready() -> void:
	# Suites change scenes through GameManager; detach the runner so those changes don't free it.
	get_tree().current_scene = null
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var only := args[0] if args.size() > 0 else ""
	var filter := args[1] if args.size() > 1 else ""
	print("Embervale tests — data dir %s" % AppPaths.root())
	var failed := 0
	var total_passed := 0
	var failures: Array[String] = []
	for key in SUITES:
		if only != "" and key != only:
			continue
		print("[%s]" % key)
		var script: GDScript = load(SUITES[key])
		if script == null or not script.can_instantiate():
			print("  FAIL %s: suite script failed to load" % key)
			failures.append("%s: suite script failed to load" % key)
			failed += 1
			continue
		var suite: TestSuite = script.new()
		suite.suite_name = key
		add_child(suite)
		failed += await suite.run_all(filter)
		total_passed += suite.passed
		failures.append_array(suite.failures)
		suite.queue_free()
		await get_tree().process_frame
	print("")
	print("%d passed, %d failed" % [total_passed, failed])
	for f in failures:
		print("  - " + f)
	_cleanup_data_dir()
	get_tree().quit(1 if failed > 0 else 0)


func _cleanup_data_dir() -> void:
	var root := AppPaths.root()
	if not AppPaths.is_isolated():
		return
	_remove_tree(root)


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	for d in dir.get_directories():
		_remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)
