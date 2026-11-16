extends SceneTree

# Headless tests for incidents (Biến cố): for each of the seven, the
# trigger that makes a seeded soldier waver at the start of its side's
# phase, the reaction that calms it and the effect it has when it fires at
# the end of that phase; an enemy soldier defecting when its leader falls;
# seeds drawn from the battle seed (the same seed, the same seeds and
# events); karma, marks and leader traits shifting the odds over many
# seeds; the end-of-battle report. Side B is played by hand unless a check
# says otherwise. Cells are (col, row).

const Kit := preload("res://Tests/tactics_test_kit.gd")
const LAC_HONG: StringName = &"leader.lac_hong"
const MOON_SPEAR: StringName = &"leader.moon_spear"
const LIEU_MI: StringName = &"leader.lieu_mi"
const THIET_NHA: StringName = &"leader.thiet_nha"
const SPEARMAN: StringName = &"troop.spearman"
const SCENARIO: StringName = &"scenario.river_crossing"
const A: int = TacticsBattle.SIDE_A
const B: int = TacticsBattle.SIDE_B
const BAD: Array[StringName] = [&"incident.discontent", &"incident.riot", &"incident.flee", &"incident.betray"]

var _kit := Kit.new()


func _initialize() -> void:
	var ok := _run()
	_kit.free_battles()
	if ok:
		print("Tactics incident test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not _kit.load_catalog():
		return false
	var checks: Array[Callable] = [
		_check_rescue, _check_rescue_fades, _check_stand, _check_stand_calmed, _check_hesitates, _check_surge,
		_check_discontent, _check_discontent_calmed, _check_riot, _check_riot_calmed,
		_check_flee, _check_flee_calmed, _check_betray, _check_betray_calmed, _check_enemy_defects,
		_check_no_incidents_without_rules, _check_seeds_from_seed, _check_determinism,
		_check_karma_odds, _check_mark_odds, _check_trait_odds, _check_ai_side_pool,
		_check_karma_counts, _check_report, _check_refused_setup,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Tactics incident test failed in %s" % check.get_method())
			return false
	return true


# Rules with one hit per engagement, so hp goes down in small steps.
func _one_hit_rules() -> TacticsRulesData:
	var rules := _kit.catalog.rules.duplicate() as TacticsRulesData
	rules.hits_per_engagement = 1
	return rules


func _spearmen(count: int) -> Array:
	var squad: Array = []
	for index: int in count:
		squad.append(_kit.troop(SPEARMAN))
	return squad


func _leader(id: StringName, changes: Dictionary = {}) -> TacticsLeaderData:
	var all := {"keywords": _kit.keywords([])}
	all.merge(changes, true)
	return _kit.leader(id, [], all)


func _enable(battle: TacticsBattle, seeds: Dictionary = {}, seed_value: int = 1) -> bool:
	if not battle.set_incident_rules(_kit.catalog.incident_rules, seed_value):
		return false
	for unit: int in seeds:
		if not battle.set_incident_seed(unit, seeds[unit]):
			return false
	return true


func _state(battle: TacticsBattle, unit: int) -> Dictionary:
	return battle.get_unit_state(unit)


func _types(events: Array) -> Array:
	return events.map(func(event: Dictionary) -> StringName: return event["type"])


func _first(events: Array, type: StringName) -> Dictionary:
	var found := Kit.of_type(events, type)
	return found[0] if not found.is_empty() else {}


# Side A's phase now: plays rounds where `attacker` (side B) hits `target`
# once until `soldier` wavers at the start of A's phase; false after 30.
func _wound_until_wavering(battle: TacticsBattle, attacker: int, target: int, soldier: int) -> bool:
	for round_index: int in 30:
		if _state(battle, soldier)["wavering"] != &"":
			return true
		battle.end_phase()
		if battle.get_attack_targets(attacker).has(target):
			battle.attack(attacker, target)
		battle.end_phase()
	return Kit.expect_true("soldier %d never wavered" % soldier, false)


# Ends side A's phase and side B's (doing nothing), returning A's events.
func _pass_round(battle: TacticsBattle) -> Array:
	var events := battle.end_phase().duplicate()
	events.append_array(battle.end_phase())
	return events


# Lạc Hồng falls under 40% next to Thiết Nha; her spearman wavers, fires at
# the end of our phase and then takes the blow aimed at her.
func _check_rescue() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows(), false, _one_hit_rules())
	var leader := _kit.add(battle, A, _leader(LAC_HONG, {"attack_pct": 0, "hp_pct": 30}), Vector2i(5, 8), _spearmen(1))
	var soldier := leader + 1
	var enemy := _kit.add(battle, B, _leader(THIET_NHA, {"attack_pct": 300}), Vector2i(5, 7))
	if not _enable(battle, {soldier: &"incident.rescue"}):
		return false
	battle.start()
	if not _wound_until_wavering(battle, enemy, leader, soldier):
		return false
	var hp_pct := Kit.hp_of(battle, leader) * 100 / int(_state(battle, leader)["max_hp"])
	var events := battle.end_phase()
	var fired := _first(events, &"incident_fired")
	var mark := _first(events, &"mark_earned")
	var leader_hp := Kit.hp_of(battle, leader)
	var soldier_hp := Kit.hp_of(battle, soldier)
	var hit := battle.attack(enemy, leader)
	var damage := _first(hit, &"damage_dealt")
	return Kit.expect_true("leader under 40%% (%d%%)" % hp_pct, hp_pct <= 40) \
		and Kit.expect("fired incident", fired.get("incident"), &"incident.rescue") and Kit.expect("fired is good", fired.get("is_good"), true) \
		and Kit.expect("mark of the leader", mark.get("leader_id"), LAC_HONG) and Kit.expect("mark count", mark.get("count"), 1) \
		and Kit.expect("guarding", _state(battle, soldier)["is_guarding"], true) \
		and Kit.expect("the guard took the hit", damage.get("target"), soldier) and Kit.expect("guarded leader", damage.get("guarded"), leader) \
		and Kit.expect("leader hp kept", Kit.hp_of(battle, leader), leader_hp) and Kit.expect_true("guard hurt", Kit.hp_of(battle, soldier) < soldier_hp) \
		and Kit.expect("seed spent", battle.get_incident_seeds()[0]["stage"], &"fired")


# The leader holds her soldier in place and steps out of its reach: the
# rescue fades (calm "faded"), the seed waits again.
func _check_rescue_fades() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows(), false, _one_hit_rules())
	var leader := _kit.add(battle, A, _leader(LAC_HONG, {"attack_pct": 0, "hp_pct": 30}), Vector2i(5, 8), _spearmen(1))
	var soldier := leader + 1
	var enemy := _kit.add(battle, B, _leader(THIET_NHA, {"attack_pct": 300}), Vector2i(5, 7))
	var rules := _kit.catalog.incident_rules.duplicate() as TacticsIncidentRulesData
	var incidents: Array[TacticsIncidentData] = []
	for incident: TacticsIncidentData in rules.incidents:
		incidents.append(incident.duplicate() as TacticsIncidentData)
	incidents[0].radius_cells = 2
	rules.incidents = incidents
	if not battle.set_incident_rules(rules, 1) or not battle.set_incident_seed(soldier, &"incident.rescue"):
		return false
	battle.start()
	if not _wound_until_wavering(battle, enemy, leader, soldier):
		return false
	battle.set_order(leader, &"order.hold")
	battle.move_leader(leader, Vector2i(8, 8))
	var calmed := _first(battle.end_phase(), &"incident_calmed")
	return Kit.expect("calmed", calmed.get("reason"), &"faded") and Kit.expect("not wavering", _state(battle, soldier)["wavering"], &"") \
		and Kit.expect("seed waits", battle.get_incident_seeds()[0]["stage"], &"dormant")


