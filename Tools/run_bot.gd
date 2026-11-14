extends SceneTree

# Balance bot: plays whole runs headless with a simple greedy policy through
# the public RunState API and a Battle node, then prints per-stage win rates,
# average morale left and the run win rate. --weak stands in for a new
# player: it buys the first affordable unit, never refreshes, sells or buys
# supply, and places units left to right. Both take the road encounter
# option that gives the most gold. Not shipped (Tools/ is excluded from
# every export preset). Usage:
#   godot --headless --path . --script res://Tools/run_bot.gd -- <runs> [first_seed] [verbose] [--weak]
# See Docs/systems/run.md for the policy and the latest numbers.

const MAX_BATTLE_TICKS: int = 4000
## Safety limit: the bot gives a run up after this many battles.
const MAX_BATTLES_PER_RUN: int = 60
const MAX_REFRESHES: int = 10
const REFRESH_KEEP_GOLD: int = 1
const MELEE_CLASSES: Array[StringName] = [&"class.shield", &"class.sword", &"class.spear", &"class.cavalry"]
const COLUMN_ORDER: Array[int] = [4, 3, 5, 2, 6, 1, 7]

var _catalog: Catalog
var _attempts: Dictionary[int, int] = {}
var _wins: Dictionary[int, int] = {}
var _morale_after: Dictionary[int, int] = {}
var _first_wins: Dictionary[int, int] = {}
var _first_attempts: Dictionary[int, int] = {}
var _given_up: int = 0
var _epiphanies: int = 0
var _boss_casts: int = 0
var _boss_petrified: int = 0
var _boss_fights: int = 0
var _verbose: bool = false
var _is_weak: bool = false
var _encounters: int = 0
var _bets_won: int = 0
var _bets: int = 0
var _streak_gold: int = 0


func _initialize() -> void:
	_catalog = load("res://Data/catalog.tres") as Catalog
	var problems := _catalog.validate()
	if not problems.is_empty():
		for problem: String in problems:
			push_error(problem)
		quit(1)
		return
	var args := Array(OS.get_cmdline_user_args())
	_is_weak = args.has("--weak")
	_verbose = args.has("verbose")
	args = args.filter(func(arg: String) -> bool: return arg.is_valid_int())
	var runs := int(args[0]) if args.size() > 0 else 200
	var first_seed := int(args[1]) if args.size() > 1 else 1000
	var won := 0
	var cleared_total := 0
	for index: int in runs:
		var run := RunState.new(_catalog, first_seed + index)
		run.streak_paid.connect(func(_streak: int, gold: int) -> void: _streak_gold += gold)
		run.bet_settled.connect(func(is_win: bool, _gold: int) -> void:
			_bets += 1
			_bets_won += 1 if is_win else 0)
		run.start()
		if _play(run):
			won += 1
		cleared_total += run.stages_cleared
	_report(runs, won, cleared_total)
	quit(0)


func _play(run: RunState) -> bool:
	var battles := 0
	var seen_stages: Dictionary[int, bool] = {}
	while run.phase == RunState.Phase.PREP:
		battles += 1
		if battles > MAX_BATTLES_PER_RUN:
			_given_up += 1
			return false
		if _is_weak:
			_prepare_weak(run)
		else:
			_prepare(run)
		var stage := run.stage
		if _verbose:
			print("stage %d level %d gold %d supply %d board %s" % [stage, run.level, run.gold, run.supply, _describe_board(run)])
		run.begin_battle()
		var result := _fight(run)
		run.finish_battle(result[0], result[1], result[2])
		_attempts[stage] = _attempts.get(stage, 0) + 1
		_wins[stage] = _wins.get(stage, 0) + (1 if result[0] else 0)
		_morale_after[stage] = _morale_after.get(stage, 0) + run.morale
		if not seen_stages.has(stage):
			seen_stages[stage] = true
			_first_attempts[stage] = _first_attempts.get(stage, 0) + 1
			_first_wins[stage] = _first_wins.get(stage, 0) + (1 if result[0] else 0)
		if run.phase == RunState.Phase.REWARD:
			# The bot always takes the first Kỳ Ngộ card.
			if run.epiphanies.has_pending():
				run.choose_epiphany(0)
				_epiphanies += 1
			run.choose_reward(_pick_reward(run))
		if run.phase == RunState.Phase.ENCOUNTER:
			run.choose_encounter(_pick_encounter_option(run))
			_encounters += 1
	return run.phase == RunState.Phase.WON


# "unit*star" per board piece, for the verbose log.
func _describe_board(run: RunState) -> Array[String]:
	var names: Array[String] = []
	for slot: LineupSlot in run.get_board_slots():
		names.append("%s*%d" % [String(slot.unit_id).trim_prefix("unit."), slot.star])
	return names


