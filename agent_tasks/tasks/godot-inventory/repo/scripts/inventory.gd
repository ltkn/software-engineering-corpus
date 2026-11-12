class_name Inventory
extends RefCounted

signal slot_changed(index: int)


class Slot:
	var item: ItemData
	var count: int = 0


var slots: Array[Slot] = []


func _init(size: int) -> void:
	for i in size:
		slots.append(Slot.new())


## Add `amount` of `item`; returns how many did not fit.
func add(item: ItemData, amount: int) -> int:
	for slot in slots:
		if slot.item == null:
			slot.item = item
			slot.count += amount
			return 0
	return 0


## Remove up to `amount` items with this id; returns how many were removed.
func remove(item_id: StringName, amount: int) -> int:
	for slot in slots:
		if slot.item != null and slot.item.id == item_id:
			slot.count -= amount
			return amount
	return 0


func count(item_id: StringName) -> int:
	var total := 0
	for slot in slots:
		if slot.item != null and slot.item.id == item_id:
			total += slot.count
	return total


## Move the stack in `from` onto `to`.
func move(from: int, to: int) -> void:
	var tmp := slots[to]
	slots[to] = slots[from]
	slots[from] = tmp
