class_name CutsceneData
extends Resource
## One cutscene as data: a painted backdrop, two speakers (unit ids; the
## sage is ExtraFigures.SAGE_UNIT_ID), the lines they say (translation keys,
## each with the side that says it) and, optionally, two choices. A Kỳ Ngộ
## and a road encounter build one at run time; the story scene is a .tres
## in Data/Cutscenes/. See Docs/systems/cutscene.md.

const LEFT: int = 0
const RIGHT: int = 1
## The backdrops CutsceneBackdrop can paint.
const BACKDROPS: Array[StringName] = [&"backdrop.mountain", &"backdrop.camp", &"backdrop.road"]

@export var id: StringName = &""
@export var backdrop: StringName = &"backdrop.mountain"
@export var left_unit: StringName = &""
@export var right_unit: StringName = &""
## Translation keys of the lines, in order.
@export var line_keys: Array[String] = []
## Who says each line: LEFT or RIGHT, one entry per line.
@export var line_speakers: Array[int] = []
## Empty, or exactly two choices: a small heading (the kind) and the text.
@export var choice_titles: Array[String] = []
@export var choice_texts: Array[String] = []
## Empty, or one per choice: the IconPainter icon drawn on the card instead
## of the Kỳ Ngộ seal.
@export var choice_icons: Array[StringName] = []
## Empty, or one per choice: true greys the card out and refuses it (the
## player cannot pay for it).
@export var choice_disabled: Array[bool] = []


func has_choices() -> bool:
	return not choice_titles.is_empty()


func is_choice_disabled(index: int) -> bool:
	return index >= 0 and index < choice_disabled.size() and choice_disabled[index]


func validate(catalog: Catalog) -> Array[String]:
	var problems: Array[String] = []
	var where := "Cutscene '%s'" % id
	if not BACKDROPS.has(backdrop):
		problems.append("%s: unknown backdrop '%s'" % [where, backdrop])
	for unit_id: StringName in [left_unit, right_unit]:
		if unit_id != ExtraFigures.SAGE_UNIT_ID and (catalog == null or catalog.get_unit(unit_id) == null):
			problems.append("%s: unknown speaker '%s'" % [where, unit_id])
	if line_keys.is_empty():
		problems.append("%s: has no lines" % where)
	if line_speakers.size() != line_keys.size():
		problems.append("%s: needs one speaker per line" % where)
	for speaker: int in line_speakers:
		if speaker != LEFT and speaker != RIGHT:
			problems.append("%s: speaker %d is not LEFT or RIGHT" % [where, speaker])
	if not choice_titles.is_empty() and (choice_titles.size() != 2 or choice_texts.size() != 2):
		problems.append("%s: needs no choices or exactly two" % where)
	for extra: Array in [choice_icons, choice_disabled]:
		if not extra.is_empty() and extra.size() != choice_titles.size():
			problems.append("%s: choice icons and disabled flags need one entry per choice" % where)
	return problems
