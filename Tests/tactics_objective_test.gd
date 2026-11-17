extends SceneTree

# Headless tests for the objective kinds (Docs/systems/tactics_objectives.md),
# each won and lost: take the pass (held after the enemy turn; time runs
# out), hold the city (held for its rounds; the keep lost a round later;
# waves come on their round), escort (the cart walks its road and leaves
# by the edge; it holds on order and stops by an enemy; it is lost; the
# enemy strikes it first, and under fog goes where it could be), break the
# siege (a leader on an exit leaves with its squad; enough leaders out
# win; the leader that must get out falls), bring down the general (slain;
# hurt, he turns to flee, runs and gets out; he keeps to his post). A win
# lists the side goals met and pays their supplies; the report carries
# them; the same commands give the same state hash.

const Kit := preload("res://Tests/tactics_test_kit.gd")
const A: int = TacticsBattle.SIDE_A
const B: int = TacticsBattle.SIDE_B

var _kit := Kit.new()


func _initialize() -> void:
	var ok := _run()
	_kit.free_battles()
	if ok:
		print("Tactics objective test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not _kit.load_catalog():
		return false
	var checks: Array[Callable] = [
		_check_take_pass_win, _check_take_pass_time, _check_hold_city_win, _check_keep_lost, _check_waves,
		_check_escort_win, _check_convoy_hold_and_halt, _check_convoy_lost, _check_convoy_targeted, _check_convoy_under_fog,
		_check_siege_win, _check_siege_needs_count, _check_siege_leader_lost, _check_general_slain, _check_general_flees,
		_check_general_keeps_post, _check_goals, _check_determinism,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Tactics objective test failed in %s" % check.get_method())
			return false
	return true


func _objective(kind: StringName, changes: Dictionary = {}) -> TacticsObjectiveData:
	var objective := TacticsObjectiveData.new()
	objective.id = &"objective.test"
	objective.kind = kind
	for key: String in changes:
		objective.set(key, changes[key])
	return objective


func _goal(kind: StringName, value: int, supplies: int) -> TacticsGoalData:
	var goal := TacticsGoalData.new()
	goal.kind = kind
	goal.value = value
	goal.supplies = supplies
	return goal


func _cells(list: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.assign(list)
	return cells


func _rules(max_rounds: int) -> TacticsRulesData:
	var rules := _kit.catalog.rules.duplicate() as TacticsRulesData
	rules.max_rounds = max_rounds
	return rules


func _ended(events: Array) -> Dictionary:
	var ended := Kit.of_type(events, &"battle_ended")
	return ended[0] if not ended.is_empty() else {}


func _expect_end(battle: TacticsBattle, events: Array, winner: int, reason: StringName) -> bool:
	var ended := _ended(events)
	return Kit.expect("ended", [battle.is_finished(), battle.get_winner(), battle.get_end_reason()], [true, winner, reason]) \
		and Kit.expect("battle_ended last", events.back()["type"] if not events.is_empty() else &"", &"battle_ended") \
		and Kit.expect("battle_ended says why", ended.get("reason"), reason)


# Every phase until the battle ends or `phases` ran out; returns the
# events of the last phase.
func _run_phases(battle: TacticsBattle, phases: int) -> Array:
	var events: Array = []
	for phase: int in phases:
		if battle.is_finished():
			break
		events = battle.end_phase()
	return events


func _check_take_pass_win() -> bool:
	var battle := _kit.new_site_battle(_kit.plain_rows(), [[_kit.site("pass_fort", {"reinforce_round": 0, "reinforce_leader": null}), Vector2i(5, 5), B]])
	_kit.add(battle, A, _kit.leader(&"leader.lac_hong"), Vector2i(5, 6))
	_kit.add(battle, B, _kit.leader(&"leader.ba_khac"), Vector2i(5, 11))
	battle.set_objective(_objective(&"objective_kind.take_pass", {"site": 0}))
	battle.start()
	battle.move_leader(0, Vector2i(5, 5))
	var taken := battle.end_phase()
	var owner: int = battle.get_sites(A)[0]["owner"]
	var early := battle.is_finished()
	var events := battle.end_phase()
	return Kit.expect("captured at the end of our turn", [Kit.of_type(taken, &"site_changed").size(), owner, early], [1, A, false]) \
		and _expect_end(battle, events, A, &"objective")


func _check_take_pass_time() -> bool:
	var battle := _kit.new_site_battle(_kit.plain_rows(), [[_kit.site("pass_fort", {"reinforce_round": 0, "reinforce_leader": null}), Vector2i(5, 5), B]], false, _rules(2))
	_kit.add(battle, A, _kit.leader(&"leader.lac_hong"), Vector2i(1, 1))
	_kit.add(battle, B, _kit.leader(&"leader.ba_khac"), Vector2i(5, 11))
	battle.set_objective(_objective(&"objective_kind.take_pass", {"site": 0}))
	battle.start()
	return _expect_end(battle, _run_phases(battle, 6), B, &"time_limit")


func _city(rounds: int, waves: Array = []) -> TacticsBattle:
	var battle := _kit.new_site_battle(_kit.plain_rows(), [[_kit.site("keep"), Vector2i(5, 5), A]])
	_kit.add(battle, A, _kit.leader(&"leader.lac_hong"), Vector2i(5, 5))
	_kit.add(battle, B, _kit.leader(&"leader.ba_khac"), Vector2i(11, 11))
	var typed: Array[TacticsWaveData] = []
	typed.assign(waves)
	battle.set_objective(_objective(&"objective_kind.hold_city", {"site": 0, "rounds": rounds, "waves": typed}))
	return battle


func _check_hold_city_win() -> bool:
	var battle := _city(2)
	battle.start()
	var events := _run_phases(battle, 3)
	var early := battle.is_finished()
	events = _run_phases(battle, 1)
	return Kit.expect("not before the last round ends", early, false) and _expect_end(battle, events, A, &"held")


# The enemy takes the keep and still has it at the end of the next round.
func _check_keep_lost() -> bool:
	var battle := _kit.new_site_battle(_kit.plain_rows(), [[_kit.site("keep"), Vector2i(5, 5), A]])
	_kit.add(battle, A, _kit.leader(&"leader.lac_hong"), Vector2i(1, 1))
	var enemy := _kit.add(battle, B, _kit.leader(&"leader.ba_khac"), Vector2i(5, 7))
	battle.set_objective(_objective(&"objective_kind.hold_city", {"site": 0, "rounds": 9}))
	battle.start()
	battle.end_phase()
	battle.move_leader(enemy, Vector2i(5, 5))
	var taken := battle.end_phase()
	var owner: int = battle.get_sites(A)[0]["owner"]
	var early := battle.is_finished()
	battle.end_phase()
	var events := battle.end_phase()
	return Kit.expect("the enemy takes it", [Kit.of_type(taken, &"site_changed").size(), owner, early], [1, B, false]) \
		and _expect_end(battle, events, B, &"keep_lost")


func _check_waves() -> bool:
	var wave := TacticsWaveData.new()
	wave.round = 2
	var leaders: Array[TacticsLeaderData] = [_kit.leader(&"leader.ho_bao")]
	wave.leaders = leaders
	wave.entry_cells = _cells([Vector2i(0, 11)])
	var battle := _city(5, [wave])
	var count := battle.get_unit_count()
	battle.start()
	var first := battle.end_phase()
	var sent_early: int = battle.get_objective_state()["waves_sent"]
	battle.end_phase()
	battle.end_phase()
	var state := battle.get_objective_state()
	var arrived := battle.get_units().slice(count)
	return Kit.expect("none in round 1", Kit.of_type(first, &"unit_arrived").size(), 0) \
		and Kit.expect("arrived at the enemy's turn of round 2", [arrived.size(), arrived[0]["arrival"] if not arrived.is_empty() else &"", arrived[0]["side"] if not arrived.is_empty() else -1], [1, &"wave", B]) \
		and Kit.expect("near its entry", Kit.cell_of(battle, count).distance_to(Vector2i(0, 11)) <= 1.0, true) \
		and Kit.expect("waves sent", [sent_early, state["waves_sent"], (state["waves"] as Array).size()], [0, 1, 1])


# A road up column 5 from (5, 10) to the top edge.
func _road() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row: int in range(10, -1, -1):
		cells.append(Vector2i(5, row))
	return cells


func _escort(cart_changes: Dictionary = {}, ai_b: bool = false, enemy_cell: Vector2i = Vector2i(11, 11)) -> TacticsBattle:
	var battle := _kit.new_site_battle(_kit.plain_rows(), [], ai_b)
	_kit.add(battle, A, _kit.leader(&"leader.lac_hong"), Vector2i(8, 10))
	_kit.add(battle, B, _kit.leader(&"leader.ba_khac"), enemy_cell)
	battle.set_objective(_objective(&"objective_kind.escort", {"road_cells": _road(), "convoy": _kit.troop(&"troop.supply_cart", cart_changes)}))
	return battle


func _convoy(battle: TacticsBattle) -> int:
	return battle.get_objective_state()["convoy"]


func _check_escort_win() -> bool:
	var battle := _escort()
	battle.start()
	var cart := _convoy(battle)
	var start := Kit.cell_of(battle, cart)
	var path := battle.get_convoy_path()
	var walk := battle.end_phase()
	var moved := Kit.of_type(walk, &"unit_moved").filter(func(event: Dictionary) -> bool: return event["unit"] == cart)
	var after_one := Kit.cell_of(battle, cart)
	var events := _run_phases(battle, 12)
	var escaped := Kit.of_type(events, &"unit_escaped")
	return Kit.expect("starts on the road", start, Vector2i(5, 10)) and Kit.expect("the path it will walk", path, [Vector2i(5, 10), Vector2i(5, 9), Vector2i(5, 8), Vector2i(5, 7)]) \
		and Kit.expect("walks after our turn", [moved.size(), after_one], [1, Vector2i(5, 7)]) \
		and Kit.expect("leaves by the edge", escaped.map(func(event: Dictionary) -> int: return event["unit"]), [cart]) \
		and _expect_end(battle, events, A, &"escorted") and Kit.expect("not by the enemy", battle.get_round() <= 4, true)


func _check_convoy_hold_and_halt() -> bool:
	var battle := _escort()
	battle.start()
	var cart := _convoy(battle)
	var order := battle.set_convoy_hold(true)
	var halted := battle.end_phase()
	var held_at := Kit.cell_of(battle, cart)
	# An enemy beside the road ahead stops it short.
	var blocked := _escort({}, false, Vector2i(6, 8))
	blocked.start()
	var blocked_cart := _convoy(blocked)
	var short_path := blocked.get_convoy_path()
	blocked.end_phase()
	return Kit.expect("the order", Kit.of_type(order, &"convoy_halted").map(func(event: Dictionary) -> StringName: return event["kind"]), [&"hold"]) \
		and Kit.expect("holds", [held_at, Kit.of_type(halted, &"convoy_halted").map(func(event: Dictionary) -> StringName: return event["kind"])], [Vector2i(5, 10), [&"holding"]]) \
		and Kit.expect("stops before the enemy", [short_path, Kit.cell_of(blocked, blocked_cart)], [[Vector2i(5, 10), Vector2i(5, 9)], Vector2i(5, 9)])


func _check_convoy_lost() -> bool:
	var battle := _escort({"hp_pct": 1}, false, Vector2i(4, 10))
	battle.start()
	battle.set_convoy_hold(true)
	battle.end_phase()
	var events := battle.attack(1, _convoy(battle))
	return _expect_end(battle, events, B, &"convoy_lost")


# The enemy strikes the cart before our leader standing just as near.
func _check_convoy_targeted() -> bool:
	var battle := _escort({}, true, Vector2i(6, 8))
	battle.start()
	battle.set_convoy_hold(true)
	battle.move_leader(0, Vector2i(7, 9))
	var events := battle.end_phase()
	var strikes := Kit.of_type(events, &"engagement_started").filter(func(event: Dictionary) -> bool: return event["unit"] == 1)
	return Kit.expect("the cart first", strikes.map(func(event: Dictionary) -> int: return event["target"]), [_convoy(battle)])


# Under fog the enemy does not know where the cart is: it heads for the
# road's end, not for the cart.
func _check_convoy_under_fog() -> bool:
	var environment := TacticsScenarioData.new()
	environment.id = &"scenario.objective_test"
	environment.fog_of_war = true
	environment.weather = _kit.catalog.get_weather(&"weather.clear")
	var cycle: Array[TacticsDaytimeData] = [_kit.catalog.get_daytime(&"daytime.day")]
	environment.daytimes = cycle
	var battle := _escort({}, true, Vector2i(10, 1))
	battle.set_environment(environment)
	battle.start()
	battle.set_convoy_hold(true)
	var cart := _convoy(battle)
	var seen := battle.is_unit_seen(B, cart)
	var before := Kit.cell_of(battle, 1)
	battle.end_phase()
	var after := Kit.cell_of(battle, 1)
	var road_end := Vector2i(5, 0)
	return Kit.expect("the cart unseen", seen, false) \
		and Kit.expect_true("toward the road's end (%s -> %s)" % [before, after], after.distance_to(road_end) < before.distance_to(road_end)) \
		and Kit.expect("not at the cart", after.distance_to(Kit.cell_of(battle, cart)) > 2.0, true)


func _siege(count: int, ours: Array[TacticsLeaderData], cells: Array[Vector2i]) -> TacticsBattle:
	var battle := _kit.new_site_battle(_kit.plain_rows(), [])
	for index: int in ours.size():
		_kit.add(battle, A, ours[index], cells[index], [_kit.troop(&"troop.spearman")])
	_kit.add(battle, B, _kit.leader(&"leader.ba_khac"), Vector2i(11, 11))
	battle.set_objective(_objective(&"objective_kind.break_siege", {"count": count, "required_leader": 0, "rounds": 9, "exit_cells": _cells([Vector2i(0, 5), Vector2i(0, 6)])}))
	return battle


func _check_siege_win() -> bool:
	var battle := _siege(1, [_kit.leader(&"leader.lac_hong"), _kit.leader(&"leader.moon_spear")], _cells([Vector2i(2, 5), Vector2i(8, 8)]))
	battle.start()
	var events := battle.move_leader(0, Vector2i(0, 5))
	var escaped := Kit.of_type(events, &"unit_escaped")
	return Kit.expect("the leader and its soldier get out", escaped.size(), 2) and _expect_end(battle, events, A, &"broke_out") \
		and Kit.expect("counted", battle.get_objective_state()["escaped"], 1)


func _check_siege_needs_count() -> bool:
	var battle := _siege(2, [_kit.leader(&"leader.lac_hong"), _kit.leader(&"leader.moon_spear")], _cells([Vector2i(2, 5), Vector2i(2, 7)]))
	battle.start()
	battle.move_leader(2, Vector2i(0, 6))
	var after_one := battle.is_finished()
	var events := battle.move_leader(0, Vector2i(0, 5))
	return Kit.expect("one of two is not enough", after_one, false) and _expect_end(battle, events, A, &"broke_out")


func _check_siege_leader_lost() -> bool:
	var battle := _siege(1, [_kit.leader(&"leader.lac_hong", [], {"hp_pct": 1}), _kit.leader(&"leader.moon_spear")], _cells([Vector2i(10, 11), Vector2i(2, 5)]))
	battle.start()
	battle.end_phase()
	var events := battle.attack(battle.get_unit_count() - 1, 0)
	return _expect_end(battle, events, B, &"leader_lost")


func _general(changes: Dictionary, ai_b: bool, general_cell: Vector2i, hold_cells: int = 2, flee_pct: int = 30) -> TacticsBattle:
	var battle := _kit.new_site_battle(_kit.plain_rows(), [], ai_b)
	_kit.add(battle, A, _kit.leader(&"leader.lac_hong"), Vector2i(5, 6))
	_kit.add(battle, B, _kit.leader(&"leader.hac_ho", [], changes), general_cell)
	battle.set_objective(_objective(&"objective_kind.slay_general", {"general": 0, "flee_hp_pct": flee_pct, "general_hold_cells": hold_cells, "exit_cells": _cells([Vector2i(11, 5)])}))
	return battle


func _check_general_slain() -> bool:
	var battle := _general({"hp_pct": 1}, false, Vector2i(5, 5))
	battle.start()
	var events := battle.attack(0, 1)
	return _expect_end(battle, events, A, &"general_slain")


# At his flee point (here 100%: any hp) he turns at a turn's start, runs
# for his exit and gets out.
func _check_general_flees() -> bool:
	var battle := _general({}, true, Vector2i(9, 5), 2, 100)
	var start := battle.start()
	var state := battle.get_objective_state()
	var fleeing := Kit.of_type(start, &"general_fleeing")
	var turn := battle.end_phase()
	return Kit.expect("the post is known", state["cell"], Vector2i(9, 5)) \
		and Kit.expect("turns to flee", [fleeing.size(), state["general_fleeing"]], [1, true]) \
		and Kit.expect("gets out", Kit.of_type(turn, &"unit_escaped").map(func(event: Dictionary) -> int: return event["unit"]), [1]) \
		and _expect_end(battle, turn, B, &"general_fled")


# He does not leave his post to strike or to chase.
func _check_general_keeps_post() -> bool:
	var battle := _general({}, true, Vector2i(5, 1), 0)
	battle.start()
	battle.end_phase()
	var after := Kit.cell_of(battle, 1)
	return Kit.expect("kept to his post", after, Vector2i(5, 1)) and Kit.expect("no strike from there", battle.get_unit_state(0)["hp"], battle.get_unit_state(0)["max_hp"]) \
		and Kit.expect("unhurt, he does not flee", battle.get_objective_state()["general_fleeing"], false)


func _check_goals() -> bool:
	var battle := _kit.new_site_battle(_kit.plain_rows(), [
		[_kit.site("pass_fort", {"reinforce_round": 0, "reinforce_leader": null}), Vector2i(5, 5), B],
		[_kit.site("village"), Vector2i(0, 0), -1], [_kit.site("camp"), Vector2i(11, 0), B],
	])
	_kit.add(battle, A, _kit.leader(&"leader.lac_hong"), Vector2i(5, 6))
	_kit.add(battle, B, _kit.leader(&"leader.ba_khac"), Vector2i(5, 11))
	var goals: Array[TacticsGoalData] = [
		_goal(&"goal.villages_safe", 0, 2), _goal(&"goal.no_losses", 0, 3), _goal(&"goal.by_round", 1, 4), _goal(&"goal.camps_taken", 0, 5),
	]
	battle.set_objective(_objective(&"objective_kind.take_pass", {"site": 0, "goals": goals}))
	battle.start()
	battle.move_leader(0, Vector2i(5, 5))
	battle.end_phase()
	var events := battle.end_phase()
	var met := Kit.of_type(events, &"goal_met").map(func(event: Dictionary) -> int: return event["goal"])
	var report := battle.get_battle_report()
	var shown: Array = battle.get_objective_state()["goals"]
	return _expect_end(battle, events, A, &"objective") and Kit.expect("met", met, [0, 1, 2]) \
		and Kit.expect("their supplies", [battle.get_supplies(A), report["supplies"], report["goals_met"]], [9, 9, [0, 1, 2]]) \
		and Kit.expect("shown met", shown.map(func(goal: Dictionary) -> bool: return goal["is_met"]), [true, true, true, false])


func _check_determinism() -> bool:
	var hashes: Array[String] = []
	for run: int in 2:
		var battle := _escort({}, true, Vector2i(6, 6))
		battle.start()
		_run_phases(battle, 8)
		hashes.append(battle.get_state_hash())
	var held := _escort({}, true, Vector2i(6, 6))
	held.start()
	held.set_convoy_hold(true)
	_run_phases(held, 8)
	return Kit.expect("same commands, same hash", hashes[0], hashes[1]) and Kit.expect_true("a held cart, another hash", held.get_state_hash() != hashes[0])
