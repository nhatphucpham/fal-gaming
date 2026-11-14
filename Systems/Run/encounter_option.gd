class_name EncounterOption
extends Resource
## One of the two choices of a road encounter: a short heading for its card
## and the effects it applies, in order. The card's text is written from
## the effects (EncounterEffects.describe), so tuning a number never needs
## a new string.

@export var title_key: String = ""
@export var effects: Array[EncounterEffect] = []


## True when nothing in it costs anything or needs bench room, so the
## player can always take it.
func is_always_affordable() -> bool:
	for effect: EncounterEffect in effects:
		if effect == null or EncounterEffects.can_be_refused(effect):
			return false
	return true
