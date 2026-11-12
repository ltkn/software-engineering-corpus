extends "res://tests/test_case.gd"

var potion := ItemData.make(&"potion", 10)
var sword := ItemData.make(&"sword", 1)
var arrow := ItemData.make(&"arrow", 50)


func describe(inv: Inventory) -> Array:
	var out := []
	for slot in inv.slots:
		out.append([slot.item.id if slot.item else &"", slot.count])
	return out


func test_tops_up_existing_stacks_first() -> bool:
	var inv := Inventory.new(4)
	check_eq(inv.add(potion, 4), 0, "first add")
	check_eq(inv.add(sword, 1), 0, "sword")
	check_eq(inv.add(potion, 9), 0, "second add")
	check_eq(describe(inv), [[&"potion", 10], [&"sword", 1], [&"potion", 3], [&"", 0]], "slots")
	return true


func test_returns_what_does_not_fit() -> bool:
	var inv := Inventory.new(2)
	check_eq(inv.add(arrow, 120), 20, "leftover")
	check_eq(inv.count(&"arrow"), 100, "count")
	check_eq(inv.add(sword, 1), 1, "no room for a sword")
	return true


func test_unstackable_items_take_a_slot_each() -> bool:
	var inv := Inventory.new(3)
	check_eq(inv.add(sword, 2), 0, "two swords")
	check_eq(describe(inv), [[&"sword", 1], [&"sword", 1], [&"", 0]], "slots")
	return true


func test_remove_takes_from_the_last_stacks_and_clears_empty_slots() -> bool:
	var inv := Inventory.new(3)
	inv.add(potion, 25)
	check_eq(inv.remove(&"potion", 7), 7, "removed")
	check_eq(describe(inv), [[&"potion", 10], [&"potion", 8], [&"", 0]], "after removing 7")
	check_eq(inv.remove(&"potion", 50), 18, "removes only what exists")
	check_eq(describe(inv), [[&"", 0], [&"", 0], [&"", 0]], "all empty")
	check(inv.slots[0].item == null, "empty slot has no item")
	return true


func test_move_merges_then_swaps() -> bool:
	var inv := Inventory.new(3)
	inv.add(potion, 16)
	inv.remove(&"potion", 3)
	check_eq(describe(inv), [[&"potion", 10], [&"potion", 3], [&"", 0]], "setup")
	inv.move(0, 1)
	check_eq(describe(inv), [[&"potion", 3], [&"potion", 10], [&"", 0]], "merge up to max, rest stays")
	inv.add(sword, 1)
	inv.move(2, 0)
	check_eq(describe(inv), [[&"sword", 1], [&"potion", 10], [&"potion", 3]], "different items swap")
	inv.move(2, 1)
	check_eq(describe(inv), [[&"sword", 1], [&"potion", 10], [&"potion", 3]], "full target: nothing moves")
	return true


func test_signals_once_per_changed_slot() -> bool:
	var inv := Inventory.new(3)
	var seen: Array[int] = []
	inv.slot_changed.connect(func(index: int) -> void: seen.append(index))
	inv.add(potion, 15)
	check_eq(seen, [0, 1] as Array[int], "add")
	seen.clear()
	inv.remove(&"potion", 6)
	check_eq(seen, [1, 0] as Array[int], "remove")
	seen.clear()
	check_eq(inv.add(potion, 0), 0, "adding nothing")
	check_eq(seen, [] as Array[int], "no change, no signal")
	return true
