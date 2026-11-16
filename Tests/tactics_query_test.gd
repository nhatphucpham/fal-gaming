extends SceneTree

# Headless tests for the queries the tactics screen asks before a command:
# a scenario loaded with other squads, can_move / can_act, attack targets,
# the cells a skill can be cast on, the skill preview against the real
# cast, and the modifiers the forecast lists. Every query must leave the
# state hash unchanged. Cells are (col, row).

const Kit := preload("res://Tests/tactics_test_kit.gd")
const A: int = TacticsBattle.SIDE_A
const B: int = TacticsBattle.SIDE_B

var _kit := Kit.new()


func _initialize() -> void:
	var ok := _run()
	_kit.free_battles()
	if ok:
		print("Tactics query test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not _kit.load_catalog():
		return false
	var checks: Array[Callable] = [
		_check_scenario_squads, _check_refused_squads, _check_move_and_act, _check_attack_targets,
		_check_skill_cells, _check_skill_preview_damage, _check_skill_preview_support,
		_check_forecast_modifiers, _check_counter_modifiers,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Tactics query test failed in %s" % check.get_method())
			return false
	return true


func _scenario() -> TacticsScenarioData:
	return _kit.catalog.get_scenario(&"scenario.river_crossing")


func _new_battle() -> TacticsBattle:
	var battle := TacticsBattle.new()
	_kit._battles.append(battle)
	return battle


func _squads_of(battle: TacticsBattle, side: int) -> Array:
	var squads: Array = []
	for unit: Dictionary in battle.get_units():
		if unit["role"] == &"leader" and unit["side"] == side:
			squads.append(Array(unit["soldiers"]).map(func(soldier: int) -> StringName: return battle.get_unit_state(soldier)["id"]))
	return squads


# A soldier moved from Nguyệt Thương to Lạc Hồng (capacity 4 + 1).
func _check_scenario_squads() -> bool:
	var archer := _kit.catalog.get_troop(&"troop.archer")
	var spearman := _kit.catalog.get_troop(&"troop.spearman")
	var shieldman := _kit.catalog.get_troop(&"troop.shieldman")
	var swordsman := _kit.catalog.get_troop(&"troop.swordsman")
	var rider := _kit.catalog.get_troop(&"troop.rider")
	var squads: Array = [[spearman, spearman, archer, shieldman, rider], [spearman, swordsman], [archer, archer, shieldman]]
	var battle := _new_battle()
	if not Kit.expect_true("load with squads", battle.load_scenario_with_squads(_scenario(), A, squads)):
		return false
	var lac_hong := battle.get_unit_state(0)
	return Kit.expect("side A squads", _squads_of(battle, A), [
		[&"troop.spearman", &"troop.spearman", &"troop.archer", &"troop.shieldman", &"troop.rider"],
		[&"troop.spearman", &"troop.swordsman"], [&"troop.archer", &"troop.archer", &"troop.shieldman"],
	]) and Kit.expect("Lạc Hồng capacity", lac_hong["capacity"], 5) \
		and Kit.expect("side B keeps its squads", _squads_of(battle, B), [
			[&"troop.rider", &"troop.rider", &"troop.swordsman"], [&"troop.spearman", &"troop.archer", &"troop.kite_scout"],
		]) and Kit.expect("starts", battle.start()[0]["type"], &"battle_started")


# Over capacity, or the wrong number of squads: refused, nothing set up.
func _check_refused_squads() -> bool:
	var rider := _kit.catalog.get_troop(&"troop.rider")
	var battle := _new_battle()
	var too_many: Array = [[], [rider, rider, rider, rider], []]
	var over := battle.load_scenario_with_squads(_scenario(), A, too_many)
	var after_over := battle.get_unit_count()
	var wrong_count := battle.load_scenario_with_squads(_scenario(), A, [[], []])
	return Kit.expect("over capacity refused", over, false) and Kit.expect("nothing set up", after_over, 0) \
		and Kit.expect("wrong count refused", wrong_count, false) and Kit.expect("start refused", battle.start(), [])


func _check_move_and_act() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _kit.leader(&"leader.moon_spear"), Vector2i(5, 8))
	var enemy := _kit.add(battle, B, _kit.leader(&"leader.thiet_nha"), Vector2i(5, 1))
	battle.start()
	var hash := battle.get_state_hash()
	var fresh := battle.can_move(leader) and battle.can_act(leader) and not battle.can_move(enemy) and not battle.can_act(enemy)
	var same_hash := battle.get_state_hash() == hash
	battle.move_leader(leader, Vector2i(5, 6))
	var moved := not battle.can_move(leader) and battle.can_act(leader)
	battle.wait(leader)
	var done := not battle.can_move(leader) and not battle.can_act(leader)
	return Kit.expect_true("fresh leader can move and act, the enemy cannot", fresh) \
		and Kit.expect_true("a moved leader can still act", moved) and Kit.expect_true("a waiting leader is done", done) \
		and Kit.expect_true("queries keep the hash", same_hash)


func _check_attack_targets() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _kit.leader(&"leader.moon_spear"), Vector2i(5, 8))
	var near := _kit.add(battle, B, _kit.leader(&"leader.thiet_nha"), Vector2i(5, 6))
	var far := _kit.add(battle, B, _kit.leader(&"leader.ba_khac"), Vector2i(1, 1))
	battle.start()
	var hash := battle.get_state_hash()
	var targets := battle.get_attack_targets(leader)
	var enemy_targets := battle.get_attack_targets(near)
	return Kit.expect("in range (2 cells)", targets, [near]) and Kit.expect("not the far one", targets.has(far), false) \
		and Kit.expect("not in the enemy's phase", enemy_targets, []) and Kit.expect("hash", battle.get_state_hash(), hash)


