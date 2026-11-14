class_name RunState
extends RefCounted
## The whole run of 12 stages: morale, gold, supply, level, the pieces on
## bench and board, the shop, and the stage flow prep -> battle -> reward.
## Pure data and rules: no nodes, no clock. Screens send commands (each
## returns a Result) and listen to the signals; they never edit fields. All
## randomness comes from one RandomNumberGenerator seeded from the run seed.
## See Docs/systems/run.md.
## [codeblock]
## var run := RunState.new(catalog, 1234)
## run.start()
## if run.buy(0) == RunState.Result.OK: ...
## [/codeblock]

signal gold_changed(gold: int, delta: int)
signal supply_changed(supply: int, delta: int)
signal morale_changed(morale: int, delta: int)
signal level_changed(level: int)
## The shop offers were replaced (a new stage or a refresh).
signal shop_rolled()
## A purchase made a piece; it may merge right after (pieces_merged).
signal piece_bought(piece_id: int, shop_slot: int)
## A piece changed place (moves and both sides of a swap).
signal piece_moved(piece_id: int)
signal piece_sold(piece_id: int, gold: int, supply: int)
## `result_id` gained a star and now stands where the merge put it; the
## `consumed_ids` pieces are gone.
signal pieces_merged(result_id: int, consumed_ids: Array[int])
signal phase_changed(phase: Phase)
## Preparation of `stage` began (income paid, shop rolled).
signal stage_started(stage: int)
signal battle_resolved(is_win: bool, gold_delta: int, supply_delta: int, morale_delta: int)

enum Result { OK, NOT_ENOUGH_GOLD, NOT_ENOUGH_SUPPLY, BENCH_FULL, BOARD_FULL, LEGEND_LIMIT, BAD_TARGET, NO_PIECE, EMPTY_SLOT, MAX_LEVEL, WRONG_PHASE, NOT_OFFERED }
enum Phase { PREP, BATTLE, REWARD, WON, LOST }
enum Reward { REST, HUNT, BLACK_MARKET }

const REWARD_IDS: Array[StringName] = [&"reward.rest", &"reward.hunt", &"reward.black_market"]

var rules: RunRules
var catalog: Catalog
var run_seed: int = 0
var phase: Phase = Phase.PREP
var stage: int = 1
var morale: int = 0
var gold: int = 0
var supply: int = 0
var level: int = 0
## Stages won so far (the end screen shows it).
var stages_cleared: int = 0

var _rng := RandomNumberGenerator.new()
var _roster: RunRoster
var _shop: Shop
var _rewards: Array[Reward] = []
# Black market: this stage's shop rolls as if a level higher, and the first
# refresh is free.
var _is_black_market: bool = false
var _free_refreshes: int = 0
var _is_black_market_next: bool = false


func _init(run_catalog: Catalog, seed_value: int) -> void:
	catalog = run_catalog
	rules = run_catalog.run_rules
	run_seed = seed_value
	_rng.seed = seed_value
	_roster = RunRoster.new(run_catalog, rules)
	_roster.piece_moved.connect(piece_moved.emit)
	_roster.pieces_merged.connect(pieces_merged.emit)
	_shop = Shop.new(run_catalog, rules)
	morale = rules.start_morale
	gold = rules.start_gold
	supply = rules.start_supply
	level = rules.start_level


## Begins stage 1's preparation.
func start() -> void:
	_begin_prep(true)


# --- Queries -------------------------------------------------------------

func get_piece(piece_id: int) -> RunPiece:
	return _roster.get_piece(piece_id)


func get_pieces() -> Array[RunPiece]:
	return _roster.get_all()


func get_bench_piece(slot: int) -> RunPiece:
	return _roster.get_bench_piece(slot)


func get_board_piece(cell: Vector2i) -> RunPiece:
	return _roster.get_board_piece(cell)


## Board pieces in board order (rank 1 first, then lower column).
func get_board_pieces() -> Array[RunPiece]:
	return _roster.get_board_pieces()


