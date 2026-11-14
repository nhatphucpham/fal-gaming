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
## A preparation command succeeded and changed the run (the screen saves it).
signal prep_changed()
## A Kỳ Ngộ fired after the battle: the reward waits for choose_epiphany().
signal epiphany_offered(family: StringName)
signal epiphany_chosen(epiphany_id: StringName)
## A road encounter is waiting for choose_encounter() (phase ENCOUNTER).
signal encounter_offered(encounter_id: StringName)
signal encounter_chosen(encounter_id: StringName, option: int)
## A piece came for free (a road encounter), not from the shop; it may merge
## right after (pieces_merged).
signal piece_gifted(piece_id: int)
## A win in a row paid `gold` more on top of win_gold (before battle_resolved).
signal streak_paid(streak: int, gold: int)
## A road encounter's bet ended with the battle: `gold` paid (0 on a loss).
signal bet_settled(is_win: bool, gold: int)

enum Result { OK, NOT_ENOUGH_GOLD, NOT_ENOUGH_SUPPLY, BENCH_FULL, BOARD_FULL, LEGEND_LIMIT, BAD_TARGET, NO_PIECE, EMPTY_SLOT, MAX_LEVEL, WRONG_PHASE, NOT_OFFERED, EPIPHANY_PENDING, NOT_ENOUGH_MORALE }
## ENCOUNTER: a road encounter waits after the reward, before the next stage.
enum Phase { PREP, BATTLE, REWARD, WON, LOST, ENCOUNTER }
enum Reward { REST, HUNT, BLACK_MARKET, LOOT }

const REWARD_IDS: Array[StringName] = [&"reward.rest", &"reward.hunt", &"reward.black_market", &"reward.loot"]

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
## Kỳ Ngộ meters, thresholds and mutations; read it, change it only through
## the commands here.
var epiphanies: EpiphanyTracker
## Road encounters drawn, pending and the open bet; read it, change it only
## through choose_encounter().
var encounters: EncounterTracker
## Battles won in a row (a loss resets it).
var win_streak: int = 0

var _rng := RandomNumberGenerator.new()
var _roster: RunRoster
var _shop: Shop
var _rewards: Array[Reward] = []
# Black market: this stage's shop rolls as if a level higher, and the first
# refresh is free.
var _is_black_market: bool = false
var _free_refreshes: int = 0
# The black market was taken at a road stage and opens after the encounter.
var _is_black_market_next: bool = false
# Free refreshes a road encounter gave for the next preparation.
var _encounter_refreshes: int = 0


func _init(run_catalog: Catalog, seed_value: int) -> void:
	catalog = run_catalog
	rules = run_catalog.run_rules
	run_seed = seed_value
	_rng.seed = seed_value
	_roster = RunRoster.new(run_catalog, rules)
	_roster.piece_moved.connect(piece_moved.emit)
	_roster.pieces_merged.connect(pieces_merged.emit)
	_shop = Shop.new(run_catalog, rules)
	epiphanies = EpiphanyTracker.new(run_catalog, seed_value)
	encounters = EncounterTracker.new(run_catalog)
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


## The player's Kỳ Ngộ mutations as Synergy overrides (Synergy.evaluate,
## Battle.set_synergy_overrides for side A).
func get_synergy_overrides() -> Array:
	return epiphanies.get_overrides()


## True when a bench slot is free (a free unit from an encounter needs one).
func has_free_bench_slot() -> bool:
	for slot: int in rules.bench_slots:
		if _roster.get_bench_piece(slot) == null:
			return true
	return false


## OK when option 0 or 1 of the pending encounter can be taken now, else
## what the run lacks (EncounterEffects.get_option_refusal).
func get_encounter_refusal(option: int) -> Result:
	var data := encounters.get_pending()
	if phase != Phase.ENCOUNTER or data == null:
		return Result.WRONG_PHASE
	if option < 0 or option >= data.options.size():
		return Result.NOT_OFFERED
	return EncounterEffects.get_option_refusal(self, data.options[option])


## True when this stage's line-up has a boss.
func is_boss_stage() -> bool:
	return stage == rules.boss_stage


# --- Preparation commands ------------------------------------------------

## Buys the unit in `shop_slot` onto the first free bench slot. A full
## bench is fine when the purchase completes a merge at once.
func buy(shop_slot: int) -> Result:
	return _changed_if_ok(_buy(shop_slot, RunPiece.NO_BENCH, RunPiece.NO_CELL))


