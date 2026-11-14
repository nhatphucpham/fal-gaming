extends SceneTree

# Headless tests of road encounters, the win-streak bonus and the loot
# reward: the seeded draw, every effect kind, refused options, the bet, and
# saves with a pending encounter or bet (good and tampered). States are built
# through load_save_data(), the path a saved run takes.

var _catalog: Catalog
var _failures: int = 0


func _initialize() -> void:
	_catalog = load("res://Data/catalog.tres") as Catalog
	var checks: Array[Callable] = [
		_check_data, _check_stage_rules, _check_draw, _check_run_draw, _check_gold_supply_morale, _check_free_unit,
		_check_free_refreshes, _check_refusals, _check_bet, _check_pending_save, _check_bet_save,
		_check_tampered_saves, _check_refresh_allowance, _check_black_market_save, _check_streak, _check_loot,
	]
	for check: Callable in checks:
		if not check.call():
			_failures += 1
			push_error("Encounter test failed in %s" % check.get_method())
	if _failures == 0:
		print("Encounter test passed (%d checks)" % checks.size())
		quit(0)
	else:
		quit(1)


# The save of a fresh seed-7 run with `changes`. The encounter save defaults
# to the catalog's first encounters met before `stage`.
func _data(changes: Dictionary) -> Dictionary:
	var start := RunState.new(_catalog, 7)
	start.start()
	var data := start.to_save_data()
	data["pieces"] = [{"id": 1, "unit_id": "unit.archer", "star": 1, "bench": -1, "col": 4, "rank": 1, "has_fought": true}]
	data["next_piece_id"] = 2
	data.merge(changes, true)
	if not changes.has("encounter"):
		var drawn: Array[String] = []
		for encounter_stage: int in _catalog.run_rules.encounter_stages:
			if encounter_stage < data["stage"]:
				drawn.append(String(_catalog.encounters[drawn.size()].id))
		data["encounter"] = {"drawn": drawn, "pending": "", "taken": -1 if drawn.is_empty() else 0, "bet_gold": 0}
	return JSON.parse_string(JSON.stringify(data))


func _load(data: Dictionary) -> RunState:
	var run := RunState.new(_catalog, 0)
	if not run.load_save_data(data):
		push_error("Encounter test: state did not load: %s" % data)
		return null
	return run


# A run at stage 2's road encounter `id` with `changes`.
func _at_encounter(id: String, changes: Dictionary = {}) -> RunState:
	var values := {"phase": "encounter", "stage": 2, "stages_cleared": 2, "rewards": [],
		"encounter": {"drawn": [id], "pending": id, "taken": -1, "bet_gold": 0}}
	values.merge(changes, true)
	return _load(_data(values))


# Drops the test's lambdas: one that holds the run it listens to would keep
# the run alive past the test.
func _disconnect_all(source: Signal) -> void:
	for connection: Dictionary in source.get_connections():
		source.disconnect(connection["callable"])


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
	return condition


# [gold, supply, morale, pieces] when the encounter's option is applied,
# before the next stage's income.
func _choose_and_read(run: RunState, option: int) -> Array:
	var seen := []
	run.encounter_chosen.connect(func(_id: StringName, _option: int) -> void:
		seen.append_array([run.gold, run.supply, run.morale, run.get_pieces().size()]), CONNECT_ONE_SHOT)
	var result := run.choose_encounter(option)
	if result != RunState.Result.OK:
		push_error("Encounter test: option %d was refused (%s)" % [option, RunState.Result.keys()[result]])
	return seen


# After a battle: takes the Kỳ Ngộ card if one fired, the first reward and,
# at a road stage, the first option the run can pay.
func _advance(run: RunState) -> void:
	if run.epiphanies.has_pending():
		run.choose_epiphany(0)
	run.choose_reward(run.get_reward_options()[0])
	if run.phase == RunState.Phase.ENCOUNTER:
		run.choose_encounter(1 if run.get_encounter_refusal(0) != RunState.Result.OK else 0)


