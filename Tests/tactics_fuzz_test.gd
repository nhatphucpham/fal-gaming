extends SceneTree

# Random-command test of the tactics simulation. Each seed builds a random
# map and random leaders (sample ones and altered copies), then sends a mix
# of legal and illegal commands and checks after each one: queries and
# refused commands leave the hash unchanged, a command is accepted exactly
# when its query said so (can_move, can_act, get_attack_targets,
# get_skill_cells), the move follows get_path_to() and preview_squad(),
# the attack lands what forecast_engagement() said, a skill what
# preview_skill() said, the
# events account for every cell, hp and charge change, one unit per cell,
# battle_ended is last, and a replay of the commands gives the same hashes.
# Strikes (get_strike_cell, then a move there and the attack) land what
# forecast_move_attack() said. Leaders often move several times in a row
# (the turn stays open until "Chờ"): no unit walks more cells in a phase
# than its move points, its points left only go down, and no soldier
# strikes twice in a phase. Undo is a stack: it is offered exactly while
# the leader's plain human moves since its last other command are not all
# taken back (a move that shows an enemy, or passes one in sight, cannot
# be), and each undo gives back the hash from before that move and
# every query from before it too (units, incident seeds and stages, karma,
# the report, intents, zones). A second replay leaves out each undone move
# (and the refused commands between it and its undo): every later command
# must give the same events and hash, so nothing outside the hash (the
# incident generator, event ids) differs after an undo either.
# Every other seed plays with incidents, most soldiers seeded with a random
# one: the events must account for flights and defections too. Every third
# seed plays under fog of war with a weather (turning on some) and times of
# day: a walk may stop at an ambush, and the rest must hold as well.

const Kit := preload("res://Tests/tactics_test_kit.gd")
const SEED_COUNT: int = 24
const MAX_COMMANDS: int = 160
const LEADERS: Array[StringName] = [
	&"leader.lac_hong", &"leader.moon_spear", &"leader.lieu_mi", &"leader.ba_khac", &"leader.thiet_nha",
]
const ORDERS: Array[StringName] = [&"order.follow", &"order.vanguard", &"order.flank", &"order.hold", &"order.free"]
const CHARGES: Array[StringName] = [
	&"charge.turns", &"charge.engagements", &"charge.focus", &"charge.damage_taken", &"charge.soldiers_lost",
]
const INCIDENTS: Array[StringName] = [
	&"incident.rescue", &"incident.stand", &"incident.surge", &"incident.discontent", &"incident.riot", &"incident.flee", &"incident.betray",
]
## Map symbols drawn for each cell; plain is the most common.
const MAP_SYMBOLS: String = "........................fffhhhrrddbtv"

var _kit := Kit.new()
var _rng := RandomNumberGenerator.new()
var _failures: Array[String] = []
var _seed: int = 0
## Per unit: the cell, hp, alive and charge the events so far add up to.
var _model: Dictionary = {}
var _zone_count: int = 0
## Incident events seen over all seeds, by type.
var _incident_counts: Dictionary = {}
## Sight and sky events seen on the fog seeds.
var _sight_counts: Dictionary = {}
## The moves that can still be taken back, the last on top: each
## {hash, snapshot, index, budget} from before the move; and whose they are.
var _undo_stack: Array[Dictionary] = []
var _undo_leader: int = -1
## Per unit of the human side: move points it may still walk in this turn
## (cells), from its points at the turn's first command; and that turn.
var _budget: Dictionary = {}
var _budget_turn: int = -1
## [turn, unit] pairs that struck, to catch a second strike in a phase.
var _soldier_strikes: Dictionary = {}
## [first, last] command indexes of each undone move and its undo.
var _undone_spans: Array = []
var _command_index: int = 0
var _undos: int = 0
## The leader the last command moved, else -1 (an undo is likelier next).
var _last_moved: int = -1
var _strikes: int = 0
## The most moves of one leader taken back one by one in a row.
var _deepest_undo: int = 0


func _initialize() -> void:
	if not _kit.load_catalog():
		quit(1)
		return
	# Refused commands are part of the test; their errors would flood the log.
	Engine.print_error_messages = false
	for seed_value: int in range(1, SEED_COUNT + 1):
		_seed = seed_value
		_run_seed()
		_kit.free_battles()
	Engine.print_error_messages = true
	for failure: String in _failures.slice(0, 20):
		printerr("Tactics fuzz test: %s" % failure)
	print("Tactics fuzz test: incident events %s, %d strikes, %d undos (up to %d moves deep)" % [_incident_counts, _strikes, _undos, _deepest_undo])
	print("Tactics fuzz test: sight events %s" % _sight_counts)
	for type: StringName in [&"vision_changed", &"weather_changed", &"daytime_changed"]:
		if _sight_counts.get(type, 0) == 0:
			_failures.append("no %s on any fog seed" % type)
	if _incident_counts.get(&"incident_fired", 0) == 0:
		_failures.append("no incident fired on any seed")
	if _deepest_undo < 3:
		_failures.append("no leader had three moves to take back one by one")
	if _failures.is_empty():
		print("Tactics fuzz test passed")
		quit(0)
	else:
		quit(1)


func _fail(what: String) -> void:
	_failures.append("seed %d: %s" % [_seed, what])