func get_board_count() -> int:
	return _roster.count_board()


func get_capacity() -> int:
	return rules.get_capacity(level)


func get_shop_offers() -> Array[StringName]:
	return _shop.get_offers()


## Gold the next refresh costs (0 while a black-market refresh is left).
func get_refresh_cost() -> int:
	return 0 if _free_refreshes > 0 else rules.refresh_gold


## Supply the next level costs, or -1 at the top level.
func get_level_up_cost() -> int:
	return rules.get_supply_to_next(level)


## Gold and supply selling this piece would give, as Vector2i(gold, supply).
func get_sell_value(piece_id: int) -> Vector2i:
	var piece := _roster.get_piece(piece_id)
	if piece == null:
		return Vector2i.ZERO
	var unit := catalog.get_unit(piece.unit_id)
	return Vector2i(unit.cost * piece.star, piece.star if piece.has_fought else 0)


## True when buying this unit now would complete a merge at once.
func would_merge(unit_id: StringName) -> bool:
	return _roster.would_merge(unit_id)


func get_stage_data() -> StageData:
	return catalog.stages[clampi(stage, 1, catalog.stages.size()) - 1]


## The board as battle slots for side A, in board order.
func get_board_slots() -> Array[LineupSlot]:
	var slots: Array[LineupSlot] = []
	for piece: RunPiece in _roster.get_board_pieces():
		slots.append(LineupSlot.create(piece.unit_id, piece.star, piece.cell.x, piece.cell.y))
	return slots


## The rewards offered now (only in the REWARD phase).
func get_reward_options() -> Array[Reward]:
	return _rewards.duplicate()


func is_black_market_active() -> bool:
	return _is_black_market


# --- Preparation commands ------------------------------------------------

## Buys the unit in `shop_slot` onto the first free bench slot. A full
## bench is fine when the purchase completes a merge at once.
func buy(shop_slot: int) -> Result:
	return _buy(shop_slot, RunPiece.NO_BENCH, RunPiece.NO_CELL)


## Buys the unit in `shop_slot` straight onto a free bench slot or a free
## board cell (one of them set). A purchase that merges ignores the target.
func buy_to(shop_slot: int, bench_slot: int, cell: Vector2i) -> Result:
	return _buy(shop_slot, bench_slot, cell)


func refresh_shop() -> Result:
	if phase != Phase.PREP:
		return Result.WRONG_PHASE
	var cost := get_refresh_cost()
	if gold < cost:
		return Result.NOT_ENOUGH_GOLD
	if _free_refreshes > 0:
		_free_refreshes -= 1
	_add_gold(-cost)
	_roll_shop()
	return Result.OK


func buy_supply() -> Result:
	if phase != Phase.PREP:
		return Result.WRONG_PHASE
	if gold < rules.supply_pack_gold:
		return Result.NOT_ENOUGH_GOLD
	_add_gold(-rules.supply_pack_gold)
	_add_supply(rules.supply_pack_amount)
	return Result.OK


func level_up() -> Result:
	if phase != Phase.PREP:
		return Result.WRONG_PHASE
	var cost := get_level_up_cost()
	if cost < 0:
		return Result.MAX_LEVEL
	if supply < cost:
		return Result.NOT_ENOUGH_SUPPLY
	_add_supply(-cost)
	level += 1
	level_changed.emit(level)
	return Result.OK


func sell(piece_id: int) -> Result:
	if phase != Phase.PREP:
		return Result.WRONG_PHASE
	if _roster.get_piece(piece_id) == null:
		return Result.NO_PIECE
	var value := get_sell_value(piece_id)
	_roster.remove(piece_id)
	piece_sold.emit(piece_id, value.x, value.y)
	_add_gold(value.x)
	_add_supply(value.y)
	return Result.OK