# Nguyệt Thương's thrust (single, range 2) needs an enemy within 2 cells.
func _check_skill_cells() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _kit.leader(&"leader.moon_spear"), Vector2i(5, 8))
	var near := _kit.add(battle, B, _kit.leader(&"leader.thiet_nha"), Vector2i(6, 7))
	_kit.add(battle, B, _kit.leader(&"leader.ba_khac"), Vector2i(1, 1))
	battle.start()
	var not_ready := battle.get_skill_cells(leader)
	# Two phases without moving fill the focus charge.
	for phase: int in 4:
		battle.end_phase()
	var hash := battle.get_state_hash()
	var cells := battle.get_skill_cells(leader)
	return Kit.expect("not ready: no cells", not_ready, []) and Kit.expect("ready", battle.get_skill_charge(leader)["is_ready"], true) \
		and Kit.expect("the near enemy's cell", cells, [battle.get_unit_state(near)["cell"]]) and Kit.expect("hash", battle.get_state_hash(), hash)


# Ba Khắc's fire rain: the preview's cells, targets and damage are the cast's.
func _check_skill_preview_damage() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var caster := _kit.add(battle, A, _kit.leader(&"leader.ba_khac"), Vector2i(5, 8))
	var first := _kit.add(battle, B, _kit.leader(&"leader.thiet_nha"), Vector2i(5, 7))
	var second := _kit.add(battle, B, _kit.leader(&"leader.lieu_mi"), Vector2i(6, 6))
	battle.start()
	# Taking 300 damage fills fire rain's charge: let the enemies hit it.
	while not battle.get_skill_charge(caster)["is_ready"] and not battle.is_finished():
		battle.wait(caster)
		battle.end_phase()
		for enemy: int in [first, second]:
			if battle.get_attack_targets(enemy).has(caster):
				battle.attack(enemy, caster)
		battle.end_phase()
	var hash := battle.get_state_hash()
	var preview := battle.preview_skill(caster, Vector2i(5, 7))
	var out_of_range := battle.preview_skill(caster, Vector2i(0, 0))
	if not Kit.expect_true("preview valid", preview["is_valid"]) or not Kit.expect("hash", battle.get_state_hash(), hash):
		return false
	var events := battle.use_skill(caster, Vector2i(5, 7))
	var used: Dictionary = Kit.of_type(events, &"skill_used")[0]
	var resolved: Dictionary = Kit.of_type(events, &"skill_resolved")[0]
	var results: Array = []
	for result: Dictionary in resolved["results"]:
		results.append({"unit": result["unit"], "amount": result["amount"], "hp_after": result["hp_after"], "is_dead": result["is_dead"]})
	return Kit.expect("out of range invalid", out_of_range["is_valid"], false) and Kit.expect("two targets", preview["targets"].size(), 2) \
		and Kit.expect("cells", preview["cells"], used["cells"]) and Kit.expect("targets", preview["targets"], used["targets"]) \
		and Kit.expect("results", preview["results"], results) and Kit.expect("fire zone cells", preview["zone_cells"].size(), 9)