# A spearman alone between two enemy leaders, its leader gone: it stands.
func _stand_battle() -> Array:
	var battle := _kit.new_battle(_kit.plain_rows(), false, _one_hit_rules())
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(5, 2), _spearmen(1))
	var soldier := leader + 1
	_kit.add(battle, B, _leader(THIET_NHA, {"attack_pct": 0}), Vector2i(4, 3))
	_kit.add(battle, B, _leader(LIEU_MI, {"attack_pct": 0, "min_range_cells": 1}), Vector2i(6, 3))
	_enable(battle, {soldier: &"incident.stand"})
	battle.start()
	battle.set_order(leader, &"order.hold")
	battle.move_leader(leader, Vector2i(5, 0))
	return [battle, leader, soldier]


func _check_stand() -> bool:
	var parts := _stand_battle()
	var battle: TacticsBattle = parts[0]
	var leader: int = parts[1]
	var soldier: int = parts[2]
	var wavered := _first(_pass_round(battle), &"soldier_wavered")
	var armor: int = _state(battle, soldier)["armor"]
	var events := battle.end_phase()
	var fired := _first(events, &"incident_fired")
	var buff := _first(events, &"buff_applied")
	battle.end_phase()
	var cell := Kit.cell_of(battle, soldier)
	battle.set_order(leader, &"order.follow")
	battle.move_leader(leader, Vector2i(2, 0))
	return Kit.expect("wavered", wavered.get("incident"), &"incident.stand") and Kit.expect("fired", fired.get("incident"), &"incident.stand") \
		and Kit.expect("armor buff", buff.get("amount"), 30) and Kit.expect("armor up", _state(battle, soldier)["armor"], armor + 30) \
		and Kit.expect("holds its ground", _state(battle, soldier)["holds_ground"], true) and Kit.expect("did not follow", Kit.cell_of(battle, soldier), cell)


