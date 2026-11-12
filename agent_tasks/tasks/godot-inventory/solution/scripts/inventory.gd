class_name Inventory
extends RefCounted

signal slot_changed(index: int)


class Slot:
	var item: ItemData
	var count: int = 0

	func is_empty() -> bool:
		return item == null

	func holds(item_id: StringName) -> bool:
		return item != null and item.id == item_id

	func room() -> int:
		return item.max_stack - count

	func clear() -> void:
		item = null
		count = 0


var slots: Array[Slot] = []


func _init(size: int) -> void:
	for i in size:
		slots.append(Slot.new())


## Add `amount` of `item`; returns how many did not fit.
func add(item: ItemData, amount: int) -> int:
	var left := amount
	# Top up existing stacks first, then fill empty slots.
	for pass_empty in [false, true]:
		for i in slots.size():
			if left <= 0:
				return 0
			var slot := slots[i]
			if pass_empty:
				if not slot.is_empty():
					continue
				slot.item = item
			elif not slot.holds(item.id) or slot.room() <= 0:
				continue
			var put := mini(left, slot.room())
			slot.count += put
			left -= put
			slot_changed.emit(i)
	return maxi(left, 0)


## Remove up to `amount` items with this id; returns how many were removed.
func remove(item_id: StringName, amount: int) -> int:
	var removed := 0
	for i in range(slots.size() - 1, -1, -1):
		if removed >= amount:
			break
		var slot := slots[i]
		if not slot.holds(item_id):
			continue
		var take := mini(amount - removed, slot.count)
		slot.count -= take
		removed += take
		if slot.count == 0:
			slot.clear()
		slot_changed.emit(i)
	return removed


func count(item_id: StringName) -> int:
	var total := 0
	for slot in slots:
		if slot.holds(item_id):
			total += slot.count
	return total


## Move the stack in `from` onto `to`: merge same items up to max_stack, otherwise swap.
func move(from: int, to: int) -> void:
	if from == to:
		return
	var source := slots[from]
	var target := slots[to]
	if source.is_empty():
		return
	if target.holds(source.item.id):
		var put := mini(source.count, target.room())
		if put == 0:
			return
		target.count += put
		source.count -= put
		if source.count == 0:
			source.clear()
	else:
		slots[to] = source
		slots[from] = target
	slot_changed.emit(from)
	slot_changed.emit(to)
