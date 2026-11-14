class_name RunSave
extends RefCounted
## Saves and loads the run in progress as JSON at [member path] (normally
## user://run_save.json; on the web that is the browser's IndexedDB). A
## missing file is normal; a broken file, an unknown version or a failed
## write is reported once with push_warning and otherwise ignored, so the
## game keeps running.
## [codeblock]
## RunSave.save(run)
## var run := RunSave.load_run(catalog)   # null without a usable save
## [/codeblock]

const PATH: String = "user://run_save.json"
## 2 added the phase and the offered rewards, 3 the Kỳ Ngộ state, 4 the
## road encounters, the win streak and the loot reward; older saves are
## ignored.
const VERSION: int = 4

## Where save(), load_run(), has_save() and delete() go without a path
## argument. Only tests change it, so they never touch the player's save.
static var path: String = PATH
static var _has_warned: bool = false


## Writes the run (in its preparation or reward choice). False (with one
## warning) when the file cannot be written.
static func save(run: RunState, file_path: String = "") -> bool:
	if not run.can_save():
		push_error("Run: a run in %s cannot be saved" % RunState.Phase.keys()[run.phase])
		return false
	var target := _resolve(file_path)
	var data := run.to_save_data()
	data["version"] = VERSION
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		_warn("could not write %s (error %d)" % [target, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


static func has_save(file_path: String = "") -> bool:
	return FileAccess.file_exists(_resolve(file_path))


## The saved run, in its preparation or reward choice, or null when there
## is none or it cannot be used (warned once).
static func load_run(catalog: Catalog, file_path: String = "") -> RunState:
	var source := _resolve(file_path)
	if not FileAccess.file_exists(source):
		return null
	var json := JSON.new()
	var data: Variant = json.data if json.parse(FileAccess.get_file_as_string(source)) == OK else null
	if not data is Dictionary:
		_warn("%s is not a save file; ignored" % source)
		return null
	var reader := SaveReader.new(data)
	var version := reader.get_int("version")
	if not reader.is_valid or version != VERSION:
		_warn("%s has version %s, expected %d; ignored" % [source, data.get("version", "none"), VERSION])
		return null
	var run := RunState.new(catalog, 0)
	if not run.load_save_data(data):
		_warn("%s has broken run data; ignored" % source)
		return null
	return run


## Removes the save (the run ended).
static func delete(file_path: String = "") -> void:
	var target := _resolve(file_path)
	if FileAccess.file_exists(target):
		var error := DirAccess.remove_absolute(target)
		if error != OK:
			_warn("could not delete %s (error %d)" % [target, error])


static func _resolve(file_path: String) -> String:
	return file_path if file_path != "" else path


static func _warn(message: String) -> void:
	if _has_warned:
		return
	_has_warned = true
	push_warning("Run: " + message)
