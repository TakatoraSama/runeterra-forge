extends SceneTree

## Headless test runner for res://Tests/test_*.gd.
##
## Not a test itself: it discovers every `test_*.gd` in res://Tests, runs each
## `test_*` method it declares, and prints one line per test. Run it through
## tools/run_tests.sh (which imports first and also fails on SCRIPT ERROR /
## Parse Error), or directly:
##
##   godot --headless --path . -s res://Tests/run_all.gd -- [name_filter]
##
## With a filter, only files whose path contains that substring are run.

const TEST_DIR := "res://Tests"
const TEST_PREFIX := "test_"
const TEST_SUFFIX := ".gd"

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	# One frame of slack so the autoloads exist before any test runs.
	process_frame.connect(_run_tests, CONNECT_ONE_SHOT)


func _run_tests() -> void:
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		filter += str(arg)

	for path in _discover(filter):
		var script: GDScript = load(path) as GDScript
		if script == null or not script.can_instantiate():
			print("[FAIL] %s — could not load" % path)
			_failed += 1
			continue
		var instance: Object = script.new()
		if instance == null:
			print("[FAIL] %s — could not instantiate" % path)
			_failed += 1
			continue
		for method in _test_methods(script):
			_run_one(instance, path, method)

	print("[TESTS] %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


## Every `res://Tests/test_*.gd`, sorted, optionally filtered by substring.
func _discover(filter: String) -> Array[String]:
	var found: Array[String] = []
	for file_name in DirAccess.get_files_at(TEST_DIR):
		if not file_name.begins_with(TEST_PREFIX) or not file_name.ends_with(TEST_SUFFIX):
			continue
		var path := TEST_DIR + "/" + file_name
		if not filter.is_empty() and not path.contains(filter):
			continue
		found.append(path)
	found.sort()
	return found


## Names of the `test_*` methods declared by `script`, sorted.
func _test_methods(script: GDScript) -> Array[String]:
	var names: Array[String] = []
	for info in script.get_script_method_list():
		var method_name := str(info.get("name", ""))
		if method_name.begins_with(TEST_PREFIX):
			names.append(method_name)
	names.sort()
	return names


func _run_one(instance: Object, path: String, method: String) -> void:
	if instance.has_method("before_each"):
		instance.call("before_each")
	instance.call("_reset")
	instance.call(method)
	var failures: Array = instance.call("_get_failures")
	if failures.is_empty():
		_passed += 1
		print("[PASS] %s::%s" % [path, method])
		return
	_failed += 1
	for failure in failures:
		print("[FAIL] %s::%s — %s" % [path, method, failure])