## Moves a piece onto a board cell (local col, rank), swapping with a piece
## already there. Refused over capacity or past the legend limit.
func move_to_board(piece_id: int, cell: Vector2i) -> Result:
	var piece := _roster.get_piece(piece_id)
	var check := _check_move(piece)
	return check if check != Result.OK else _roster.move_to_board(piece, cell, get_capacity())


## Moves a piece onto a bench slot, swapping with a piece already there.
func move_to_bench(piece_id: int, slot: int) -> Result:
	var piece := _roster.get_piece(piece_id)
	var check := _check_move(piece)
	return check if check != Result.OK else _roster.move_to_bench(piece, slot)


# --- Battle and reward ---------------------------------------------------

## Ends the preparation: every board piece now counts as having fought.
func begin_battle() -> Result:
	if phase != Phase.PREP:
		return Result.WRONG_PHASE
	for piece: RunPiece in _roster.get_board_pieces():
		piece.has_fought = true
	_set_phase(Phase.BATTLE)
	return Result.OK


## Applies a battle result: `enemies_alive` living enemy units at the end.
## Moves to REWARD, or ends the run (WON or LOST).
func finish_battle(is_win: bool, enemies_alive: int) -> Result:
	if phase != Phase.BATTLE:
		return Result.WRONG_PHASE
	var morale_delta := 0
	if is_win:
		stages_cleared += 1
		_add_gold(rules.win_gold)
		_add_supply(rules.win_supply)
	else:
		morale_delta = -(rules.loss_morale_base + rules.loss_morale_per_enemy * maxi(0, enemies_alive))
		_add_morale(morale_delta)
	battle_resolved.emit(is_win, rules.win_gold if is_win else 0, rules.win_supply if is_win else 0, morale_delta)
	if morale <= 0:
		_set_phase(Phase.LOST)
	elif is_win and stage >= rules.stage_count:
		_set_phase(Phase.WON)
	else:
		_offer_rewards(is_win)
		_set_phase(Phase.REWARD)
	return Result.OK


## Takes one of the offered rewards and begins the next stage's preparation
## (stage 12 repeats after a loss, without gold or supply income).
func choose_reward(reward: Reward) -> Result:
	if phase != Phase.REWARD:
		return Result.WRONG_PHASE
	if not _rewards.has(reward):
		return Result.NOT_OFFERED
	match reward:
		Reward.REST:
			_add_morale(mini(rules.rest_morale, rules.max_morale - morale))
		Reward.HUNT:
			_add_supply(rules.hunt_supply)
		Reward.BLACK_MARKET:
			_is_black_market_next = true
	_rewards.clear()
	var is_repeat := stage >= rules.stage_count
	if not is_repeat:
		stage += 1
	_begin_prep(not is_repeat)
	return Result.OK


# --- Save ----------------------------------------------------------------

## Everything needed to continue this run, as JSON-safe data. 64-bit
## numbers are strings: JSON numbers are doubles.
func to_save_data() -> Dictionary:
	return {
		"seed": str(run_seed), "rng_state": str(_rng.state), "stage": stage,
		"stages_cleared": stages_cleared, "morale": morale, "gold": gold,
		"supply": supply, "level": level, "next_piece_id": _roster.get_next_id(),
		"pieces": _roster.to_save_data(), "shop": _shop.get_offers().map(func(id: StringName) -> String: return String(id)),
		"black_market": _is_black_market, "free_refreshes": _free_refreshes,
	}


