class_name TacticsRoster
extends RefCounted
## Sổ quân: every soldier of ours as a person kept between tactics battles,
## saved as JSON at [member path] (normally user://tactics_roster.json). A
## person has a stable id, a troop, a face seed (`look`), a status and the
## marks (Dấu) incidents left on it. Death is permanent. A missing file
## gives an empty roster; a broken file or an unknown version is warned
## about once, kept aside as `<path>.unreadable` and replaced by an empty
## one. A save is written whole to `<path>.tmp` first and then renamed over
## the file, so a crash mid-save never leaves half a roster.
## See Docs/systems/tactics_roster.md.
## [codeblock]
## var roster := TacticsRoster.load_roster()
## roster.save()
## [/codeblock]

const PATH: String = "user://tactics_roster.json"
## A save is written here first, then renamed over the roster.
const TEMP_SUFFIX: String = ".tmp"
## An unreadable roster is moved here instead of being overwritten.
const UNREADABLE_SUFFIX: String = ".unreadable"
const VERSION: int = 1
## active: fights for us; dead: fell (never comes back); deserted: fled the
## map; traitor: went over to the enemy.
const STATUSES: Array[String] = ["active", "dead", "deserted", "traitor"]
## The fallen who left no mark are forgotten past this many (the most
## recent stay), so a long campaign's save and roster list stay small.
const UNMARKED_FALLEN_KEPT: int = 30

## Where save(), load_roster() and delete() go without a path argument.
## Only tests change it, so they never touch the player's roster.
static var path: String = PATH
static var _has_warned: bool = false

## Seeds every battle's incidents (with the battle count).
var seed_value: int = 1
## Battles fought with this roster.
var battles: int = 0
var next_id: int = 1
## Bait and rescue karma carried into the next battle.
var karma_bait: int = 0
var karma_rescue: int = 0
## Per troop id, how many of that troop were ever recruited (the ordinal of
## a soldier's name and biography).
var troop_counts: Dictionary = {}
## One Dictionary per person: id, troop, number, look, status,
## first_leader, is_named and marks (Array of {incident, leader_id,
## terrain, round, battle}).
var people: Array[Dictionary] = []


static func load_roster(file_path: String = "") -> TacticsRoster:
	var source := file_path if file_path != "" else path
	if not FileAccess.file_exists(source):
		return create()
	var roster := TacticsRoster.new()
	var json := JSON.new()
	var data: Variant = json.data if json.parse(FileAccess.get_file_as_string(source)) == OK else null
	if not data is Dictionary or not roster._read(data):
		# Kept aside: a save from a newer build or a damaged file is not
		# overwritten by the next battle.
		DirAccess.rename_absolute(source, source + UNREADABLE_SUFFIX)
		_warn("set aside the unreadable roster %s as %s" % [source, source + UNREADABLE_SUFFIX])
		return create()
	return roster


## An empty roster; a seed of 0 picks one from the clock.
static func create(roster_seed: int = 0) -> TacticsRoster:
	var roster := TacticsRoster.new()
	roster.seed_value = roster_seed if roster_seed != 0 else absi(int(Time.get_unix_time_from_system()) ^ randi()) % 1000000007 + 1
	return roster


## Removes the roster and what a save or a load left beside it.
static func delete(file_path: String = "") -> void:
	var target := file_path if file_path != "" else path
	for file: String in [target, target + TEMP_SUFFIX, target + UNREADABLE_SUFFIX]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


## Writes the roster whole beside the file, then renames it over the file;
## false (with one warning, the old file untouched) when it cannot.
func save(file_path: String = "") -> bool:
	var target := file_path if file_path != "" else path
	var temp := target + TEMP_SUFFIX
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		_warn("could not write %s (error %d)" % [temp, FileAccess.get_open_error()])
		return false
	var is_written := file.store_string(JSON.stringify(to_save_data(), "\t"))
	file.close()
	var error := DirAccess.rename_absolute(temp, target) if is_written else ERR_FILE_CANT_WRITE
	if error != OK:
		DirAccess.remove_absolute(temp)
		_warn("could not save %s (%s)" % [target, error_string(error)])
		return false
	return true


func to_save_data() -> Dictionary:
	var saved_people: Array = []
	for person: Dictionary in people:
		var marks: Array = []
		for mark: Dictionary in person["marks"]:
			marks.append({
				"incident": String(mark["incident"]), "leader_id": String(mark["leader_id"]), "terrain": String(mark["terrain"]),
				"round": mark["round"], "battle": mark["battle"],
			})
		saved_people.append({
			"id": person["id"], "troop": String(person["troop"]), "number": person["number"], "look": person["look"],
			"status": person["status"], "first_leader": String(person["first_leader"]), "is_named": person["is_named"], "marks": marks,
		})
	return {
		"version": VERSION, "seed": str(seed_value), "battles": battles, "next_id": next_id,
		"karma_bait": karma_bait, "karma_rescue": karma_rescue, "troop_counts": troop_counts.duplicate(), "people": saved_people,
	}


