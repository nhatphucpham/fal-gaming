extends SceneTree

# Headless tests of RunState, Shop, RunSave and the run data. Exact states
# (pieces, shop offers) are built through load_save_data(), the same public
# path a saved run takes, so no test touches private fields.

const SAVE_PATH: String = "user://run_test_save.json"
# Marks a save key that _write_save() leaves out.
const MISSING_KEY: String = "<missing>"

var _catalog: Catalog
var _failures: int = 0


func _initialize() -> void:
	_catalog = load("res://Data/catalog.tres") as Catalog
	RunSave.path = SAVE_PATH
	var checks: Array[Callable] = [
		_check_catalog, _check_start, _check_shop_determinism, _check_buy_sell,
		_check_refresh, _check_buy_refusals, _check_merge_bench, _check_merge_board,
		_check_merge_chain, _check_legends, _check_levels, _check_moves, _check_bench_queries,
		_check_income, _check_battle_results, _check_rewards, _check_black_market,
		_check_stage_12, _check_run_lost, _check_save_round_trip, _check_reward_round_trip,
		_check_prep_changed, _check_bad_saves,
	]
	for check: Callable in checks:
		if not check.call():
			_failures += 1
			push_error("Run test failed in %s" % check.get_method())
	if _failures == 0:
		print("Run test passed (%d checks)" % checks.size())
		quit(0)
	else:
		quit(1)


# A run in its preparation with exactly these pieces and shop offers.
# `pieces` rows: [unit, star, bench slot or -1, local col, local rank, has_fought].
func _make(pieces: Array, shop: Array, values: Dictionary = {}) -> RunState:
	var rows: Array = []
	for index: int in pieces.size():
		var row: Array = pieces[index]
		rows.append({
			"id": index + 1, "unit_id": "unit." + row[0], "star": row[1], "bench": row[2],
			"col": row[3], "rank": row[4], "has_fought": row[5] if row.size() > 5 else false,
		})
	var offers: Array = []
	for offer: String in shop:
		offers.append("unit." + offer if offer != "" else "")
	var data := {
		"seed": "99", "rng_state": str(_fresh_rng_state(99)), "phase": "prep", "stage": 1, "morale": 60,
		"gold": 50, "supply": 0, "level": 3, "next_piece_id": 1, "pieces": rows, "shop": offers,
		"black_market": false, "free_refreshes": 0, "rewards": [],
		"epiphany": EpiphanyTracker.new(_catalog, 99).to_save_data(), "win_streak": 0,
	}
	data.merge(values, true)
	if not values.has("stages_cleared"):
		data["stages_cleared"] = data["stage"] - 1
	if not values.has("encounter"):
		data["encounter"] = _encounters_before(data["stage"])
	var run := RunState.new(_catalog, 0)
	if not run.load_save_data(data):
		push_error("Test state did not load: %s" % data)
		return null
	return run


# The encounter save of a run in the preparation or reward of `stage` that
# met the catalog's first encounters at the stages before it.
func _encounters_before(stage: int) -> Dictionary:
	var drawn: Array[String] = []
	for encounter_stage: int in _catalog.run_rules.encounter_stages:
		if encounter_stage < stage:
			drawn.append(String(_catalog.encounters[drawn.size()].id))
	return {"drawn": drawn, "pending": "", "bet_gold": 0}


# Takes `preferred` when offered, else the first other reward; then, when a
# road encounter waits, its first option that costs nothing.
func _take_reward(run: RunState, preferred: RunState.Reward) -> void:
	var options := run.get_reward_options()
	run.choose_reward(preferred if options.has(preferred) else options[0])
	_pass_encounter(run)


func _pass_encounter(run: RunState) -> void:
	var data := run.encounters.get_pending()
	if data == null:
		return
	for index: int in data.options.size():
		if data.options[index].is_always_affordable():
			run.choose_encounter(index)
			return