## Buys the unit in `shop_slot` straight onto a free bench slot or a free
## board cell (one of them set). A purchase that merges ignores the target.
func buy_to(shop_slot: int, bench_slot: int, cell: Vector2i) -> Result:
	return _changed_if_ok(_buy(shop_slot, bench_slot, cell))


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
	return _changed_if_ok(Result.OK)


func buy_supply() -> Result:
	if phase != Phase.PREP:
		return Result.WRONG_PHASE
	if gold < rules.supply_pack_gold:
		return Result.NOT_ENOUGH_GOLD
	_add_gold(-rules.supply_pack_gold)
	_add_supply(rules.supply_pack_amount)
	return _changed_if_ok(Result.OK)


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
	return _changed_if_ok(Result.OK)


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
	return _changed_if_ok(Result.OK)


## Moves a piece onto a board cell (local col, rank), swapping with a piece
## already there. Refused over capacity or past the legend limit.
func move_to_board(piece_id: int, cell: Vector2i) -> Result:
	var piece := _roster.get_piece(piece_id)
	var check := _check_move(piece)
	return check if check != Result.OK else _changed_if_ok(_roster.move_to_board(piece, cell, get_capacity()))


## Moves a piece onto a bench slot, swapping with a piece already there.
func move_to_bench(piece_id: int, slot: int) -> Result:
	var piece := _roster.get_piece(piece_id)
	var check := _check_move(piece)
	return check if check != Result.OK else _changed_if_ok(_roster.move_to_bench(piece, slot))


## The board pieces as buying a shop card of `unit_id` onto local `cell`
## (buy_to() with no bench slot) or, with an empty `unit_id`, as
## move_to_board(piece_id, cell) would leave them: worked out on a copy of
## the roster with the same rules (merges, capacity, legend limit). Fills
## `board` (copies) when the command would succeed; returns its Result.
func preview_board(piece_id: int, unit_id: StringName, cell: Vector2i, board: Array[RunPiece]) -> Result:
	board.clear()
	if phase != Phase.PREP:
		return Result.WRONG_PHASE
	var roster := _roster.copy()
	var result := Result.OK
	if unit_id != &"":
		var unit := catalog.get_unit(unit_id)
		if unit == null:
			return Result.NOT_OFFERED
		if gold < unit.cost:
			return Result.NOT_ENOUGH_GOLD
		var target := roster.resolve_buy_target(unit, RunPiece.NO_BENCH, cell, get_capacity())
		result = target[0]
		if result == Result.OK:
			roster.add(unit_id, 1, target[1], target[2])
			roster.merge_all()
	else:
		var piece := roster.get_piece(piece_id)
		result = Result.NO_PIECE if piece == null else roster.move_to_board(piece, cell, get_capacity())
	if result == Result.OK:
		board.assign(roster.get_board_pieces())
	return result


# --- Battle and reward ---------------------------------------------------

## Ends the preparation: every board piece now counts as having fought.
func begin_battle() -> Result:
	if phase != Phase.PREP:
		return Result.WRONG_PHASE
	for piece: RunPiece in _roster.get_board_pieces():
		piece.has_fought = true
	_set_phase(Phase.BATTLE)
	return Result.OK


## Applies a battle result: `enemies_alive` living enemy units at the end,
## `piece_damage` the damage each board piece dealt (piece id to amount)
## for the Kỳ Ngộ meters. Moves to REWARD (maybe with a pending Kỳ Ngộ), or
## ends the run (WON or LOST).
func finish_battle(is_win: bool, enemies_alive: int, piece_damage: Dictionary = {}) -> Result:
	if phase != Phase.BATTLE:
		return Result.WRONG_PHASE
	var morale_delta := 0
	win_streak = win_streak + 1 if is_win else 0
	if is_win:
		stages_cleared += 1
		_add_gold(rules.win_gold)
		_add_supply(rules.win_supply)
		var bonus := rules.get_streak_bonus(win_streak)
		if bonus > 0:
			_add_gold(bonus)
			streak_paid.emit(win_streak, bonus)
	else:
		morale_delta = -(rules.loss_morale_base + rules.loss_morale_per_enemy * maxi(0, enemies_alive))
		_add_morale(morale_delta)
	if encounters.get_bet_gold() > 0:
		var paid := encounters.settle_bet(is_win)
		_add_gold(paid)
		bet_settled.emit(is_win, paid)
	battle_resolved.emit(is_win, rules.win_gold if is_win else 0, rules.win_supply if is_win else 0, morale_delta)
	if morale <= 0:
		_set_phase(Phase.LOST)
	elif is_win and stage >= rules.stage_count:
		_set_phase(Phase.WON)
	else:
		_offer_rewards(is_win)
		var families := EpiphanyBattle.read_families(self, piece_damage)
		var fired := epiphanies.record_battle(stage, families["active"], families["damage"], is_win, _rng)
		_set_phase(Phase.REWARD)
		if fired:
			epiphany_offered.emit(epiphanies.get_pending_family())
	return Result.OK