func _run_seed() -> void:
	_rng.seed = _seed
	var rows := _random_rows(_rng.randi_range(6, 12), _rng.randi_range(6, 12))
	var objective := Vector2i(-1, -1)
	if _rng.randf() < 0.3:
		objective = Vector2i(_rng.randi_range(0, rows[0].length() - 1), _rng.randi_range(0, rows.size() - 1))
	var ai_sides: Array[bool] = [_rng.randf() < 0.1, _rng.randf() < 0.6]
	var battle := _new_battle(rows, objective, ai_sides)
	var placements: Array = _place_leaders(battle, rows)
	var seeds := _plant_incidents(battle)
	_reset_model(battle)
	var events := battle.start()
	if events.is_empty():
		return
	_apply_model(battle, events)
	var commands: Array = []
	var hashes: Array[String] = []
	var event_texts: Array[String] = []
	_undone_spans.clear()
	_undo_stack.clear()
	_undo_leader = -1
	_budget.clear()
	_budget_turn = -1
	_soldier_strikes.clear()
	while commands.size() < MAX_COMMANDS and not battle.is_finished():
		_command_index = commands.size()
		var before := battle.get_state_hash()
		_check_queries(battle)
		if battle.get_state_hash() != before:
			_fail("queries changed the hash before command %d" % commands.size())
		_note_turn(battle)
		var command := _pick_command(battle)
		events = _run_checked(battle, command)
		_note_undo_stack(battle, command, events)
		if events.is_empty() and battle.get_state_hash() != before and command[0] != &"undo":
			_fail("refused %s changed the hash" % [command])
		_check_events(battle, events)
		_apply_model(battle, events)
		_check_board(battle)
		commands.append(command)
		hashes.append(battle.get_state_hash())
		event_texts.append(var_to_str(events))
	if battle.is_finished():
		_check_nothing_after_end(battle)
	_replay_without_undone(rows, objective, ai_sides, placements, seeds, commands, hashes, event_texts)
	var replay := _new_battle(rows, objective, ai_sides)
	for placement: Array in placements:
		replay.add_leader(placement[0], placement[1], placement[2])
	_apply_incidents(replay, seeds)
	replay.start()
	for index: int in commands.size():
		_run(replay, commands[index])
		if replay.get_state_hash() != hashes[index]:
			_fail("replay differs after command %d %s" % [index, commands[index]])
			return


## Replays the commands without the undone moves (and what lay between each
## one and its undo): from each undo on, the same events and hashes.
func _replay_without_undone(rows: PackedStringArray, objective: Vector2i, ai_sides: Array[bool], placements: Array, seeds: Array, commands: Array, hashes: Array[String], event_texts: Array[String]) -> void:
	if _undone_spans.is_empty():
		return
	var skipped: Dictionary = {}
	for span: Array in _undone_spans:
		for index: int in range(span[0], span[1] + 1):
			skipped[index] = true
	var replay := _new_battle(rows, objective, ai_sides)
	for placement: Array in placements:
		replay.add_leader(placement[0], placement[1], placement[2])
	_apply_incidents(replay, seeds)
	replay.start()
	for index: int in commands.size():
		if skipped.has(index):
			continue
		var events := _run(replay, commands[index])
		if index > _undone_spans[0][1] and (replay.get_state_hash() != hashes[index] or var_to_str(events) != event_texts[index]):
			_fail("without the undone moves, command %d %s gives other %s" % [index, commands[index], "events" if replay.get_state_hash() == hashes[index] else "hash"])
			return


## Every query's answer that must come back with an undo.
func _snapshot(battle: TacticsBattle) -> Dictionary:
	return {
		"units": var_to_str(battle.get_units()),
		"zones": var_to_str(battle.get_zones()),
		"seeds": var_to_str(battle.get_incident_seeds()),
		"karma": var_to_str([battle.get_karma(TacticsBattle.SIDE_A), battle.get_karma(TacticsBattle.SIDE_B)]),
		"report": var_to_str(battle.get_battle_report()),
		"intents": var_to_str(battle.get_enemy_intents()),
		"round": [battle.get_round(), battle.get_turn(), battle.get_active_side()],
	}


## The path of `leader` to `cell` passes a cell an enemy it does not see
## stands on.
func _crosses_unseen(battle: TacticsBattle, leader: int, cell: Vector2i) -> bool:
	var side: int = battle.get_unit_state(leader)["side"]
	for step: Vector2i in battle.get_path_to(leader, cell):
		for unit: Dictionary in battle.get_units():
			if unit["alive"] and unit["side"] != side and unit["cell"] == step and not battle.is_unit_seen(side, unit["index"]):
				return true
	return false


## On even seeds: incident rules and a random incident on most soldiers;
## returns [unit, incident] pairs ([[-1]] for incidents without forced
## seeds, [] without incidents) so the replay can do the same.
func _plant_incidents(battle: TacticsBattle) -> Array:
	if _seed % 2 != 0:
		return []
	var seeds: Array = [[-1]]
	for unit: Dictionary in battle.get_units():
		if unit["role"] == &"soldier" and _rng.randf() < 0.7:
			seeds.append([unit["index"], INCIDENTS[_rng.randi_range(0, INCIDENTS.size() - 1)]])
	_apply_incidents(battle, seeds)
	return seeds


func _apply_incidents(battle: TacticsBattle, seeds: Array) -> void:
	if seeds.is_empty():
		return
	battle.set_incident_rules(_kit.catalog.incident_rules, _seed)
	for pair: Array in seeds.slice(1):
		battle.set_incident_seed(pair[0], pair[1])