# The leader comes back next to the soldier: it is no longer alone.
func _check_stand_calmed() -> bool:
	var parts := _stand_battle()
	var battle: TacticsBattle = parts[0]
	var leader: int = parts[1]
	var soldier: int = parts[2]
	_pass_round(battle)
	var is_wavering: bool = _state(battle, soldier)["wavering"] == &"incident.stand"
	battle.move_leader(leader, Kit.cell_of(battle, soldier) + Vector2i(0, -1))
	var events := battle.end_phase()
	return Kit.expect_true("wavered first", is_wavering) and Kit.expect("calmed", _first(events, &"incident_calmed").get("reason"), &"faded") \
		and Kit.expect("no incident", Kit.of_type(events, &"incident_fired").size(), 0)


# A wavering soldier hesitates: next to two enemies it could hit for free,
# it neither steps nor strikes in that phase.
func _check_hesitates() -> bool:
	var parts := _stand_battle()
	var battle: TacticsBattle = parts[0]
	var leader: int = parts[1]
	var soldier: int = parts[2]
	_pass_round(battle)
	var is_wavering: bool = _state(battle, soldier)["wavering"] == &"incident.stand"
	var cell := Kit.cell_of(battle, soldier)
	var events := battle.wait(leader)
	var strikes := Kit.of_type(events, &"engagement_started").filter(func(event: Dictionary) -> bool: return event["unit"] == soldier)
	return Kit.expect_true("wavered first", is_wavering) and Kit.expect("no strike while wavering", strikes.size(), 0) \
		and Kit.expect("no step while wavering", Kit.cell_of(battle, soldier), cell)


# A comrade next to it falls; it surges, even with its leader beside it.
func _check_surge() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows(), false, _one_hit_rules())
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR, {"attack_pct": 0, "lead_capacity": 4}), Vector2i(5, 6), _spearmen(4))
	var soldier := leader + 1
	var victim := leader + 4
	var enemy := _kit.add(battle, B, _leader(THIET_NHA, {"attack_pct": 2000}), Vector2i(3, 7))
	if not _enable(battle, {soldier: &"incident.surge"}) or not Kit.expect("victim beside", Kit.cell_of(battle, victim), Vector2i(4, 7)):
		return false
	battle.start()
	battle.set_order(leader, &"order.hold")
	var attack: int = _state(battle, soldier)["attack"]
	# Soldiers no longer strike into a counter that kills them, so the enemy
	# leader kills the comrade in its own phase.
	battle.end_phase()
	var died: bool = not Kit.of_type(battle.attack(enemy, victim), &"unit_died").is_empty()
	var wavered := _first(battle.end_phase(), &"soldier_wavered")
	var fired := _first(battle.end_phase(), &"incident_fired")
	return Kit.expect_true("the comrade fell", died and not _state(battle, victim)["alive"]) and Kit.expect("wavered", wavered.get("incident"), &"incident.surge") \
		and Kit.expect("fired next to the leader", fired.get("incident"), &"incident.surge") \
		and Kit.expect("attack up 60%", _state(battle, soldier)["attack"], attack * 160 / 100)


