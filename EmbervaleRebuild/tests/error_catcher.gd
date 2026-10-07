class_name ErrorCatcher
extends Logger
## Records script errors raised while a test runs, so a test that aborts on a runtime error is reported
## as a failure instead of silently passing.

var errors: Array[String] = []
var _mutex := Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type != ERROR_TYPE_SCRIPT:
		return
	_mutex.lock()
	errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file.get_file(), line, function])
	_mutex.unlock()


func take() -> Array[String]:
	_mutex.lock()
	var out := errors.duplicate()
	errors.clear()
	_mutex.unlock()
	return out
