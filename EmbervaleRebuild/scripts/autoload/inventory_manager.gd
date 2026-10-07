extends Node
## 28-slot inventory. Stackable items use one slot per item ID; others one slot each. Every change
## that can fail is a transaction: the final inventory is computed and checked first, so a failure
## changes nothing. Quantities stay positive integers within the exact JSON range.

signal inventory_changed
signal item_added(id: String, qty: int)
signal item_removed(id: String, qty: int)
signal item_examined(id: String, slot: int)
signal inventory_full(id: String)
signal item_dropped(id: String, qty: int)

const SLOTS := 28

var slots: Array = []


func _init() -> void:
	reset()


func reset() -> void:
	slots = []
	slots.resize(SLOTS)
	inventory_changed.emit()


func to_dict() -> Dictionary:
	var out: Array = []
	for s in slots:
		out.append(null if s == null else {"id": s.id, "qty": s.qty})
	return {"slots": out}


## Loads validated data (SaveManager.validate output).
func from_dict(data: Dictionary) -> void:
	slots = []
	slots.resize(SLOTS)
	var raw: Array = data.get("slots", [])
	for i in mini(raw.size(), SLOTS):
		if raw[i] is Dictionary:
			slots[i] = {"id": raw[i].id, "qty": int(raw[i].qty)}
	inventory_changed.emit()


func count(id: String) -> int:
	var n := 0
	for s in slots:
		if s != null and s.id == id:
			n += s.qty
	return n


func has(id: String, qty: int = 1) -> bool:
	return count(id) >= qty


func free_slots() -> int:
	var n := 0
	for s in slots:
		if s == null:
			n += 1
	return n


func is_empty() -> bool:
	return free_slots() == SLOTS


func slot(i: int) -> Variant:
	return slots[i] if i >= 0 and i < SLOTS else null


func first_slot_of(id: String) -> int:
	for i in SLOTS:
		if slots[i] != null and slots[i].id == id:
			return i
	return -1


## Whether adding these items would fit (existing stacks grow; new stacks need free slots).
func can_add(id: String, qty: int = 1) -> bool:
	return _simulate({}, {id: qty}).ok


## Adds items, or nothing at all. Returns false (and emits inventory_full) when they don't fit.
func add_item(id: String, qty: int = 1) -> bool:
	var res := transact({}, {id: qty})
	return res.ok


## Removes items (from any slots holding them), or nothing if there are not enough.
func remove_item(id: String, qty: int = 1) -> bool:
	return transact({id: qty}, {}).ok


## Atomically removes `remove` and adds `add` ({id: qty}). The final inventory, including slots freed
## by the removals, is checked before anything changes. Returns {ok, error}.
func transact(remove: Dictionary, add: Dictionary) -> Dictionary:
	var sim := _simulate(remove, add)
	if not sim.ok:
		if sim.get("full", false):
			for id in add:
				inventory_full.emit(id)
		return sim
	slots = sim.slots
	for id in remove:
		if remove[id] > 0:
			item_removed.emit(id, remove[id])
	for id in add:
		if add[id] > 0:
			item_added.emit(id, add[id])
	inventory_changed.emit()
	return {"ok": true}


## Checks a transaction without applying it. Returns {ok, slots} or {ok: false, error, full}.
func preflight(remove: Dictionary, add: Dictionary) -> Dictionary:
	return _simulate(remove, add)


func _simulate(remove: Dictionary, add: Dictionary) -> Dictionary:
	var work := slots.duplicate(true)
	for id in remove:
		var need: int = remove[id]
		if need < 0 or not ItemDB.exists(id):
			return {"ok": false, "error": "Invalid removal."}
		if need == 0:
			continue
		for i in range(SLOTS - 1, -1, -1):
			if need <= 0:
				break
			var s: Variant = work[i]
			if s == null or s.id != id:
				continue
			var take: int = mini(need, s.qty)
			s.qty -= take
			need -= take
			if s.qty <= 0:
				work[i] = null
		if need > 0:
			return {"ok": false, "error": "You don't have enough %s." % ItemDB.display_name(id).to_lower()}
	for id in add:
		var qty: int = add[id]
		if qty < 0 or not ItemDB.exists(id):
			return {"ok": false, "error": "Invalid item."}
		if qty == 0:
			continue
		if ItemDB.is_stackable(id):
			var placed := false
			for s in work:
				if s != null and s.id == id:
					if s.qty + qty > ItemDB.MAX_QTY:
						return {"ok": false, "error": "You can't carry that many %s." % ItemDB.display_name(id).to_lower()}
					s.qty += qty
					placed = true
					break
			if not placed:
				var free := work.find(null)
				if free < 0:
					return {"ok": false, "full": true, "error": _full_message()}
				work[free] = {"id": id, "qty": qty}
		else:
			for k in qty:
				var free := work.find(null)
				if free < 0:
					return {"ok": false, "full": true, "error": _full_message()}
				work[free] = {"id": id, "qty": 1}
	return {"ok": true, "slots": work}


func _full_message() -> String:
	return "Your inventory is too full. Drop or sell something to make room."


## Examines the item in a slot (posts its description through the signal).
func inspect(i: int) -> void:
	var s: Variant = slot(i)
	if s == null:
		return
	item_examined.emit(s.id, i)


## Permanently discards the whole stack in a slot. Protected items (the sword) can't be dropped.
func drop_slot(i: int) -> Dictionary:
	var s: Variant = slot(i)
	if s == null:
		return {"ok": false, "error": "That slot is empty."}
	if ItemDB.is_protected(s.id):
		return {"ok": false, "error": "You can't drop your %s." % ItemDB.display_name(s.id)}
	var id: String = s.id
	var qty: int = s.qty
	slots[i] = null
	item_removed.emit(id, qty)
	item_dropped.emit(id, qty)
	inventory_changed.emit()
	return {"ok": true, "id": id, "qty": qty}
