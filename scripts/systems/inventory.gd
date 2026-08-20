class_name Inventory
extends RefCounted
## 36-slot inventory (first 9 = hotbar). Slots: {id: int, count: int} or {}.

signal changed

const SIZE := 36
var slots: Array = []

func _init() -> void:
	for i in SIZE:
		slots.append({})

func is_empty_slot(i: int) -> bool:
	return slots[i].is_empty() or int(slots[i].get("count", 0)) <= 0

func count_item(id: int) -> int:
	var n := 0
	for s in slots:
		if int(s.get("id", -1)) == id:
			n += int(s.get("count", 0))
	return n

## Returns the number NOT added (inventory full).
func add_item(id: int, n: int) -> int:
	if n <= 0:
		return 0
	var remaining := n
	# stack first
	for i in SIZE:
		if remaining <= 0:
			break
		var s: Dictionary = slots[i]
		if int(s.get("id", -1)) == id:
			var take := mini(remaining, 64 - int(s["count"]))
			s["count"] = int(s["count"]) + take
			remaining -= take
	# then empty slots
	for i in SIZE:
		if remaining <= 0:
			break
		if is_empty_slot(i):
			var take := mini(remaining, 64)
			slots[i] = {"id": id, "count": take}
			remaining -= take
	emit_signal("changed")
	return remaining

## Returns how many were actually removed.
func remove_item(id: int, n: int) -> int:
	var remaining := n
	var removed := 0
	for i in SIZE:
		if remaining <= 0:
			break
		var s: Dictionary = slots[i]
		if int(s.get("id", -1)) == id:
			var take := mini(remaining, int(s["count"]))
			s["count"] = int(s["count"]) - take
			removed += take
			if int(s["count"]) <= 0:
				slots[i] = {}
			remaining -= take
	if removed > 0:
		emit_signal("changed")
	return removed

func get_slot(i: int) -> Dictionary:
	return slots[i]

func set_slot(i: int, id: int, count: int) -> void:
	if count <= 0:
		slots[i] = {}
	else:
		slots[i] = {"id": id, "count": count}
	emit_signal("changed")

func clear() -> void:
	for i in SIZE:
		slots[i] = {}
	emit_signal("changed")

func to_list() -> Array:
	var out: Array = []
	for s in slots:
		out.append({"id": int(s.get("id", 0)), "count": int(s.get("count", 0))})
	return out

func from_list(list: Array) -> void:
	clear()
	for i in mini(list.size(), SIZE):
		var e: Dictionary = list[i]
		if int(e.get("id", 0)) > 0 and int(e.get("count", 0)) > 0:
			slots[i] = {"id": int(e["id"]), "count": int(e["count"])}
	emit_signal("changed")