func _check_data() -> bool:
	var stages := _catalog.run_rules.encounter_stages
	if not _expect(Array(stages) == [2, 4, 6, 8, 10] and _catalog.encounters.size() == 8, "Five road stages and eight encounters"):
		return false
	for data: EncounterData in _catalog.encounters:
		if not _expect(data.options.size() == 2 and data.options.any(func(o: EncounterOption) -> bool: return o.is_always_affordable()), "%s needs two options, one always affordable" % data.id):
			return false
	return true


# Encounter stages must be sorted, once each, inside 1..stage_count - 1 and
# off the boss stage and the story stage before it.
func _check_stage_rules() -> bool:
	var rules := _catalog.run_rules.duplicate() as RunRules
	if not _expect(rules.validate().is_empty(), "The shipped run rules should be valid: %s" % [rules.validate()]):
		return false
	var cases := [
		["the story stage", [2, rules.boss_stage - 1]], ["the boss stage", [rules.boss_stage]],
		["stage 0", [0, 2]], ["past the last stage", [rules.stage_count + 1]],
		["a doubled stage", [2, 2, 4]], ["unsorted stages", [4, 2]],
	]
	for case: Array in cases:
		rules.encounter_stages = PackedInt32Array(case[1])
		var problems := rules.validate()
		if not _expect(not problems.is_empty() and Array(problems).all(func(problem: String) -> bool: return problem.contains("encounter")), "Encounter stages with %s must be refused: %s" % [case[0], problems]):
			return false
	return true


# The same seed draws the same encounters; no run meets one twice.
func _check_draw() -> bool:
	var orders: Array = []
	for attempt: int in 2:
		var tracker := EncounterTracker.new(_catalog)
		var rng := RandomNumberGenerator.new()
		rng.seed = 12345
		var ids: Array[StringName] = []
		for draw: int in _catalog.encounters.size():
			ids.append(tracker.draw(rng).id)
			tracker.take(0)
		orders.append(ids)
	var unique := {}
	for id: StringName in orders[0]:
		unique[id] = true
	return _expect(orders[0] == orders[1] and unique.size() == _catalog.encounters.size(), "Draws must repeat per seed and never repeat an encounter: %s" % [orders])


# Two runs with one seed, played alike, meet the same five encounters at the
# road stages, each offered as the reward is taken.
func _check_run_draw() -> bool:
	var met: Array = []
	for attempt: int in 2:
		var run := RunState.new(_catalog, 77)
		run.start()
		var offered: Array = []
		run.encounter_offered.connect(func(id: StringName) -> void: offered.append([run.stage, id]))
		while run.stage < 11:
			run.begin_battle()
			run.finish_battle(true, 0)
			_advance(run)
		_disconnect_all(run.encounter_offered)
		met.append(offered)
	var stages: Array = met[0].map(func(row: Array) -> int: return row[0])
	return _expect(met[0] == met[1] and stages == [2, 4, 6, 8, 10], "Seeded runs should meet the same encounters at 2, 4, 6, 8, 10: %s" % [met])


func _check_gold_supply_morale() -> bool:
	var run := _at_encounter("encounter.merchants", {"gold": 2, "supply": 1})
	var gold := _choose_and_read(run, 0)
	if not _expect(gold.size() == 4 and gold[0] == 8 and run.phase == RunState.Phase.PREP and run.stage == 3, "Merchants A gives 6 gold, then stage 3 (got %s)" % [gold]):
		return false
	run = _at_encounter("encounter.merchants", {"gold": 2, "supply": 1})
	var supply := _choose_and_read(run, 1)
	if not _expect(supply.size() == 4 and supply[1] == 6, "Merchants B gives 5 supply (got %s)" % [supply]):
		return false
	run = _at_encounter("encounter.villagers", {"morale": 40})
	var morale := _choose_and_read(run, 0)
	if not _expect(morale.size() == 4 and morale[2] == 48, "Villagers A gives 8 morale (got %s)" % [morale]):
		return false
	run = _at_encounter("encounter.villagers", {"morale": 58})
	morale = _choose_and_read(run, 0)
	return _expect(morale.size() == 4 and morale[2] == _catalog.run_rules.max_morale, "Morale from an encounter is capped (got %s)" % [morale])


