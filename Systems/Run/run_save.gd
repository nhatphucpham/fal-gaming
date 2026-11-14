class_name RunSave
extends RefCounted
## Saves and loads the run in progress as JSON at user://run_save.json (on
## the web that is the browser's IndexedDB). A missing file is normal; a
## broken file, an unknown version or a failed write is reported once with
## push_warning and otherwise ignored, so the game keeps running.
## [codeblock]
## RunSave.save(run)
## var run := RunSave.load_run(catalog)   # null without a usable save
## [/codeblock]

const PATH: String = "user://run_save.json"
const VERSION: int = 1

static var _has_warned: bool = false


## Writes the run. False (with one warning) when the file cannot be written.
static func save(run: RunState, path: String = PATH) -> bool:
	var data := run.to_save_data()
	data["version"] = VERSION
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_warn("could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


static func has_save(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)


## The saved run, ready in its preparation, or null when there is none or
## it cannot be used (warned once).
static func load_run(catalog: Catalog, path: String = PATH) -> RunState:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	var data: Variant = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if not data is Dictionary:
		_warn("%s is not a save file; ignored" % path)
		return null
	if int(data.get("version", -1)) != VERSION:
		_warn("%s has version %s, expected %d; ignored" % [path, data.get("version", "none"), VERSION])
		return null
	var run := RunState.new(catalog, 0)
	if not run.load_save_data(data):
		_warn("%s has broken run data; ignored" % path)
		return null
	return run


## Removes the save (the run ended).
static func delete(path: String = PATH) -> void:
	if FileAccess.file_exists(path):
		var error := DirAccess.remove_absolute(path)
		if error != OK:
			_warn("could not delete %s (error %d)" % [path, error])


static func _warn(message: String) -> void:
	if _has_warned:
		return
	_has_warned = true
	push_warning("Run: " + message)
