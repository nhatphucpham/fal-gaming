class_name EpiphanyTracker
extends RefCounted
## The run's Kỳ Ngộ: one Ngộ meter per milestone family, its hidden
## threshold (rolled from the run seed), the mutations chosen so far and the
## pending choice. Pure data, owned by RunState, which calls
## [method record_battle] after each battle and saves it. The rules and
## numbers are in Docs/systems/epiphany.md.
## [codeblock]
## var tracker := EpiphanyTracker.new(catalog, run_seed)
## if tracker.record_battle(stage, active, damage, is_win, rng): show the cutscene
## tracker.choose(0)
## synergy.evaluate(pieces, tracker.get_overrides())
## [/codeblock]

# Mixed into the run seed for the thresholds, so rolling them does not
# change the run's own generator (and its shops).
const THRESHOLD_SEED_SALT: int = 0x4E676F
const NO_STAGE: int = 0

var _catalog: Catalog
var _rules: RunRules
## Family ids in catalog milestone order (the tie order).
var _families: Array[StringName] = []
var _thresholds: Dictionary[StringName, int] = {}
var _meters: Dictionary[StringName, int] = {}
## Chosen epiphany ids, in the order they were chosen.
var _chosen: Array[StringName] = []
var _pending_family: StringName = &""
var _pending_options: Array[StringName] = []
var _last_stage: int = NO_STAGE


func _init(catalog: Catalog, run_seed: int) -> void:
	_catalog = catalog
	_rules = catalog.run_rules
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ THRESHOLD_SEED_SALT
	for milestone: MilestoneData in catalog.milestones:
		if catalog.get_epiphany_family(milestone.id) == null:
			continue
		_families.append(milestone.id)
		_thresholds[milestone.id] = rng.randi_range(_rules.ngo_threshold_min, _rules.ngo_threshold_max)
		_meters[milestone.id] = 0


# --- Queries -------------------------------------------------------------

func get_families() -> Array[StringName]:
	return _families.duplicate()


func get_meter(family: StringName) -> int:
	return _meters.get(family, 0)


## The hidden threshold (tests and the bot; the screen only hints at it).
func get_threshold(family: StringName) -> int:
	return _thresholds.get(family, 0)


## True when the family's meter is one short of its threshold or at it,
## and it can still fire (not mutated, not pending, the run's Kỳ Ngộ not
## used up): the prep panel shakes its milestone.
func is_near(family: StringName) -> bool:
	return _thresholds.has(family) and not is_mutated(family) and _pending_family != family \
		and _chosen.size() < _rules.epiphanies_per_run and get_meter(family) >= get_threshold(family) - 1


func is_mutated(family: StringName) -> bool:
	return get_mutation(family) != null


## The mutation chosen for a family, or null.
func get_mutation(family: StringName) -> EpiphanyData:
	for id: StringName in _chosen:
		var epiphany := _catalog.get_epiphany(id)
		if epiphany.family == family:
			return epiphany
	return null


func get_chosen_ids() -> Array[StringName]:
	return _chosen.duplicate()


func has_pending() -> bool:
	return _pending_family != &""


func get_pending_family() -> StringName:
	return _pending_family


## The two mutations offered, as EpiphanyData.
func get_pending_options() -> Array[EpiphanyData]:
	var options: Array[EpiphanyData] = []
	for id: StringName in _pending_options:
		options.append(_catalog.get_epiphany(id))
	return options


## The chosen mutations as Synergy overrides, for the player's side only.
func get_overrides() -> Array:
	var overrides: Array = []
	for id: StringName in _chosen:
		var epiphany := _catalog.get_epiphany(id)
		overrides.append(epiphany.to_override(_catalog.get_milestone(epiphany.family)))
	return overrides


# --- Rules ---------------------------------------------------------------

## Adds this battle's Ngộ: `active` families had a tier reached,
## `damage` maps family to its units' damage. Fires at most one Kỳ Ngộ
## (drawing its two options from `rng`); true when one fired.
func record_battle(stage: int, active: Array[StringName], damage: Dictionary, is_win: bool, rng: RandomNumberGenerator) -> bool:
	var top := _top_damage_family(active, damage)
	for family: StringName in _families:
		if not active.has(family) or is_mutated(family):
			continue
		var gain := _rules.ngo_per_active + (0 if is_win else _rules.ngo_loss_bonus)
		if family == top:
			gain += _rules.ngo_top_damage_bonus
		_meters[family] = mini(_meters[family] + gain, _rules.ngo_meter_max)
	return _try_fire(stage, rng)


