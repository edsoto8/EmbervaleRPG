extends Node
## Runtime settings, persisted separately from the adventure save (user://settings.json). Every change
## applies immediately; a failed write keeps the change in memory and reports it.

signal settings_changed(key: String, value: Variant)
signal write_failed(message: String)

const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const QUALITY_NAMES := ["Low", "Medium", "High"]
const DEFAULTS := {
	"resolution": Vector2i(1280, 720),
	"fullscreen": false,
	"master_volume": 0.8,
	"mouse_sensitivity": 1.0,
	"graphics_quality": 1,
}

var values := DEFAULTS.duplicate()
var last_error := ""
## Test hook: when true the next write fails.
var fail_next_write := false


func _init() -> void:
	# Resolve the (possibly isolated) data directory before anything is read.
	AppPaths.root()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_all()


func settings_path() -> String:
	return AppPaths.settings_path()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


## Validates, applies and persists one setting. Returns false if the value was invalid.
func set_value(key: String, value: Variant) -> bool:
	if not DEFAULTS.has(key):
		return false
	var v: Variant = _sanitize(key, value)
	if v == null:
		return false
	values[key] = v
	_apply(key)
	settings_changed.emit(key, v)
	save_settings()
	return true


func reset_to_defaults() -> void:
	values = DEFAULTS.duplicate()
	apply_all()
	save_settings()


func load_settings() -> void:
	values = DEFAULTS.duplicate()
	if not FileAccess.file_exists(settings_path()):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(settings_path())) != OK or not json.data is Dictionary:
		push_warning("Settings file is unreadable; using defaults.")
		return
	for key in DEFAULTS:
		if json.data.has(key):
			var v: Variant = _sanitize(key, json.data[key])
			if v != null:
				values[key] = v


func save_settings() -> bool:
	var data := {
		"resolution": [values.resolution.x, values.resolution.y],
		"fullscreen": values.fullscreen,
		"master_volume": values.master_volume,
		"mouse_sensitivity": values.mouse_sensitivity,
		"graphics_quality": values.graphics_quality,
	}
	DirAccess.make_dir_recursive_absolute(settings_path().get_base_dir())
	var f: FileAccess = null
	if fail_next_write:
		fail_next_write = false
	else:
		f = FileAccess.open(settings_path(), FileAccess.WRITE)
	if f == null:
		last_error = "Settings could not be saved; your changes apply until you quit."
		write_failed.emit(last_error)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	last_error = ""
	return true


## Returns the valid value for a key, or null when the input is unusable. Unsupported resolutions use
## the 1280 x 720 default (as the spec requires) rather than being rejected.
func _sanitize(key: String, v: Variant) -> Variant:
	match key:
		"resolution":
			var r := Vector2i.ZERO
			if v is Vector2i:
				r = v
			elif v is Array and v.size() == 2 and _num(v[0]) and _num(v[1]):
				r = Vector2i(int(v[0]), int(v[1]))
			return r if r in RESOLUTIONS else DEFAULTS.resolution
		"fullscreen":
			return v if v is bool else DEFAULTS.fullscreen
		"master_volume":
			return clampf(float(v), 0.0, 1.0) if _num(v) else DEFAULTS.master_volume
		"mouse_sensitivity":
			return clampf(float(v), 0.25, 2.5) if _num(v) else DEFAULTS.mouse_sensitivity
		"graphics_quality":
			if _num(v) and float(v) == floor(float(v)) and int(v) >= 0 and int(v) <= 2:
				return int(v)
			return DEFAULTS.graphics_quality
	return null


static func _num(v: Variant) -> bool:
	return v is int or (v is float and is_finite(v))


func apply_all() -> void:
	for key in DEFAULTS:
		_apply(key)


func _apply(key: String) -> void:
	match key:
		"master_volume":
			var bus := AudioServer.get_bus_index("Master")
			var vol: float = values.master_volume
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(vol, 0.0001)))
			AudioServer.set_bus_mute(bus, vol <= 0.0)
		"fullscreen", "resolution":
			_apply_window()


func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	if win == null:
		return
	if values.fullscreen:
		win.mode = Window.MODE_FULLSCREEN
	else:
		if win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
			win.mode = Window.MODE_WINDOWED
		var size: Vector2i = values.resolution
		var screen := DisplayServer.screen_get_usable_rect(win.current_screen).size
		if screen.x > 0 and screen.y > 0:
			size = Vector2i(mini(size.x, screen.x), mini(size.y, screen.y))
		win.size = size
		if screen.x > 0:
			win.position = DisplayServer.screen_get_usable_rect(win.current_screen).position + (screen - size) / 2
