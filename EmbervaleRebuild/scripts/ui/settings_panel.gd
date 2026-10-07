class_name SettingsPanel
extends ModalPanel
## Resolution, fullscreen, volume, mouse sensitivity and graphics quality. Changes apply immediately
## through SettingsManager and persist separately from the save.

var resolution: OptionButton
var fullscreen: CheckButton
var volume: HSlider
var sensitivity: HSlider
var quality: OptionButton
var status: Label


static func show_panel() -> SettingsPanel:
	var p := SettingsPanel.new()
	p._build()
	p.open()
	return p


func _build() -> void:
	var heading := UITheme.label("Settings", 30, UITheme.ACCENT)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	resolution = OptionButton.new()
	for r in SettingsManager.RESOLUTIONS:
		resolution.add_item("%d × %d" % [r.x, r.y])
	resolution.select(SettingsManager.RESOLUTIONS.find(SettingsManager.get_value("resolution")))
	resolution.item_selected.connect(func(i: int) -> void: SettingsManager.set_value("resolution", SettingsManager.RESOLUTIONS[i]))
	_row(grid, "Resolution", resolution)
	fullscreen = CheckButton.new()
	fullscreen.button_pressed = SettingsManager.get_value("fullscreen")
	fullscreen.toggled.connect(func(on: bool) -> void: SettingsManager.set_value("fullscreen", on))
	_row(grid, "Fullscreen", fullscreen)
	volume = UITheme.slider(0.0, 1.0, 0.05, SettingsManager.get_value("master_volume"),
			func(v: float) -> void: SettingsManager.set_value("master_volume", v))
	_row(grid, "Master volume", volume)
	sensitivity = UITheme.slider(0.25, 2.5, 0.05, SettingsManager.get_value("mouse_sensitivity"),
			func(v: float) -> void: SettingsManager.set_value("mouse_sensitivity", v))
	_row(grid, "Mouse sensitivity", sensitivity)
	quality = OptionButton.new()
	for q in SettingsManager.QUALITY_NAMES:
		quality.add_item(q)
	quality.select(SettingsManager.get_value("graphics_quality"))
	quality.item_selected.connect(func(i: int) -> void: SettingsManager.set_value("graphics_quality", i))
	_row(grid, "Graphics quality", quality)
	status = UITheme.wrapped("", 15, UITheme.DANGER, 420)
	box.add_child(status)
	SettingsManager.write_failed.connect(_on_write_failed)
	var close_button := UITheme.button("Close", close)
	close_button.name = "Close"
	var row := UITheme.hbox()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(close_button)
	box.add_child(row)


func _row(grid: GridContainer, text: String, control: Control) -> void:
	grid.add_child(UITheme.label(text, 18, UITheme.MUTED))
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 240)
	grid.add_child(control)


func _on_write_failed(message: String) -> void:
	status.text = message


func _exit_tree() -> void:
	if SettingsManager.write_failed.is_connected(_on_write_failed):
		SettingsManager.write_failed.disconnect(_on_write_failed)
