extends SceneTree
## Measures how the soldiers fight: plays seeded battles of a scenario
## (the river crossing unless `--scenario=<name>`), side B by the AI and side
## A by a simple scripted policy (random squads, or the soldiers the scenario
## supplies, and random orders per seed, incidents on), and prints the
## average soldiers lost per battle on each side and the share of soldier
## attacks that killed their target or traded well (dealt more than they
## took and lived). The scripted player plays by sight as the AI does: it
## goes for the enemy leaders it sees, else where it last saw one, else
## scouts toward the objective. With an objective kind it plays for it
## (Docs/systems/tactics_objectives.md): to the pass, around the keep,
## ahead of the cart, out by the exits, after the general; it takes what a
## site offers (recruits, healing, camps, shrines) and never loots.
## It also prints the side goals met. `--policy=idle` plays side A as a player who
## never gives a command (it only ends its phases), to check that the enemy
## beats a player who does nothing. `--no-fog` plays the scenario in clear
## sight, to compare. `--pressure=N` plays the enemy at world-map pressure N
## (TacticsCampaign's enemy power, +15 % hp and attack a level) and
## `--bond-level=N` gives every pair of our leaders a bond of level N, as a
## campaign battle has them (Docs/systems/tactics_world.md);
## `--pressure-step=P` tries another % per level than the world data's;
## `--items` uses one of each market item (war drum, herb kit).
## Run: godot --headless --path . --script res://Tools/tactics_brain_probe.gd -- --battles=200 [--scenario=night_raid] [--policy=idle] [--no-fog] [--pressure=2] [--pressure-step=10] [--bond-level=1] [--items]

const CATALOG_PATH: String = "res://Data/Tactics/tactics_catalog.tres"
const SCENARIO_FORMAT: String = "res://Data/Tactics/Scenarios/%s.tres"
const ORDERS: Array[StringName] = [&"order.follow", &"order.vanguard", &"order.flank", &"order.free"]
const MAX_COMMANDS: int = 400
const COHESION_CELLS: int = 4

var _rng := RandomNumberGenerator.new()
var _is_idle: bool = false
## Per enemy leader: what it declared at the start of our phase and what it
## then did, to measure how often the shown intent comes true.
var _declared: Dictionary = {}
## The cell side A takes to win, where it scouts when it sees no enemy.
var _objective := Vector2i(-1, -1)
var _map: TacticsMapData
## Goal cell -> walking cost from every cell to it (terrain costs, rivers
## kept out), so the scripted player finds the fords and bridges.
var _costs: Dictionary = {}
## get_objective_state() at the start of side A's current phase.
var _goal: Dictionary = {}
var _kind: StringName = &""
## Bond level every pair of our leaders gets (0: none, the battle has no bonds).
var _bond_level: int = 0


