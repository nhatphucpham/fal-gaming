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
# forecast_move_attack() said; an undo is offered exactly after a plain
# human move and gives back the hash from before it.
# Every other seed plays with incidents, most soldiers seeded with a random
# one: the events must account for flights and defections too.

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
## Per leader: the hash before its last accepted move.
var _move_hashes: Dictionary = {}
var _undos: int = 0
## The leader the last command moved, else -1 (an undo is likelier next).
var _last_moved: int = -1
var _strikes: int = 0


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
	print("Tactics fuzz test: incident events %s, %d strikes, %d undos" % [_incident_counts, _strikes, _undos])
	if _incident_counts.get(&"incident_fired", 0) == 0:
		_failures.append("no incident fired on any seed")
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
	while commands.size() < MAX_COMMANDS and not battle.is_finished():
		var before := battle.get_state_hash()
		_check_queries(battle)
		if battle.get_state_hash() != before:
			_fail("queries changed the hash before command %d" % commands.size())
		var command := _pick_command(battle)
		events = _run_checked(battle, command)
		if events.is_empty() and battle.get_state_hash() != before and command[0] != &"undo":
			_fail("refused %s changed the hash" % [command])
		_check_events(battle, events)
		_apply_model(battle, events)
		_check_board(battle)
		commands.append(command)
		hashes.append(battle.get_state_hash())
	if battle.is_finished():
		_check_nothing_after_end(battle)
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
	return battle


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
	var can_act: bool = is_commandable and not state["has_acted"]
	var expected := true
	var path: Array = []
	var preview: Array = []
	var forecast: Dictionary = {}
	var is_ready := false
	var skill_preview: Dictionary = {}
	if battle.can_act(unit) != can_act or battle.can_move(unit) != (can_act and not state["has_moved"]):
		_fail("can_act/can_move of %d disagree with its state %s" % [unit, state])
	match command[0]:
		&"move":
			expected = can_act and not state["has_moved"] and battle.get_reachable_cells(unit).has(command[2])
			path = battle.get_path_to(unit, command[2])
			preview = battle.preview_squad(unit, command[2]) if expected else []
		&"attack":
			forecast = battle.forecast_engagement(unit, command[2])
			expected = can_act and forecast["is_valid"]
			if battle.get_attack_targets(unit).has(command[2]) != expected:
				_fail("get_attack_targets(%d) disagrees about %d" % [unit, command[2]])
		&"skill":
			is_ready = state["role"] == &"leader" and battle.get_skill_charge(unit)["is_ready"]
			expected = battle.get_skill_cells(unit).has(command[2])
			skill_preview = battle.preview_skill(unit, command[2])
			if skill_preview["is_valid"] != expected:
				_fail("preview_skill(%d, %s) is %s, get_skill_cells() says %s" % [unit, command[2], skill_preview["is_valid"], expected])
		&"wait":
			expected = can_act
		_:
			expected = is_commandable
	var hash_before := battle.get_state_hash()
	var events := _run(battle, command)
	if command[0] == &"move" and not events.is_empty():
		_move_hashes[unit] = hash_before
		_last_moved = unit
		var is_plain := not battle.is_finished() and not battle.is_side_ai(state["side"])
		for event: Dictionary in events:
			is_plain = is_plain and event["type"] in [&"unit_moved", &"skill_charge_changed"]
		if battle.can_undo_move(unit) != is_plain:
			_fail("after %s can_undo_move is %s, the move was plain=%s" % [command, battle.can_undo_move(unit), is_plain])
	if command[0] == &"skill":
		if not events.is_empty() and not (can_act and is_ready):
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
		_check_move(battle, events, path, preview)
	elif command[0] == &"attack":
		_check_engagement(events, forecast)
	return events


## An undo: taken exactly when can_undo_move said so, back to the hash
## before that move; the event model starts again from the battle.
func _run_undo(battle: TacticsBattle, unit: int) -> Array:
	var expected := battle.can_undo_move(unit)
	var is_undone := battle.undo_move(unit)
	if is_undone != expected:
		_fail("undo_move(%d) gave %s, can_undo_move said %s" % [unit, is_undone, expected])
	if is_undone:
		_undos += 1
		if battle.get_state_hash() != _move_hashes.get(unit, ""):
			_fail("undo_move(%d) did not give back the hash before the move" % unit)
		if battle.can_undo_move(unit):
			_fail("undo_move(%d) can be taken twice" % unit)
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
	var used: Dictionary = events[0]
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
	if not reachable.is_empty() and state["side"] == battle.get_active_side() and not state["has_moved"] and not state["has_acted"]:
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
		if not forecast.get("is_valid", false) and not forecast.get("target_gone", false):
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
		_model[unit["index"]] = {"cell": unit["cell"], "hp": unit["hp"], "alive": unit["alive"], "charge": charge, "side": unit["side"]}


## Applies the events to the model, then compares it with the battle: every
## change of cell, hp, life, charge and zones must come with its event.
func _apply_model(battle: TacticsBattle, events: Array) -> void:
	for event: Dictionary in events:
		match event["type"]:
			&"unit_moved":
				if _model[event["unit"]]["cell"] != event["from"]:
					_fail("unit %d moved from %s, but it was on %s" % [event["unit"], event["from"], _model[event["unit"]]["cell"]])
				_model[event["unit"]]["cell"] = event["to"]
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
		if String(event["type"]) in ["soldier_wavered", "incident_calmed", "incident_fired", "mark_earned", "unit_fled", "unit_defected"]:
			_incident_counts[event["type"]] = int(_incident_counts.get(event["type"], 0)) + 1
	for unit: Dictionary in battle.get_units():
		var entry: Dictionary = _model[unit["index"]]
		var charge: int = battle.get_skill_charge(unit["index"])["value"] if unit["role"] == &"leader" else 0
		var actual := {"cell": unit["cell"], "hp": unit["hp"], "alive": unit["alive"], "charge": charge, "side": unit["side"]}
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