# Liễu Mi shoots a spearman left far from its leader, two phases running.
func _discontent_battle() -> Array:
	var battle := _kit.new_battle(_kit.plain_rows(), false, _one_hit_rules())
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(5, 6), _spearmen(1))
	var soldier := leader + 1
	var enemy := _kit.add(battle, B, _leader(LIEU_MI, {"attack_pct": 10}), Vector2i(5, 10))
	_enable(battle, {soldier: &"incident.discontent"})
	battle.start()
	battle.set_order(leader, &"order.hold")
	battle.move_leader(leader, Vector2i(5, 2))
	for round_index: int in 2:
		battle.end_phase()
		battle.attack(enemy, soldier)
		battle.end_phase()
	return [battle, leader, soldier, enemy]


func _check_discontent() -> bool:
	var parts := _discontent_battle()
	var battle: TacticsBattle = parts[0]
	var soldier: int = parts[2]
	var wavering: StringName = _state(battle, soldier)["wavering"]
	var fired := _first(battle.end_phase(), &"incident_fired")
	battle.end_phase()
	var free: bool = _state(battle, soldier)["acts_free"]
	var before := Kit.cell_of(battle, soldier)
	battle.end_phase()
	var after := Kit.cell_of(battle, soldier)
	return Kit.expect("wavered", wavering, &"incident.discontent") and Kit.expect("fired", fired.get("incident"), &"incident.discontent") \
		and Kit.expect_true("acts free", free) and Kit.expect_true("it left the hold for the archer", after != before and after.y > before.y)


func _check_discontent_calmed() -> bool:
	var parts := _discontent_battle()
	var battle: TacticsBattle = parts[0]
	var leader: int = parts[1]
	var soldier: int = parts[2]
	var is_wavering: bool = _state(battle, soldier)["wavering"] == &"incident.discontent"
	battle.move_leader(leader, Vector2i(5, 5))
	var calmed := _first(battle.end_phase(), &"incident_calmed")
	return Kit.expect_true("wavered first", is_wavering) and Kit.expect("calmed by the leader", calmed.get("reason"), &"leader")


# Two of four spearmen fall to two strong enemies; the seeded one riots.
func _riot_battle() -> Array:
	var battle := _kit.new_battle(_kit.plain_rows(), false, _one_hit_rules())
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR, {"attack_pct": 0, "lead_capacity": 4}), Vector2i(5, 6), _spearmen(4))
	var soldier := leader + 1
	var east := _kit.add(battle, B, _leader(THIET_NHA, {"attack_pct": 2000}), Vector2i(7, 6))
	var west := _kit.add(battle, B, _leader(THIET_NHA, {"attack_pct": 2000}), Vector2i(3, 6))
	_enable(battle, {soldier: &"incident.riot"})
	battle.start()
	battle.set_order(leader, &"order.hold")
	# Soldiers do not strike into a counter that kills them, so the enemy
	# leaders kill the two beside them in their own phase.
	battle.end_phase()
	battle.attack(east, leader + 3)
	battle.attack(west, leader + 2)
	battle.end_phase()
	return [battle, leader, soldier, leader + 4]