func _initialize() -> void:
	var battles := 200
	var scenario_name := "river_crossing"
	var has_fog := true
	var pressure := 0
	var pressure_step := -1
	var has_items := false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--battles="):
			battles = int(argument.get_slice("=", 1))
		elif argument.begins_with("--scenario="):
			scenario_name = argument.get_slice("=", 1)
		elif argument == "--policy=idle":
			_is_idle = true
		elif argument == "--no-fog":
			has_fog = false
		elif argument.begins_with("--pressure="):
			pressure = int(argument.get_slice("=", 1))
		elif argument.begins_with("--pressure-step="):
			pressure_step = int(argument.get_slice("=", 1))
		elif argument == "--items":
			has_items = true
		elif argument.begins_with("--bond-level="):
			_bond_level = int(argument.get_slice("=", 1))
	var catalog := load(CATALOG_PATH) as TacticsCatalog
	var scenario := load(SCENARIO_FORMAT % scenario_name) as TacticsScenarioData
	if not has_fog:
		scenario = scenario.duplicate()
		scenario.fog_of_war = false
	var world_data := load(TacticsWorldData.PATH) as TacticsWorldData
	if pressure > 0 or has_items:
		# The campaign's pressed enemy and boosted leaders, on a fresh roster
		# (no named leaders).
		var step := pressure_step if pressure_step >= 0 else world_data.pressure_step_pct
		var roster := TacticsRoster.create(1)
		var items: Array = []
		for item: TacticsItemData in world_data.items if has_items else []:
			roster.items[String(item.id)] = 1
			items.append(item)
		var plan := {"enemy_power_pct": 100 + step * pressure, "items": items}
		scenario = TacticsCampaign.new(roster, catalog, scenario, plan).scenario
	var totals := {
		"lost_a": 0, "lost_b": 0, "attacks_a": 0, "attacks_b": 0, "good_a": 0, "good_b": 0,
		"kills_a": 0, "kills_b": 0, "suicides_a": 0, "suicides_b": 0, "wins_a": 0, "rounds": 0,
		"leaders_lost_a": 0, "leaders_lost_b": 0, "skills_a": 0, "skills_b": 0,
		"endings": {},
		"intents": 0, "intents_kept": 0, "intent_cells_kept": 0,
		"goals_met": {}, "sites_used": 0, "supplies": 0,
	}
	var start_ms := Time.get_ticks_msec()
	for seed_value: int in range(1, battles + 1):
		_play(seed_value, catalog, scenario, totals, world_data)
	var elapsed := Time.get_ticks_msec() - start_ms
	var count := float(battles)
	print("Tactics brain probe: %s, %d battles in %d ms, side A %s, pressure %d, bond level %d%s" % [scenario.id, battles, elapsed, "idle" if _is_idle else "scripted", pressure, _bond_level, ", items" if has_items else ""])
	print("  soldiers lost per battle: ours (A) %.2f, enemy (B) %.2f" % [totals["lost_a"] / count, totals["lost_b"] / count])
	for side: String in ["a", "b"]:
		var attacks: int = totals["attacks_" + side]
		var share: float = 0.0 if attacks == 0 else 100.0 * totals["good_" + side] / attacks
		var kill_share: float = 0.0 if attacks == 0 else 100.0 * totals["kills_" + side] / attacks
		var suicide_share: float = 0.0 if attacks == 0 else 100.0 * totals["suicides_" + side] / attacks
		print("  side %s soldier attacks %d: killed or traded well %.1f%%, killed %.1f%%, died to the counter %.1f%%" % [side.to_upper(), attacks, share, kill_share, suicide_share])
	print("  leaders lost per battle: ours (A) %.2f, enemy (B) %.2f; skills cast per battle: A %.2f, B %.2f" % [totals["leaders_lost_a"] / count, totals["leaders_lost_b"] / count, totals["skills_a"] / count, totals["skills_b"] / count])
	print("  enemy intents %d: the move and the action as declared %.1f%%, the move as declared %.1f%%" % [totals["intents"], 100.0 * totals["intents_kept"] / maxi(1, totals["intents"]), 100.0 * totals["intent_cells_kept"] / maxi(1, totals["intents"])])
	print("  side A wins %d / %d, average rounds %.1f, endings %s" % [totals["wins_a"], battles, totals["rounds"] / count, totals["endings"]])
	print("  side goals met %s, sites used per battle %.2f, supplies per battle %.2f" % [totals["goals_met"], totals["sites_used"] / count, totals["supplies"] / count])
	quit(0)


