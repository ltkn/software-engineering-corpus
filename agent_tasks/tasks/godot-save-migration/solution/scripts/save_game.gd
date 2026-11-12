class_name SaveGame
extends RefCounted

const VERSION := 2
const DEFAULT_MUSIC_VOLUME := 0.8


## Write atomically: a temporary file renamed over the old save.
static func save_game(path: String, data: Dictionary) -> Error:
	var to_write := data.duplicate(true)
	to_write.version = VERSION
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_write, "\t"))
	file.close()
	if file.get_error() != OK:
		return file.get_error()
	return DirAccess.rename_absolute(tmp, path)


static func load_game(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("no save file at %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("cannot open %s: %s" % [path, error_string(FileAccess.get_open_error())])
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return _fail("corrupt save (line %d): %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _fail("corrupt save: expected an object")
	var raw: Dictionary = json.data
	var version := int(raw.get("version", 1))
	if version > VERSION:
		return _fail("save version %d is newer than this game supports (%d)" % [version, VERSION])
	var data := _from_v1(raw) if version == 1 else raw
	return {"ok": true, "data": _normalize(data), "error": ""}


static func _from_v1(old: Dictionary) -> Dictionary:
	return {
		"version": VERSION,
		"player": {"health": old.get("hp", 100), "position": {"x": old.get("x", 0.0), "y": old.get("y", 0.0)}},
		"inventory": old.get("items", []),
		"settings": {"music_volume": DEFAULT_MUSIC_VOLUME},
	}


## JSON numbers are floats: restore the fields that are integers.
static func _normalize(data: Dictionary) -> Dictionary:
	var player: Dictionary = data.get("player", {})
	var position: Dictionary = player.get("position", {})
	var settings: Dictionary = data.get("settings", {})
	return {
		"version": VERSION,
		"player": {
			"health": int(player.get("health", 100)),
			"position": {"x": float(position.get("x", 0.0)), "y": float(position.get("y", 0.0))},
		},
		"inventory": Array(data.get("inventory", [])),
		"settings": {"music_volume": float(settings.get("music_volume", DEFAULT_MUSIC_VOLUME))},
	}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": message}
