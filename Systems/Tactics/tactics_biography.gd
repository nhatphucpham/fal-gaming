class_name TacticsBiography
extends RefCounted
## The name and biography of a soldier named for its marks, built only
## from its roster record, so they never change once it has them: the name
## is its number word plus the place word of the terrain where most of its
## first marks were left ("Bảy Cầu"); one named after another soldier
## already called that adds its troop ("Bảy Cung Cầu"), and its number too
## when that soldier is of its troop ("Bảy Giáo Cầu số 17"), so no two are
## alike; the biography is an opening line, one line per first mark and a
## closing line, all Locale templates.
## See Docs/systems/tactics_roster.md.
## [codeblock]
## var bio := TacticsBiography.new(text, 3)
## label.text = bio.person_name(person)
## [/codeblock]

## How many numbers have their own word (NAME_NUMBER_1..10).
const NUMBER_WORDS: int = 10

var text: TacticsText
## The marks a name and biography are built from (marks_to_name).
var marks_to_name: int = 3
## Names leader ids that are not in the catalog (leaders named from the
## roster): StringName -> String.
var leader_names: Dictionary = {}
## The roster whose named soldiers a name must differ from; null skips it.
var roster: TacticsRoster


func _init(tactics_text: TacticsText, mark_count: int) -> void:
	text = tactics_text
	marks_to_name = maxi(mark_count, 1)


## "Bảy Cầu": the name a soldier earns at marks_to_name marks, made
## longer when a soldier named before it already has it (see the class doc).
func person_name(person: Dictionary) -> String:
	var number := _number_word(int(person["number"]), "NAME_NUMBER_%d")
	var place := tr("NAME_PLACE_" + _key_tail(_main_terrain(person)))
	var base := "%s %s" % [number, place]
	if roster == null:
		return base
	var is_taken := false
	var is_taken_by_troop := false
	for other: Dictionary in roster.people:
		if other["is_named"] and other["id"] != person["id"] and _is_named_before(other, person) and _base_name(other) == base:
			is_taken = true
			is_taken_by_troop = is_taken_by_troop or other["troop"] == person["troop"]
	if not is_taken:
		return base
	var troop_data := text.unit_data(person["troop"])
	var troop := tr(troop_data.name_key + "_SHORT") if troop_data != null else String(person["troop"])
	if not is_taken_by_troop:
		return tr("NAME_TROOP_FORMAT") % [number, troop, place]
	return tr("NAME_TROOP_NUMBER_FORMAT") % [number, troop, place, int(person["number"])]


## "Binh giáo số 7": what a soldier without a name is called.
func plain_name(person: Dictionary) -> String:
	return tr("ROSTER_PLAIN_NAME_FORMAT") % [text.unit_name(person["troop"]), int(person["number"])]


## The name for a named soldier, else the plain one.
func display_name(person: Dictionary) -> String:
	return person_name(person) if person["is_named"] else plain_name(person)


## The lines of the biography, from the first marks_to_name marks.
func biography(person: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var number := int(person["number"])
	# Past ten the ordinal is the number itself: the 17th is not the 7th.
	var ordinal := _number_word(number, "NAME_ORDINAL_%d") if number <= NUMBER_WORDS else str(number)
	lines.append(tr("BIO_OPENING_FORMAT") % [text.unit_name(person["troop"]), ordinal, leader_name(person["first_leader"])])
	var marks: Array = person["marks"]
	var count := mini(marks.size(), marks_to_name)
	# Marks from several battles say which battle, so two alike never read
	# as the same sentence twice.
	var is_one_battle := true
	for index: int in count:
		is_one_battle = is_one_battle and int(marks[index].get("battle", 0)) == int(marks[0].get("battle", 0))
	for index: int in count:
		var mark: Dictionary = marks[index]
		var key := "BIO_MARK_%s_FORMAT" % _key_tail(mark["incident"])
		var when: String = tr("BIO_WHEN_ROUND_FORMAT") % int(mark["round"]) if is_one_battle else tr("BIO_WHEN_BATTLE_FORMAT") % [int(mark.get("battle", 0)), int(mark["round"])]
		var line: String = tr(key) % [when, text.terrain_name(mark["terrain"]).to_lower(), leader_name(mark["leader_id"])]
		# Two records of one deed (an old or hand-edited save) tell it once.
		if not lines.has(line):
			lines.append(line)
	lines.append(tr("BIO_CLOSING_FORMAT") % person_name(person))
	return lines


## One line for a mark, for the character sheet: "Cứu trợ · cầu · vòng 3".
func mark_line(mark: Dictionary) -> String:
	return tr("ROSTER_MARK_LINE_FORMAT") % [incident_name(mark["incident"]), text.terrain_name(mark["terrain"]).to_lower(), int(mark["round"]), leader_name(mark["leader_id"])]


func incident_name(incident: StringName) -> String:
	return text.incident_name(incident)


func leader_name(leader_id: StringName) -> String:
	if leader_names.has(leader_id):
		return leader_names[leader_id]
	return text.unit_name(leader_id)


func _base_name(person: Dictionary) -> String:
	return "%s %s" % [_number_word(int(person["number"]), "NAME_NUMBER_%d"), tr("NAME_PLACE_" + _key_tail(_main_terrain(person)))]


# Named in an earlier battle (the battle of the mark that named it), or in
# the same one with a lower id.
func _is_named_before(other: Dictionary, person: Dictionary) -> bool:
	var other_battle := _naming_battle(other)
	var battle := _naming_battle(person)
	return other_battle < battle or (other_battle == battle and int(other["id"]) < int(person["id"]))


func _naming_battle(person: Dictionary) -> int:
	var marks: Array = person["marks"]
	if marks.is_empty():
		return 0
	return int(marks[mini(marks.size(), marks_to_name) - 1].get("battle", 0))


# The terrain most of the first marks were left on, the earliest on a tie.
func _main_terrain(person: Dictionary) -> StringName:
	var counts := {}
	var best: StringName = &"terrain.plain"
	var best_count := 0
	var marks: Array = person["marks"]
	for index: int in mini(marks.size(), marks_to_name):
		var terrain: StringName = marks[index]["terrain"]
		counts[terrain] = int(counts.get(terrain, 0)) + 1
		if counts[terrain] > best_count:
			best = terrain
			best_count = counts[terrain]
	return best


func _number_word(number: int, key_format: String) -> String:
	return tr(key_format % ((maxi(number, 1) - 1) % NUMBER_WORDS + 1))


# `incident.rescue` -> `RESCUE`, `terrain.plain` -> `PLAIN`.
static func _key_tail(id: StringName) -> String:
	return String(id).get_slice(".", 1).to_upper()