func _check_free_unit() -> bool:
	var run := _at_encounter("encounter.stranger")
	var gifted: Array[int] = []
	run.piece_gifted.connect(func(piece_id: int) -> void: gifted.append(piece_id))
	var seen := _choose_and_read(run, 1)
	var piece := run.get_piece(gifted[0]) if gifted.size() == 1 else null
	return _expect(seen.size() == 4 and seen[3] == 2 and piece != null and piece.is_on_bench() and _catalog.get_unit(piece.unit_id).cost == 2, "The stranger's B card gives one cost-2 unit on the bench")


func _check_free_refreshes() -> bool:
	var run := _at_encounter("encounter.stranger", {"gold": 0})
	_choose_and_read(run, 0)
	if not _expect(run.get_refresh_cost() == 0 and run.refresh_shop() == RunState.Result.OK and run.refresh_shop() == RunState.Result.OK, "The stranger's A card gives two free refreshes"):
		return false
	var saved := _load(run.to_save_data())
	return _expect(saved != null and run.get_refresh_cost() == _catalog.run_rules.refresh_gold and saved.get_refresh_cost() == run.get_refresh_cost(), "After two free refreshes the next one costs gold again")


# Costs the run cannot pay grey the card out and change nothing; the other
# card stays open.
func _check_refusals() -> bool:
	var cases := [
		["encounter.deserters", 0, {"gold": 2}, RunState.Result.NOT_ENOUGH_GOLD],
		["encounter.surplus", 0, {"supply": 3}, RunState.Result.NOT_ENOUGH_SUPPLY],
		["encounter.storehouse", 0, {"morale": 6}, RunState.Result.NOT_ENOUGH_MORALE],
		["encounter.wager", 1, {"gold": 2}, RunState.Result.NOT_ENOUGH_GOLD],
	]
	for case: Array in cases:
		var run := _at_encounter(case[0], case[2])
		var before := run.to_save_data()
		var refusal := run.get_encounter_refusal(case[1])
		var cutscene := EncounterCutscene.build(run)
		if not _expect(refusal == case[3] and run.choose_encounter(case[1]) == case[3] and run.to_save_data() == before, "%s option %d should be refused with %s" % [case[0], case[1], RunState.Result.keys()[case[3]]]):
			return false
		if not _expect(cutscene.is_choice_disabled(case[1]) and not cutscene.is_choice_disabled(1 - case[1]), "%s: only the card it cannot pay should be greyed out" % case[0]):
			return false
	var full := []
	var units := ["spearman", "shield_guard", "fire_adept", "wolf_rider", "light_rider", "iron_guard"]
	for slot: int in _catalog.run_rules.bench_slots:
		full.append({"id": slot + 2, "unit_id": "unit." + units[slot], "star": 1, "bench": slot, "col": 0, "rank": 0, "has_fought": false})
	var crowded := _at_encounter("encounter.stranger", {"next_piece_id": 20, "pieces": [{"id": 1, "unit_id": "unit.archer", "star": 1, "bench": -1, "col": 4, "rank": 1, "has_fought": true}] + full})
	if not _expect(crowded.get_encounter_refusal(1) == RunState.Result.BENCH_FULL and crowded.get_encounter_refusal(0) == RunState.Result.OK, "A free unit needs a free bench slot"):
		return false
	var just_enough := _at_encounter("encounter.deserters", {"gold": 3})
	return _expect(just_enough.get_encounter_refusal(0) == RunState.Result.OK and just_enough.get_encounter_refusal(2) == RunState.Result.NOT_OFFERED, "Exactly enough gold pays; a third option does not exist")


# The bet costs 3 gold now and pays 10 only if the next battle is won.
func _check_bet() -> bool:
	var paid := []
	for is_win: bool in [true, false]:
		var run := _at_encounter("encounter.wager", {"gold": 5})
		var seen := _choose_and_read(run, 1)
		if not _expect(seen.size() == 4 and seen[0] == 2 and run.encounters.get_bet_gold() == 10, "The wager costs 3 gold and opens a 10-gold bet"):
			return false
		run.bet_settled.connect(func(won: bool, gold: int) -> void: paid.append([won, gold]))
		var gold_before := run.gold
		run.begin_battle()
		run.finish_battle(is_win, 0 if is_win else 2)
		var expected := gold_before + (_catalog.run_rules.win_gold + _catalog.run_rules.get_streak_bonus(run.win_streak) + 10 if is_win else 0)
		if not _expect(run.gold == expected and run.encounters.get_bet_gold() == 0, "A %s bet battle should end at %d gold, got %d" % ["won" if is_win else "lost", expected, run.gold]):
			return false
	return _expect(paid == [[true, 10], [false, 0]], "bet_settled should report the payout: %s" % [paid])