## Takes option 0 or 1 of the pending Kỳ Ngộ; it lasts the rest of the run.
func choose_epiphany(option: int) -> Result:
	if phase != Phase.REWARD:
		return Result.WRONG_PHASE
	if not epiphanies.has_pending():
		return Result.NOT_OFFERED
	var id: StringName = epiphanies.get_pending_options()[option].id if option >= 0 and option < 2 else &""
	if not epiphanies.choose(option):
		return Result.NOT_OFFERED
	epiphany_chosen.emit(id)
	return Result.OK


## Takes one of the offered rewards. Then a road encounter may wait (phase
## ENCOUNTER, encounter_offered); otherwise the next stage's preparation
## begins (stage 12 repeats after a loss, without gold or supply income).
func choose_reward(reward: Reward) -> Result:
	if phase != Phase.REWARD:
		return Result.WRONG_PHASE
	if epiphanies.has_pending():
		return Result.EPIPHANY_PENDING
	if not _rewards.has(reward):
		return Result.NOT_OFFERED
	match reward:
		Reward.REST:
			_add_morale(mini(rules.rest_morale, rules.max_morale - morale))
		Reward.HUNT:
			_add_supply(rules.hunt_supply)
		Reward.BLACK_MARKET:
			_is_black_market_next = true
		Reward.LOOT:
			_add_gold(rules.loot_gold)
	_rewards.clear()
	if stage < rules.stage_count and encounters.is_due(stage):
		var data := encounters.draw(_rng)
		_set_phase(Phase.ENCOUNTER)
		encounter_offered.emit(data.id)
		return Result.OK
	_begin_next_stage()
	return Result.OK


## Takes option 0 or 1 of the pending road encounter, applies its effects
## in order, then begins the next stage's preparation. A refused option
## (see get_encounter_refusal) changes nothing.
func choose_encounter(option: int) -> Result:
	var refusal := get_encounter_refusal(option)
	if refusal != Result.OK:
		return refusal
	var data := encounters.get_pending()
	encounters.take(option)
	var handlers := _get_effect_handlers()
	for effect: EncounterEffect in data.options[option].effects:
		handlers[effect.kind].call(effect.amount)
	encounter_chosen.emit(data.id, option)
	_begin_next_stage()
	return Result.OK


# --- Save ----------------------------------------------------------------

## Everything needed to continue this run from its preparation or its
## reward choice, as JSON-safe data. 64-bit numbers are strings: JSON
## numbers are doubles.
func to_save_data() -> Dictionary:
	return {
		"seed": str(run_seed), "rng_state": str(_rng.state), "phase": RunSaveFields.get_phase_name(phase),
		"stage": stage, "stages_cleared": stages_cleared, "morale": morale, "gold": gold,
		"supply": supply, "level": level, "next_piece_id": _roster.get_next_id(),
		"pieces": _roster.to_save_data(), "shop": _shop.get_offers().map(func(id: StringName) -> String: return String(id)),
		"black_market": _is_black_market, "black_market_next": _is_black_market_next,
		"free_refreshes": _free_refreshes, "rewards": _rewards.map(func(reward: Reward) -> String: return String(REWARD_IDS[reward])),
		"epiphany": epiphanies.to_save_data(),
		"encounter": encounters.to_save_data(), "win_streak": win_streak,
	}


## True in the phases a save can hold (PREP, REWARD and ENCOUNTER).
func can_save() -> bool:
	return RunSaveFields.PHASES.values().has(phase)


