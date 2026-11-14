class_name RunSettings
extends RefCounted
## Player settings kept between sessions in user://settings.json: for now
## the preparation time (60 s, 90 s or unlimited, chosen on the title
## screen). A missing or broken file gives the defaults; a failed write is
## warned about once.

const PATH: String = "user://settings.json"
## Preparation seconds the player can pick; 0 means no time limit.
const PREP_CHOICES: Array[int] = [60, 90, 0]
const DEFAULT_PREP_SECONDS: int = 60

static var _has_warned: bool = false


## The saved preparation time in seconds (0: unlimited).
static func load_prep_seconds(path: String = PATH) -> int:
	if not FileAccess.file_exists(path):
		return DEFAULT_PREP_SECONDS
	var json := JSON.new()
	var data: Variant = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if not data is Dictionary:
		return DEFAULT_PREP_SECONDS
	var seconds := int(data.get("prep_seconds", DEFAULT_PREP_SECONDS))
	return seconds if PREP_CHOICES.has(seconds) else DEFAULT_PREP_SECONDS


static func save_prep_seconds(seconds: int, path: String = PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		if not _has_warned:
			_has_warned = true
			push_warning("Run: could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify({"prep_seconds": seconds}))
	file.close()


## The choice after `seconds` in PREP_CHOICES, wrapping around.
static func next_prep_seconds(seconds: int) -> int:
	var index := PREP_CHOICES.find(seconds)
	return PREP_CHOICES[(index + 1) % PREP_CHOICES.size()]