func _check_riot() -> bool:
	var parts := _riot_battle()
	var battle: TacticsBattle = parts[0]
	var leader: int = parts[1]
	var soldier: int = parts[2]
	var neighbour: int = parts[3]
	var wavering: StringName = _state(battle, soldier)["wavering"]
	var hp := Kit.hp_of(battle, neighbour)
	var from := Kit.cell_of(battle, neighbour)
	battle.set_order(leader, &"order.hold")
	battle.move_leader(leader, Vector2i(5, 3))
	var events := battle.end_phase()
	var shove := Kit.of_type(events, &"unit_moved").filter(func(event: Dictionary) -> bool: return event["kind"] == &"shove")
	return Kit.expect("wavered", wavering, &"incident.riot") and Kit.expect("fired", _first(events, &"incident_fired").get("incident"), &"incident.riot") \
		and Kit.expect("one shove", shove.size(), 1) and Kit.expect("shoved away", Kit.cell_of(battle, neighbour), from + Vector2i(-1, 0)) \
		and Kit.expect("jostled", Kit.hp_of(battle, neighbour), hp - 40)


func _check_riot_calmed() -> bool:
	var parts := _riot_battle()
	var battle: TacticsBattle = parts[0]
	var soldier: int = parts[2]
	var is_wavering: bool = _state(battle, soldier)["wavering"] == &"incident.riot"
	var calmed := _first(battle.end_phase(), &"incident_calmed")
	return Kit.expect_true("wavered first", is_wavering) and Kit.expect("the leader beside calms it", calmed.get("reason"), &"leader")


# The leader marches four cells away; an enemy stands two cells from the
# soldier it left behind.
func _flee_battle() -> Array:
	var battle := _kit.new_battle(_kit.plain_rows(), false, _one_hit_rules())
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(5, 6), _spearmen(1))
	var soldier := leader + 1
	_kit.add(battle, B, _leader(THIET_NHA, {"attack_pct": 0}), Vector2i(5, 9))
	_enable(battle, {soldier: &"incident.flee"})
	battle.start()
	battle.set_order(leader, &"order.hold")
	battle.move_leader(leader, Vector2i(5, 2))
	_pass_round(battle)
	return [battle, leader, soldier]


func _check_flee() -> bool:
	var parts := _flee_battle()
	var battle: TacticsBattle = parts[0]
	var soldier: int = parts[2]
	var wavering: StringName = _state(battle, soldier)["wavering"]
	var events := battle.end_phase()
	var fled := _first(events, &"unit_fled")
	var report: Dictionary = battle.get_battle_report()["units"][soldier]
	return Kit.expect("wavered", wavering, &"incident.flee") and Kit.expect("fled", fled.get("unit"), soldier) \
		and Kit.expect("to the edge", fled.get("to"), Vector2i(0, 7)) and Kit.expect("gone", _state(battle, soldier)["alive"], false) \
		and Kit.expect("has fled", _state(battle, soldier)["has_fled"], true) and Kit.expect("report", report["status"], &"fled") \
		and Kit.expect("mark kept", (report["marks"] as Array).size(), 1)


func _check_flee_calmed() -> bool:
	var parts := _flee_battle()
	var battle: TacticsBattle = parts[0]
	var leader: int = parts[1]
	var soldier: int = parts[2]
	var is_wavering: bool = _state(battle, soldier)["wavering"] == &"incident.flee"
	battle.move_leader(leader, Vector2i(5, 4))
	var calmed := _first(battle.end_phase(), &"incident_calmed")
	return Kit.expect_true("wavered first", is_wavering) and Kit.expect("no longer alone", calmed.get("reason"), &"faded") \
		and Kit.expect("still here", _state(battle, soldier)["alive"], true)


# Liễu Mi wears Nguyệt Thương down from three cells; his spearman, left
# three cells behind and three from her, goes over to her.
func _betray_battle() -> Array:
	var battle := _kit.new_battle(_kit.plain_rows(), false, _one_hit_rules())
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR, {"attack_pct": 0}), Vector2i(5, 5), _spearmen(1))
	var soldier := leader + 1
	_kit.add(battle, A, _leader(LAC_HONG, {"attack_pct": 0}), Vector2i(0, 11))
	var enemy := _kit.add(battle, B, _leader(LIEU_MI, {"attack_pct": 150}), Vector2i(3, 7))
	_enable(battle, {soldier: &"incident.betray"})
	battle.start()
	battle.set_order(leader, &"order.hold")
	battle.move_leader(leader, Vector2i(2, 5))
	_wound_until_wavering(battle, enemy, leader, soldier)
	return [battle, leader, soldier, enemy]


