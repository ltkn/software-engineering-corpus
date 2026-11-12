extends "res://tests/test_case.gd"

const PATH := "user://test_save.json"


func write_raw(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func sample() -> Dictionary:
	return {"version": 2, "player": {"health": 75, "position": {"x": 3.5, "y": -1.0}},
			"inventory": ["sword", "potion"], "settings": {"music_volume": 0.5}}


func test_round_trip_keeps_types() -> bool:
	check_eq(SaveGame.save_game(PATH, sample()), OK, "save")
	var r: Dictionary = SaveGame.load_game(PATH)
	check_eq(r.ok, true, "ok")
	check_eq(r.data.player.health, 75, "health stays an int")
	check_eq(r.data.player.position.x, 3.5, "x")
	check_eq(r.data.version, 2, "version is an int")
	check_eq(r.data.inventory, ["sword", "potion"], "inventory")
	check(not FileAccess.file_exists(PATH + ".tmp"), "no temporary file left behind")
	return true


func test_migrates_version_one() -> bool:
	write_raw('{"hp": 80, "x": 1.5, "y": -2, "items": ["bow"]}')
	var r: Dictionary = SaveGame.load_game(PATH)
	check_eq(r.ok, true, "ok")
	check_eq(r.data.get("version"), 2, "version")
	check_eq(r.data.get("player", {}).get("health"), 80, "health")
	check_eq(r.data.get("player", {}).get("position", {}).get("y"), -2.0, "y is a float")
	check_eq(r.data.get("inventory"), ["bow"], "inventory")
	check_eq(r.data.get("settings", {}).get("music_volume"), 0.8, "default volume")
	return true


func test_newer_versions_are_refused() -> bool:
	write_raw('{"version": 3, "player": {}}')
	var r: Dictionary = SaveGame.load_game(PATH)
	check_eq(r.ok, false, "not ok")
	check(String(r.error).contains("3"), "error names the version: " + String(r.error))
	return true


func test_missing_and_corrupt_files_do_not_crash() -> bool:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	var missing: Dictionary = SaveGame.load_game(PATH)
	check_eq(missing.ok, false, "missing file")
	check(not String(missing.error).is_empty(), "missing file has an error message")
	write_raw("{ not json")
	var corrupt: Dictionary = SaveGame.load_game(PATH)
	check_eq(corrupt.ok, false, "corrupt file")
	write_raw("[1, 2, 3]")
	check_eq(SaveGame.load_game(PATH).ok, false, "not an object")
	return true


func test_save_replaces_an_existing_file() -> bool:
	write_raw("old contents")
	var data := sample()
	data.player.health = 12
	check_eq(SaveGame.save_game(PATH, data), OK, "save")
	check_eq(SaveGame.load_game(PATH).data.player.health, 12, "new contents")
	check(not FileAccess.file_exists(PATH + ".tmp"), "no temporary file left behind")
	return true
