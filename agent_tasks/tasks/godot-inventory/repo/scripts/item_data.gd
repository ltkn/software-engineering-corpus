class_name ItemData
extends Resource

@export var id: StringName
@export_range(1, 999) var max_stack: int = 1


static func make(item_id: StringName, stack: int) -> ItemData:
	var item := ItemData.new()
	item.id = item_id
	item.max_stack = stack
	return item