## Restores a run saved by to_save_data() into its preparation or reward
## choice. False (and nothing usable) when a field is missing, of the wrong
## type or out of range, or the pieces or offers break a rule (see
## Docs/systems/run.md).
func load_save_data(data: Dictionary) -> bool:
	var fields := RunSaveFields.read(data, catalog)
	if fields.is_empty() or not _roster.load_save_data(fields["pieces"], fields["next_piece_id"], rules.get_capacity(fields["level"])):
		return false
	epiphanies = EpiphanyTracker.new(catalog, fields["seed"])
	if not epiphanies.load_save_data(data.get("epiphany"), fields["phase"], fields["stage"]):
		return false
	encounters = EncounterTracker.new(catalog)
	if not encounters.load_save_data(data.get("encounter"), fields["phase"], fields["stage"]) or fields["win_streak"] > fields["stages_cleared"]:
		return false
	stage = fields["stage"]
	stages_cleared = fields["stages_cleared"]
	morale = fields["morale"]
	gold = fields["gold"]
	supply = fields["supply"]
	level = fields["level"]
	run_seed = fields["seed"]
	_rng.seed = run_seed
	_rng.state = fields["rng_state"]
	_shop.set_offers(fields["shop"])
	_is_black_market = fields["black_market"]
	_is_black_market_next = fields["black_market_next"]
	win_streak = fields["win_streak"]
	# Only a black-market stage or the stage after an encounter has free
	# refreshes, and never more than they give.
	var most_refreshes := (rules.black_market_free_refreshes if _is_black_market else 0) + encounters.get_free_refresh_allowance(stage)
	_free_refreshes = clampi(fields["free_refreshes"], 0, most_refreshes)
	_rewards.assign(fields["rewards"])
	phase = fields["phase"]
	return true


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
	var target := _roster.resolve_buy_target(unit, bench_slot, cell, get_capacity())
	if target[0] != Result.OK:
		return target[0]
	_shop.take(shop_slot)
	_add_gold(-unit.cost)
	var piece := _roster.add(unit_id, 1, target[1], target[2])
	piece_bought.emit(piece.id, shop_slot)
	_roster.merge_all()
	return Result.OK


func _check_move(piece: RunPiece) -> Result:
	if phase != Phase.PREP:
		return Result.WRONG_PHASE
	return Result.NO_PIECE if piece == null else Result.OK


func _changed_if_ok(result: Result) -> Result:
	if result == Result.OK:
		prep_changed.emit()
	return result


# Drawn from all rewards: rewards_after_win cards after a win,
# rewards_after_loss after a loss.
func _offer_rewards(is_win: bool) -> void:
	_rewards = [Reward.REST, Reward.HUNT, Reward.BLACK_MARKET, Reward.LOOT]
	if not is_win and stage >= rules.stage_count:
		# The final stage repeats after a loss: resting there could outpace
		# narrow losses and let the run go on forever.
		_rewards.erase(Reward.REST)
	while _rewards.size() > (rules.rewards_after_win if is_win else rules.rewards_after_loss):
		_rewards.remove_at(_rng.randi_range(0, _rewards.size() - 1))


# One handler per EncounterEffects kind, called with the effect's amount.
# Built per call: kept in a member, the lambdas would hold the run alive.
func _get_effect_handlers() -> Dictionary[StringName, Callable]:
	return {
		EncounterEffects.GOLD: _add_gold, EncounterEffects.SUPPLY: _add_supply,
		EncounterEffects.MORALE: func(amount: int) -> void: _add_morale(mini(amount, rules.max_morale - morale)),
		EncounterEffects.FREE_UNIT: _gift_unit,
		EncounterEffects.FREE_REFRESHES: func(amount: int) -> void: _encounter_refreshes += amount,
		EncounterEffects.BET: encounters.place_bet,
	}


func _begin_next_stage() -> void:
	var is_repeat := stage >= rules.stage_count
	if not is_repeat:
		stage += 1
	_begin_prep(not is_repeat)


# A random unit of cost `cost` onto the first free bench slot (the option
# was refused without one), merging if it completes copies.
func _gift_unit(cost: int) -> void:
	var pool: Array[UnitData] = []
	for unit: UnitData in catalog.units:
		if unit.cost == cost and not unit.is_boss:
			pool.append(unit)
	if pool.is_empty():
		push_error("Run: no unit of cost %d to give" % cost)
		return
	var unit := pool[_rng.randi_range(0, pool.size() - 1)]
	var target := _roster.resolve_buy_target(unit, RunPiece.NO_BENCH, RunPiece.NO_CELL, get_capacity())
	if target[0] != Result.OK:
		push_error("Run: no room for the free unit %s" % unit.id)
		return
	var piece := _roster.add(unit.id, 1, target[1], target[2])
	piece_gifted.emit(piece.id)
	_roster.merge_all()


func _begin_prep(with_income: bool) -> void:
	if with_income:
		_add_gold(rules.get_stage_income(stage))
		_add_supply(rules.get_stage_supply(stage))
	_is_black_market = _is_black_market_next
	_is_black_market_next = false
	_free_refreshes = (rules.black_market_free_refreshes if _is_black_market else 0) + _encounter_refreshes
	_encounter_refreshes = 0
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