func _random_rows(width: int, height: int) -> PackedStringArray:
	var rows := PackedStringArray()
	for row: int in height:
		var line := ""
		for col: int in width:
			line += MAP_SYMBOLS[_rng.randi_range(0, MAP_SYMBOLS.length() - 1)]
		rows.append(line)
	return rows


func _new_battle(rows: PackedStringArray, objective: Vector2i, ai_sides: Array[bool]) -> TacticsBattle:
	var battle := _kit.new_battle(rows, ai_sides[1], null, objective)
	battle.set_side_ai(TacticsBattle.SIDE_A, ai_sides[0])
	var environment := _environment()
	if environment != null and not battle.set_environment(environment):
		_fail("the environment was refused")
	return battle


## On every third seed: fog of war, a weather (that may turn) and a cycle
## of times of day, all picked from the seed alone so a replay has the same.
func _environment() -> TacticsScenarioData:
	if _seed % 3 != 0:
		return null
	var weathers: Array[StringName] = [&"weather.clear", &"weather.rain", &"weather.fog", &"weather.wind"]
	var scenario := TacticsScenarioData.new()
	scenario.id = &"scenario.fuzz"
	scenario.fog_of_war = true
	scenario.weather = _kit.catalog.get_weather(weathers[_seed % weathers.size()])
	if _seed % 2 == 0:
		scenario.weather_change_round = 2 + _seed % 3
		scenario.weather_after = _kit.catalog.get_weather(weathers[(_seed + 1 + _seed / 3) % weathers.size()])
	var cycle: Array[TacticsDaytimeData] = [_kit.catalog.get_daytime(&"daytime.night"), _kit.catalog.get_daytime(&"daytime.day"), _kit.catalog.get_daytime(&"daytime.dusk")]
	scenario.daytimes = cycle
	scenario.daytime_start_index = _seed % cycle.size()
	scenario.daytime_step_rounds = 1 + _seed % 2
	return scenario


## Adds 1 to 3 leaders per side on random cells; returns [side, data, cell]
## for each one that was placed.
func _place_leaders(battle: TacticsBattle, rows: PackedStringArray) -> Array:
	var placements: Array = []
	for side: int in 2:
		var wanted := _rng.randi_range(1, 3)
		var placed := 0
		for attempt: int in 40:
			if placed == wanted:
				break
			var data := _random_leader()
			var cell := Vector2i(_rng.randi_range(0, rows[0].length() - 1), _rng.randi_range(0, rows.size() - 1))
			var symbol := rows[cell.y][cell.x]
			if _kit.catalog.get_terrain(Kit.TERRAIN_IDS[Kit.SYMBOLS.find(symbol)]).is_impassable or _unit_at(battle, cell) >= 0:
				continue
			if battle.add_leader(side, data, cell) >= 0:
				placements.append([side, data, cell])
				placed += 1
	return placements


## A sample leader, or a copy with random passives, skill charge, keywords,
## ranges, move points, order and squad.
func _random_leader() -> TacticsLeaderData:
	var data := _kit.catalog.get_leader(LEADERS[_rng.randi_range(0, LEADERS.size() - 1)])
	if _rng.randf() < 0.4:
		return data
	data = data.duplicate() as TacticsLeaderData
	var pool: Array = _kit.catalog.passives.duplicate()
	var passives: Array[TacticsPassiveData] = []
	for index: int in _rng.randi_range(1, 3):
		passives.append(pool.pop_at(_rng.randi_range(0, pool.size() - 1)))
	data.passives = passives
	var skill := _kit.catalog.skills[_rng.randi_range(0, _kit.catalog.skills.size() - 1)].duplicate() as TacticsSkillData
	skill.charge_threshold = 1 if _rng.randf() < 0.6 else skill.charge_threshold
	skill.charge = CHARGES[_rng.randi_range(0, CHARGES.size() - 1)] if _rng.randf() < 0.5 else skill.charge
	data.skill = skill
	var keywords: Array[TacticsKeywordData] = []
	for keyword: TacticsKeywordData in _kit.catalog.keywords:
		if _rng.randf() < 0.2:
			keywords.append(keyword)
	data.keywords = keywords
	data.min_range_cells = _rng.randi_range(1, 2)
	data.max_range_cells = data.min_range_cells + _rng.randi_range(0, 2)
	data.move_points = _rng.randi_range(0, 6)
	data.default_order = ORDERS[_rng.randi_range(0, ORDERS.size() - 1)]
	var squad: Array[TacticsTroopData] = []
	for index: int in _rng.randi_range(0, 3):
		squad.append(_kit.catalog.troops[_rng.randi_range(0, _kit.catalog.troops.size() - 1)])
	data.squad = squad
	return data


func _unit_at(battle: TacticsBattle, cell: Vector2i) -> int:
	for unit: Dictionary in battle.get_units():
		if unit["alive"] and unit["cell"] == cell:
			return unit["index"]
	return -1


