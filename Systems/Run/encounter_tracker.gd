class_name EncounterTracker
extends RefCounted
## The road encounters of one run: which were drawn (never twice), the one
## waiting for a choice, and a bet waiting for the next battle. RunState
## owns it and draws with the run's generator after the reward of each
## stage in RunRules.encounter_stages. Read it; change it only through
## RunState. See Docs/systems/encounter.md.

var _catalog: Catalog
var _drawn: Array[StringName] = []
var _pending: StringName = &""
var _bet_gold: int = 0


func _init(catalog: Catalog) -> void:
	_catalog = catalog


## True when the reward of `stage` leads to an encounter (one is left).
func is_due(stage: int) -> bool:
	return _catalog.run_rules.encounter_stages.has(stage) and _drawn.size() < _catalog.encounters.size()


## Draws an encounter not drawn before and makes it the pending one.
func draw(rng: RandomNumberGenerator) -> EncounterData:
	var left: Array[EncounterData] = []
	for data: EncounterData in _catalog.encounters:
		if not _drawn.has(data.id):
			left.append(data)
	if left.is_empty():
		return null
	var data := left[rng.randi_range(0, left.size() - 1)]
	_drawn.append(data.id)
	_pending = data.id
	return data


func has_pending() -> bool:
	return _pending != &""


## The encounter waiting for a choice, or null.
func get_pending() -> EncounterData:
	return _catalog.get_encounter(_pending) if has_pending() else null


func clear_pending() -> void:
	_pending = &""


## Ids in the order they were drawn.
func get_drawn_ids() -> Array[StringName]:
	return _drawn.duplicate()


## Gold the bet pays if the next battle is won (0: no bet).
func get_bet_gold() -> int:
	return _bet_gold


func place_bet(gold: int) -> void:
	_bet_gold += gold


## Ends the bet after a battle; returns the gold it pays (0 on a loss).
func settle_bet(is_win: bool) -> int:
	var paid := _bet_gold if is_win else 0
	_bet_gold = 0
	return paid


## The most free refreshes a preparation of `stage` can still hold from an
## encounter: the last one's, if it came right before this stage.
func get_free_refresh_allowance(stage: int) -> int:
	var data := _get_last()
	if data == null or not _catalog.run_rules.encounter_stages.has(stage - 1):
		return 0
	var most := 0
	for option: EncounterOption in data.options:
		for effect: EncounterEffect in option.effects:
			if effect.kind == EncounterEffects.FREE_REFRESHES:
				most = maxi(most, effect.amount)
	return most


func to_save_data() -> Dictionary:
	return {
		"drawn": _drawn.map(func(id: StringName) -> String: return String(id)),
		"pending": String(_pending), "bet_gold": _bet_gold,
	}


## Restores a save, false when it is impossible for `phase` and `stage`:
## unknown or doubled ids, not exactly one draw per encounter stage passed,
## a pending encounter outside the ENCOUNTER phase (or not the last drawn),
## or a bet that is not one of the last encounter's, outside the
## preparation right after it.
func load_save_data(data: Variant, phase: int, stage: int) -> bool:
	if not data is Dictionary:
		return false
	var reader := SaveReader.new(data)
	var drawn := reader.get_array("drawn")
	var pending := StringName(reader.get_string("pending"))
	var bet_gold := reader.get_int("bet_gold")
	if not reader.is_valid:
		return false
	_drawn.clear()
	for id: Variant in drawn:
		if not id is String or _catalog.get_encounter(StringName(id)) == null or _drawn.has(StringName(id)):
			return false
		_drawn.append(StringName(id))
	_pending = pending
	_bet_gold = bet_gold
	return _is_consistent(phase, stage)


func _is_consistent(phase: int, stage: int) -> bool:
	var rules := _catalog.run_rules
	var is_encounter := phase == RunState.Phase.ENCOUNTER
	var expected := 0
	for encounter_stage: int in rules.encounter_stages:
		if encounter_stage < stage or (is_encounter and encounter_stage == stage):
			expected += 1
	if _drawn.size() != mini(expected, _catalog.encounters.size()):
		return false
	if is_encounter != has_pending() or (has_pending() and _pending != _drawn.back()):
		return false
	if is_encounter and not rules.encounter_stages.has(stage):
		return false
	if _bet_gold == 0:
		return true
	return phase == RunState.Phase.PREP and rules.encounter_stages.has(stage - 1) and _get_bets().has(_bet_gold)


func _get_last() -> EncounterData:
	return _catalog.get_encounter(_drawn.back()) if not _drawn.is_empty() else null


# The bet amounts the last encounter offers.
func _get_bets() -> Array[int]:
	var bets: Array[int] = []
	var data := _get_last()
	if data == null:
		return bets
	for option: EncounterOption in data.options:
		for effect: EncounterEffect in option.effects:
			if effect.kind == EncounterEffects.BET:
				bets.append(effect.amount)
	return bets