# Closed at a road encounter, the run reloads on the same encounter and
# takes the same option to the same state.
func _check_pending_save() -> bool:
	var run := RunState.new(_catalog, 5)
	run.start()
	while run.phase != RunState.Phase.ENCOUNTER:
		run.begin_battle()
		run.finish_battle(true, 0)
		if run.epiphanies.has_pending():
			run.choose_epiphany(0)
		run.choose_reward(run.get_reward_options()[0])
	var data := JSON.parse_string(JSON.stringify(run.to_save_data())) as Dictionary
	var copy := _load(data)
	if not _expect(copy != null and copy.phase == RunState.Phase.ENCOUNTER and copy.encounters.get_pending().id == run.encounters.get_pending().id, "A pending encounter must survive the save"):
		return false
	var option := 0 if run.get_encounter_refusal(0) == RunState.Result.OK else 1
	run.choose_encounter(option)
	copy.choose_encounter(option)
	return _expect(copy.to_save_data() == run.to_save_data(), "The reloaded run must take the encounter to the same state")


func _check_bet_save() -> bool:
	var run := _at_encounter("encounter.wager", {"gold": 5})
	run.choose_encounter(1)
	var copy := _load(JSON.parse_string(JSON.stringify(run.to_save_data())))
	if not _expect(copy != null and copy.encounters.get_bet_gold() == 10, "An open bet must survive the save"):
		return false
	copy.begin_battle()
	var gold := copy.gold
	copy.finish_battle(true, 0)
	return _expect(copy.gold == gold + _catalog.run_rules.win_gold + _catalog.run_rules.get_streak_bonus(copy.win_streak) + 10, "The reloaded bet pays on a win")