## A command for a random leader of the active side (now and then another
## unit, a dead leader or a cell off the map), mostly picked from queries.
func _pick_command(battle: TacticsBattle) -> Array:
	var moved := _last_moved
	_last_moved = -1
	if moved >= 0 and _rng.randf() < 0.3:
		return [&"undo", moved, null]
	# The turn stays open after a move: often the same leader moves on.
	if moved >= 0 and _rng.randf() < 0.45 and not battle.get_reachable_cells(moved).is_empty():
		var next_cells: Array = battle.get_reachable_cells(moved)
		return [&"move", moved, next_cells[_rng.randi_range(0, next_cells.size() - 1)]]
	var leaders: Array[int] = []
	for unit: Dictionary in battle.get_units():
		if unit["role"] == &"leader" and unit["side"] == battle.get_active_side() and (unit["alive"] or _rng.randf() < 0.1):
			leaders.append(unit["index"])
	var any_unit := _rng.randi_range(0, battle.get_unit_count() - 1)
	var leader: int = any_unit if leaders.is_empty() or _rng.randf() < 0.03 else leaders[_rng.randi_range(0, leaders.size() - 1)]
	var off_map := Vector2i(_rng.randi_range(-1, battle.get_map_width()), _rng.randi_range(-1, battle.get_map_height()))
	var is_leader: bool = battle.get_unit_state(leader)["role"] == &"leader"
	var roll := _rng.randf()
	if is_leader and battle.get_skill_charge(leader)["is_ready"] and _rng.randf() < 0.6:
		roll = 0.6
	if roll < 0.32:
		var cells: Array = battle.get_reachable_cells(leader)
		return [&"move", leader, cells[_rng.randi_range(0, cells.size() - 1)] if not cells.is_empty() and _rng.randf() < 0.85 else off_map]
	if roll < 0.55:
		var targets: Array[int] = []
		for unit: int in battle.get_unit_count():
			if battle.forecast_engagement(leader, unit)["is_valid"]:
				targets.append(unit)
		return [&"attack", leader, targets[_rng.randi_range(0, targets.size() - 1)] if not targets.is_empty() and _rng.randf() < 0.85 else any_unit]
	if roll < 0.67:
		var skill_cells: Array = battle.get_skill_cells(leader)
		if not skill_cells.is_empty() and _rng.randf() < 0.5:
			return [&"skill", leader, skill_cells[_rng.randi_range(0, skill_cells.size() - 1)]]
		var own: Vector2i = battle.get_unit_state(leader)["cell"]
		var cells: Array[Vector2i] = [own]
		for unit: Dictionary in battle.get_units():
			var cell: Vector2i = unit["cell"]
			if unit["alive"] and absi(cell.x - own.x) + absi(cell.y - own.y) <= 4:
				cells.append(cell)
		return [&"skill", leader, cells[_rng.randi_range(0, cells.size() - 1)] if _rng.randf() < 0.85 else off_map]
	if roll < 0.69:
		return [&"wait", leader, null]
	if roll < 0.71:
		return [&"undo", leader, null]
	if roll < 0.79 and is_leader:
		var strike_targets: Array = battle.get_strike_targets(leader)
		var target: int = strike_targets[_rng.randi_range(0, strike_targets.size() - 1)] if not strike_targets.is_empty() else any_unit
		return [&"strike", leader, target, battle.get_strike_cell(leader, target)]
	if roll < 0.83:
		return [&"order", leader, ORDERS[_rng.randi_range(0, ORDERS.size() - 1)]]
	return [&"end_phase", -1, null]


func _run(battle: TacticsBattle, command: Array) -> Array:
	match command[0]:
		&"move":
			return battle.move_leader(command[1], command[2])
		&"attack":
			return battle.attack(command[1], command[2])
		&"skill":
			return battle.use_skill(command[1], command[2])
		&"wait":
			return battle.wait(command[1])
		&"order":
			return battle.set_order(command[1], command[2])
		&"undo":
			battle.undo_move(command[1])
			return []
		&"strike":
			return _strike(battle, command[1], command[2], command[3])
		_:
			return battle.end_phase()


## A move to the strike cell (unless the leader stands on it) and the attack.
func _strike(battle: TacticsBattle, leader: int, target: int, cell: Vector2i) -> Array:
	if cell == Vector2i(-1, -1):
		return []
	var events: Array = []
	if cell != battle.get_unit_state(leader)["cell"]:
		events = battle.move_leader(leader, cell).duplicate()
		if events.is_empty():
			return []
	if not battle.is_finished() and battle.get_unit_state(target)["alive"]:
		events.append_array(battle.attack(leader, target))
	return events


