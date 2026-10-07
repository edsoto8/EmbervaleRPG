class_name CraftPanel
extends ModalPanel
## The furnace or anvil menu (SPEC_SMITHING.md K3): every recipe for the station with its
## ingredients, level and XP, and Make 1 / Make all. Recipes that can't be made are disabled with the
## reason. Choosing one closes the panel and SmithyDirector runs the crafting loop.

var director: SmithyDirector
var station: CraftStation
var list: VBoxContainer


static func show_panel(d: SmithyDirector, s: CraftStation) -> CraftPanel:
	var p := CraftPanel.new()
	p.director = d
	p.station = s
	p._build()
	p.open()
	return p


func _build() -> void:
	var furnace := station.station == "furnace"
	box.add_child(UITheme.label("Brann's Furnace" if furnace else "Brann's Anvil", 28, UITheme.ACCENT))
	box.add_child(UITheme.wrapped("Smelt ore into bars. Iron ore sometimes crumbles." if furnace
			else "Hammer bars into tools and armour. You need a hammer.", 15, UITheme.MUTED, 620))
	list = UITheme.vbox(6)
	list.custom_minimum_size.x = 620
	box.add_child(list)
	for id in SkillData.recipes_for(station.station):
		list.add_child(_row(id))
	var close_row := UITheme.hbox()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var close_button := UITheme.button("Close", close, 160)
	close_button.name = "Close"
	close_row.add_child(close_button)
	box.add_child(close_row)


func _row(id: String) -> HBoxContainer:
	var r: Dictionary = SkillData.RECIPES[id]
	var row := UITheme.hbox(10)
	row.name = "Row_" + id
	var icon := ItemIcon.new()
	icon.custom_minimum_size = Vector2(40, 36)
	icon.set_item(id)
	row.add_child(icon)
	var text := UITheme.vbox(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var needs: Array[String] = []
	for input in r.inputs:
		needs.append("%d %s" % [r.inputs[input], ItemDB.display_name(input).to_lower()])
	text.add_child(UITheme.label("%s  ·  level %d  ·  %d XP" % [ItemDB.display_name(id), r.level, int(r.xp)], 16))
	var err := director.craft_error(id)
	var sub := UITheme.label("Needs " + ", ".join(needs) + ("" if err == "" else "  —  " + err), 13,
			UITheme.MUTED if err == "" else UITheme.DANGER)
	sub.name = "Reason"
	text.add_child(sub)
	row.add_child(text)
	for spec in [["MakeOne", "Make 1", 1], ["MakeAll", "Make all", SmithyDirector.MAKE_ALL]]:
		var b := UITheme.button(spec[1], _make.bind(id, spec[2]), 90)
		b.name = spec[0]
		b.disabled = err != ""
		if err != "":
			b.tooltip_text = err
		row.add_child(b)
	return row


func _make(id: String, count: int) -> void:
	close()
	director.craft(id, count, station)


## A named button in a recipe's row (tests and UI navigation).
func button_for(id: String, button_name: String) -> Button:
	var row := list.get_node_or_null("Row_" + id)
	return row.get_node_or_null(button_name) if row else null