## Restores a run saved by to_save_data() into its preparation. False (and
## nothing usable) when the data is malformed or names unknown units.
func load_save_data(data: Dictionary) -> bool:
	for key: String in ["seed", "rng_state", "stage", "morale", "gold", "supply", "level", "pieces", "shop"]:
		if not data.has(key):
			return false
	if not data["pieces"] is Array or not data["shop"] is Array:
		return false
	if not _roster.load_save_data(data["pieces"], int(data.get("next_piece_id", 1))):
		return false
	for piece: RunPiece in _roster.get_all():
		if catalog.get_unit(piece.unit_id) == null:
			return false
	var offers: Array[StringName] = []
	for offer: Variant in data["shop"]:
		var unit_id := StringName(str(offer))
		if unit_id != &"" and catalog.get_unit(unit_id) == null:
			return false
		offers.append(unit_id)
	run_seed = str(data["seed"]).to_int()
	_rng.seed = run_seed
	_rng.state = str(data["rng_state"]).to_int()
	stage = clampi(int(data["stage"]), 1, rules.stage_count)
	stages_cleared = int(data.get("stages_cleared", stage - 1))
	morale = int(data["morale"])
	gold = int(data["gold"])
	supply = int(data["supply"])
	level = clampi(int(data["level"]), rules.start_level, rules.max_level)
	_shop.set_offers(offers)
	_is_black_market = bool(data.get("black_market", false))
	_free_refreshes = int(data.get("free_refreshes", 0))
	phase = Phase.PREP
	return morale > 0


# --- Internals -----------------------------------------------------------

func _buy(shop_slot: int, bench_slot: int, cell: Vector2i) -> Result:
	if phase != Phase.PREP:
		return Result.WRONG_PHASE
	var unit_id := _shop.get_offer(shop_slot)
	if unit_id == &"":
		return Result.EMPTY_SLOT
	var unit := catalog.get_unit(unit_id)
	if gold < unit.cost:
		return Result.NOT_ENOUGH_GOLD
	var merges := would_merge(unit_id)
	if not merges:
		var target_check := _roster.check_buy_target(unit, bench_slot, cell, get_capacity())
		if target_check != Result.OK:
			return target_check
		if bench_slot == RunPiece.NO_BENCH and cell == RunPiece.NO_CELL:
			bench_slot = _roster.first_free_bench_slot()
	else:
		bench_slot = RunPiece.NO_BENCH
		cell = RunPiece.NO_CELL
	_shop.take(shop_slot)
	_add_gold(-unit.cost)
	var piece := _roster.add(unit_id, 1, bench_slot, cell)
	piece_bought.emit(piece.id, shop_slot)
	_roster.merge_all()
	return Result.OK


func _check_move(piece: RunPiece) -> Result:
	if phase != Phase.PREP:
		return Result.WRONG_PHASE
	return Result.NO_PIECE if piece == null else Result.OK


func _offer_rewards(is_win: bool) -> void:
	_rewards = [Reward.REST, Reward.HUNT, Reward.BLACK_MARKET]
	if is_win:
		return
	if stage >= rules.stage_count:
		# The final stage repeats after a loss: resting there could outpace
		# narrow losses and let the run go on forever.
		_rewards.erase(Reward.REST)
	while _rewards.size() > rules.rewards_after_loss:
		_rewards.remove_at(_rng.randi_range(0, _rewards.size() - 1))


func _begin_prep(with_income: bool) -> void:
	if with_income:
		_add_gold(rules.get_stage_income(stage))
		_add_supply(rules.get_stage_supply(stage))
	_is_black_market = _is_black_market_next
	_is_black_market_next = false
	_free_refreshes = rules.black_market_free_refreshes if _is_black_market else 0
	_roll_shop()
	_set_phase(Phase.PREP)
	stage_started.emit(stage)


func _roll_shop() -> void:
	var roll_level := level
	if _is_black_market:
		roll_level = mini(level + rules.black_market_levels, rules.max_level)
	_shop.roll(roll_level, _rng)
	shop_rolled.emit()


func _set_phase(value: Phase) -> void:
	phase = value
	phase_changed.emit(value)


func _add_gold(delta: int) -> void:
	if delta != 0:
		gold += delta
		gold_changed.emit(gold, delta)


func _add_supply(delta: int) -> void:
	if delta != 0:
		supply += delta
		supply_changed.emit(supply, delta)


func _add_morale(delta: int) -> void:
	if delta != 0:
		morale = clampi(morale + delta, 0, rules.max_morale)
		morale_changed.emit(morale, delta)
