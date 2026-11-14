class_name EncounterEffects
extends RefCounted
## The registry of road-encounter effect kinds: the card line each one
## writes, whether it can cost the player something, and whether the run
## can pay it now. RunState applies them with a handler per kind
## (choose_encounter). Adding a kind means one entry here and one handler
## there. See Docs/systems/encounter.md.
## [codeblock]
## EncounterEffects.describe(effect)                 # "+6 vàng"
## EncounterEffects.get_option_refusal(run, option)  # Result.OK when it can be taken
## [/codeblock]

const GOLD: StringName = &"gain.gold"
const SUPPLY: StringName = &"gain.supply"
const MORALE: StringName = &"gain.morale"
const FREE_UNIT: StringName = &"gain.free_unit"
const FREE_REFRESHES: StringName = &"gain.free_refreshes"
const BET: StringName = &"gain.bet"
## Each kind: its text key, whether the amount is signed (a cost is
## negative) and the amount range allowed in data.
const KINDS: Dictionary[StringName, Dictionary] = {
	GOLD: {"text": "ENCOUNTER_FX_GOLD", "signed": true, "min": -20, "max": 20},
	SUPPLY: {"text": "ENCOUNTER_FX_SUPPLY", "signed": true, "min": -20, "max": 20},
	MORALE: {"text": "ENCOUNTER_FX_MORALE", "signed": true, "min": -20, "max": 20},
	FREE_UNIT: {"text": "ENCOUNTER_FX_FREE_UNIT", "signed": false, "min": 1, "max": 4},
	FREE_REFRESHES: {"text": "ENCOUNTER_FX_FREE_REFRESHES", "signed": false, "min": 1, "max": 5},
	BET: {"text": "ENCOUNTER_FX_BET", "signed": false, "min": 1, "max": 30},
}
## The resource each signed kind spends, as the Result for lacking it.
const LACKING: Dictionary[StringName, RunState.Result] = {
	GOLD: RunState.Result.NOT_ENOUGH_GOLD,
	SUPPLY: RunState.Result.NOT_ENOUGH_SUPPLY,
	MORALE: RunState.Result.NOT_ENOUGH_MORALE,
}


## An empty string, or what is wrong with the effect's data.
static func check_data(effect: EncounterEffect) -> String:
	if effect == null or not KINDS.has(effect.kind):
		return "unknown effect kind %s" % (effect.kind if effect != null else &"<null>")
	var kind: Dictionary = KINDS[effect.kind]
	if effect.amount < kind["min"] or effect.amount > kind["max"] or effect.amount == 0:
		return "%s amount %d must be %d..%d and not 0" % [effect.kind, effect.amount, kind["min"], kind["max"]]
	return ""


## True when the effect may stop the player from taking its option: a cost,
## or a unit that needs bench room.
static func can_be_refused(effect: EncounterEffect) -> bool:
	return effect.kind == FREE_UNIT or (LACKING.has(effect.kind) and effect.amount < 0)


## OK when `run` can take `option` now, else what it lacks: gold, supply or
## morale for the costs (summed per resource; morale must stay above 0),
## or BENCH_FULL for a unit with no free bench slot.
static func get_option_refusal(run: RunState, option: EncounterOption) -> RunState.Result:
	var totals: Dictionary[StringName, int] = {}
	for effect: EncounterEffect in option.effects:
		if effect.kind == FREE_UNIT and not run.has_free_bench_slot():
			return RunState.Result.BENCH_FULL
		if LACKING.has(effect.kind):
			totals[effect.kind] = totals.get(effect.kind, 0) + effect.amount
	var held := {GOLD: run.gold, SUPPLY: run.supply, MORALE: run.morale - 1}
	for kind: StringName in totals:
		if totals[kind] < 0 and held[kind] < -totals[kind]:
			return LACKING[kind]
	return RunState.Result.OK


## The effect as one line of its card ("+6 vàng", "Một quân giá 3").
static func describe(effect: EncounterEffect) -> String:
	var kind: Dictionary = KINDS.get(effect.kind, {})
	if kind.is_empty():
		return ""
	var amount: Variant = ("+%d" if effect.amount > 0 else "%d") % effect.amount if kind["signed"] else effect.amount
	return TranslationServer.translate(kind["text"]) % amount


## Every line of an option's card, one per effect.
static func describe_option(option: EncounterOption) -> String:
	var lines := PackedStringArray()
	for effect: EncounterEffect in option.effects:
		lines.append(describe(effect))
	return "\n".join(lines)