# The affordable option that gives the most gold now (a bet counts at half
# its payout); ties go to the first.
func _pick_encounter_option(run: RunState) -> int:
	var options := run.encounters.get_pending().options
	var best := -1
	var best_gold := -INF
	for index: int in options.size():
		if run.get_encounter_refusal(index) != RunState.Result.OK:
			continue
		var gold := 0.0
		for effect: EncounterEffect in options[index].effects:
			if effect.kind == EncounterEffects.GOLD:
				gold += effect.amount
			elif effect.kind == EncounterEffects.BET:
				gold += effect.amount * 0.5
		if gold > best_gold:
			best = index
			best_gold = gold
	return best


# A new player: levels up whenever supply allows, buys the first offer it
# can pay until nothing fits, fills the board from the left.
func _prepare_weak(run: RunState) -> void:
	_level_up(run)
	var bought := true
	while bought:
		bought = false
		var offers := run.get_shop_offers()
		for slot: int in offers.size():
			if offers[slot] != &"" and run.gold >= _catalog.get_unit(offers[slot]).cost and run.buy(slot) == RunState.Result.OK:
				bought = true
				break
	var pieces := run.get_pieces()
	pieces.sort_custom(func(a: RunPiece, b: RunPiece) -> bool: return a.star > b.star if a.star != b.star else a.id < b.id)
	var cells: Array[Vector2i] = []
	for rank: int in [1, 2, 3, 4]:
		for col: int in range(1, 8):
			cells.append(Vector2i(col, rank))
	for piece: RunPiece in pieces:
		if piece.is_on_bench() and run.get_board_count() < run.get_capacity():
			for cell: Vector2i in cells:
				if run.get_board_piece(cell) == null and run.move_to_board(piece.id, cell) == RunState.Result.OK:
					break


# [is_win, enemies alive, damage dealt by piece id], with the player's Kỳ
# Ngộ mutations on side A, as the run screen fights.
func _fight(run: RunState) -> Array:
	var stage := run.get_stage_data()
	var slots := run.get_board_slots()
	if slots.is_empty():
		return [false, stage.slots.size(), {}]
	var battle := BattleFactory.create(_catalog)
	battle.set_synergy_overrides(Battle.SIDE_A, run.get_synergy_overrides())
	var indexes := BattleFactory.add_slots(battle, _catalog, Battle.SIDE_A, slots)
	BattleFactory.add_slots(battle, _catalog, Battle.SIDE_B, stage.slots)
	var is_boss := run.is_boss_stage()
	if is_boss:
		battle.event_emitted.connect(_count_boss_event.bind(indexes))
		_boss_fights += 1
	battle.run_to_end(MAX_BATTLE_TICKS)
	var damage := {}
	var pieces := run.get_board_pieces()
	for index: int in indexes.size():
		if indexes[index] >= 0:
			damage[pieces[index].id] = battle.get_unit_state(indexes[index])["damage_dealt"]
	var result := [battle.get_winner() == Battle.SIDE_A, BattleFactory.count_alive(battle, Battle.SIDE_B), damage]
	battle.free()
	return result


func _count_boss_event(event: Dictionary, player_indexes: Array[int]) -> void:
	if event["type"] == &"skill_resolved" and player_indexes.has(event["unit"]):
		_boss_casts += 1
	elif event["type"] == &"status_applied" and event["status"] == &"status.petrified":
		_boss_petrified += 1


func _prepare(run: RunState) -> void:
	_level_up(run)
	var refreshes := 0
	while true:
		_buy_round(run)
		_level_up(run)
		if refreshes >= MAX_REFRESHES or run.gold < run.get_refresh_cost() + REFRESH_KEEP_GOLD:
			break
		run.refresh_shop()
		refreshes += 1
	_arrange(run)
	# Spare gold goes into supply once the board is full.
	while run.get_board_count() >= run.get_capacity() and run.gold >= run.rules.supply_pack_gold and run.get_level_up_cost() > 0:
		run.buy_supply()
		_level_up(run)
	_arrange(run)


func _level_up(run: RunState) -> void:
	while run.get_level_up_cost() > 0 and run.supply >= run.get_level_up_cost():
		run.level_up()