# Saves edited by hand (or broken) are refused.
func _check_tampered_saves() -> bool:
	var pending := {"phase": "encounter", "stage": 2, "stages_cleared": 2, "rewards": []}
	var cases := [
		["an unknown encounter", pending.merged({"encounter": {"drawn": ["encounter.nobody"], "pending": "encounter.nobody", "taken": -1, "bet_gold": 0}}, true)],
		["no encounter drawn at the road stage", pending.merged({"encounter": {"drawn": [], "pending": "", "taken": -1, "bet_gold": 0}}, true)],
		["a pending encounter that is not the last drawn", pending.merged({"stage": 4, "stages_cleared": 4, "encounter": {"drawn": ["encounter.merchants", "encounter.wager"], "pending": "encounter.merchants", "taken": -1, "bet_gold": 0}}, true)],
		["an encounter drawn twice", {"stage": 5, "stages_cleared": 4, "encounter": {"drawn": ["encounter.wager", "encounter.wager"], "pending": "", "taken": 0, "bet_gold": 0}}],
		["too few encounters for the stage", {"stage": 5, "stages_cleared": 4, "encounter": {"drawn": ["encounter.wager"], "pending": "", "taken": 0, "bet_gold": 0}}],
		["too many encounters for the stage", {"stage": 2, "stages_cleared": 1, "encounter": {"drawn": ["encounter.wager"], "pending": "", "taken": 0, "bet_gold": 0}}],
		["a pending encounter in the preparation", {"stage": 3, "stages_cleared": 2, "encounter": {"drawn": ["encounter.wager"], "pending": "encounter.wager", "taken": -1, "bet_gold": 0}}],
		["the encounter phase off a road stage", pending.merged({"stage": 3, "stages_cleared": 3, "encounter": {"drawn": ["encounter.wager"], "pending": "encounter.wager", "taken": -1, "bet_gold": 0}}, true)],
		["the encounter phase at the final stage", pending.merged({"stage": 12, "stages_cleared": 12}, true)],
		["a bet the encounter does not offer", {"stage": 3, "stages_cleared": 2, "encounter": {"drawn": ["encounter.merchants"], "pending": "", "taken": 0, "bet_gold": 10}}],
		["a bet of the wrong size", {"stage": 3, "stages_cleared": 2, "encounter": {"drawn": ["encounter.wager"], "pending": "", "taken": 1, "bet_gold": 99}}],
		["a bet a stage late", {"stage": 4, "stages_cleared": 3, "encounter": {"drawn": ["encounter.wager"], "pending": "", "taken": 1, "bet_gold": 10}}],
		["a negative bet", {"stage": 3, "stages_cleared": 2, "encounter": {"drawn": ["encounter.wager"], "pending": "", "taken": 1, "bet_gold": -1}}],
		["encounter as text", {"encounter": "encounter.wager"}],
		["drawn as text", {"encounter": {"drawn": "encounter.wager", "pending": "", "taken": 0, "bet_gold": 0}}],
		["an option taken while pending", pending.merged({"encounter": {"drawn": ["encounter.wager"], "pending": "encounter.wager", "taken": 0, "bet_gold": 0}}, true)],
		["no option taken after an encounter", {"stage": 3, "stages_cleared": 2, "encounter": {"drawn": ["encounter.wager"], "pending": "", "taken": -1, "bet_gold": 0}}],
		["an option the encounter does not have", {"stage": 3, "stages_cleared": 2, "encounter": {"drawn": ["encounter.wager"], "pending": "", "taken": 2, "bet_gold": 0}}],
		["a negative option", {"stage": 3, "stages_cleared": 2, "encounter": {"drawn": ["encounter.wager"], "pending": "", "taken": -2, "bet_gold": 0}}],
		["the option as text", {"stage": 3, "stages_cleared": 2, "encounter": {"drawn": ["encounter.wager"], "pending": "", "taken": "1", "bet_gold": 0}}],
		["a bet of the option not taken", {"stage": 3, "stages_cleared": 2, "encounter": {"drawn": ["encounter.wager"], "pending": "", "taken": 0, "bet_gold": 10}}],
		["a win streak past the stages cleared", {"stage": 3, "stages_cleared": 2, "win_streak": 3}],
		["a negative win streak", {"win_streak": -1}],
		["a win streak as text", {"win_streak": "2"}],
		["a black market waiting in the preparation", {"stage": 3, "stages_cleared": 2, "black_market_next": true}],
		["a black market waiting in the reward choice", {"phase": "reward", "stage": 3, "stages_cleared": 3, "rewards": ["reward.rest", "reward.hunt", "reward.loot"], "black_market_next": true}],
		["a waiting black market as text", pending.merged({"black_market_next": "yes"}, true)],
	]
	var accepted: Array[String] = []
	for case: Array in cases:
		var run := RunState.new(_catalog, 0)
		if run.load_save_data(_data(case[1])):
			accepted.append(case[0])
	var good := _data({"stage": 3, "stages_cleared": 2, "win_streak": 2, "encounter": {"drawn": ["encounter.wager"], "pending": "", "taken": 1, "bet_gold": 10}})
	var is_good_loaded := RunState.new(_catalog, 0).load_save_data(good)
	return _expect(accepted.is_empty() and is_good_loaded, "Tampered saves must be refused (accepted %s) and a good bet save loaded (%s)" % [accepted, is_good_loaded])


# Saved free refreshes are capped by what the option taken gave: a save
# that took the stranger's free unit cannot claim the refreshes of its other
# card, while one that took them keeps them.
func _check_refresh_allowance() -> bool:
	var refreshes := []
	for taken: int in [0, 1]:
		var run := _load(_data({"stage": 3, "stages_cleared": 2, "free_refreshes": 2,
			"encounter": {"drawn": ["encounter.stranger"], "pending": "", "taken": taken, "bet_gold": 0}}))
		if run == null:
			return false
		var free := 0
		while run.get_refresh_cost() == 0 and free < 5:
			run.refresh_shop()
			free += 1
		refreshes.append(free)
	var given := 0
	for effect: EncounterEffect in _catalog.get_encounter(&"encounter.stranger").options[0].effects:
		if effect.kind == EncounterEffects.FREE_REFRESHES:
			given += effect.amount
	return _expect(refreshes == [given, 0], "Free refreshes after the stranger's cards should be [%d, 0], got %s" % [given, refreshes])