## A new person of that troop, first mustered under `leader_id`.
func recruit(troop_id: StringName, leader_id: StringName) -> Dictionary:
	var number: int = int(troop_counts.get(String(troop_id), 0)) + 1
	troop_counts[String(troop_id)] = number
	var person := {
		"id": next_id, "troop": troop_id, "number": number, "look": _look_for(next_id), "status": "active",
		"first_leader": leader_id, "is_named": false, "marks": [],
	}
	next_id += 1
	people.append(person)
	return person


## Forgets the fallen without a mark beyond the UNMARKED_FALLEN_KEPT most
## recent (highest ids); a soldier with a mark is a story and stays.
func forget_old_fallen() -> void:
	var unmarked := 0
	for index: int in range(people.size() - 1, -1, -1):
		var person := people[index]
		if person["status"] != "dead" or not (person["marks"] as Array).is_empty():
			continue
		unmarked += 1
		if unmarked > UNMARKED_FALLEN_KEPT:
			people.remove_at(index)


func get_person(id: int) -> Dictionary:
	for person: Dictionary in people:
		if person["id"] == id:
			return person
	return {}


## Active people of that troop not in `taken` (the named ones who lead
## are), most marks first, then the lower id.
func find_soldiers(troop_id: StringName, taken: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for person: Dictionary in people:
		if person["troop"] == troop_id and person["status"] == "active" and not taken.has(person["id"]):
			found.append(person)
	found.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_marks: int = (left["marks"] as Array).size()
		var right_marks: int = (right["marks"] as Array).size()
		return left_marks > right_marks or (left_marks == right_marks and int(left["id"]) < int(right["id"])))
	return found


## Active people named for their marks, by id.
func get_named() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for person: Dictionary in people:
		if person["status"] == "active" and person["is_named"]:
			found.append(person)
	return found


## Deserters and traitors with at least `min_marks` marks, by id: they come
## back as enemy leaders.
func get_returning(min_marks: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for person: Dictionary in people:
		if (person["status"] == "deserted" or person["status"] == "traitor") and (person["marks"] as Array).size() >= min_marks:
			found.append(person)
	return found


## The incident id most of this person's marks name (the earliest on a tie).
static func main_incident(person: Dictionary) -> StringName:
	var counts := {}
	var best: StringName = &""
	for mark: Dictionary in person["marks"]:
		var incident: StringName = mark["incident"]
		counts[incident] = int(counts.get(incident, 0)) + 1
		if best == &"" or counts[incident] > counts[best]:
			best = incident
	return best


# A face seed spread from the id, the same on every machine.
func _look_for(id: int) -> int:
	return absi(hash("%d:%d" % [seed_value, id])) % 1000000


func _read(data: Dictionary) -> bool:
	var reader := SaveReader.new(data)
	if reader.get_int("version") != VERSION:
		return false
	seed_value = reader.get_int_string("seed")
	battles = reader.get_int("battles")
	next_id = reader.get_int("next_id")
	karma_bait = reader.get_int("karma_bait")
	karma_rescue = reader.get_int("karma_rescue")
	var counts: Variant = data.get("troop_counts")
	if not counts is Dictionary:
		return false
	troop_counts = {}
	for key: Variant in counts:
		var count: Variant = counts[key]
		if not key is String or not (count is float or count is int):
			return false
		troop_counts[key] = int(count)
	people.clear()
	for entry: Variant in reader.get_array("people"):
		if not entry is Dictionary or not _read_person(entry):
			return false
	return reader.is_valid


func _read_person(entry: Dictionary) -> bool:
	var reader := SaveReader.new(entry)
	var person := {
		"id": reader.get_int("id"), "troop": StringName(reader.get_string("troop")), "number": reader.get_int("number"),
		"look": reader.get_int("look"), "status": reader.get_string("status"),
		"first_leader": StringName(reader.get_string("first_leader")), "is_named": reader.get_bool("is_named"), "marks": [],
	}
	for mark_entry: Variant in reader.get_array("marks"):
		if not mark_entry is Dictionary:
			return false
		var mark_reader := SaveReader.new(mark_entry)
		person["marks"].append({
			"incident": StringName(mark_reader.get_string("incident")), "leader_id": StringName(mark_reader.get_string("leader_id")),
			"terrain": StringName(mark_reader.get_string("terrain")), "round": mark_reader.get_int("round"), "battle": mark_reader.get_int("battle"),
		})
		if not mark_reader.is_valid:
			return false
	if not reader.is_valid or not STATUSES.has(person["status"]):
		return false
	people.append(person)
	return true


static func _warn(message: String) -> void:
	if not _has_warned:
		_has_warned = true
		push_warning("TacticsRoster: " + message)