func _fresh_rng_state(seed_value: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng.state


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
	return condition


func _check_catalog() -> bool:
	var problems := _catalog.validate()
	if not _expect(problems.is_empty(), "Catalog problems: %s" % problems):
		return false
	var broken := StageData.new()
	broken.id = &"stage.broken"
	broken.slots = [
		LineupSlot.create(&"unit.nobody", 1, 1, 1), LineupSlot.create(&"unit.archer", 1, 2, 3),
		LineupSlot.create(&"unit.archer", 1, 2, 3), LineupSlot.create(&"unit.archer", 1, 8, 1),
	]
	var found := broken.validate(_catalog, 3)
	var text := "\n".join(found)
	return _expect(found.size() == 5 and text.contains("no name_key") and text.contains("unknown unit") and text.contains("two units") and text.contains("off the board") and text.contains("expected 3"), "StageData.validate missed problems: %s" % found)


func _check_start() -> bool:
	var run := RunState.new(_catalog, 1)
	run.start()
	return _expect(run.morale == 60 and run.gold == 14 and run.supply == 2 and run.level == 3 and run.stage == 1 and run.get_capacity() == 3 and run.get_pieces().is_empty() and run.phase == RunState.Phase.PREP, "Bad start: morale %d gold %d supply %d level %d" % [run.morale, run.gold, run.supply, run.level])


func _check_shop_determinism() -> bool:
	var sequences: Array[Array] = []
	for seed_value: int in [7, 7, 8]:
		var run := RunState.new(_catalog, seed_value)
		run.start()
		var seen: Array = [run.get_shop_offers()]
		for refresh: int in 3:
			run.refresh_shop()
			seen.append(run.get_shop_offers())
		sequences.append(seen)
	return _expect(sequences[0] == sequences[1], "Same seed gave different shops") and _expect(sequences[0] != sequences[2], "Different seeds gave the same shops")


func _check_buy_sell() -> bool:
	var run := _make([["wolf_blade", 2, -1, 4, 1, true]], ["archer", "wolf_blade", "", "", ""], {"gold": 5})
	if not _expect(run.buy(0) == RunState.Result.OK and run.gold == 4 and run.get_bench_piece(0) != null, "Buying a cost-1 unit"):
		return false
	if not _expect(run.get_shop_offers()[0] == &"" and run.buy(0) == RunState.Result.EMPTY_SLOT, "A bought slot must stay empty"):
		return false
	var archer := run.get_bench_piece(0)
	if not _expect(run.sell(archer.id) == RunState.Result.OK and run.gold == 5 and run.supply == 0, "Selling an unfought 1-star cost-1: gold %d supply %d" % [run.gold, run.supply]):
		return false
	var blade := run.get_board_piece(Vector2i(4, 1))
	return _expect(run.get_sell_value(blade.id) == Vector2i(4, 2) and run.sell(blade.id) == RunState.Result.OK and run.gold == 9 and run.supply == 2, "Selling a fought 2-star cost-2: gold %d supply %d" % [run.gold, run.supply])


func _check_refresh() -> bool:
	var run := _make([], ["archer", "", "", "", ""], {"gold": 3})
	if not _expect(run.get_refresh_cost() == 2 and run.refresh_shop() == RunState.Result.OK and run.gold == 1, "Refresh costs 2"):
		return false
	return _expect(run.refresh_shop() == RunState.Result.NOT_ENOUGH_GOLD and run.gold == 1, "Refresh without gold must be refused")


func _check_buy_refusals() -> bool:
	var poor := _make([], ["iron_guard", "", "", "", ""], {"gold": 2})
	if not _expect(poor.buy(0) == RunState.Result.NOT_ENOUGH_GOLD and poor.gold == 2, "Buying without gold"):
		return false
	var full_bench: Array = []
	for slot: int in 6:
		full_bench.append([["archer", "fire_adept", "wolf_rider", "wolf_spear", "spearman", "blade_wanderer"][slot], 1, slot, 0, 0])
	var run := _make(full_bench + [["fire_adept", 1, -1, 4, 3]], ["shield_guard", "fire_adept", "", "", ""])
	if not _expect(run.buy(0) == RunState.Result.BENCH_FULL, "Buying with a full bench"):
		return false
	# Two Hỏa Pháp Đồ owned: the third merges at once, full bench or not.
	if not _expect(run.buy(1) == RunState.Result.OK and run.get_pieces().size() == 6, "A merge-completing buy with a full bench must work"):
		return false
	var merged := run.get_board_piece(Vector2i(4, 3))
	return _expect(merged != null and merged.star == 2 and merged.unit_id == &"unit.fire_adept", "The merged piece must take the board copy's place")


func _check_merge_bench() -> bool:
	var run := _make([["archer", 1, 3, 0, 0], ["shield_guard", 1, 0, 0, 0], ["archer", 1, 1, 0, 0]], ["archer", "", "", "", ""])
	var merges: Array = []
	run.pieces_merged.connect(func(result_id: int, consumed: Array[int]) -> void: merges.append([result_id, consumed]))
	run.buy(0)
	var result := run.get_bench_piece(1)
	return _expect(merges.size() == 1 and result != null and result.star == 2 and run.get_bench_piece(3) == null and run.get_pieces().size() == 2, "Three bench archers must merge into the earliest slot (1)")


func _check_merge_board() -> bool:
	var run := _make([["archer", 1, -1, 2, 3], ["archer", 1, -1, 6, 2], ["shield_guard", 1, 0, 0, 0]], ["archer", "", "", "", ""])
	run.buy(0)
	var result := run.get_board_piece(Vector2i(6, 2))
	return _expect(result != null and result.star == 2 and run.get_board_piece(Vector2i(2, 3)) == null and run.get_bench_piece(1) == null and run.get_pieces().size() == 2, "The merge must keep the first board copy in board order (rank 2 before rank 3)")


func _check_merge_chain() -> bool:
	var run := _make([["spearman", 2, -1, 3, 1], ["spearman", 2, 4, 0, 0], ["spearman", 1, 0, 0, 0], ["spearman", 1, 2, 0, 0]], ["spearman", "", "", "", ""])
	var merge_count := [0]
	run.pieces_merged.connect(func(_result_id: int, _consumed: Array[int]) -> void: merge_count[0] += 1)
	run.buy(0)
	var result := run.get_board_piece(Vector2i(3, 1))
	return _expect(merge_count[0] == 2 and result != null and result.star == 3 and run.get_pieces().size() == 1, "Three 1-stars then three 2-stars must chain into a 3-star on the board")


func _check_legends() -> bool:
	var run := _make([["lieu_mi", 2, 0, 0, 0], ["lieu_mi", 1, 2, 0, 0], ["ba_khac", 2, -1, 1, 1], ["thiet_nha", 2, -1, 2, 1]], ["lieu_mi", "", "", "", ""], {"level": 5})
	run.buy(0)
	# The new copy merges with the 1-star into a second 2-star; two 2-star
	# legends must then stay apart (they would merge if legends went to 3).
	var lieu := run.get_bench_piece(0)
	var second := run.get_bench_piece(2)
	if not _expect(run.get_pieces().size() == 4 and lieu != null and second != null and lieu.star == 2 and second.star == 2 and second.unit_id == &"unit.lieu_mi", "Two copies of a cost-5 must make a 2-star"):
		return false
	for piece: RunPiece in run.get_pieces():
		if not _expect(piece.star < 3, "Two 2-star cost-5 units must not merge into a 3-star"):
			return false
	if not _expect(run.move_to_board(lieu.id, Vector2i(4, 4)) == RunState.Result.LEGEND_LIMIT, "A third cost-5 on the board must be refused"):
		return false
	var ba_khac := run.get_board_piece(Vector2i(1, 1))
	# Swapping one legend for another keeps two on the board.
	return _expect(run.move_to_board(lieu.id, Vector2i(1, 1)) == RunState.Result.OK and run.get_bench_piece(0) == ba_khac, "Swapping legends must be allowed")


func _check_levels() -> bool:
	var run := _make([], [""], {"supply": 100})
	var costs: Array[int] = []
	var capacities: Array[int] = [run.get_capacity()]
	while run.get_level_up_cost() > 0:
		costs.append(run.get_level_up_cost())
		run.level_up()
		capacities.append(run.get_capacity())
	if not _expect(costs == [2, 4, 6, 10, 14, 20] and run.supply == 44, "Level costs %s" % [costs]):
		return false
	if not _expect(capacities == [3, 4, 5, 6, 7, 8, 8] and run.level == 9 and run.level_up() == RunState.Result.MAX_LEVEL, "Capacities %s" % [capacities]):
		return false
	var poor := _make([], [""], {"supply": 1})
	if not _expect(poor.level_up() == RunState.Result.NOT_ENOUGH_SUPPLY and poor.level == 3, "Level up without supply"):
		return false
	var buyer := _make([], [""], {"gold": 9})
	return _expect(buyer.buy_supply() == RunState.Result.OK and buyer.buy_supply() == RunState.Result.OK and buyer.gold == 1 and buyer.supply == 8 and buyer.buy_supply() == RunState.Result.NOT_ENOUGH_GOLD, "Buying supply: 4 gold for 4")


func _check_moves() -> bool:
	var pieces: Array = [["archer", 1, -1, 1, 1], ["archer", 1, -1, 2, 1], ["fire_adept", 1, -1, 3, 1], ["shield_guard", 1, 0, 0, 0], ["wolf_rider", 1, 1, 0, 0]]
	var run := _make(pieces, [""])
	var guard := run.get_bench_piece(0)
	if not _expect(run.move_to_board(guard.id, Vector2i(5, 2)) == RunState.Result.BOARD_FULL, "Placing over capacity must be refused"):
		return false
	var adept := run.get_board_piece(Vector2i(3, 1))
	if not _expect(run.move_to_board(guard.id, Vector2i(3, 1)) == RunState.Result.OK and run.get_bench_piece(0) == adept, "Bench to an occupied cell swaps"):
		return false
	if not _expect(run.move_to_bench(guard.id, 5) == RunState.Result.OK and run.get_board_count() == 2 and guard.bench_slot == 5, "Board to a free bench slot"):
		return false
	var rider := run.get_bench_piece(1)
	if not _expect(run.move_to_bench(rider.id, 5) == RunState.Result.OK and guard.bench_slot == 1, "Bench to bench swaps"):
		return false
	if not _expect(run.move_to_board(rider.id, Vector2i(8, 1)) == RunState.Result.BAD_TARGET, "A cell off the half"):
		return false
	var board_archer := run.get_board_piece(Vector2i(1, 1))
	return _expect(run.move_to_board(board_archer.id, Vector2i(7, 4)) == RunState.Result.OK and run.get_board_piece(Vector2i(7, 4)) == board_archer, "Board to board move")


# Board pieces carry bench slot NO_BENCH (-1): asking for that slot, or any
# slot off the bench, must not find them (a drag from a bench gap sold one).
func _check_bench_queries() -> bool:
	var run := _make([["archer", 1, -1, 4, 2], ["spearman", 1, 5, 0, 0]], [""])
	return _expect(run.get_bench_piece(RunPiece.NO_BENCH) == null and run.get_bench_piece(-7) == null and run.get_bench_piece(6) == null and run.get_bench_piece(5) != null, "get_bench_piece must be null off the bench")


# The last gold and supply change before each stage_started is its income
# (rewards, streaks and encounters pay before it).
func _check_income() -> bool:
	var run := RunState.new(_catalog, 3)
	run.start()
	var gold_seen: Array[int] = []
	var supply_seen: Array[int] = []
	var last := [0, 0]
	run.gold_changed.connect(func(_gold: int, delta: int) -> void: last[0] = delta)
	run.supply_changed.connect(func(_supply: int, delta: int) -> void: last[1] = delta)
	run.stage_started.connect(func(_stage: int) -> void:
		gold_seen.append(last[0])
		supply_seen.append(last[1]))
	for stage: int in range(1, 12):
		run.begin_battle()
		run.finish_battle(true, 0)
		_take_reward(run, RunState.Reward.BLACK_MARKET)
	return _expect(gold_seen == [4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 10] and supply_seen == [2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1], "Stage income %s, supply %s" % [gold_seen, supply_seen])


func _check_battle_results() -> bool:
	var run := _make([["archer", 1, -1, 4, 3]], [""], {"gold": 0, "supply": 0, "morale": 60})
	run.begin_battle()
	if not _expect(run.get_piece(1).has_fought, "A board piece must count as having fought"):
		return false
	run.finish_battle(true, 0)
	if not _expect(run.gold == 1 and run.supply == 2 and run.morale == 60 and run.phase == RunState.Phase.REWARD and run.get_reward_options().size() == 3, "Win effects"):
		return false
	var loser := _make([], [""], {"morale": 60})
	loser.begin_battle()
	loser.finish_battle(false, 3)
	return _expect(loser.morale == 48 and loser.get_reward_options().size() == 2, "A loss with 3 enemies alive costs 12 morale, got %d" % (60 - loser.morale))


func _check_rewards() -> bool:
	var after_win := {"phase": "reward", "stage": 9, "stages_cleared": 9, "rewards": ["reward.rest", "reward.hunt", "reward.loot"]}
	var run := _make([], [""], after_win.merged({"morale": 50, "supply": 0}, true))
	run.choose_reward(RunState.Reward.REST)
	if not _expect(run.morale == 60 and run.stage == 10, "Rest is capped at 60 (got %d)" % run.morale):
		return false
	run = _make([], [""], after_win.merged({"supply": 0}, true))
	run.choose_reward(RunState.Reward.HUNT)
	if not _expect(run.supply == 6 + 1, "Hunt gives 6 supply (plus winter income 1)"):
		return false
	run = _make([], [""], after_win.merged({"gold": 0}, true))
	run.choose_reward(RunState.Reward.LOOT)
	return _expect(run.gold == _catalog.run_rules.loot_gold + _catalog.run_rules.get_stage_income(10), "Loot gives %d gold (plus income), got %d" % [_catalog.run_rules.loot_gold, run.gold])


func _check_black_market() -> bool:
	var run := _make([], [""], {"phase": "reward", "stages_cleared": 1, "rewards": ["reward.rest", "reward.hunt", "reward.black_market"]})
	run.choose_reward(RunState.Reward.BLACK_MARKET)
	if not _expect(run.is_black_market_active() and run.get_refresh_cost() == 0, "Black market: the first refresh is free"):
		return false
	var gold_before := run.gold
	run.refresh_shop()
	if not _expect(run.gold == gold_before and run.get_refresh_cost() == 2, "Black market: only one free refresh"):
		return false
	# Level 3 shops never offer cost 3; rolled as level 4 they sometimes do.
	var plain := _make([], [""], {"gold": 200})
	var market := _make([], [""], {"gold": 200, "black_market": true})
	return _expect(not _offers_cost(plain, 3) and _offers_cost(market, 3), "The black-market shop must roll as one level higher")


# True when any of 40 refreshes offers a unit of `cost`.
func _offers_cost(run: RunState, cost: int) -> bool:
	for refresh: int in 40:
		run.refresh_shop()
		for offer: StringName in run.get_shop_offers():
			if _catalog.get_unit(offer).cost == cost:
				return true
	return false


func _check_stage_12() -> bool:
	var run := _make([], [""], {"stage": 12, "morale": 60, "gold": 0})
	run.begin_battle()
	run.finish_battle(false, 1)
	if not _expect(not run.get_reward_options().has(RunState.Reward.REST), "A stage-12 loss must not offer the rest reward"):
		return false
	var supply_before := run.supply
	# Two of hunt, black market and loot; anything but loot leaves gold alone.
	var choice := RunState.Reward.BLACK_MARKET if run.get_reward_options().has(RunState.Reward.BLACK_MARKET) else RunState.Reward.HUNT
	run.choose_reward(choice)
	var hunted := _catalog.run_rules.hunt_supply if choice == RunState.Reward.HUNT else 0
	if not _expect(run.stage == 12 and run.phase == RunState.Phase.PREP and run.gold == 0 and run.supply == supply_before + hunted, "A stage-12 loss must repeat stage 12 without gold or supply income"):
		return false
	run.begin_battle()
	run.finish_battle(true, 0)
	return _expect(run.phase == RunState.Phase.WON, "A stage-12 win must win the run")


func _check_run_lost() -> bool:
	var run := _make([], [""], {"morale": 10})
	var phases: Array = []
	run.phase_changed.connect(func(phase: RunState.Phase) -> void: phases.append(phase))
	run.begin_battle()
	run.finish_battle(false, 2)
	return _expect(run.morale == 0 and run.phase == RunState.Phase.LOST and phases.back() == RunState.Phase.LOST and run.choose_reward(RunState.Reward.REST) == RunState.Result.WRONG_PHASE, "Morale 0 must lose the run")


func _check_save_round_trip() -> bool:
	var run := RunState.new(_catalog, 424242)
	run.start()
	run.buy(0)
	run.buy(1)
	var first := run.get_pieces()[0]
	run.move_to_board(first.id, Vector2i(4, 2))
	run.begin_battle()
	run.finish_battle(true, 0)
	_take_reward(run, RunState.Reward.BLACK_MARKET)
	if not _expect(RunSave.save(run, SAVE_PATH), "Saving failed"):
		return false
	var loaded := RunSave.load_run(_catalog, SAVE_PATH)
	DirAccess.remove_absolute(SAVE_PATH)
	if not _expect(loaded != null and loaded.to_save_data() == run.to_save_data(), "The loaded run differs from the saved one"):
		return false
	run.refresh_shop()
	loaded.refresh_shop()
	run.refresh_shop()
	loaded.refresh_shop()
	var piece := loaded.get_board_piece(Vector2i(4, 2))
	return _expect(loaded.get_shop_offers() == run.get_shop_offers() and piece != null and piece.has_fought and loaded.get_refresh_cost() == run.get_refresh_cost(), "A loaded run must continue with the same shops")


# A run saved in its reward choice offers the same rewards after loading,
# and choosing one gives the same next stage as without the round trip.
func _check_reward_round_trip() -> bool:
	for is_win: bool in [true, false]:
		var run := RunState.new(_catalog, 5150)
		run.start()
		run.buy(0)
		run.move_to_board(run.get_pieces()[0].id, Vector2i(3, 1))
		run.begin_battle()
		run.finish_battle(is_win, 2)
		if not _expect(RunSave.save(run, SAVE_PATH), "Saving in the reward phase failed"):
			return false
		var loaded := RunSave.load_run(_catalog, SAVE_PATH)
		DirAccess.remove_absolute(SAVE_PATH)
		if not _expect(loaded != null and loaded.phase == RunState.Phase.REWARD and loaded.get_reward_options() == run.get_reward_options() and loaded.to_save_data() == run.to_save_data(), "A reward-phase save must load with the same options (win %s)" % is_win):
			return false
		var choice: RunState.Reward = run.get_reward_options().back()
		run.choose_reward(choice)
		loaded.choose_reward(choice)
		if not _expect(loaded.phase == RunState.Phase.PREP and loaded.to_save_data() == run.to_save_data(), "Choosing a loaded reward must give the same next shop (win %s)" % is_win):
			return false
	# A final-stage loss offers what is left without the rest, even when the
	# rules ask for more rewards after a loss.
	var rules := _catalog.run_rules
	var saved_count := rules.rewards_after_loss
	rules.rewards_after_loss = RunState.REWARD_IDS.size()
	var last := _make([["archer", 1, -1, 4, 1]], [""], {"stage": rules.stage_count})
	last.begin_battle()
	last.finish_battle(false, 1)
	var reloaded := RunState.new(_catalog, 0)
	var is_loaded := reloaded.load_save_data(last.to_save_data())
	var problems := rules.validate()
	rules.rewards_after_loss = 0
	var bad_problems := rules.validate()
	rules.rewards_after_loss = saved_count
	return _expect(is_loaded and last.get_reward_options().size() == RunState.REWARD_IDS.size() - 1 and reloaded.get_reward_options() == last.get_reward_options(), "A final-stage loss must reload with any rewards_after_loss") \
		and _expect(problems.is_empty() and bad_problems.size() == 1, "rewards_after_loss must be validated: %s / %s" % [problems, bad_problems])


# Every successful preparation command reports a change (the screen saves
# on it); refused ones and battle commands do not.
func _check_prep_changed() -> bool:
	var run := _make([["archer", 1, 0, 0, 0], ["spearman", 1, -1, 4, 1, true]], ["archer", "spearman", "", "", ""], {"supply": 20})
	var changes := [0]
	run.prep_changed.connect(func() -> void: changes[0] += 1)
	var commands: Array[Callable] = [
		run.buy.bind(0), run.buy_to.bind(1, 3, RunPiece.NO_CELL), run.refresh_shop, run.buy_supply, run.level_up,
		run.move_to_board.bind(1, Vector2i(2, 1)), run.move_to_bench.bind(1, 5), run.sell.bind(2),
	]
	for command: Callable in commands:
		if not _expect(command.call() == RunState.Result.OK, "%s should succeed" % command.get_method()):
			return false
	var expected := commands.size()
	run.move_to_bench(99, 0)
	run.sell(99)
	run.begin_battle()
	run.finish_battle(true, 0)
	return _expect(changes[0] == expected, "Expected %d preparation changes, got %d" % [expected, changes[0]])


func _check_bad_saves() -> bool:
	print("Run test: the next warning (a broken save) is expected")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	if not _expect(RunSave.load_run(_catalog) == null, "A file that is not JSON must be ignored"):
		return false
	var bad_count := 0
	for case: Array in _bad_save_cases():
		_write_save(case[1], case[2] if case.size() > 2 else [])
		if not _expect(RunSave.load_run(_catalog) == null, "A save with %s must be ignored" % case[0]):
			bad_count += 1
	if bad_count > 0:
		return false
	# A bench row's col and rank must be there but are ignored, free
	# refreshes are capped, and a reward-phase save keeps its options.
	_write_save({"free_refreshes": 5}, [_row(1, "archer", 1, 0, 9, 9)])
	var loaded := RunSave.load_run(_catalog)
	var bench_ok := loaded != null and loaded.get_bench_piece(0) != null and loaded.get_board_count() == 0 and loaded.get_refresh_cost() == 2
	_write_save({"free_refreshes": 5, "black_market": true})
	var market := RunSave.load_run(_catalog)
	var market_ok := market != null and market.get_refresh_cost() == 0 and market.refresh_shop() == RunState.Result.OK and market.get_refresh_cost() == 2
	_write_save({"phase": "reward", "stages_cleared": 2, "rewards": ["reward.hunt", "reward.black_market"]})
	var reward := RunSave.load_run(_catalog)
	var reward_ok := reward != null and reward.phase == RunState.Phase.REWARD and reward.get_reward_options() == [RunState.Reward.HUNT, RunState.Reward.BLACK_MARKET]
	RunSave.delete()
	return _expect(bench_ok and market_ok and reward_ok and not RunSave.has_save(), "Valid saves must load with normalised pieces, capped refreshes and their rewards")


# [label, top-level fields to change, pieces (empty: one archer on bench 0)].
func _bad_save_cases() -> Array:
	var on_board := func(id: int, unit: String, col: int) -> Dictionary: return _row(id, unit, 1, -1, col, 1)
	return [
		["version 99", {"version": 99}], ["version as text", {"version": "2"}], ["version as object", {"version": {}}],
		["version 1", {"version": 1}], ["version 2", {"version": 2}],
		["stage as object", {"stage": {}}], ["stage as text", {"stage": "abc"}], ["stage 1.5", {"stage": 1.5}],
		["morale null", {"morale": null}], ["gold as array", {"gold": []}], ["black_market as text", {"black_market": "yes"}],
		["seed as object", {"seed": {}}], ["seed not a number", {"seed": "abc"}], ["rng_state past 64 bits", {"rng_state": "99999999999999999999"}],
		["free_refreshes as text", {"free_refreshes": "1"}], ["pieces as text", {"pieces": "none"}], ["shop of numbers", {"shop": [5, 6]}],
		["too many offers", {"shop": ["", "", "", "", "", ""]}], ["an unknown offer", {"shop": ["unit.nobody"]}],
		["morale 0", {"morale": 0}], ["morale 9999", {"morale": 9999}], ["gold -1", {"gold": -1}], ["supply -1", {"supply": -1}],
		["level 2", {"level": 2}], ["level 10", {"level": 10}], ["stage 0", {"stage": 0}], ["stage 13", {"stage": 13}],
		["stages_cleared past the stage", {"stages_cleared": 5}], ["stages_cleared -1", {"stages_cleared": -1}],
		["phase battle", {"phase": "battle"}], ["phase as number", {"phase": 2}], ["phase empty", {"phase": ""}],
		["rewards as text", {"rewards": "reward.rest"}], ["rewards in prep", {"rewards": ["reward.rest"]}],
		["no rewards in the reward phase", {"phase": "reward"}],
		["an unknown reward", {"phase": "reward", "rewards": ["reward.rest", "reward.gold"]}],
		["a reward as number", {"phase": "reward", "rewards": [0, 1]}],
		["a reward twice", {"phase": "reward", "rewards": ["reward.rest", "reward.rest"]}],
		["one reward", {"phase": "reward", "rewards": ["reward.hunt"]}],
		["four rewards", {"phase": "reward", "rewards": ["reward.rest", "reward.hunt", "reward.black_market", "reward.hunt"]}],
		["rest at the final stage", {"phase": "reward", "stage": 12, "rewards": ["reward.rest", "reward.hunt"]}],
		["the final stage cleared in the reward phase", {"phase": "reward", "stage": 12, "stages_cleared": 12, "rewards": ["reward.hunt", "reward.black_market"]}],
		["a reward-phase stage cleared twice", {"phase": "reward", "stages_cleared": 3, "rewards": ["reward.hunt", "reward.black_market"]}],
		["bench col missing", {}, [_without(_row(1, "archer", 1, 0, 0, 0), "col")]],
		["bench rank as text", {}, [_row(1, "archer", 1, 0, 0, 0).merged({"rank": "x"}, true)]],
		["a piece id as text", {}, [_row("abc", "archer", 1, 0, 0, 0)]],
		["a unit id as number", {}, [_row(1, 5, 1, 0, 0, 0)]],
		["a bench slot as object", {}, [_row(1, "archer", 1, {}, 0, 0)]],
		["has_fought as text", {}, [_row(1, "archer", 1, 0, 0, 0, "x")]],
		["a piece row as text", {}, ["archer"]],
		["an unknown unit", {}, [_row(1, "nobody", 1, 0, 0, 0)]],
		["star 0", {}, [_row(1, "archer", 0, 0, 0, 0)]], ["star 4", {}, [_row(1, "archer", 4, 0, 0, 0)]],
		["a 3-star cost-5", {}, [_row(1, "lac_hong", 3, 0, 0, 0)]],
		["two pieces on one cell", {}, [on_board.call(1, "archer", 4), on_board.call(2, "spearman", 4)]],
		["bench 7 with a valid cell", {}, [on_board.call(1, "archer", 4), _row(2, "spearman", 1, 7, 4, 1)]],
		["two pieces on one bench slot", {}, [_row(1, "archer", 1, 2, 0, 0), _row(2, "spearman", 1, 2, 0, 0)]],
		["a cell off the board", {}, [_row(1, "archer", 1, -1, 9, 9)]],
		["two pieces with one id", {}, [_row(1, "archer", 1, 0, 0, 0), _row(1, "spearman", 1, 1, 0, 0)]],
		["more on the board than the level", {}, [on_board.call(1, "archer", 1), on_board.call(2, "spearman", 2), on_board.call(3, "shield_guard", 3), on_board.call(4, "fire_adept", 4)]],
		["three legends on the board", {"level": 5}, [on_board.call(1, "lac_hong", 1), on_board.call(2, "lieu_mi", 2), on_board.call(3, "ba_khac", 3)]],
		["three unmerged copies", {}, [_row(1, "archer", 1, 0, 0, 0), _row(2, "archer", 1, 1, 0, 0), _row(3, "archer", 1, 2, 0, 0)]],
	] + _missing_key_cases()


# Every key the game writes is required: one case per key left out.
func _missing_key_cases() -> Array:
	var cases: Array = []
	for key: String in _valid_save().keys():
		cases.append(["no %s" % key, {key: MISSING_KEY}])
	return cases


func _without(row: Dictionary, key: String) -> Dictionary:
	row.erase(key)
	return row


func _valid_save() -> Dictionary:
	return {
		"version": RunSave.VERSION, "seed": "1", "rng_state": "5", "phase": "prep", "stage": 2, "stages_cleared": 1,
		"morale": 60, "gold": 5, "supply": 1, "level": 3, "next_piece_id": 2,
		"pieces": [_row(1, "archer", 1, 0, 0, 0)], "shop": ["unit.archer", "", "", "", ""],
		"black_market": false, "free_refreshes": 0, "rewards": [],
		"epiphany": EpiphanyTracker.new(_catalog, 1).to_save_data(),
		"encounter": _encounters_before(2), "win_streak": 0,
	}


func _row(id: Variant, unit: Variant, star: int, bench: Variant, col: int, rank: int, has_fought: Variant = false) -> Dictionary:
	return {"id": id, "unit_id": "unit." + unit if unit is String else unit, "star": star, "has_fought": has_fought, "bench": bench, "col": col, "rank": rank}


# A valid stage-2 save with `fields` changed (MISSING_KEY removes a key) and
# these piece rows.
func _write_save(fields: Dictionary, pieces: Array = []) -> void:
	var data := _valid_save()
	if not pieces.is_empty():
		data["pieces"] = pieces
	data.merge(fields, true)
	for key: String in data.keys():
		if data[key] is String and data[key] == MISSING_KEY:
			data.erase(key)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