func _check_betray() -> bool:
	var parts := _betray_battle()
	var battle: TacticsBattle = parts[0]
	var leader: int = parts[1]
	var soldier: int = parts[2]
	var enemy: int = parts[3]
	var wavering: StringName = _state(battle, soldier)["wavering"]
	var events := battle.end_phase()
	var defected := _first(events, &"unit_defected")
	var report: Dictionary = battle.get_battle_report()["units"][soldier]
	return Kit.expect("wavered", wavering, &"incident.betray") and Kit.expect("defected to B", defected.get("side"), B) \
		and Kit.expect("joined Liễu Mi", _state(battle, soldier)["leader"], enemy) and Kit.expect("side", _state(battle, soldier)["side"], B) \
		and Kit.expect_true("left the old squad", not (_state(battle, leader)["soldiers"] as Array).has(soldier)) \
		and Kit.expect("in the new squad", _state(battle, enemy)["soldiers"], [soldier]) \
		and Kit.expect("report", report["has_defected"], true) and Kit.expect("start side", report["start_side"], A)


func _check_betray_calmed() -> bool:
	var parts := _betray_battle()
	var battle: TacticsBattle = parts[0]
	var leader: int = parts[1]
	var soldier: int = parts[2]
	var is_wavering: bool = _state(battle, soldier)["wavering"] == &"incident.betray"
	battle.move_leader(leader, Kit.cell_of(battle, soldier) + Vector2i(-1, -1))
	var calmed := _first(battle.end_phase(), &"incident_calmed")
	return Kit.expect_true("wavered first", is_wavering) and Kit.expect("calmed by the leader", calmed.get("reason"), &"leader") \
		and Kit.expect("still ours", _state(battle, soldier)["side"], A)


# An enemy soldier whose leader falls next to our strong leader comes over
# at the end of its side's phase.
func _check_enemy_defects() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows(), false)
	var ours := _kit.add(battle, A, _leader(THIET_NHA, {"attack_pct": 2000}), Vector2i(5, 6))
	var victim := _kit.add(battle, B, _leader(MOON_SPEAR, {"hp_pct": 10, "attack_pct": 0}), Vector2i(5, 5), _spearmen(1))
	var soldier := victim + 1
	_kit.add(battle, B, _leader(MOON_SPEAR), Vector2i(0, 0))
	if not _enable(battle, {soldier: &"incident.betray"}):
		return false
	battle.start()
	battle.attack(ours, victim)
	var killed: bool = not _state(battle, victim)["alive"]
	var wavered := _first(battle.end_phase(), &"soldier_wavered")
	var defected := _first(battle.end_phase(), &"unit_defected")
	return Kit.expect_true("enemy leader fell", killed) and Kit.expect("wavered", wavered.get("incident"), &"incident.betray") \
		and Kit.expect("came to us", defected.get("side"), A) and Kit.expect("under our leader", _state(battle, soldier)["leader"], ours)


func _scenario_battle(seed_value: int, ai_both: bool = false) -> TacticsBattle:
	var battle := TacticsBattle.new()
	_kit._battles.append(battle)
	battle.load_scenario(_kit.catalog.get_scenario(SCENARIO))
	if ai_both:
		battle.set_side_ai(A, true)
	battle.set_incident_rules(_kit.catalog.incident_rules, seed_value)
	return battle


func _check_no_incidents_without_rules() -> bool:
	var battle := TacticsBattle.new()
	_kit._battles.append(battle)
	battle.load_scenario(_kit.catalog.get_scenario(SCENARIO))
	battle.start()
	return Kit.expect("no seeds", battle.get_incident_seeds(), [])