func _play(seed_value: int, catalog: TacticsCatalog, scenario: TacticsScenarioData, totals: Dictionary, world_data: TacticsWorldData) -> void:
	_rng.seed = seed_value
	_costs.clear()
	var battle := TacticsBattle.new()
	battle.set_side_ai(TacticsBattle.SIDE_B, true)
	var squads: Array = []
	for leader: TacticsLeaderData in scenario.leaders_a:
		var squad: Array[TacticsTroopData] = []
		for slot: int in leader.lead_capacity:
			squad.append(catalog.troops[_rng.randi_range(0, catalog.troops.size() - 1)])
		squads.append(squad)
	# The idle player keeps the scenario's squads and orders; a scenario
	# that supplies its soldiers is played with them.
	if _is_idle or not scenario.supplied_sizes.is_empty() or not battle.load_scenario_with_squads(scenario, TacticsBattle.SIDE_A, squads):
		battle.load_scenario(scenario)
	_map = scenario.map
	_goal = battle.get_objective_state()
	_kind = _goal.get("kind", &"")
	_objective = _goal.get("cell", Vector2i(-1, -1))
	battle.set_incident_rules(catalog.incident_rules, seed_value)
	if _bond_level > 0:
		_set_bonds(battle, world_data)
	var events: Array = battle.start().duplicate()
	for unit: Dictionary in battle.get_units():
		if unit["role"] == &"leader" and unit["side"] == TacticsBattle.SIDE_A and not _is_idle:
			events.append_array(battle.set_order(unit["index"], ORDERS[_rng.randi_range(0, ORDERS.size() - 1)]))
	_count(battle, events, totals)
	var commands := 0
	while not battle.is_finished() and commands < MAX_COMMANDS:
		_goal = battle.get_objective_state()
		for unit: Dictionary in battle.get_units():
			if _is_idle:
				break
			if battle.is_finished():
				break
			if unit["role"] != &"leader" or unit["side"] != TacticsBattle.SIDE_A or not battle.can_act(unit["index"]):
				continue
			_count(battle, _play_leader(battle, unit["index"]), totals)
			commands += 1
		if not battle.is_finished():
			_count(battle, battle.end_phase(), totals)
			commands += 1
	if battle.get_winner() == TacticsBattle.SIDE_A:
		totals["wins_a"] += 1
	var report := battle.get_battle_report()
	for index: int in report.get("goals_met", []):
		var goal_kind := String(scenario.objective.goals[index].kind)
		totals["goals_met"][goal_kind] = int(totals["goals_met"].get(goal_kind, 0)) + 1
	totals["supplies"] += int(report.get("supplies", 0))
	var ending := "%s_%s" % ["a" if battle.get_winner() == TacticsBattle.SIDE_A else "b", battle.get_end_reason()]
	totals["endings"][ending] = int(totals["endings"].get(ending, 0)) + 1
	totals["rounds"] += battle.get_round()
	battle.free()


# Every pair of our leaders bonded at _bond_level.
func _set_bonds(battle: TacticsBattle, world_data: TacticsWorldData) -> void:
	var leaders: Array[int] = []
	for unit: Dictionary in battle.get_units():
		if unit["role"] == &"leader" and unit["side"] == TacticsBattle.SIDE_A:
			leaders.append(unit["index"])
	var bonds: Array = []
	for first: int in leaders.size():
		for second: int in range(first + 1, leaders.size()):
			bonds.append({"a": leaders[first], "b": leaders[second], "level": _bond_level})
	battle.set_bonds(bonds, world_data.get_bond_rules())


