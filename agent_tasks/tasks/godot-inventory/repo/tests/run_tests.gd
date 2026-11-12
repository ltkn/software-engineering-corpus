extends SceneTree
## Headless test runner: godot --headless --path . --script res://tests/run_tests.gd

const SUITES: Array[String] = ["res://tests/test_inventory.gd"]


func _init() -> void:
	var failed := 0
	var total := 0
	for path in SUITES:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("FAIL ", path, ": does not load")
			failed += 1
			continue
		var suite: Object = script.new()
		for method in suite.get_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			total += 1
			suite.failures.clear()
			var finished: Variant = suite.call(name)
			if finished != true:
				suite.failures.append("did not finish (script error?)")
			if suite.failures.is_empty():
				print("ok   ", path.get_file(), " ", name)
			else:
				failed += 1
				for f in suite.failures:
					print("FAIL ", path.get_file(), " ", name, ": ", f)
	print("%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 or total == 0 else 0)
