extends SceneTree
## Measures how the soldiers fight: plays seeded battles of the river
## crossing, side B by the AI and side A by a simple scripted policy (random
## squads and orders per seed, incidents on), and prints the average soldiers
## lost per battle on each side and the share of soldier attacks that killed
## their target or traded well (dealt more than they took and lived).
## `--policy=idle` plays side A as a player who never gives a command (it
## only ends its phases), to check that the enemy beats a player who does
## nothing.
## Run: godot --headless --path . --script res://Tools/tactics_brain_probe.gd -- --battles=200 [--policy=idle]

const CATALOG_PATH: String = "res://Data/Tactics/tactics_catalog.tres"
const SCENARIO_PATH: String = "res://Data/Tactics/Scenarios/river_crossing.tres"
const ORDERS: Array[StringName] = [&"order.follow", &"order.vanguard", &"order.flank", &"order.free"]
const MAX_COMMANDS: int = 400

var _rng := RandomNumberGenerator.new()
var _is_idle: bool = false
## Per enemy leader: what it declared at the start of our phase and what it
## then did, to measure how often the shown intent comes true.
var _declared: Dictionary = {}


func _initialize() -> void:
	var battles := 200
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--battles="):
			battles = int(argument.get_slice("=", 1))
		elif argument == "--policy=idle":
			_is_idle = true
	var catalog := load(CATALOG_PATH) as TacticsCatalog
	var scenario := load(SCENARIO_PATH) as TacticsScenarioData
	var totals := {
		"lost_a": 0, "lost_b": 0, "attacks_a": 0, "attacks_b": 0, "good_a": 0, "good_b": 0,
		"kills_a": 0, "kills_b": 0, "suicides_a": 0, "suicides_b": 0, "wins_a": 0, "rounds": 0,
		"leaders_lost_a": 0, "leaders_lost_b": 0, "skills_a": 0, "skills_b": 0,
		"endings": {},
		"intents": 0, "intents_kept": 0, "intent_cells_kept": 0,
	}
	var start_ms := Time.get_ticks_msec()
	for seed_value: int in range(1, battles + 1):
		_play(seed_value, catalog, scenario, totals)
	var elapsed := Time.get_ticks_msec() - start_ms
	var count := float(battles)
	print("Tactics brain probe: %d battles in %d ms, side A %s" % [battles, elapsed, "idle" if _is_idle else "scripted"])
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
	quit(0)


func _play(seed_value: int, catalog: TacticsCatalog, scenario: TacticsScenarioData, totals: Dictionary) -> void:
	_rng.seed = seed_value
	var battle := TacticsBattle.new()
	battle.set_side_ai(TacticsBattle.SIDE_B, true)
	var squads: Array = []
	for leader: TacticsLeaderData in scenario.leaders_a:
		var squad: Array[TacticsTroopData] = []
		for slot: int in leader.lead_capacity:
			squad.append(catalog.troops[_rng.randi_range(0, catalog.troops.size() - 1)])
		squads.append(squad)
	# The idle player keeps the scenario's squads and orders.
	if _is_idle or not battle.load_scenario_with_squads(scenario, TacticsBattle.SIDE_A, squads):
		battle.load_scenario(scenario)
	battle.set_incident_rules(catalog.incident_rules, seed_value)
	var events: Array = battle.start().duplicate()
	for unit: Dictionary in battle.get_units():
		if unit["role"] == &"leader" and unit["side"] == TacticsBattle.SIDE_A and not _is_idle:
			events.append_array(battle.set_order(unit["index"], ORDERS[_rng.randi_range(0, ORDERS.size() - 1)]))
	_count(battle, events, totals)
	var commands := 0
	while not battle.is_finished() and commands < MAX_COMMANDS:
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
	var ending := "%s_%s" % ["a" if battle.get_winner() == TacticsBattle.SIDE_A else "b", battle.get_end_reason()]
	totals["endings"][ending] = int(totals["endings"].get(ending, 0)) + 1
	totals["rounds"] += battle.get_round()
	battle.free()


## Move toward the nearest (sometimes the second nearest) enemy leader and
## attack the weakest enemy in reach.
func _play_leader(battle: TacticsBattle, leader: int) -> Array:
	var events: Array = []
	var cell: Vector2i = battle.get_unit_state(leader)["cell"]
	var targets: Array = []
	for unit: Dictionary in battle.get_units():
		if unit["alive"] and unit["side"] == TacticsBattle.SIDE_B and unit["role"] == &"leader":
			targets.append(unit)
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _distance(a["cell"], cell) < _distance(b["cell"], cell))
	if not targets.is_empty() and battle.get_attack_targets(leader).is_empty():
		var goal: Vector2i = targets[mini(targets.size() - 1, 1 if _rng.randf() < 0.3 else 0)]["cell"]
		var best := cell
		for reachable: Vector2i in battle.get_reachable_cells(leader):
			if _distance(reachable, goal) < _distance(best, goal):
				best = reachable
		if best != cell:
			events.append_array(battle.move_leader(leader, best))
	if battle.is_finished() or not battle.can_act(leader):
		return events
	var weakest := -1
	for target: int in battle.get_attack_targets(leader):
		if weakest < 0 or int(battle.get_unit_state(target)["hp"]) < int(battle.get_unit_state(weakest)["hp"]):
			weakest = target
	if weakest >= 0:
		events.append_array(battle.attack(leader, weakest))
	else:
		events.append_array(battle.wait(leader))
	return events


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


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