# Seeds come from the battle seed: the same seed plants the same seeds,
# 1..3 on our side, and other seeds plant others.
func _check_seeds_from_seed() -> bool:
	var first := _scenario_battle(7)
	first.start()
	var again := _scenario_battle(7)
	again.start()
	var ours: int = first.get_incident_seeds().filter(func(seed_entry: Dictionary) -> bool: return first.get_unit_state(seed_entry["unit"])["side"] == A).size()
	var differs := false
	for seed_value: int in range(8, 16):
		var other := _scenario_battle(seed_value)
		other.start()
		differs = differs or other.get_incident_seeds() != first.get_incident_seeds()
	var no_leader := first.get_incident_seeds().all(func(seed_entry: Dictionary) -> bool: return first.get_unit_state(seed_entry["unit"])["role"] == &"soldier")
	return Kit.expect("same seeds", again.get_incident_seeds(), first.get_incident_seeds()) and Kit.expect_true("1..3 of ours (%d)" % ours, ours >= 1 and ours <= 3) \
		and Kit.expect_true("other seeds differ", differs) and Kit.expect_true("only soldiers", no_leader)


# Two AI sides play the river crossing to the end on several seeds: the
# same seed gives the same events and hash, and soldiers waver.
func _check_determinism() -> bool:
	var incident_count := 0
	for seed_value: int in [3, 11, 19, 27, 35, 43, 7, 22]:
		var runs: Array = []
		for run: int in 2:
			var battle := _scenario_battle(seed_value, true)
			var events := battle.start()
			runs.append([_types(events), battle.get_state_hash(), events.size()])
			incident_count += Kit.of_type(events, &"soldier_wavered").size() if run == 0 else 0
		if not Kit.expect("seed %d replays" % seed_value, runs[1], runs[0]):
			return false
	return Kit.expect_true("soldiers wavered on some seed (%d)" % incident_count, incident_count > 0)


func _bad_share(battle_setup: Callable, side: int) -> float:
	var bad := 0
	var total := 0
	for seed_value: int in 300:
		var battle := _scenario_battle(seed_value)
		battle_setup.call(battle)
		battle.start()
		for seed_entry: Dictionary in battle.get_incident_seeds():
			if battle.get_unit_state(seed_entry["unit"])["side"] == side:
				total += 1
				bad += 1 if BAD.has(seed_entry["incident"]) else 0
		_kit._battles.erase(battle)
		battle.free()
	return float(bad) / maxf(total, 1)


# Carried bait karma makes bad seeds likelier; rescue karma good ones.
func _check_karma_odds() -> bool:
	var plain := _bad_share(func(_battle: TacticsBattle) -> void: pass, A)
	var baited := _bad_share(func(battle: TacticsBattle) -> void: battle.set_karma(A, 12, 0), A)
	var rescued := _bad_share(func(battle: TacticsBattle) -> void: battle.set_karma(A, 0, 12), A)
	return Kit.expect_true("bait raises bad seeds (%.2f -> %.2f)" % [plain, baited], baited > plain + 0.1) \
		and Kit.expect_true("rescues lower them (%.2f -> %.2f)" % [plain, rescued], rescued < plain - 0.1)


# A soldier with three marks carries a seed far more often than its mates.
func _check_mark_odds() -> bool:
	var marked_count := 0
	var other_count := 0
	for seed_value: int in 200:
		var battle := _scenario_battle(seed_value)
		battle.set_unit_record(1, 42, 3, 0)
		battle.start()
		for seed_entry: Dictionary in battle.get_incident_seeds():
			marked_count += 1 if seed_entry["unit"] == 1 else 0
			other_count += 1 if seed_entry["unit"] == 2 else 0
		_kit._battles.erase(battle)
		battle.free()
	return Kit.expect_true("marked %d vs %d" % [marked_count, other_count], marked_count > other_count * 3)