## Move toward the nearest (sometimes the second nearest) enemy leader it
## sees, else where one was last seen, else toward the objective (a scout's
## walk), and attack the weakest enemy in reach. With an objective kind the
## walk goes where the objective wants (_objective_goal).
func _play_leader(battle: TacticsBattle, leader: int) -> Array:
	var events: Array = []
	var cell: Vector2i = battle.get_unit_state(leader)["cell"]
	var targets: Array = []
	for unit: Dictionary in battle.get_units():
		if unit["alive"] and unit["side"] == TacticsBattle.SIDE_B and unit["role"] == &"leader" and battle.is_unit_seen(TacticsBattle.SIDE_A, unit["index"]):
			targets.append(unit)
	if targets.is_empty():
		for ghost: Dictionary in battle.get_last_seen(TacticsBattle.SIDE_A):
			if battle.get_unit_state(ghost["unit"])["role"] == &"leader":
				targets.append({"cell": ghost["cell"]})
	if targets.is_empty() and _objective.x >= 0:
		targets.append({"cell": _objective})
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _distance(a["cell"], cell) < _distance(b["cell"], cell))
	var goals: Array = _objective_goal(battle, leader, targets)
	if goals.is_empty() and not targets.is_empty():
		goals = [targets[mini(targets.size() - 1, 1 if _rng.randf() < 0.3 else 0)]["cell"]]
	var focus := _focus_target(battle, leader)
	if not goals.is_empty() and (battle.get_attack_targets(leader).is_empty() or _is_walk_first(battle, leader, focus)):
		# By the walking cost, which finds the ford or the bridge.
		var best := cell
		var road: Array = _goal.get("road_cells", [])
		# The one furthest behind walks free, so the others can wait for it.
		var last := leader
		for unit: Dictionary in battle.get_units():
			if unit["alive"] and unit["side"] == TacticsBattle.SIDE_A and unit["role"] == &"leader" and _goal_cost(unit["cell"], goals) > _goal_cost(battle.get_unit_state(last)["cell"], goals):
				last = unit["index"]
		for reachable: Vector2i in battle.get_reachable_cells(leader):
			if road.has(reachable) or not (last == leader or _is_with(battle.get_unit_state(last)["cell"], reachable)):
				continue
			if _goal_cost(reachable, goals) < _goal_cost(best, goals):
				best = reachable
		if best != cell:
			events.append_array(battle.move_leader(leader, best))
	if battle.is_finished() or not battle.get_unit_state(leader)["alive"] or not battle.can_act(leader):
		return events
	events.append_array(_take_site(battle, leader))
	if battle.is_finished() or not battle.can_act(leader):
		return events
	var cast := _best_skill_cell(battle, leader)
	if cast.x >= 0:
		events.append_array(battle.use_skill(leader, cast))
		return events
	var weakest := -1
	for target: int in battle.get_attack_targets(leader):
		if target == focus:
			weakest = target
			break
		if weakest < 0 or int(battle.get_unit_state(target)["hp"]) < int(battle.get_unit_state(weakest)["hp"]):
			weakest = target
	if weakest >= 0:
		events.append_array(battle.attack(leader, weakest))
	elif battle.can_act(leader):
		events.append_array(battle.wait(leader))
	return events


# The skill cell that does the most: enemy hp taken (a kill counts
# double), soldiers of ours buffed; (-1, -1) when it does nothing.
func _best_skill_cell(battle: TacticsBattle, leader: int) -> Vector2i:
	if not battle.can_cast(leader):
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_score := 0
	for cell: Vector2i in battle.get_skill_cells(leader):
		var preview := battle.preview_skill(leader, cell)
		if not preview.get("is_valid", false):
			continue
		var score: int = (preview["buffed"] as Array).size() * 150
		for result: Dictionary in preview["results"]:
			var sign := 1 if battle.get_unit_state(result["unit"])["side"] == TacticsBattle.SIDE_B else -2
			score += sign * int(result["amount"]) * (2 if result["is_dead"] else 1)
		if score > best_score:
			best_score = score
			best = cell
	return best


# Where the objective sends this leader; empty: chase the enemy leaders.
func _objective_goal(battle: TacticsBattle, leader: int, targets: Array) -> Array:
	var cell: Vector2i = battle.get_unit_state(leader)["cell"]
	match _kind:
		&"objective_kind.take_pass":
			return [_goal["cell"]]
		&"objective_kind.hold_city":
			var keep: Vector2i = _goal["cell"]
			if _nearest_leader_to(battle, keep) == leader:
				return [keep]
			# The others meet what comes near the keep, else stand by it.
			for target: Dictionary in targets:
				if target.has("index") and _distance(target["cell"], keep) <= 4:
					return [target["cell"]]
			return [keep + Vector2i(0, 1), keep + Vector2i(1, 0), keep + Vector2i(-1, 0), keep + Vector2i(0, -1)]
		&"objective_kind.escort":
			var convoy: int = _goal["convoy"]
			if convoy < 0 or not battle.get_unit_state(convoy)["alive"]:
				return []
			var at: Vector2i = battle.get_unit_state(convoy)["cell"]
			for target: Dictionary in targets:
				if target.has("index") and _distance(target["cell"], at) <= 5:
					return [target["cell"]]
			# Beside the road ahead of the cart: a unit on the road stops it.
			var road: Array = _goal["road_cells"]
			var ahead: Vector2i = road[mini(road.find(at) + 3, road.size() - 1)]
			var beside: Array = []
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if not road.has(ahead + step):
					beside.append(ahead + step)
			return beside
		&"objective_kind.break_siege":
			return _goal["exit_cells"]
		&"objective_kind.slay_general":
			var general: int = _goal["general"]
			if general < 0 or not battle.get_unit_state(general)["alive"]:
				return []
			if battle.is_unit_seen(TacticsBattle.SIDE_A, general):
				return [battle.get_unit_state(general)["cell"]]
			for ghost: Dictionary in battle.get_last_seen(TacticsBattle.SIDE_A):
				if ghost["unit"] == general:
					return [ghost["cell"]]
			return [_goal["cell"]] if _distance(cell, _goal["cell"]) > 1 else []
	return []


