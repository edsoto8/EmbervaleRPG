class_name SkillsPanel
extends PanelContainer
## Every skill with its level, XP and progress to the next level, plus hitpoints. Opens with K or the
## HUD button; gameplay continues while it is open.

var rows := {}
var hp_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UITheme.style(UITheme.PANEL, UITheme.BORDER, 2, 10, 12))
	var v := UITheme.vbox(3)
	add_child(v)
	var head := UITheme.hbox()
	var title := UITheme.label("Skills", 20, UITheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := UITheme.button("✕", hide_panel, 36)
	close_btn.name = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	head.add_child(close_btn)
	v.add_child(head)
	for s in SkillData.SKILLS:
		var box := UITheme.vbox(0)
		box.name = s
		var top := UITheme.hbox(8)
		var name_label := UITheme.label(SkillData.SKILL_NAMES[s], 15)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_label)
		var lvl := UITheme.label("", 15, UITheme.ACCENT)
		top.add_child(lvl)
		box.add_child(top)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(240, 10)
		bar.max_value = 1.0
		bar.show_percentage = false
		box.add_child(bar)
		var xp := UITheme.label("", 12, UITheme.MUTED)
		box.add_child(xp)
		v.add_child(box)
		rows[s] = {"level": lvl, "bar": bar, "xp": xp}
	hp_label = UITheme.label("", 16, Color("ff8a7a"))
	v.add_child(hp_label)
	SkillsManager.xp_gained.connect(_on_xp)
	SkillsManager.hitpoints_changed.connect(_on_hp)
	refresh()
	visible = false


func _exit_tree() -> void:
	if SkillsManager.xp_gained.is_connected(_on_xp):
		SkillsManager.xp_gained.disconnect(_on_xp)
	if SkillsManager.hitpoints_changed.is_connected(_on_hp):
		SkillsManager.hitpoints_changed.disconnect(_on_hp)


func _on_xp(_s: String, _a: float) -> void:
	refresh()


func _on_hp(_c: int, _m: int) -> void:
	refresh()


func refresh() -> void:
	for s in rows:
		var xp: float = SkillsManager.xp[s]
		var lvl := SkillData.level_for_xp(xp)
		rows[s].level.text = "Level %d" % lvl
		rows[s].bar.value = SkillData.level_progress(xp)
		if lvl >= SkillData.MAX_LEVEL:
			rows[s].xp.text = "%s XP" % _fmt(xp)
		else:
			rows[s].xp.text = "%s / %s XP" % [_fmt(xp), _fmt(SkillData.xp_for_level(lvl + 1))]
	hp_label.text = "Hitpoints  %d / %d" % [SkillsManager.hitpoints, SkillData.MAX_HITPOINTS]


static func _fmt(v: float) -> String:
	var n := int(floor(v))
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func show_panel() -> void:
	refresh()
	visible = true


func hide_panel() -> void:
	visible = false


func toggle() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()