# Nguyệt Thương is strict: his soldiers flee less than Liễu Mi's.
func _check_trait_odds() -> bool:
	var flee := {MOON_SPEAR: 0, LIEU_MI: 0}
	var seeds := {MOON_SPEAR: 0, LIEU_MI: 0}
	for seed_value: int in 400:
		var battle := _scenario_battle(seed_value)
		battle.start()
		for seed_entry: Dictionary in battle.get_incident_seeds():
			var state := battle.get_unit_state(seed_entry["unit"])
			var leader_id: StringName = battle.get_unit_state(state["leader"])["id"]
			if seeds.has(leader_id):
				seeds[leader_id] += 1
				flee[leader_id] += 1 if seed_entry["incident"] == &"incident.flee" else 0
		_kit._battles.erase(battle)
		battle.free()
	var strict := float(flee[MOON_SPEAR]) / maxf(seeds[MOON_SPEAR], 1)
	var plain := float(flee[LIEU_MI]) / maxf(seeds[LIEU_MI], 1)
	return Kit.expect_true("strict leader's soldiers flee less (%.2f vs %.2f)" % [strict, plain], strict < plain * 0.7)


func _check_ai_side_pool() -> bool:
	for seed_value: int in 60:
		var battle := _scenario_battle(seed_value)
		battle.start()
		for seed_entry: Dictionary in battle.get_incident_seeds():
			var is_enemy: bool = battle.get_unit_state(seed_entry["unit"])["side"] == B
			if is_enemy and not [&"incident.flee", &"incident.betray"].has(seed_entry["incident"]):
				return Kit.expect_true("enemy seed %s" % seed_entry["incident"], false)
		_kit._battles.erase(battle)
		battle.free()
	return true


# Bait: hit while the leader stands far. Rescue: the leader's move ends
# next to a hurt soldier with an enemy beside it.
func _check_karma_counts() -> bool:
	var parts := _discontent_battle()
	var battle: TacticsBattle = parts[0]
	var bait: int = battle.get_karma(A)["bait"]
	var rescue := _kit.new_battle(_kit.plain_rows(), false, _one_hit_rules())
	var leader := _kit.add(rescue, A, _leader(MOON_SPEAR), Vector2i(5, 3), _spearmen(1))
	var enemy := _kit.add(rescue, B, _leader(THIET_NHA, {"attack_pct": 600}), Vector2i(5, 10))
	_enable(rescue)
	rescue.start()
	rescue.set_order(leader, &"order.hold")
	rescue.end_phase()
	rescue.move_leader(enemy, Kit.cell_of(rescue, leader + 1) + Vector2i(0, 1))
	rescue.attack(enemy, leader + 1)
	rescue.end_phase()
	var hurt := Kit.hp_of(rescue, leader + 1) * 100 / int(_state(rescue, leader + 1)["max_hp"])
	var events := rescue.move_leader(leader, Kit.cell_of(rescue, leader + 1) + Vector2i(1, 0))
	var karma := _first(events, &"karma_changed")
	return Kit.expect("two bait", bait, 2) and Kit.expect_true("soldier hurt (%d%%)" % hurt, hurt <= 50) \
		and Kit.expect("rescue karma", karma.get("kind"), &"rescue") and Kit.expect("rescue count", rescue.get_karma(A)["rescue"], 1)


func _check_report() -> bool:
	var battle := _scenario_battle(5)
	battle.set_unit_record(1, 77, 1, 2)
	battle.set_karma(A, 3, 4)
	battle.start()
	var report := battle.get_battle_report()
	var entry: Dictionary = report["units"][1]
	var karma: Dictionary = report["karma"][A]
	return Kit.expect("record id", entry["record_id"], 77) and Kit.expect("status", entry["status"], &"alive") \
		and Kit.expect("leader id", entry["leader_id"], &"leader.lac_hong") and Kit.expect("carried karma", karma["carried_bait"], 3) \
		and Kit.expect("units", (report["units"] as Array).size(), battle.get_unit_count()) and Kit.expect("not over", report["is_finished"], false)


func _check_refused_setup() -> bool:
	var battle := _scenario_battle(1)
	print("Tactics incident test: the next 3 errors (refused setup) are expected")
	var leader_seed := battle.set_incident_seed(0, &"incident.flee")
	var unknown := battle.set_incident_seed(1, &"incident.unknown")
	battle.start()
	var late := battle.set_incident_rules(_kit.catalog.incident_rules, 2)
	return Kit.expect("no seed on a leader", leader_seed, false) and Kit.expect("unknown incident", unknown, false) and Kit.expect("after start", late, false)