## Runs the command and checks it against what the queries said before.
func _run_checked(battle: TacticsBattle, command: Array) -> Array:
	if command[0] == &"undo":
		return _run_undo(battle, command[1])
	if command[0] == &"strike":
		return _run_strike(battle, command)
	if command[0] == &"end_phase":
		var ended := battle.end_phase()
		if ended.is_empty():
			_fail("end_phase refused in a running battle")
		return ended
	var unit: int = command[1]
	var state := battle.get_unit_state(unit)
	var is_commandable: bool = state["role"] == &"leader" and state["alive"] and state["side"] == battle.get_active_side()
	var can_act: bool = is_commandable and not state["has_waited"]
	var can_attack: bool = can_act and not state["has_attacked"]
	var expected := true
	var path: Array = []
	var preview: Array = []
	var forecast: Dictionary = {}
	var is_ready := false
	var skill_preview: Dictionary = {}
	_check_turn_queries(battle, unit, state, can_act, can_attack)
	match command[0]:
		&"move":
			expected = can_act and battle.get_reachable_cells(unit).has(command[2])
			path = battle.get_path_to(unit, command[2])
			preview = battle.preview_squad(unit, command[2]) if expected else []
		&"attack":
			forecast = battle.forecast_engagement(unit, command[2])
			expected = can_attack and forecast["is_valid"]
			if battle.get_attack_targets(unit).has(command[2]) != expected:
				_fail("get_attack_targets(%d) disagrees about %d" % [unit, command[2]])
		&"skill":
			is_ready = state["role"] == &"leader" and battle.get_skill_charge(unit)["is_ready"]
			expected = battle.get_skill_cells(unit).has(command[2])
			skill_preview = battle.preview_skill(unit, command[2])
			if skill_preview["is_valid"] != expected:
				_fail("preview_skill(%d, %s) is %s, get_skill_cells() says %s" % [unit, command[2], skill_preview["is_valid"], expected])
		_:
			expected = can_act
	var hash_before := battle.get_state_hash()
	var snapshot := _snapshot(battle) if command[0] == &"move" else {}
	var known_before := _known_enemies(battle, unit) if command[0] == &"move" else {}
	var events := _run(battle, command)
	if command[0] == &"move" and not events.is_empty():
		_last_moved = unit
		var is_plain := not battle.is_finished() and not battle.is_side_ai(state["side"])
		# Cells coming into sight keep it plain; an enemy coming into sight,
		# one passed in sight (or an ambush) does not.
		for event: Dictionary in events:
			is_plain = is_plain and event["type"] in [&"unit_moved", &"skill_charge_changed", &"vision_changed"]
		var is_learned := _has_learned(known_before, _known_enemies(battle, unit))
		is_plain = is_plain and not is_learned
		if battle.can_undo_move(unit) != is_plain:
			_fail("after %s can_undo_move is %s, the move was plain=%s" % [command, battle.can_undo_move(unit), is_plain])
		if is_plain:
			var step := {"hash": hash_before, "snapshot": snapshot, "index": _command_index, "budget": _budget.duplicate(), "below": _undo_stack.duplicate(), "below_leader": _undo_leader}
			if _undo_leader != unit:
				_undo_stack.clear()
			_undo_leader = unit
			_undo_stack.append(step)
		else:
			_undo_stack.clear()
	if command[0] == &"skill":
		if not events.is_empty() and not (can_act and is_ready and not state["has_cast"]):
			_fail("%s accepted without a ready skill or with the leader done" % [command])
		if events.is_empty() == expected:
			_fail("%s accepted %s, get_skill_cells() said %s" % [command, not events.is_empty(), expected])
		if not events.is_empty():
			_check_skill(events, skill_preview)
		return events
	if events.is_empty() == expected:
		_fail("%s accepted %s, expected %s" % [command, not events.is_empty(), expected])
	if events.is_empty():
		return events
	if command[0] == &"move":
		# The path and the squad preview are planned with what the side
		# knows; a walk that learns more may end otherwise.
		if not _has_learned(known_before, _known_enemies(battle, unit)):
			_check_move(battle, events, path, preview)
	elif command[0] == &"attack":
		_check_engagement(events, forecast)
	return events


## Where the mover's side knows each enemy: {unit: [is_seen, cell]}, the
## cell it is seen on, else where it was last seen.
func _known_enemies(battle: TacticsBattle, mover: int) -> Dictionary:
	var side: int = battle.get_unit_state(mover)["side"]
	var known := {}
	for ghost: Dictionary in battle.get_last_seen(side):
		known[ghost["unit"]] = [false, ghost["cell"]]
	for unit: int in battle.get_unit_count():
		var state := battle.get_unit_state(unit)
		if state["alive"] and state["side"] != side and battle.is_unit_seen(side, unit):
			known[unit] = [true, state["cell"]]
	return known


## The side sees an enemy it did not, or remembers one somewhere new.
func _has_learned(before: Dictionary, after: Dictionary) -> bool:
	for unit: int in after:
		var was: Array = before.get(unit, [false, Vector2i(-1, -1)])
		if after[unit][0] and not was[0]:
			return true
		if not after[unit][0] and after[unit][1] != was[1]:
			return true
	return false


## An undo: taken exactly when can_undo_move said so, back to the hash
## before that move; the event model starts again from the battle.
func _run_undo(battle: TacticsBattle, unit: int) -> Array:
	var expected := battle.can_undo_move(unit)
	var is_undone := battle.undo_move(unit)
	if is_undone != expected:
		_fail("undo_move(%d) gave %s, can_undo_move said %s" % [unit, is_undone, expected])
	if is_undone != (unit == _undo_leader and not _undo_stack.is_empty()):
		_fail("undo_move(%d) gave %s with %d moves of %d to take back" % [unit, is_undone, _undo_stack.size(), _undo_leader])
	if is_undone and not _undo_stack.is_empty():
		_undos += 1
		_deepest_undo = maxi(_deepest_undo, _undo_stack.size())
		var step: Dictionary = _undo_stack.pop_back()
		if battle.get_state_hash() != step["hash"]:
			_fail("undo_move(%d) did not give back the hash before the move" % unit)
		var before: Dictionary = step["snapshot"]
		var after := _snapshot(battle)
		for key: String in after:
			if before.get(key) != after[key]:
				_fail("undo_move(%d) did not give back the %s from before the move" % [unit, key])
		_undone_spans.append([step["index"], _command_index])
		_budget = step["budget"]
		# The state before that move: the steps back it had come back too.
		_undo_stack.assign(step["below"])
		_undo_leader = step["below_leader"]
		var can_undo_more: bool = _undo_leader == unit and not _undo_stack.is_empty()
		if battle.can_undo_move(unit) != can_undo_more:
			_fail("after an undo can_undo_move(%d) is %s with %d moves left" % [unit, battle.can_undo_move(unit), _undo_stack.size()])
		_reset_model(battle)
		_zone_count = battle.get_zones().size()
	return []