# The black market taken at a road stage waits through the encounter: closed
# there, the run reloads with it and opens it in the next preparation, as
# without the reload. A save without the key is refused like any other.
func _check_black_market_save() -> bool:
	for seed_value: int in range(1, 100):
		var run := RunState.new(_catalog, seed_value)
		run.start()
		while run.stage < 2 or run.phase != RunState.Phase.REWARD:
			run.begin_battle()
			run.finish_battle(true, 0)
			if run.stage < 2:
				_advance(run)
		if run.epiphanies.has_pending():
			run.choose_epiphany(0)
		if not run.get_reward_options().has(RunState.Reward.BLACK_MARKET):
			continue
		run.choose_reward(RunState.Reward.BLACK_MARKET)
		var data := JSON.parse_string(JSON.stringify(run.to_save_data())) as Dictionary
		if not _expect(run.phase == RunState.Phase.ENCOUNTER and data.get("black_market_next") == true, "Seed %d: the black market should wait in the encounter save" % seed_value):
			return false
		var copy := _load(data)
		if copy == null:
			return false
		var option := 0 if run.get_encounter_refusal(0) == RunState.Result.OK else 1
		run.choose_encounter(option)
		copy.choose_encounter(option)
		if not _expect(copy.is_black_market_active() and copy.get_refresh_cost() == 0 and copy.to_save_data() == run.to_save_data(), "Seed %d: the reloaded run should open the black market at stage 3 as without the reload" % seed_value):
			return false
		data.erase("black_market_next")
		return _expect(not RunState.new(_catalog, 0).load_save_data(data), "A save without black_market_next must be refused")
	return _expect(false, "No seed offered the black market at stage 2")


# From the 2nd win in a row +1 gold, from the 4th +2; a loss starts over.
func _check_streak() -> bool:
	var run := _load(_data({"stage": 1, "stages_cleared": 0, "morale": 60}))
	var bonuses: Array[int] = []
	run.streak_paid.connect(func(_streak: int, gold: int) -> void: bonuses[bonuses.size() - 1] = gold)
	for is_win: bool in [true, true, true, true, true, false, true, true]:
		bonuses.append(0)
		run.begin_battle()
		run.finish_battle(is_win, 0 if is_win else 1)
		_advance(run)
	return _expect(bonuses == [0, 1, 1, 2, 2, 0, 0, 1] and run.win_streak == 2, "Streak gold per battle %s, streak %d" % [bonuses, run.win_streak])


# A won battle offers three of rest, hunt, black market and loot; loot pays
# loot_gold.
func _check_loot() -> bool:
	var seen := {}
	for seed_value: int in range(1, 40):
		var run := RunState.new(_catalog, seed_value)
		run.start()
		run.begin_battle()
		run.finish_battle(true, 0)
		var options := run.get_reward_options()
		if not _expect(options.size() == _catalog.run_rules.rewards_after_win, "A win offers %d rewards" % _catalog.run_rules.rewards_after_win):
			return false
		for reward: RunState.Reward in options:
			seen[reward] = true
		if options.has(RunState.Reward.LOOT):
			var gold := run.gold
			var paid := []
			run.encounter_offered.connect(func(_id: StringName) -> void: paid.append(run.gold))
			run.gold_changed.connect(func(_gold: int, delta: int) -> void: paid.append(delta), CONNECT_ONE_SHOT)
			run.choose_reward(RunState.Reward.LOOT)
			_disconnect_all(run.encounter_offered)
			if not _expect(paid.size() > 0 and paid[0] == _catalog.run_rules.loot_gold and run.gold > gold, "Loot should pay %d gold first, got %s" % [_catalog.run_rules.loot_gold, paid]):
				return false
	return _expect(seen.size() == 4, "Every reward kind, loot included, should be offered across seeds: %s" % [seen.keys()])
