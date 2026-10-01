extends RefCounted

## Minimal test harness for the pure-data match engine.
##
## Subclass with `extends "res://Tests/test_case.gd"` and add methods named
## `test_*`; an optional `before_each()` runs before every test. Failures are
## recorded rather than thrown (GDScript has no exceptions), so a single
## assert_eq() failure does not abort the rest of a test body.
##
## Type tolerance: assert_eq() treats int and float as equal when both values
## convert to the same float (so JSON round trips, which turn ints into floats,
## still compare equal). Everything else — String vs StringName, Array vs
## Dictionary — must match in type as well as in value.

## Failure messages recorded since the last _reset().
var _failures: Array[String] = []


func _reset() -> void:
	## Clears the failure buffer. The runner calls this before each test.
	_failures.clear()


func _get_failures() -> Array[String]:
	## Returns (and keeps) the failures recorded since the last _reset().
	return _failures


## Fails unless `actual` equals `expected`.
func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if _values_equal(actual, expected):
		return
	var prefix := "" if msg.is_empty() else msg + ": "
	_failures.append("%sexpected %s, got %s" % [prefix, _describe(expected), _describe(actual)])


## Fails if `actual` equals `expected`.
func assert_ne(actual: Variant, expected: Variant, msg: String = "") -> void:
	if not _values_equal(actual, expected):
		return
	var prefix := "" if msg.is_empty() else msg + ": "
	_failures.append("%sexpected anything but %s" % [prefix, _describe(expected)])


## Fails unless `cond` is true.
func assert_true(cond: bool, msg: String = "") -> void:
	if cond:
		return
	_failures.append("%sexpected true, got false" % ["" if msg.is_empty() else msg + ": "])


## Fails unless `cond` is false.
func assert_false(cond: bool, msg: String = "") -> void:
	if not cond:
		return
	_failures.append("%sexpected false, got true" % ["" if msg.is_empty() else msg + ": "])


## Records an unconditional failure.
func fail(msg: String) -> void:
	_failures.append(msg)


## int/float compare equal when both convert to the same float, recursively
## inside Arrays and Dictionaries (Godot's own `==` is type-strict there, which
## would make every JSON round trip look broken). Every other pair must have
## the same type and value.
func _values_equal(a: Variant, b: Variant) -> bool:
	if a is int or a is float:
		return (b is int or b is float) and float(a) == float(b)
	if a is Array and b is Array:
		var array_a: Array = a
		var array_b: Array = b
		if array_a.size() != array_b.size():
			return false
		for i in array_a.size():
			if not _values_equal(array_a[i], array_b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		var dict_a: Dictionary = a
		var dict_b: Dictionary = b
		if dict_a.size() != dict_b.size():
			return false
		for key in dict_a:
			if not dict_b.has(key):
				return false
			if not _values_equal(dict_a[key], dict_b[key]):
				return false
		return true
	if typeof(a) != typeof(b):
		return false
	return a == b


func _describe(v: Variant) -> String:
	if v is Array:
		return "%s" % [v]
	if v is Dictionary:
		return "%s" % [v]
	return "%s (%s)" % [v, type_string(typeof(v))]