## A strike from get_strike_cell(): its forecast must be the attack's.
func _run_strike(battle: TacticsBattle, command: Array) -> Array:
	var leader: int = command[1]
	var target: int = command[2]
	var cell: Vector2i = command[3]
	var targets: Array = battle.get_strike_targets(leader)
	if targets.has(target) != (cell != Vector2i(-1, -1)):
		_fail("get_strike_targets(%d) and get_strike_cell disagree about %d (%s)" % [leader, target, cell])
	if cell == Vector2i(-1, -1):
		return []
	var forecast := battle.forecast_move_attack(leader, cell, target)
	var events := _strike(battle, leader, target, cell)
	if events.is_empty():
		_fail("strike %s refused" % [command])
		return events
	_strikes += 1
	if forecast.get("target_gone", false) or battle.is_finished():
		return events
	for index: int in events.size():
		var event: Dictionary = events[index]
		if event["type"] == &"engagement_started" and event["unit"] == leader and event["target"] == target:
			_check_engagement(events.slice(index), forecast)
			return events
	_fail("strike %s never attacked" % [command])
	return events


func _check_move(battle: TacticsBattle, events: Array, path: Array, preview: Array) -> void:
	if events[0]["type"] != &"unit_moved" or Array(events[0]["path"]) != path:
		_fail("move took %s, get_path_to() said %s" % [events[0].get("path"), path])
	if battle.is_finished():
		return
	for placement: Dictionary in preview:
		var soldier := battle.get_unit_state(placement["unit"])
		if soldier["alive"] and soldier["cell"] != placement["cell"]:
			_fail("soldier %d went to %s, preview said %s" % [placement["unit"], soldier["cell"], placement["cell"]])


func _check_engagement(events: Array, forecast: Dictionary) -> void:
	var started: Dictionary = events[0]
	if started["type"] != &"engagement_started":
		_fail("attack began with %s" % started["type"])
		return
	var hits: Array[int] = [0, 0]
	var hp_after: Array[int] = [forecast["attacker_hp_after"], forecast["defender_hp_after"]]
	for event: Dictionary in events:
		if event["type"] != &"damage_dealt" or event["cause"] != started["id"]:
			continue
		var by_attacker: bool = event["source"] == forecast["attacker"]
		hits[0 if by_attacker else 1] += 1
		hp_after[1 if by_attacker else 0] = event["hp_after"]
		var per_hit: int = forecast["attacker_damage_per_hit"] if by_attacker else forecast["defender_damage_per_hit"]
		if event["amount"] != per_hit:
			_fail("hit of %d, forecast said %d" % [event["amount"], per_hit])
	var forecast_hits: Array[int] = [forecast["attacker_hits"], forecast["defender_hits"]]
	var forecast_hp: Array[int] = [forecast["attacker_hp_after"], forecast["defender_hp_after"]]
	if hits != forecast_hits or hp_after != forecast_hp:
		_fail("engagement landed %s to hp %s, forecast %s" % [hits, hp_after, forecast])


## The cast hit and buffed what preview_skill() said.
func _check_skill(events: Array, skill_preview: Dictionary) -> void:
	# Under fog the caster is shown first (a sight change), then it casts.
	var first := 0
	while first < events.size() - 1 and events[first]["type"] == &"vision_changed":
		first += 1
	var used: Dictionary = events[first]
	if used["type"] != &"skill_used" or Array(used["cells"]) != Array(skill_preview["cells"]) or Array(used["targets"]) != Array(skill_preview["targets"]):
		_fail("skill %s differs from its preview %s" % [used, skill_preview])
		return
	var damage: Dictionary = {}
	var buffed: Array = []
	for event: Dictionary in events:
		if event["type"] == &"damage_dealt" and event["source_id"] == used["skill"]:
			damage[event["target"]] = int(damage.get(event["target"], 0)) + int(event["amount"])
		elif event["type"] == &"buff_applied":
			buffed.append(event["unit"])
	var expected: Dictionary = {}
	for result: Dictionary in skill_preview["results"]:
		expected[result["unit"]] = result["amount"]
	if damage != expected or buffed != Array(skill_preview["buffed"]):
		_fail("skill dealt %s and buffed %s, preview said %s" % [damage, buffed, skill_preview])