# The enemy the objective wants struck first: the general.
func _focus_target(battle: TacticsBattle, _leader: int) -> int:
	if _kind == &"objective_kind.slay_general":
		var general: int = _goal["general"]
		if general >= 0 and battle.get_unit_state(general)["alive"] and battle.is_unit_seen(TacticsBattle.SIDE_A, general):
			return general
	return -1


# Walk on although an enemy is in reach: a breakout leader heads out, and
# a hunter that cannot strike the general now steps toward him.
func _is_walk_first(battle: TacticsBattle, leader: int, focus: int) -> bool:
	if _kind == &"objective_kind.break_siege":
		return true
	if _kind == &"objective_kind.take_pass":
		return _nearest_leader_to(battle, _goal["cell"]) == leader and battle.get_unit_state(leader)["cell"] != _goal["cell"]
	return focus >= 0 and not battle.get_attack_targets(leader).has(focus)


# The leaders keep together: a step may not take a leader more than
# COHESION_CELLS from the one furthest behind (a breakout runs free).
func _is_with(last_cell: Vector2i, cell: Vector2i) -> bool:
	return _kind == &"objective_kind.break_siege" or _distance(last_cell, cell) <= COHESION_CELLS


func _nearest_leader_to(battle: TacticsBattle, goal: Vector2i) -> int:
	var best := -1
	for unit: Dictionary in battle.get_units():
		if unit["alive"] and unit["side"] == TacticsBattle.SIDE_A and unit["role"] == &"leader":
			if best < 0 or _walk_cost(unit["cell"], goal) < _walk_cost(battle.get_unit_state(best)["cell"], goal):
				best = unit["index"]
	return best


# A site's offer the leader may take now: a recruit, healing, a camp, a
# shrine's charge or blessing; never a loot.
func _take_site(battle: TacticsBattle, leader: int) -> Array:
	for wanted: StringName in [&"recruit", &"heal", &"capture", &"charge", &"bless", &"calm"]:
		for action: Dictionary in battle.get_site_actions(leader):
			for choice: Dictionary in action["choices"]:
				if choice["choice"] != wanted or not choice["can"]:
					continue
				for option: int in int(choice["options"]):
					if not battle.can_use_site(leader, action["site"], wanted, option):
						continue
					# A recruit is picked at random between the two.
					var other := _rng.randi_range(0, int(choice["options"]) - 1)
					var pick := other if battle.can_use_site(leader, action["site"], wanted, other) else option
					return battle.use_site(leader, action["site"], wanted, pick)
	return []


func _goal_cost(from: Vector2i, goals: Array) -> int:
	var best := 1 << 30
	for goal: Vector2i in goals:
		if goal.x >= 0 and goal.y >= 0 and goal.x < _map.width and goal.y < _map.height:
			best = mini(best, _walk_cost(from, goal))
	return best


func _count(battle: TacticsBattle, events: Array, totals: Dictionary) -> void:
	var open: Dictionary = {}
	for event: Dictionary in events:
		_follow_intent(battle, event, totals)
		match event["type"]:
			&"engagement_started":
				var attacker: Dictionary = battle.get_unit_state(event["unit"])
				if attacker["role"] == &"soldier":
					open = {"unit": event["unit"], "target": event["target"], "side": attacker["side"], "killed": false, "died": false}
				else:
					open = {}
			&"unit_died":
				var dead: Dictionary = battle.get_unit_state(event["unit"])
				if dead["role"] == &"soldier":
					totals["lost_a" if dead["side"] == TacticsBattle.SIDE_A else "lost_b"] += 1
				else:
					totals["leaders_lost_a" if dead["side"] == TacticsBattle.SIDE_A else "leaders_lost_b"] += 1
				if not open.is_empty():
					if event["unit"] == open["target"]:
						open["killed"] = true
					elif event["unit"] == open["unit"]:
						open["died"] = true
			&"skill_used":
				totals["skills_a" if battle.get_unit_state(event["unit"])["side"] == TacticsBattle.SIDE_A else "skills_b"] += 1
			&"site_used":
				if event["side"] == TacticsBattle.SIDE_A:
					totals["sites_used"] += 1
			&"engagement_ended":
				if not open.is_empty():
					_close(open, int(event["amount"]), int(event["counter_amount"]), totals)
					open = {}
			&"battle_ended":
				if not open.is_empty():
					_close(open, 1, 0, totals)
					open = {}


