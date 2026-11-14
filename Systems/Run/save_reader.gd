class_name SaveReader
extends RefCounted
## Reads typed fields out of one parsed JSON dictionary of a save without
## script errors: a missing key, a wrong type or a number that is not a
## whole number marks the reader invalid and returns a neutral value. Callers read every field, then check [member is_valid].
## [codeblock]
## var reader := SaveReader.new(data)
## var gold := reader.get_int("gold")
## if not reader.is_valid: return false
## [/codeblock]

## Whole numbers above this lose precision as JSON doubles.
const MAX_EXACT_NUMBER: float = 9007199254740992.0
## The largest 64-bit integer, as text.
const INT64_DIGITS: String = "9223372036854775807"

## False once any field was missing or of the wrong type.
var is_valid: bool = true
var _data: Dictionary


func _init(data: Dictionary) -> void:
	_data = data


## A whole number (JSON gives floats).
func get_int(key: String) -> int:
	var value: Variant = _get_value(key)
	if value is int:
		return value
	if value is float and is_finite(value) and value == floorf(value) and absf(value) <= MAX_EXACT_NUMBER:
		return int(value)
	is_valid = false
	return 0


func get_bool(key: String) -> bool:
	var value: Variant = _get_value(key)
	if value is bool:
		return value
	is_valid = false
	return false


func get_string(key: String) -> String:
	var value: Variant = _get_value(key)
	if value is String:
		return value
	is_valid = false
	return ""


## A 64-bit integer stored as a decimal string (JSON numbers are doubles).
func get_int_string(key: String) -> int:
	var text := get_string(key)
	var digits := text.trim_prefix("-")
	# String.to_int() errors on values past 64 bits, so those are refused first.
	var is_too_long := digits.length() > INT64_DIGITS.length() or (digits.length() == INT64_DIGITS.length() and digits > INT64_DIGITS)
	if not text.is_valid_int() or not digits.is_valid_int() or is_too_long:
		is_valid = false
		return 0
	return text.to_int()


func get_array(key: String) -> Array:
	var value: Variant = _get_value(key)
	if value is Array:
		return value
	is_valid = false
	return []


func _get_value(key: String) -> Variant:
	if _data.has(key):
		return _data[key]
	is_valid = false
	return null