## Read-only queries: reachable cells and paths agree, previews list living
## soldiers, forecasts and charges answer.
func _check_queries(battle: TacticsBattle) -> void:
	battle.get_zones()
	battle.get_enemy_intents()
	for unit: Dictionary in battle.get_units():
		if not unit["alive"] and not battle.get_reachable_cells(unit["index"]).is_empty():
			_fail("dead unit %d has reachable cells" % unit["index"])
		if unit["role"] == &"leader":
			battle.get_formation_slots(unit["index"])
			battle.get_skill_charge(unit["index"])
	var leader := _rng.randi_range(0, battle.get_unit_count() - 1)
	var state := battle.get_unit_state(leader)
	if not state["alive"] or state["role"] != &"leader":
		return
	var reachable: Array = battle.get_reachable_cells(leader)
	for row: int in battle.get_map_height():
		for col: int in battle.get_map_width():
			var cell := Vector2i(col, row)
			var path: Array = battle.get_path_to(leader, cell)
			var is_reachable: bool = reachable.has(cell) or cell == state["cell"]
			if path.is_empty() == is_reachable:
				_fail("path to %s is %s but reachable is %s" % [cell, path, is_reachable])
			if not path.is_empty() and (path[0] != state["cell"] or path[path.size() - 1] != cell):
				_fail("path %s does not join %s and %s" % [path, state["cell"], cell])
	if not reachable.is_empty() and state["side"] == battle.get_active_side() and not state["has_waited"]:
		for placement: Dictionary in battle.preview_squad(leader, reachable[_rng.randi_range(0, reachable.size() - 1)]):
			if not battle.get_unit_state(placement["unit"])["alive"]:
				_fail("preview lists dead soldier %d" % placement["unit"])
	for unit: int in battle.get_unit_count():
		battle.forecast_engagement(leader, unit)
		battle.forecast_engagement(unit, leader)
	for cell: Vector2i in battle.get_skill_cells(leader):
		battle.preview_skill(leader, cell)
	battle.get_attack_targets(leader)
	battle.can_undo_move(leader)
	for target: int in battle.get_strike_targets(leader):
		var cell := battle.get_strike_cell(leader, target)
		if cell != state["cell"] and not reachable.has(cell):
			_fail("strike cell %s of %d against %d is not reachable" % [cell, leader, target])
		var forecast := battle.forecast_move_attack(leader, cell, target)
		# Under fog a walk through a cell an unseen enemy stands on stops
		# there; nothing else may make the forecast fail.
		if not forecast.get("is_valid", false) and not forecast.get("target_gone", false) and not _crosses_unseen(battle, leader, cell):
			_fail("forecast_move_attack(%d, %s, %d) is not valid" % [leader, cell, target])


func _check_events(battle: TacticsBattle, events: Array) -> void:
	for index: int in events.size():
		var event: Dictionary = events[index]
		if event["cause"] >= event["id"]:
			_fail("event %d has cause %d" % [event["id"], event["cause"]])
		if event["type"] == &"battle_ended" and index != events.size() - 1:
			_fail("%s came after battle_ended" % events[index + 1]["type"])
	if battle.is_finished() and not events.is_empty() and events.back()["type"] != &"battle_ended":
		_fail("finished, but the last event is %s" % events.back()["type"])


## One living unit per cell, on the map and on terrain it can stand on, with
## hp in 0..max_hp (above 0 while alive).
func _check_board(battle: TacticsBattle) -> void:
	var taken: Dictionary = {}
	for unit: Dictionary in battle.get_units():
		var hp: int = unit["hp"]
		if hp < 0 or hp > unit["max_hp"] or (unit["alive"] and hp == 0):
			_fail("unit %d has hp %d of %d, alive %s" % [unit["index"], hp, unit["max_hp"], unit["alive"]])
		if not unit["alive"]:
			continue
		var cell: Vector2i = unit["cell"]
		if cell.x < 0 or cell.y < 0 or cell.x >= battle.get_map_width() or cell.y >= battle.get_map_height():
			_fail("unit %d is off the map at %s" % [unit["index"], cell])
			continue
		if taken.has(cell):
			_fail("units %d and %d share %s" % [taken[cell], unit["index"], cell])
		taken[cell] = unit["index"]
		if _kit.catalog.get_terrain(battle.get_terrain_id(cell)).is_impassable and not unit["keywords"].has(&"keyword.flying"):
			_fail("unit %d stands on impassable %s" % [unit["index"], cell])


func _reset_model(battle: TacticsBattle) -> void:
	_model.clear()
	_zone_count = 0
	for unit: Dictionary in battle.get_units():
		var charge: int = battle.get_skill_charge(unit["index"])["value"] if unit["role"] == &"leader" else 0
		_model[unit["index"]] = {"cell": unit["cell"], "hp": unit["hp"], "alive": unit["alive"], "charge": charge, "side": unit["side"], "is_soldier": unit["role"] == &"soldier"}