## Takes option 0 or 1 of the pending choice. False without one.
func choose(option: int) -> bool:
	if not has_pending() or option < 0 or option >= _pending_options.size():
		return false
	_chosen.append(_pending_options[option])
	_pending_family = &""
	_pending_options.clear()
	return true


# The active, not yet mutated family whose units dealt the most damage
# (more than 0); ties go to catalog order.
func _top_damage_family(active: Array[StringName], damage: Dictionary) -> StringName:
	var best: StringName = &""
	var best_damage := 0
	for family: StringName in _families:
		var dealt: int = damage.get(family, 0)
		if active.has(family) and not is_mutated(family) and dealt > best_damage:
			best = family
			best_damage = dealt
	return best


func _try_fire(stage: int, rng: RandomNumberGenerator) -> bool:
	if has_pending() or stage == _last_stage or _chosen.size() >= _rules.epiphanies_per_run:
		return false
	var best: StringName = &""
	var best_overflow := -1
	for family: StringName in _families:
		var overflow := get_meter(family) - get_threshold(family)
		if not is_mutated(family) and overflow >= 0 and overflow > best_overflow:
			best = family
			best_overflow = overflow
	if best == &"":
		return false
	var pool: Array[StringName] = []
	for epiphany: EpiphanyData in _catalog.get_epiphany_family(best).epiphanies:
		pool.append(epiphany.id)
	_pending_options.clear()
	for draw: int in 2:
		_pending_options.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	_pending_family = best
	_last_stage = stage
	return true


# --- Save ----------------------------------------------------------------

func to_save_data() -> Dictionary:
	var meters := {}
	for family: StringName in _families:
		meters[String(family)] = _meters[family]
	return {
		"meters": meters, "chosen": _chosen.map(func(id: StringName) -> String: return String(id)),
		"pending_family": String(_pending_family),
		"pending_options": _pending_options.map(func(id: StringName) -> String: return String(id)),
		"last_stage": _last_stage,
	}


## Restores a saved state; false when anything is missing, of the wrong
## type or impossible (see "Save format" in Docs/systems/run.md). `phase`
## and `stage` are the save's: a pending choice exists only in REWARD.
func load_save_data(data: Variant, phase: int, stage: int) -> bool:
	if not data is Dictionary:
		return false
	var reader := SaveReader.new(data)
	var meters_value: Variant = data.get("meters")
	var chosen := reader.get_array("chosen")
	var pending_family := StringName(reader.get_string("pending_family"))
	var pending := reader.get_array("pending_options")
	var last_stage := reader.get_int("last_stage")
	if not reader.is_valid or not meters_value is Dictionary or not _read_meters(meters_value):
		return false
	var chosen_ids: Variant = _read_ids(chosen)
	var pending_ids: Variant = _read_ids(pending)
	if chosen_ids == null or pending_ids == null or last_stage < NO_STAGE or last_stage > stage:
		return false
	_chosen.assign(chosen_ids)
	_pending_options.assign(pending_ids)
	_pending_family = pending_family
	_last_stage = last_stage
	return _is_consistent(phase, stage)


func _read_meters(saved: Dictionary) -> bool:
	if saved.size() != _families.size():
		return false
	for family: StringName in _families:
		var reader := SaveReader.new(saved)
		var value := reader.get_int(String(family))
		if not reader.is_valid or value < 0 or value > _rules.ngo_meter_max:
			return false
		_meters[family] = value
	return true


# Known epiphany ids, each once; null otherwise.
func _read_ids(saved: Array) -> Variant:
	var ids: Array[StringName] = []
	for value: Variant in saved:
		if not value is String or _catalog.get_epiphany(StringName(value)) == null or ids.has(StringName(value)):
			return null
		ids.append(StringName(value))
	return ids


# One mutation per family, at most the per-run limit with the pending one
# and no more than the stage of the last firing (one per stage);
# a pending choice only in the reward phase, of two options of a family
# that is not mutated.
func _is_consistent(phase: int, stage: int) -> bool:
	var families: Array[StringName] = []
	for id: StringName in _chosen:
		var family := _catalog.get_epiphany(id).family
		if families.has(family):
			return false
		families.append(family)
	var pending_count := 1 if has_pending() else 0
	if _chosen.size() + pending_count > _rules.epiphanies_per_run:
		return false
	# One Kỳ Ngộ fires per stage at most, each at a later stage than the
	# one before, so there cannot be more than the last firing stage.
	if _chosen.size() + pending_count > _last_stage:
		return false
	if not has_pending():
		return _pending_options.is_empty()
	if phase != RunState.Phase.REWARD or _last_stage != stage or families.has(_pending_family) or _pending_options.size() != 2:
		return false
	for id: StringName in _pending_options:
		if _catalog.get_epiphany(id).family != _pending_family:
			return false
	return true
