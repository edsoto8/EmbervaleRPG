class_name ShopPanel
extends ModalPanel
## Marla's stall: buy one item per click, sell one or all of an item. Every trade is a preflighted
## transaction run by SkillsDirector; failures change nothing and say why.

var director: SkillsDirector
var coins_label: Label
var buy_list: VBoxContainer
var sell_list: VBoxContainer
var status: Label


static func show_panel(d: SkillsDirector) -> ShopPanel:
	var p := ShopPanel.new()
	p.director = d
	p._build()
	p.open()
	return p


func _build() -> void:
	var head := UITheme.hbox(12)
	var title := UITheme.label("Marla's Market", 28, UITheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	coins_label = UITheme.label("", 18, Color("ffe066"))
	coins_label.name = "Coins"
	head.add_child(coins_label)
	box.add_child(head)
	var cols := UITheme.hbox(24)
	box.add_child(cols)
	var left := UITheme.vbox(6)
	left.custom_minimum_size.x = 320
	left.add_child(UITheme.label("Buy", 20, UITheme.TEXT))
	buy_list = UITheme.vbox(4)
	left.add_child(buy_list)
	cols.add_child(left)
	var right := UITheme.vbox(6)
	right.custom_minimum_size.x = 360
	right.add_child(UITheme.label("Sell", 20, UITheme.TEXT))
	sell_list = UITheme.vbox(4)
	right.add_child(sell_list)
	cols.add_child(right)
	status = UITheme.wrapped("", 15, UITheme.MUTED, 680)
	status.name = "Status"
	box.add_child(status)
	var close_row := UITheme.hbox()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var close_button := UITheme.button("Close", close, 160)
	close_button.name = "Close"
	close_row.add_child(close_button)
	box.add_child(close_row)
	InventoryManager.inventory_changed.connect(refresh)
	refresh()


func _exit_tree() -> void:
	if InventoryManager.inventory_changed.is_connected(refresh):
		InventoryManager.inventory_changed.disconnect(refresh)


func _row(id: String, text: String) -> HBoxContainer:
	var row := UITheme.hbox(8)
	row.name = "Row_" + id
	var icon := ItemIcon.new()
	icon.custom_minimum_size = Vector2(34, 30)
	icon.set_item(id)
	row.add_child(icon)
	var l := UITheme.label(text, 16)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


func refresh() -> void:
	coins_label.text = "%d coins" % InventoryManager.count("coins")
	for c in buy_list.get_children():
		buy_list.remove_child(c)
		c.queue_free()
	for id in SkillsDirector.SHOP_STOCK:
		var row := _row(id, "%s — %d coins" % [ItemDB.display_name(id), ItemDB.buy_price(id)])
		var b := UITheme.button("Buy", _buy.bind(id), 70)
		b.name = "Buy"
		b.focus_mode = Control.FOCUS_NONE
		if id in SkillsDirector.UNIQUE_TOOLS and InventoryManager.has(id):
			b.disabled = true
			b.tooltip_text = "You already have one."
		row.add_child(b)
		buy_list.add_child(row)
	for c in sell_list.get_children():
		sell_list.remove_child(c)
		c.queue_free()
	var seen := {}
	for s in InventoryManager.slots:
		if s == null or seen.has(s.id):
			continue
		seen[s.id] = true
		var price := ItemDB.sell_price(s.id)
		if price <= 0 or ItemDB.is_protected(s.id):
			continue
		var n := InventoryManager.count(s.id)
		var row := _row(s.id, "%s × %d — %d each" % [ItemDB.display_name(s.id), n, price])
		var one := UITheme.button("Sell 1", _sell.bind(s.id, false), 70)
		one.name = "SellOne"
		one.focus_mode = Control.FOCUS_NONE
		var all := UITheme.button("Sell all", _sell.bind(s.id, true), 80)
		all.name = "SellAll"
		all.focus_mode = Control.FOCUS_NONE
		row.add_child(one)
		row.add_child(all)
		sell_list.add_child(row)
	if sell_list.get_child_count() == 0:
		sell_list.add_child(UITheme.label("Nothing Marla wants to buy.", 15, UITheme.MUTED))


func _buy(id: String) -> void:
	var res := director.buy(id)
	_report(res, "Bought a %s." % ItemDB.display_name(id).to_lower())


func _sell(id: String, all: bool) -> void:
	var res := director.sell(id, all)
	_report(res, "Sold for %d coins." % res.get("coins", 0))


func _report(res: Dictionary, success: String) -> void:
	status.text = success if res.ok else res.error
	status.add_theme_color_override("font_color", UITheme.GOOD if res.ok else UITheme.DANGER)
	if res.ok:
		AudioManager.play("coins", -4.0)


## Finds the row for an item and returns a named button in it (tests and UI navigation).
func button_for(id: String, button_name: String, selling: bool) -> Button:
	var list := sell_list if selling else buy_list
	var row := list.get_node_or_null("Row_" + id)
	return row.get_node_or_null(button_name) if row else null