# Buys merges and pairs first, then units that fill the board or beat the
# weakest piece, dearest first. Selling a 1-star returns its cost, so lone
# bench pieces are sold to make room and to pay for refreshes.
func _buy_round(run: RunState) -> void:
	var bought := true
	while bought:
		bought = false
		for slot: int in _offer_order(run):
			var unit := _catalog.get_unit(run.get_shop_offers()[slot])
			if not _wants(run, unit):
				continue
			if not run.would_merge(unit.id) and _bench_full(run) and not _sell_lone_bench(run, unit.cost):
				continue
			if run.gold >= unit.cost and run.buy(slot) == RunState.Result.OK:
				bought = true
				break
	while run.get_pieces().size() > run.get_capacity() + 2 and _sell_lone_bench(run, 99):
		pass


func _offer_order(run: RunState) -> Array[int]:
	var scored: Array[Array] = []
	var offers := run.get_shop_offers()
	for slot: int in offers.size():
		if offers[slot] == &"":
			continue
		var unit := _catalog.get_unit(offers[slot])
		var score := unit.cost + (20 if run.would_merge(unit.id) else 0) + (10 if _copies(run, unit.id) > 0 else 0)
		scored.append([-score, slot])
	scored.sort()
	var order: Array[int] = []
	for pair: Array in scored:
		order.append(pair[1])
	return order


func _wants(run: RunState, unit: UnitData) -> bool:
	if run.would_merge(unit.id):
		return true
	if _copies(run, unit.id) > 0 and unit.cost >= _min_pair_cost(run):
		return true
	if run.get_pieces().size() < run.get_capacity():
		return true
	return float(unit.cost) > _weakest_value(run)


# Late in the run cheap pairs stop being worth the bench space.
func _min_pair_cost(run: RunState) -> int:
	return 1 if run.stage <= 4 else (2 if run.stage <= 8 else 3)


func _weakest_value(run: RunState) -> float:
	var weakest := INF
	for piece: RunPiece in run.get_pieces():
		weakest = minf(weakest, _value(piece))
	return weakest


func _copies(run: RunState, unit_id: StringName) -> int:
	var count := 0
	for piece: RunPiece in run.get_pieces():
		if piece.unit_id == unit_id and piece.star == 1:
			count += 1
	return count


func _bench_full(run: RunState) -> bool:
	for slot: int in run.rules.bench_slots:
		if run.get_bench_piece(slot) == null:
			return false
	return true


# Sells the weakest bench piece that has no copy and is worth less than
# `below`; false when there is none.
func _sell_lone_bench(run: RunState, below: float) -> bool:
	var weakest: RunPiece = null
	for slot: int in run.rules.bench_slots:
		var piece := run.get_bench_piece(slot)
		if piece == null or _value(piece) >= below or (piece.star == 1 and _copies(run, piece.unit_id) > 1):
			continue
		if weakest == null or _value(piece) < _value(weakest):
			weakest = piece
	if weakest == null:
		return false
	return run.sell(weakest.id) == RunState.Result.OK


func _value(piece: RunPiece) -> float:
	return _catalog.get_unit(piece.unit_id).cost * pow(2.5, piece.star - 1)


# Puts the strongest pieces on the board: front-liners in ranks 1-2,
# archers and mages in ranks 3-4, centred.
func _arrange(run: RunState) -> void:
	var chosen := _choose_board(run)
	var targets := _target_cells(chosen)
	for piece: RunPiece in run.get_board_pieces():
		if not chosen.has(piece):
			var free_slot := _free_bench_slot(run)
			if free_slot >= 0:
				run.move_to_bench(piece.id, free_slot)
	for index: int in chosen.size():
		var piece: RunPiece = chosen[index]
		if run.move_to_board(piece.id, targets[index]) == RunState.Result.BOARD_FULL:
			for other: RunPiece in run.get_board_pieces():
				if not chosen.has(other):
					run.move_to_board(piece.id, other.cell)
					run.move_to_board(piece.id, targets[index])
					break


func _choose_board(run: RunState) -> Array[RunPiece]:
	var pieces := run.get_pieces()
	pieces.sort_custom(func(a: RunPiece, b: RunPiece) -> bool: return _value(a) > _value(b))
	var chosen: Array[RunPiece] = []
	var legends := 0
	for piece: RunPiece in pieces:
		if chosen.size() >= run.get_capacity():
			break
		var is_legend := _catalog.get_unit(piece.unit_id).cost == run.rules.legend_cost
		if is_legend and legends >= run.rules.legend_board_limit:
			continue
		legends += 1 if is_legend else 0
		chosen.append(piece)
	return chosen