# Declared intents against the enemy phase that follows them.
func _follow_intent(battle: TacticsBattle, event: Dictionary, totals: Dictionary) -> void:
	match event["type"]:
		&"intent_declared":
			_declared[event["unit"]] = {"to": event["to"], "action": event["action"], "target": event["target"], "cell": battle.get_unit_state(event["unit"])["cell"], "did": &"wait", "did_target": -1}
		&"unit_moved":
			if _declared.has(event["unit"]) and event["kind"] == &"move":
				_declared[event["unit"]]["cell"] = event["to"]
		&"engagement_started":
			if _declared.has(event["unit"]) and not _declared[event["unit"]].has("done"):
				_declared[event["unit"]]["did"] = &"attack"
				_declared[event["unit"]]["did_target"] = event["target"]
				_declared[event["unit"]]["done"] = true
		&"skill_used":
			if _declared.has(event["unit"]):
				_declared[event["unit"]]["did"] = &"skill"
				_declared[event["unit"]]["done"] = true
		&"unit_died":
			_declared.erase(event["unit"])
		&"phase_ended":
			if event["side"] != TacticsBattle.SIDE_B:
				return
			for entry: Dictionary in _declared.values():
				totals["intents"] += 1
				var is_cell_kept: bool = entry["cell"] == entry["to"]
				var is_action_kept: bool = entry["did"] == entry["action"] and (entry["action"] != &"attack" or entry["did_target"] == entry["target"])
				totals["intent_cells_kept"] += 1 if is_cell_kept else 0
				totals["intents_kept"] += 1 if is_cell_kept and is_action_kept else 0
			_declared.clear()


func _close(open: Dictionary, dealt: int, taken: int, totals: Dictionary) -> void:
	var key: String = "a" if open["side"] == TacticsBattle.SIDE_A else "b"
	totals["attacks_" + key] += 1
	if open["killed"]:
		totals["kills_" + key] += 1
	if open["died"]:
		totals["suicides_" + key] += 1
	if open["killed"] or (not open["died"] and dealt > taken):
		totals["good_" + key] += 1


# The cost to walk from `from` to `goal` over the map's terrain (Dijkstra
# from the goal, cached), plus the straight distance to break ties.
func _walk_cost(from: Vector2i, goal: Vector2i) -> int:
	if not _costs.has(goal):
		var width := _map.width
		var count := width * _map.height
		var costs := PackedInt32Array()
		costs.resize(count)
		costs.fill(1 << 20)
		costs[goal.y * width + goal.x] = 0
		var open: Array[Vector2i] = [goal]
		while not open.is_empty():
			var at: Vector2i = open.pop_front()
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next := at + step
				if next.x < 0 or next.y < 0 or next.x >= width or next.y >= _map.height:
					continue
				var terrain := _terrain(next)
				if terrain == null or terrain.is_impassable:
					continue
				var cost: int = costs[at.y * width + at.x] + terrain.move_cost
				if cost < costs[next.y * width + next.x]:
					costs[next.y * width + next.x] = cost
					open.append(next)
		_costs[goal] = costs
	return (_costs[goal] as PackedInt32Array)[from.y * _map.width + from.x] * 64 + _distance(from, goal)


func _terrain(cell: Vector2i) -> TacticsTerrainData:
	var symbol := _map.rows[cell.y][cell.x]
	var index := _map.legend_symbols.find(symbol)
	return _map.legend_terrains[index] as TacticsTerrainData if index >= 0 else null


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
