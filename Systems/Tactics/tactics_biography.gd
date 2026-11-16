class_name TacticsBiography
extends RefCounted
## The name and biography of a soldier named for its marks, built only
## from its roster record, so they never change once it has them: the name
## is its number word plus the place word of the terrain where most of its
## first marks were left ("Bảy Cầu"); the biography is an opening line, one
## line per first mark and a closing line, all Locale templates.
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


func _init(tactics_text: TacticsText, mark_count: int) -> void:
	text = tactics_text
	marks_to_name = maxi(mark_count, 1)


## "Bảy Cầu": the name a soldier earns at marks_to_name marks.
func person_name(person: Dictionary) -> String:
	return "%s %s" % [_number_word(int(person["number"]), "NAME_NUMBER_%d"), tr("NAME_PLACE_" + _key_tail(_main_terrain(person)))]


## "Binh giáo số 7": what a soldier without a name is called.
func plain_name(person: Dictionary) -> String:
	return tr("ROSTER_PLAIN_NAME_FORMAT") % [text.unit_name(person["troop"]), int(person["number"])]


## The name for a named soldier, else the plain one.
func display_name(person: Dictionary) -> String:
	return person_name(person) if person["is_named"] else plain_name(person)


## The lines of the biography, from the first marks_to_name marks.
func biography(person: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	lines.append(tr("BIO_OPENING_FORMAT") % [text.unit_name(person["troop"]), _number_word(int(person["number"]), "NAME_ORDINAL_%d"), leader_name(person["first_leader"])])
	var marks: Array = person["marks"]
	for index: int in mini(marks.size(), marks_to_name):
		var mark: Dictionary = marks[index]
		var key := "BIO_MARK_%s_FORMAT" % _key_tail(mark["incident"])
		lines.append(tr(key) % [int(mark["round"]), text.terrain_name(mark["terrain"]).to_lower(), leader_name(mark["leader_id"])])
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
