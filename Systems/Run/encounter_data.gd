class_name EncounterData
extends Resource
## One road encounter (Kỳ Ngộ dọc đường), one file per encounter in
## Data/Encounters/, listed in Data/catalog.tres (`encounters`). It plays
## through the cutscene screen: the player's unit (left) meets `speaker`
## (right), 2-3 lines, then two option cards. See
## Docs/systems/encounter.md.
## [codeblock]
## var data := catalog.get_encounter(&"encounter.merchants")
## data.options[0].effects   # what the first card does
## [/codeblock]

## The generic figure (an old sage), drawn by ExtraFigures in the scenes;
## the rules layer names it without loading scene code.
const SAGE_SPEAKER: StringName = &"unit.sage"
const SPEAKER_PLAYER: int = 0
const SPEAKER_STRANGER: int = 1

## Stable id, `encounter.<name>`.
@export var id: StringName = &""
## Its name, shown under the cutscene title.
@export var name_key: String = ""
## Who the player meets: a catalog unit id, or SAGE_SPEAKER
## for a generic figure.
@export var speaker: StringName = SAGE_SPEAKER
@export var line_keys: Array[String] = []
## SPEAKER_PLAYER or SPEAKER_STRANGER, one per line.
@export var line_speakers: Array[int] = []
## Exactly two.
@export var options: Array[EncounterOption] = []


## Problems in the data, one message each; empty when valid.
func validate(catalog: Catalog) -> PackedStringArray:
	var problems := PackedStringArray()
	var where := "Run: encounter %s (%s)" % [id, resource_path]
	if not String(id).begins_with("encounter.") or name_key.is_empty():
		problems.append("%s needs an encounter.<name> id and a name_key" % where)
	if speaker != SAGE_SPEAKER and catalog.get_unit(speaker) == null:
		problems.append("%s has unknown speaker %s" % [where, speaker])
	if line_keys.size() < 2 or line_keys.size() > 3 or line_speakers.size() != line_keys.size():
		problems.append("%s needs 2-3 lines with one speaker each" % where)
	for line_speaker: int in line_speakers:
		if line_speaker != SPEAKER_PLAYER and line_speaker != SPEAKER_STRANGER:
			problems.append("%s has line speaker %d, expected 0 or 1" % [where, line_speaker])
	if options.size() != 2 or options.has(null):
		problems.append("%s needs exactly two options" % where)
		return problems
	var has_free_option := false
	for option: EncounterOption in options:
		if option.title_key.is_empty() or option.effects.is_empty():
			problems.append("%s has an option without a title_key or effects" % where)
		for effect: EncounterEffect in option.effects:
			var problem := EncounterEffects.check_data(effect)
			if not problem.is_empty():
				problems.append("%s: %s" % [where, problem])
		has_free_option = has_free_option or option.is_always_affordable()
	if not has_free_option:
		problems.append("%s needs one option that costs nothing" % where)
	return problems