# Front-liners fill ranks 1-2 from the centre out; then two formation
# habits: a mage or archer goes right behind a front shield (Hộ Pháp) or
# spear (Thương Che Cung), and three archers stand together in rank 4
# (Mưa Tên). The rest fill ranks 3-4 from the centre out.
func _target_cells(chosen: Array[RunPiece]) -> Array[Vector2i]:
	var front: Array[Vector2i] = []
	var back: Array[Vector2i] = []
	for rank: int in [1, 2]:
		for col: int in COLUMN_ORDER:
			front.append(Vector2i(col, rank))
	for rank: int in [3, 4]:
		for col: int in COLUMN_ORDER:
			back.append(Vector2i(col, rank))
	var cells: Array[Vector2i] = []
	cells.resize(chosen.size())
	var used: Dictionary[Vector2i, bool] = {}
	var guards: Dictionary[StringName, Array] = {&"class.shield": [], &"class.spear": []}
	var archers: Array[int] = []
	for index: int in chosen.size():
		var unit := _catalog.get_unit(chosen[index].unit_id)
		if not MELEE_CLASSES.has(unit.class_id):
			if unit.class_id == &"class.archer":
				archers.append(index)
			continue
		cells[index] = front.pop_front()
		used[cells[index]] = true
		if cells[index].y == 1 and guards.has(unit.class_id):
			guards[unit.class_id].append(cells[index].x)
	if archers.size() >= 3:
		for pair: Array in [[archers[0], Vector2i(4, 4)], [archers[1], Vector2i(3, 4)], [archers[2], Vector2i(5, 4)]]:
			cells[pair[0]] = pair[1]
			used[pair[1]] = true
	for index: int in chosen.size():
		var unit := _catalog.get_unit(chosen[index].unit_id)
		if MELEE_CLASSES.has(unit.class_id) or cells[index] != Vector2i.ZERO:
			continue
		var guard_class := &"class.shield" if unit.class_id == &"class.mage" else &"class.spear"
		var cell := Vector2i.ZERO
		for col: int in guards[guard_class]:
			if not used.has(Vector2i(col, 2)):
				cell = Vector2i(col, 2)
				break
		while cell == Vector2i.ZERO or used.has(cell):
			cell = back.pop_front()
		cells[index] = cell
		used[cell] = true
	return cells


func _free_bench_slot(run: RunState) -> int:
	for slot: int in run.rules.bench_slots:
		if run.get_bench_piece(slot) == null:
			return slot
	return -1


# Rest when hurt, supply while levels remain (loot next), else loot and the
# black market.
func _pick_reward(run: RunState) -> RunState.Reward:
	var options := run.get_reward_options()
	var preferred: Array[RunState.Reward] = [RunState.Reward.HUNT, RunState.Reward.LOOT, RunState.Reward.BLACK_MARKET, RunState.Reward.REST]
	if run.morale <= 40:
		preferred = [RunState.Reward.REST, RunState.Reward.HUNT, RunState.Reward.LOOT, RunState.Reward.BLACK_MARKET]
	elif run.get_level_up_cost() < 0:
		preferred = [RunState.Reward.LOOT, RunState.Reward.BLACK_MARKET, RunState.Reward.REST, RunState.Reward.HUNT]
	for reward: RunState.Reward in preferred:
		if options.has(reward):
			return reward
	return options[0]


func _report(runs: int, won: int, cleared_total: int) -> void:
	print("Run bot: %d runs" % runs)
	print("stage  reached  first try win%  attempts  win% per attempt  avg morale after")
	for stage: int in range(1, _catalog.run_rules.stage_count + 1):
		var attempts: int = _attempts.get(stage, 0)
		var firsts: int = _first_attempts.get(stage, 0)
		if attempts == 0:
			print("%5d  %7d               -  %8d                 -  -" % [stage, 0, 0])
			continue
		print("%5d  %7d  %14.0f  %8d  %16.0f  %5.1f" % [stage, firsts, 100.0 * _first_wins.get(stage, 0) / firsts, attempts, 100.0 * _wins.get(stage, 0) / attempts, float(_morale_after.get(stage, 0)) / attempts])
	print("run win rate: %.1f%% (%d/%d), average stages cleared %.1f, given up after %d battles: %d" % [100.0 * won / runs, won, runs, float(cleared_total) / runs, MAX_BATTLES_PER_RUN, _given_up])
	print("mode %s; road encounters %d (%.2f per run), bets won %d of %d, streak gold %.2f per run" % ["weak" if _is_weak else "normal", _encounters, float(_encounters) / runs, _bets_won, _bets, float(_streak_gold) / runs])
	print("ky ngo taken: %d (%.2f per run); boss fights %d, player casts %d, Hoa Da %d (%.2f per fight)" % [_epiphanies, float(_epiphanies) / runs, _boss_fights, _boss_casts, _boss_petrified, float(_boss_petrified) / maxi(1, _boss_fights)])
