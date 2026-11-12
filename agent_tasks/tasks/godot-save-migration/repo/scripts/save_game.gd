class_name SaveGame
extends RefCounted

const VERSION := 2


static func save_game(path: String, data: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	return OK


static func load_game(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	return {"ok": true, "data": data, "error": ""}
