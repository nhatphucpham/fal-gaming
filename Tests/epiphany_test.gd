extends SceneTree

# Headless tests of Kỳ Ngộ: the Ngộ gain rules, thresholds from the run
# seed, the firing limits (one per stage, four per run, each family once),
# both kinds of mutation changing Synergy.evaluate and a battle (player
# side only), and save/load with mutations and a pending choice. Writes no
# save: the run data goes through to_save_data / load_save_data.

const SHIELD := &"milestone.class_shield"
const SWORD := &"milestone.class_sword"
const SPEAR := &"milestone.class_spear"
const BATTLE_TICKS: int = 120

var _catalog: Catalog
var _battles: Array[Battle] = []


func _initialize() -> void:
	_catalog = load("res://Data/catalog.tres") as Catalog
	var ok := _run()
	for battle: Battle in _battles:
		battle.free()
	if ok:
		print("Epiphany test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not ClassDB.class_exists("Battle"):
		push_error("Battle is missing: build the GDExtension (scons) before importing")
		return false
	var problems := _catalog.validate()
	if not problems.is_empty():
		push_error("Catalog is invalid: %s" % ", ".join(problems))
		return false
	var checks: Array[Callable] = [
		_check_families, _check_gain_rules, _check_thresholds, _check_one_per_stage,
		_check_run_limit, _check_lower_evaluate, _check_variant_evaluate,
		_check_lower_battle, _check_variant_battle, _check_run_commands, _check_save_round_trip,
		_check_bad_saves, _check_bad_variant_data,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Epiphany test failed in %s" % check.get_method())
			return false
	return true


# Every milestone family has a list with at least three options, of both
# kinds.
func _check_families() -> bool:
	for milestone: MilestoneData in _catalog.milestones:
		var family := _catalog.get_epiphany_family(milestone.id)
		if family == null or family.epiphanies.size() < 3:
			push_error("%s needs at least 3 Kỳ Ngộ options" % milestone.id)
			return false
		var kinds := {}
		for epiphany: EpiphanyData in family.epiphanies:
			kinds[epiphany.kind] = true
		if not kinds.has(EpiphanyData.KIND_LOWER) or not kinds.has(EpiphanyData.KIND_VARIANT):
			push_error("%s needs both a Hạ Mốc and a Biến Dị option" % milestone.id)
			return false
	return true


# +1 per active family, +1 more after a loss, +2 for the active family whose
# units dealt the most damage; inactive families and zero damage give none.
func _check_gain_rules() -> bool:
	var tracker := EpiphanyTracker.new(_catalog, 1)
	var rng := _rng()
	var active: Array[StringName] = [SHIELD, SWORD]
	tracker.record_battle(1, active, {SHIELD: 40, SWORD: 90, SPEAR: 500}, true, rng)
	if tracker.get_meter(SHIELD) != 1 or tracker.get_meter(SWORD) != 3 or tracker.get_meter(SPEAR) != 0:
		push_error("Win: expected shield 1, sword 3, spear 0, got %d %d %d" % [tracker.get_meter(SHIELD), tracker.get_meter(SWORD), tracker.get_meter(SPEAR)])
		return false
	var other := EpiphanyTracker.new(_catalog, 1)
	other.record_battle(1, active, {}, false, rng)
	if other.get_meter(SHIELD) != 2 or other.get_meter(SWORD) != 2:
		push_error("Loss without damage: expected 2 and 2, got %d %d" % [other.get_meter(SHIELD), other.get_meter(SWORD)])
		return false
	return true


# Thresholds lie in 4..7, come from the run seed alone and do not move the
# run's own random numbers (the shop of a seed is unchanged).
func _check_thresholds() -> bool:
	var rules := _catalog.run_rules
	var first := EpiphanyTracker.new(_catalog, 777)
	var again := EpiphanyTracker.new(_catalog, 777)
	var differs := false
	for seed_value: int in [1, 2, 3, 4, 5]:
		var other := EpiphanyTracker.new(_catalog, seed_value)
		for family: StringName in first.get_families():
			differs = differs or other.get_threshold(family) != first.get_threshold(family)
	for family: StringName in first.get_families():
		var threshold := first.get_threshold(family)
		if threshold < rules.ngo_threshold_min or threshold > rules.ngo_threshold_max or threshold != again.get_threshold(family):
			push_error("%s threshold %d is outside %d..%d or not from the seed" % [family, threshold, rules.ngo_threshold_min, rules.ngo_threshold_max])
			return false
	if not differs:
		push_error("Other seeds should give other thresholds")
		return false
	return true


# Three full meters after one battle fire one Kỳ Ngộ (the highest
# overflow); another battle of the same stage fires none; the next stage
# fires the next one. A family near its threshold is "near".
func _check_one_per_stage() -> bool:
	var tracker := EpiphanyTracker.new(_catalog, 5)
	var rng := _rng()
	var active: Array[StringName] = [SHIELD, SWORD, SPEAR]
	# Losses add 2 a battle (4 for the spears, which deal the damage).
	var stage := 1
	while stage < 20 and not tracker.record_battle(stage, active, {SPEAR: 10}, false, rng):
		stage += 1
	if not tracker.has_pending():
		push_error("A full meter should fire a Kỳ Ngộ")
		return false
	var fired := tracker.get_pending_family()
	var best := -99
	for family: StringName in active:
		best = maxi(best, tracker.get_meter(family) - tracker.get_threshold(family))
	if tracker.get_meter(fired) - tracker.get_threshold(fired) != best or tracker.get_pending_options().size() != 2:
		push_error("The highest overflow should fire with two options")
		return false
	if tracker.is_near(fired):
		push_error("A pending family is not near any more")
		return false
	tracker.choose(0)
	if tracker.record_battle(stage, active, {}, false, rng):
		push_error("A second Kỳ Ngộ fired in stage %d" % stage)
		return false
	if not tracker.record_battle(stage + 1, active, {}, false, rng) or tracker.get_pending_family() == fired:
		push_error("The next stage should fire another family")
		return false
	return true


# Every family over its threshold, battle after battle: four fire, each
# family once, then no more.
func _check_run_limit() -> bool:
	var tracker := EpiphanyTracker.new(_catalog, 9)
	var rng := _rng()
	var active := tracker.get_families()
	var fired: Array[StringName] = []
	for stage: int in range(1, 13):
		if tracker.record_battle(stage, active, {}, false, rng):
			fired.append(tracker.get_pending_family())
			tracker.choose(1)
	var unique := {}
	for family: StringName in fired:
		unique[family] = true
	if fired.size() != _catalog.run_rules.epiphanies_per_run or unique.size() != fired.size() or tracker.get_chosen_ids().size() != fired.size():
		push_error("Expected %d Kỳ Ngộ of different families, got %s" % [_catalog.run_rules.epiphanies_per_run, fired])
		return false
	# With the run's Kỳ Ngộ used up, a full meter is no longer "near".
	var full_meters := 0
	for family: StringName in active:
		if tracker.is_mutated(family):
			continue
		if tracker.get_meter(family) >= tracker.get_threshold(family) - 1:
			full_meters += 1
		if tracker.is_near(family):
			push_error("%s is near after the run's last Kỳ Ngộ" % family)
			return false
	if full_meters == 0:
		push_error("The run limit check needs a family with a full meter left")
		return false
	return true


# Hạ Mốc: Khiên 2 needs only one shield, so one shield reaches the tier
# with the override and not without; the thresholds say so.
func _check_lower_evaluate() -> bool:
	var pieces := [_piece(&"unit.shield_guard", 4, 1)]
	var base := _milestone(_catalog.get_synergy().evaluate(pieces), SHIELD)
	var lowered := _milestone(_catalog.get_synergy().evaluate(pieces, _overrides([&"epiphany.shield_lower_2"])), SHIELD)
	if base["reached"] != 0 or lowered["reached"] != 1 or Array(lowered["thresholds"]) != [1, 4]:
		push_error("Lowered Khiên 2: reached %d -> %d, thresholds %s" % [base["reached"], lowered["reached"], lowered["thresholds"]])
		return false
	return true


# Biến Dị: Khiên 2's +20 armour becomes 15% less damage taken; the
# thresholds stay, the tier's modifiers change.
func _check_variant_evaluate() -> bool:
	var pieces := [_piece(&"unit.shield_guard", 3, 1), _piece(&"unit.iron_guard", 5, 1)]
	var base := _milestone(_catalog.get_synergy().evaluate(pieces), SHIELD)
	var varied := _milestone(_catalog.get_synergy().evaluate(pieces, _overrides([&"epiphany.shield_stone_skin"])), SHIELD)
	var handler: StringName = varied["tier_modifiers"][0][0]["handler"]
	if varied["reached"] != 1 or varied["thresholds"] != base["thresholds"] or handler != &"mod.damage_taken_pct" or base["tier_modifiers"][0][0]["handler"] != &"mod.stat_add":
		push_error("Stone skin should replace tier 0's modifiers: %s" % varied["tier_modifiers"])
		return false
	return true


# A lone shield against a sword takes less damage with Khiên 2 lowered to
# one shield; the same override on the enemy's side changes nothing for it.
func _check_lower_battle() -> bool:
	var plain := _duel([], [&"unit.shield_guard"], [&"unit.blade_wanderer"])
	var lowered := _duel([&"epiphany.shield_lower_2"], [&"unit.shield_guard"], [&"unit.blade_wanderer"])
	var enemy_side := _duel([&"epiphany.shield_lower_2"], [&"unit.blade_wanderer"], [&"unit.shield_guard"])
	var enemy_plain := _duel([], [&"unit.blade_wanderer"], [&"unit.shield_guard"])
	if lowered[0] <= plain[0]:
		push_error("The lowered shield should keep more hp: %d vs %d" % [lowered[0], plain[0]])
		return false
	if enemy_side != enemy_plain:
		push_error("A player mutation must not change the enemy's units")
		return false
	return true


# Two shields with stone skin end the duel with other hp than without.
func _check_variant_battle() -> bool:
	var shields: Array[StringName] = [&"unit.shield_guard", &"unit.iron_guard"]
	var swords: Array[StringName] = [&"unit.blade_wanderer", &"unit.wolf_blade"]
	var plain := _duel([], shields, swords)
	var varied := _duel([&"epiphany.shield_stone_skin"], shields, swords)
	if plain == varied:
		push_error("Stone skin should change the battle: %s" % [plain])
		return false
	return true


# RunState: a pending choice blocks the reward until it is taken; the
# choice becomes a player override; a second choice is refused.
func _check_run_commands() -> bool:
	var run := _reward_run_with_pending()
	if run == null:
		return false
	if run.choose_reward(run.get_reward_options()[0]) != RunState.Result.EPIPHANY_PENDING:
		push_error("The reward must wait for the Kỳ Ngộ")
		return false
	var option: StringName = run.epiphanies.get_pending_options()[1].id
	var chosen := []
	run.epiphany_chosen.connect(func(id: StringName) -> void: chosen.append(id))
	if run.choose_epiphany(1) != RunState.Result.OK or chosen != [option] or run.choose_epiphany(0) != RunState.Result.NOT_OFFERED:
		push_error("choose_epiphany should take option 1 once")
		return false
	if run.get_synergy_overrides().size() != 2 or run.choose_reward(run.get_reward_options()[0]) != RunState.Result.OK:
		push_error("After the choice the override exists and the reward goes on")
		return false
	return true


# A run with a mutation and a pending choice saves and loads to the same
# state, overrides included.
func _check_save_round_trip() -> bool:
	var run := _reward_run_with_pending()
	if run == null:
		return false
	var data := run.to_save_data()
	var loaded := RunState.new(_catalog, 0)
	if not loaded.load_save_data(JSON.parse_string(JSON.stringify(data))):
		push_error("A run with a pending Kỳ Ngộ did not load")
		return false
	if loaded.epiphanies.to_save_data() != run.epiphanies.to_save_data() or loaded.get_synergy_overrides() != run.get_synergy_overrides():
		push_error("The Kỳ Ngộ state changed on load")
		return false
	loaded.choose_epiphany(0)
	var again := RunState.new(_catalog, 0)
	if not again.load_save_data(JSON.parse_string(JSON.stringify(loaded.to_save_data()))) or again.get_synergy_overrides().size() != 2:
		push_error("Two mutations should survive a save")
		return false
	return true


# Impossible Kỳ Ngộ saves are refused: two of one family, an unknown id, a
# pending choice in the preparation, a meter past the maximum.
func _check_bad_saves() -> bool:
	var run := _reward_run_with_pending()
	if run == null:
		return false
	var good := run.to_save_data()
	var cases: Array[Dictionary] = []
	var doubled: Dictionary = good["epiphany"].duplicate(true)
	doubled["chosen"] = ["epiphany.shield_lower_2", "epiphany.shield_lower_4"]
	cases.append(doubled)
	var unknown: Dictionary = good["epiphany"].duplicate(true)
	unknown["chosen"] = ["epiphany.nothing"]
	cases.append(unknown)
	var too_full: Dictionary = good["epiphany"].duplicate(true)
	too_full["meters"][String(SWORD)] = _catalog.run_rules.ngo_meter_max + 1
	cases.append(too_full)
	# Two chosen and one pending by stage 2: one Kỳ Ngộ fires per stage.
	var too_many: Dictionary = good["epiphany"].duplicate(true)
	too_many["chosen"] = ["epiphany.shield_lower_2", "epiphany.spear_lower_2"]
	cases.append(too_many)
	var none_fired: Dictionary = good["epiphany"].duplicate(true)
	none_fired["pending_family"] = ""
	none_fired["pending_options"] = []
	none_fired["last_stage"] = 0
	cases.append(none_fired)
	for epiphany: Dictionary in cases:
		var data := good.duplicate(true)
		data["epiphany"] = epiphany
		if RunState.new(_catalog, 0).load_save_data(data):
			push_error("A bad Kỳ Ngộ save loaded: %s" % epiphany)
			return false
	var in_prep := good.duplicate(true)
	in_prep["phase"] = "prep"
	in_prep["rewards"] = []
	if RunState.new(_catalog, 0).load_save_data(in_prep):
		push_error("A pending choice outside the reward phase should not load")
		return false
	return true


# A Biến Dị whose modifier the native synergy rules refuse on a milestone
# (scope.members belongs to formations) fails catalog validation, naming
# its family file. The loaded data is changed for the check and restored.
func _check_bad_variant_data() -> bool:
	var shield := _catalog.get_epiphany_family(SHIELD)
	var modifier := _catalog.get_epiphany(&"epiphany.shield_stone_skin").modifiers[0]
	var scope := modifier.scope
	modifier.scope = &"scope.members"
	print("Epiphany test: the next Synergy error (misplaced scope) is expected")
	var problems := _catalog.validate()
	modifier.scope = scope
	var named := Array(problems).any(func(problem: String) -> bool:
		return problem.contains("epiphany.shield_stone_skin") and problem.contains(shield.resource_path))
	if problems.size() != 1 or not named or not _catalog.validate().is_empty():
		push_error("A variant with a milestone-illegal scope should fail validation once, naming its file: %s" % problems)
		return false
	return true


# A run at stage 2's reward with the shield family mutated and a pending
# choice of the sword family, built through the save path.
func _reward_run_with_pending() -> RunState:
	var start := RunState.new(_catalog, 31)
	start.start()
	var data := start.to_save_data()
	var tracker := EpiphanyTracker.new(_catalog, 31)
	var epiphany := tracker.to_save_data()
	epiphany["chosen"] = ["epiphany.shield_lower_2"]
	epiphany["pending_family"] = String(SWORD)
	epiphany["pending_options"] = ["epiphany.sword_lower_2", "epiphany.sword_swift_edge"]
	epiphany["last_stage"] = 2
	data["epiphany"] = epiphany
	data["phase"] = "reward"
	data["stage"] = 2
	data["stages_cleared"] = 1
	data["rewards"] = ["reward.rest", "reward.hunt"]
	var run := RunState.new(_catalog, 0)
	if not run.load_save_data(JSON.parse_string(JSON.stringify(data))):
		push_error("The reward run with a pending Kỳ Ngộ did not load")
		return null
	return run


# Side A `a_units` (rank 1 from col 3) against `b_units` for BATTLE_TICKS,
# with `epiphany_ids` as side A's overrides: every unit's hp, A first.
func _duel(epiphany_ids: Array, a_units: Array[StringName], b_units: Array[StringName]) -> Array[int]:
	var battle := BattleFactory.create(_catalog)
	_battles.append(battle)
	battle.set_synergy_overrides(Battle.SIDE_A, _overrides(epiphany_ids))
	var indexes: Array[int] = []
	for index: int in a_units.size():
		indexes.append(battle.add_unit(Battle.SIDE_A, _catalog.get_unit(a_units[index]), 1, 3 + index, 1))
	for index: int in b_units.size():
		indexes.append(battle.add_unit(Battle.SIDE_B, _catalog.get_unit(b_units[index]), 1, 3 + index, 1))
	battle.start()
	for tick: int in BATTLE_TICKS:
		if battle.is_finished():
			break
		battle.step()
	var hp: Array[int] = []
	for index: int in indexes:
		hp.append(battle.get_unit_state(index)["hp"])
	return hp


func _overrides(epiphany_ids: Array) -> Array:
	var overrides: Array = []
	for id: StringName in epiphany_ids:
		var epiphany := _catalog.get_epiphany(id)
		overrides.append(epiphany.to_override(_catalog.get_milestone(epiphany.family)))
	return overrides


func _milestone(result: Dictionary, id: StringName) -> Dictionary:
	for entry: Dictionary in result["class_milestones"] + result["race_milestones"]:
		if entry["id"] == id:
			return entry
	return {}


func _piece(unit_id: StringName, col: int, rank: int) -> Dictionary:
	return {"unit": _catalog.get_unit(unit_id), "col": col, "rank": rank}


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	return rng