## Applies the events to the model, then compares it with the battle: every
## change of cell, hp, life, charge and zones must come with its event.
func _apply_model(battle: TacticsBattle, events: Array) -> void:
	for event: Dictionary in events:
		match event["type"]:
			&"unit_moved":
				if _model[event["unit"]]["cell"] != event["from"]:
					_fail("unit %d moved from %s, but it was on %s" % [event["unit"], event["from"], _model[event["unit"]]["cell"]])
				_model[event["unit"]]["cell"] = event["to"]
				_spend_budget(event)
			&"engagement_started":
				var key := [event["turn"], event["unit"]]
				if _soldier_strikes.has(key):
					_fail("%s %d struck twice in turn %d" % ["soldier" if _model[event["unit"]]["is_soldier"] else "leader", event["unit"], event["turn"]])
				_soldier_strikes[key] = true
			&"damage_dealt":
				var target: Dictionary = _model[event["target"]]
				if not target["alive"] or event["hp_after"] != maxi(0, target["hp"] - event["amount"]):
					_fail("damage %s does not follow hp %d" % [event, target["hp"]])
				target["hp"] = event["hp_after"]
			&"unit_died":
				_model[event["unit"]]["alive"] = false
			&"unit_fled":
				if _model[event["unit"]]["cell"] != event["from"]:
					_fail("unit %d fled from %s, but it was on %s" % [event["unit"], event["from"], _model[event["unit"]]["cell"]])
				_model[event["unit"]]["alive"] = false
			&"unit_defected":
				if _model[event["unit"]]["side"] != event["from_side"]:
					_fail("unit %d defected from side %d, but it was on %d" % [event["unit"], event["from_side"], _model[event["unit"]]["side"]])
				_model[event["unit"]]["side"] = event["side"]
			&"skill_charge_changed":
				_model[event["unit"]]["charge"] = event["value"]
			&"zone_created":
				_zone_count += 1
			&"zone_expired":
				_zone_count -= 1
		if String(event["type"]) in ["vision_changed", "ambushed", "weather_changed", "daytime_changed"]:
			_sight_counts[event["type"]] = int(_sight_counts.get(event["type"], 0)) + 1
		if String(event["type"]) in ["soldier_wavered", "incident_calmed", "incident_fired", "mark_earned", "unit_fled", "unit_defected"]:
			_incident_counts[event["type"]] = int(_incident_counts.get(event["type"], 0)) + 1
	for unit: Dictionary in battle.get_units():
		var entry: Dictionary = _model[unit["index"]]
		var charge: int = battle.get_skill_charge(unit["index"])["value"] if unit["role"] == &"leader" else 0
		var actual := {"cell": unit["cell"], "hp": unit["hp"], "alive": unit["alive"], "charge": charge, "side": unit["side"], "is_soldier": unit["role"] == &"soldier"}
		if not unit["alive"]:
			actual["cell"] = entry["cell"]
		if actual != entry:
			_fail("events add up to %s for unit %d, the battle has %s" % [entry, unit["index"], actual])
			_model[unit["index"]] = actual
	if battle.get_zones().size() != _zone_count:
		_fail("events add up to %d zones, the battle has %d" % [_zone_count, battle.get_zones().size()])
		_zone_count = battle.get_zones().size()


func _check_nothing_after_end(battle: TacticsBattle) -> void:
	var before := battle.get_state_hash()
	var refused := [battle.end_phase(), battle.wait(0), battle.move_leader(0, Vector2i(0, 0))]
	if refused != [[], [], []] or battle.get_state_hash() != before:
		_fail("a command changed the battle after its end")


## The leader's turn queries agree with its state: open until it waited,
## one attack and one cast, moves while its points reach a cell, and
## closed exactly when nothing is left. After "Chờ" nothing is possible.
func _check_turn_queries(battle: TacticsBattle, unit: int, state: Dictionary, can_act: bool, can_attack: bool) -> void:
	var can_move: bool = can_act and int(state["move_points_left"]) > 0 and not battle.get_reachable_cells(unit).is_empty()
	var can_cast: bool = can_act and not state.get("has_cast", false) and state["role"] == &"leader" and battle.get_skill_charge(unit)["is_ready"]
	var actual := [battle.can_act(unit), battle.can_move(unit), battle.can_attack(unit), battle.can_cast(unit)]
	if actual != [can_act, can_move, can_attack, can_cast]:
		_fail("can_act/move/attack/cast of %d are %s, its state says %s: %s" % [unit, actual, [can_act, can_move, can_attack, can_cast], state])
	if battle.get_move_points_left(unit) != int(state["move_points_left"]) or battle.has_attacked(unit) != bool(state["has_attacked"]):
		_fail("move points left or has_attacked of %d disagree with its state %s" % [unit, state])
	var is_closed: bool = not can_act or (not can_move and battle.get_strike_targets(unit).is_empty() and battle.get_skill_cells(unit).is_empty())
	if battle.is_closed(unit) != is_closed:
		_fail("is_closed(%d) is %s, expected %s: %s" % [unit, battle.is_closed(unit), is_closed, state])
	if state["has_waited"] and not (battle.get_attack_targets(unit).is_empty() and battle.get_skill_cells(unit).is_empty() and battle.get_strike_targets(unit).is_empty()):
		_fail("leader %d waited but still has targets or skill cells" % unit)


## At a human turn's first command: the move points of every unit of the
## active side, which its walking this turn may not exceed.
func _note_turn(battle: TacticsBattle) -> void:
	if battle.get_turn() == _budget_turn or battle.is_side_ai(battle.get_active_side()):
		return
	_budget_turn = battle.get_turn()
	_budget.clear()
	for unit: Dictionary in battle.get_units():
		if unit["alive"] and unit["side"] == battle.get_active_side():
			_budget[unit["index"]] = int(unit["move_points_left"])


## A move or squad walk of the human turn spends at least one point a cell.
func _spend_budget(event: Dictionary) -> void:
	if event["turn"] != _budget_turn or not _budget.has(event["unit"]) or not (event["kind"] in [&"move", &"squad"]):
		return
	var left: int = _budget[event["unit"]] - ((event["path"] as Array).size() - 1)
	if left < 0:
		_fail("unit %d walked past its move points in turn %d (%s)" % [event["unit"], event["turn"], event["path"]])
	_budget[event["unit"]] = left


## Any accepted command other than a plain move ends the moves that can be
## taken back; checks the points left never exceed the walked budget.
func _note_undo_stack(battle: TacticsBattle, command: Array, events: Array) -> void:
	if not events.is_empty() and command[0] != &"move":
		_undo_stack.clear()
	if battle.get_turn() != _budget_turn or battle.is_finished():
		return
	for unit: int in _budget:
		var state := battle.get_unit_state(unit)
		if state["alive"] and state["side"] == battle.get_active_side() and int(state["move_points_left"]) > int(_budget[unit]):
			_fail("unit %d has %d move points left, more than the %d cells it may still walk" % [unit, state["move_points_left"], _budget[unit]])
