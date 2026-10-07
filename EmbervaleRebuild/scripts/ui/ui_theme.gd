class_name UITheme
extends RefCounted
## The shared UI theme and small builders. All UI is built in code from these helpers.

const BG := Color("261c14")
const PANEL := Color(0.16, 0.12, 0.085, 0.95)
const PANEL_LIGHT := Color("3b2d20")
const BORDER := Color("b8923f")
const TEXT := Color("f1e6c8")
const MUTED := Color("bfae8a")
const ACCENT := Color("ffd36a")
const DANGER := Color("e07a5a")
const GOOD := Color("9ad07a")

static var _theme: Theme
static var _installed := false


## Merges the theme into the engine's default theme so every Control uses it, wherever it lives.
static func install() -> void:
	if _installed:
		return
	_installed = true
	ThemeDB.get_default_theme().merge_with(theme())


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("outline_size", "Label", 0)
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, BORDER, 2, 10, 18))
	t.set_stylebox("panel", "Panel", _box(PANEL, BORDER, 2, 10, 0))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var bg := Color("4a3a2a")
		var border := Color("7a6040")
		var bw := 1
		match state:
			"hover":
				bg = Color("5f4a33")
				border = BORDER
			"pressed":
				bg = Color("342619")
				border = BORDER
			"disabled":
				bg = Color("332a21")
				border = Color("4a3d2e")
			"focus":
				bg = Color(0, 0, 0, 0)
				border = ACCENT
				bw = 2
		var sb := _box(bg, border, bw, 6, 0)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		for cls in ["Button", "OptionButton", "CheckButton"]:
			t.set_stylebox(state, cls, sb)
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, ACCENT)
		t.set_color("font_pressed_color", cls, ACCENT)
		t.set_color("font_focus_color", cls, TEXT)
		t.set_color("font_disabled_color", cls, Color("7d705c"))
	var le := _box(Color("1c140e"), Color("7a6040"), 1, 5, 0)
	le.content_margin_left = 10
	le.content_margin_right = 10
	le.content_margin_top = 6
	le.content_margin_bottom = 6
	t.set_stylebox("normal", "LineEdit", le)
	var lef := le.duplicate()
	lef.border_color = ACCENT
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("font_placeholder_color", "LineEdit", Color("8a7b62"))
	var slider := _box(Color("1c140e"), Color("7a6040"), 1, 4, 0)
	slider.content_margin_top = 4
	slider.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", _box(Color("8a6a3a"), Color(0, 0, 0, 0), 0, 4, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(Color("b8923f"), Color(0, 0, 0, 0), 0, 4, 0))
	t.set_stylebox("background", "ProgressBar", _box(Color("1c140e"), Color("5a4630"), 1, 4, 0))
	t.set_stylebox("fill", "ProgressBar", _box(Color("c9a34a"), Color(0, 0, 0, 0), 0, 4, 0))
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_stylebox("panel", "PopupMenu", _box(Color("2b2118"), BORDER, 1, 6, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", ACCENT)
	t.set_stylebox("hover", "PopupMenu", _box(Color("4a3a2a"), Color(0, 0, 0, 0), 0, 4, 0))
	t.set_stylebox("panel", "TooltipPanel", _box(Color("2b2118"), BORDER, 1, 4, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)
	_theme = t
	return t


static func _box(bg: Color, border: Color, border_width: int, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


static func style(bg: Color, border: Color = Color(0, 0, 0, 0), border_width: int = 0, radius: int = 6,
		margin: int = 8) -> StyleBoxFlat:
	return _box(bg, border, border_width, radius, margin)


# --- builders -----------------------------------------------------------------------------------

static func label(text: String, size: int = 18, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String, size: int = 56) -> Label:
	var l := label(text, size, ACCENT)
	l.add_theme_constant_override("outline_size", maxi(size / 7, 4))
	l.add_theme_color_override("font_outline_color", Color("3a2410"))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func wrapped(text: String, size: int = 18, color: Color = TEXT, width: float = 420.0) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


static func button(text: String, on_pressed: Callable = Callable(), min_width: float = 220.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 42)
	b.focus_mode = Control.FOCUS_ALL
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


static func panel(margin: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	if margin != 18:
		p.add_theme_stylebox_override("panel", _box(PANEL, BORDER, 2, 10, margin))
	return p


static func vbox(separation: int = 10) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b


static func hbox(separation: int = 10) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b


static func slider(lo: float, hi: float, step: float, value: float, on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(220, 24)
	s.focus_mode = Control.FOCUS_ALL
	s.value_changed.connect(on_change)
	return s


## A colour swatch toggle button.
static func swatch(color: Color, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(32, 30)
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = color.to_html(false)
	var normal := _box(color, Color("1c140e"), 2, 6, 0)
	var hover := _box(color.lightened(0.1), BORDER, 2, 6, 0)
	var pressed := _box(color, ACCENT, 3, 6, 0)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), ACCENT, 2, 6, 0))
	b.pressed.connect(on_pressed)
	return b


## "<  value  >" selector. Calls on_change(new_index).
static func selector(options: Array, index: int, on_change: Callable) -> HBoxContainer:
	var row := hbox(6)
	var value := label(str(options[index]), 18)
	value.custom_minimum_size.x = 130
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.name = "Value"
	var state := [index]
	var change := func(delta: int) -> void:
		state[0] = wrapi(state[0] + delta, 0, options.size())
		value.text = str(options[state[0]])
		on_change.call(state[0])
	var prev := button("<", change.bind(-1), 40)
	var next := button(">", change.bind(1), 40)
	prev.custom_minimum_size.y = 36
	next.custom_minimum_size.y = 36
	prev.name = "Prev"
	next.name = "Next"
	row.add_child(prev)
	row.add_child(value)
	row.add_child(next)
	row.set_meta("state", state)
	return row


static func set_selector(row: HBoxContainer, options: Array, index: int) -> void:
	row.get_meta("state")[0] = index
	(row.get_node("Value") as Label).text = str(options[index])


## Full-screen dimming layer that swallows mouse input, for modals.
static func dimmer(alpha: float = 0.55) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0, 0, 0, alpha)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c
