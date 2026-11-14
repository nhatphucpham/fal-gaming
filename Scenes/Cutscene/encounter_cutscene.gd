class_name EncounterCutscene
extends RefCounted
## Builds the CutsceneData of a pending road encounter: the player's
## strongest unit (left) meets the encounter's speaker (right) on the road;
## the two options are the cards, each with the icon of its first effect
## and its effects as text, greyed out when the run cannot pay for it. See
## Docs/systems/encounter.md.

## The card icon per effect kind (IconPainter kinds).
const ICONS: Dictionary[StringName, StringName] = {
	EncounterEffects.GOLD: &"coin", EncounterEffects.SUPPLY: &"supply", EncounterEffects.MORALE: &"morale",
	EncounterEffects.FREE_UNIT: &"troops", EncounterEffects.FREE_REFRESHES: &"lantern", EncounterEffects.BET: &"coin",
}
const FALLBACK_SPEAKER: StringName = &"unit.shield_guard"


## The cutscene of `run`'s pending encounter, or null when none waits.
static func build(run: RunState) -> CutsceneData:
	var encounter := run.encounters.get_pending()
	if encounter == null:
		return null
	var data := CutsceneData.new()
	data.id = StringName("cutscene.road_" + String(encounter.id).trim_prefix("encounter."))
	data.backdrop = &"backdrop.road"
	data.left_unit = _player_speaker(run)
	data.right_unit = encounter.speaker
	data.line_keys.assign(encounter.line_keys)
	for speaker: int in encounter.line_speakers:
		data.line_speakers.append(CutsceneData.LEFT if speaker == EncounterData.SPEAKER_PLAYER else CutsceneData.RIGHT)
	for index: int in encounter.options.size():
		var option := encounter.options[index]
		data.choice_titles.append(option.title_key)
		data.choice_texts.append(EncounterEffects.describe_option(option))
		data.choice_icons.append(ICONS.get(option.effects[0].kind, &"coin"))
		data.choice_disabled.append(run.get_encounter_refusal(index) != RunState.Result.OK)
	return data


# The board's (else the bench's) highest-star, dearest unit.
static func _player_speaker(run: RunState) -> StringName:
	var best: RunPiece = null
	for piece: RunPiece in run.get_pieces():
		if best == null or _rank(run, piece) > _rank(run, best):
			best = piece
	return best.unit_id if best != null else FALLBACK_SPEAKER


static func _rank(run: RunState, piece: RunPiece) -> int:
	return (100 if piece.is_on_board() else 0) + piece.star * 10 + run.catalog.get_unit(piece.unit_id).cost
