class_name EpiphanyCutscene
extends RefCounted
## Builds the CutsceneData of a pending Kỳ Ngộ: a unit of that family (the
## player's own when one is on the board) talks to the sage on the
## mountain pass; the family's first line is the unit's, the rest the
## sage's; the two drawn mutations are the choices. See
## Docs/systems/cutscene.md.

## The story scene before the boss stage, played once per run.
const STORY_PATH: String = "res://Data/Cutscenes/story_before_boss.tres"


## The cutscene of `run`'s pending Kỳ Ngộ, or null when none is pending.
static func build(run: RunState) -> CutsceneData:
	var tracker := run.epiphanies
	var family := run.catalog.get_epiphany_family(tracker.get_pending_family()) if tracker.has_pending() else null
	if family == null:
		return null
	var data := CutsceneData.new()
	data.id = StringName("cutscene." + String(family.family).trim_prefix("milestone."))
	data.backdrop = &"backdrop.mountain"
	data.left_unit = _speaker(run, family.family)
	data.right_unit = ExtraFigures.SAGE_UNIT_ID
	for index: int in family.line_keys.size():
		data.line_keys.append(family.line_keys[index])
		data.line_speakers.append(CutsceneData.LEFT if index == 0 else CutsceneData.RIGHT)
	for option: EpiphanyData in tracker.get_pending_options():
		data.choice_titles.append(option.name_key)
		data.choice_texts.append(option.description_key)
	return data


## The story scene (Liễu Mi and Ba Khắc), or null when it is missing.
static func load_story() -> CutsceneData:
	return load(STORY_PATH) as CutsceneData if ResourceLoader.exists(STORY_PATH) else null


# The board's strongest unit counted by `family_id`; else the cheapest
# shop unit counted by it.
static func _speaker(run: RunState, family_id: StringName) -> StringName:
	var milestone := run.catalog.get_milestone(family_id)
	var best: RunPiece = null
	for piece: RunPiece in run.get_board_pieces():
		var unit := run.catalog.get_unit(piece.unit_id)
		if _counts(milestone, unit) and (best == null or piece.star > best.star):
			best = piece
	if best != null:
		return best.unit_id
	var fallback: UnitData = null
	for unit: UnitData in run.catalog.units:
		if not unit.is_boss and _counts(milestone, unit) and (fallback == null or unit.cost < fallback.cost):
			fallback = unit
	return fallback.id if fallback != null else &"unit.shield_guard"


static func _counts(milestone: MilestoneData, unit: UnitData) -> bool:
	if milestone == null or unit == null:
		return false
	var counted := unit.race_id if milestone.counted_kind == &"race" else unit.class_id
	return counted == milestone.counted_id