# Lạc Hồng's rally banner: cast on its own cell, its soldiers are buffed.
func _check_skill_preview_support() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var spearman := _kit.catalog.get_troop(&"troop.spearman")
	var caster := _kit.add(battle, A, _kit.leader(&"leader.lac_hong"), Vector2i(5, 8), [spearman, spearman])
	_kit.add(battle, B, _kit.leader(&"leader.thiet_nha"), Vector2i(5, 1))
	battle.start()
	for phase: int in 6:
		battle.end_phase()
	var cells := battle.get_skill_cells(caster)
	var preview := battle.preview_skill(caster, Vector2i(5, 8))
	return Kit.expect("own cell only", cells, [Vector2i(5, 8)]) and Kit.expect("buffed soldiers", preview["buffed"], [caster + 1, caster + 2]) \
		and Kit.expect("no damage", preview["results"], [])


# An archer leader shooting at a leader in a forest: the forest's ranged
# cut is listed; a fort's armor too.
func _check_forecast_modifiers() -> bool:
	var rows := _kit.plain_rows()
	rows[5] = ".....f......"
	rows[3] = ".....t......"
	var battle := _kit.new_battle(rows)
	var archer := _kit.add(battle, A, _kit.leader(&"leader.lieu_mi"), Vector2i(5, 8))
	var in_forest := _kit.add(battle, B, _kit.leader(&"leader.thiet_nha"), Vector2i(5, 5))
	var on_fort := _kit.add(battle, B, _kit.leader(&"leader.ba_khac"), Vector2i(4, 5))
	battle.start()
	var forest := battle.forecast_engagement(archer, in_forest)
	var plain := battle.forecast_engagement(archer, on_fort)
	return Kit.expect("forest listed", forest["attacker_modifiers"], [&"terrain.forest"]) \
		and Kit.expect("plain: nothing", plain["attacker_modifiers"], []) \
		and Kit.expect("no counter from melee out of range", forest["defender_modifiers"], [])


# A spearman soldier strikes first: its long weapon heads its counter's list.
func _check_counter_modifiers() -> bool:
	var rows := _kit.plain_rows()
	rows[6] = ".....t......"
	var battle := _kit.new_battle(rows)
	var attacker := _kit.add(battle, A, _kit.leader(&"leader.thiet_nha"), Vector2i(5, 8))
	var defender := _kit.add(battle, B, _kit.leader(&"leader.moon_spear", [], {"max_range_cells": 1}), Vector2i(5, 6))
	_kit.add(battle, B, _kit.leader(&"leader.ba_khac"), Vector2i(1, 1))
	battle.start()
	battle.move_leader(attacker, Vector2i(5, 7))
	var forecast := battle.forecast_engagement(attacker, defender)
	return Kit.expect("first strike", forecast["is_first_strike"], true) \
		and Kit.expect("fort armor on the defender", forecast["attacker_modifiers"], [&"terrain.fort"]) \
		and Kit.expect("long weapon first", forecast["defender_modifiers"], [&"keyword.long_weapon"])
