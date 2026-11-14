class_name RunSettings
extends RefCounted
## Player settings kept between sessions in user://settings.json: the
## preparation time (60 s, 90 s or unlimited, chosen on the title screen)
## and whether sound is muted. A missing or broken file gives the defaults;
## each save rewrites the file with the other setting kept; a failed write
## is warned about once.

const PATH: String = "user://settings.json"
## Preparation seconds the player can pick; 0 means no time limit.
const PREP_CHOICES: Array[int] = [60, 90, 0]
const DEFAULT_PREP_SECONDS: int = 60

## Where the settings live when no path is given. Only tests change it, so
## they never touch the player's settings.
static var path: String = PATH
static var _has_warned: bool = false


## The saved preparation time in seconds (0: unlimited).
static func load_prep_seconds(file_path: String = "") -> int:
	var seconds: Variant = _read(file_path).get("prep_seconds", DEFAULT_PREP_SECONDS)
	if not (seconds is float or seconds is int) or not PREP_CHOICES.has(int(seconds)):
		return DEFAULT_PREP_SECONDS
	return int(seconds)


static func save_prep_seconds(seconds: int, file_path: String = "") -> void:
	_write("prep_seconds", seconds, file_path)


## True when the player muted the sound (false without a setting).
static func load_muted(file_path: String = "") -> bool:
	var muted: Variant = _read(file_path).get("muted", false)
	return muted is bool and muted


static func save_muted(muted: bool, file_path: String = "") -> void:
	_write("muted", muted, file_path)


## The choice after `seconds` in PREP_CHOICES, wrapping around.
static func next_prep_seconds(seconds: int) -> int:
	var index := PREP_CHOICES.find(seconds)
	return PREP_CHOICES[(index + 1) % PREP_CHOICES.size()]


static func _read(file_path: String) -> Dictionary:
	var source := file_path if file_path != "" else path
	if not FileAccess.file_exists(source):
		return {}
	var json := JSON.new()
	var data: Variant = json.data if json.parse(FileAccess.get_file_as_string(source)) == OK else null
	return data if data is Dictionary else {}


static func _write(key: String, value: Variant, file_path: String) -> void:
	var target := file_path if file_path != "" else path
	var data := _read(target)
	data[key] = value
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		if not _has_warned:
			_has_warned = true
			push_warning("Run: could not write %s (error %d)" % [target, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data))
	file.close()
