extends SceneTree

# Headless tests for squads, skills, passives and zones of the tactics
# core: each order's soldier placement (with the march anticipation shift
# and the preview matching the real move), the `free` order, soldier target
# priority, each skill charge mechanism, skill targets and events, each
# passive kind and timed zones. Side B is played by hand unless a check
# says otherwise. Cells are (col, row).

const Kit := preload("res://Tests/tactics_test_kit.gd")
const LAC_HONG: StringName = &"leader.lac_hong"
const MOON_SPEAR: StringName = &"leader.moon_spear"
const LIEU_MI: StringName = &"leader.lieu_mi"
const BA_KHAC: StringName = &"leader.ba_khac"
const THIET_NHA: StringName = &"leader.thiet_nha"
const SPEARMAN: StringName = &"troop.spearman"
const A: int = TacticsBattle.SIDE_A
const B: int = TacticsBattle.SIDE_B

var _kit := Kit.new()


func _initialize() -> void:
	var ok := _run()
	_kit.free_battles()
	if ok:
		print("Tactics squad test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not _kit.load_catalog():
		return false
	var checks: Array[Callable] = [
		_check_order_slots, _check_anticipation_shift, _check_blocked_slots, _check_free_seeks,
		_check_free_helps, _check_soldier_priority, _check_charge_turns, _check_charge_engagements,
		_check_charge_focus, _check_charge_damage_taken, _check_charge_soldiers_lost,
		_check_area_skill_and_fire, _check_ai_skill, _check_ai_own_side_skill, _check_stat_passives, _check_squad_passive,
		_check_environment_passive, _check_pull_passive, _check_growth_passive,
		_check_zone_sides, _check_side_b_durations, _check_causes,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Tactics squad test failed in %s" % check.get_method())
			return false
	return true


func _spear() -> TacticsLeaderData:
	return _kit.leader(MOON_SPEAR, [], {"keywords": _kit.keywords([])})


func _spearmen(count: int, changes: Dictionary = {}) -> Array:
	var squad: Array = []
	for index: int in count:
		squad.append(_kit.troop(SPEARMAN, changes))
	return squad


func _soldier_cells(battle: TacticsBattle, leader: int) -> Array:
	return battle.get_unit_state(leader)["soldiers"].map(func(soldier: int) -> Vector2i: return Kit.cell_of(battle, soldier))


func _preview_cells(preview: Array) -> Array:
	return preview.map(func(entry: Dictionary) -> Vector2i: return entry["cell"])


# Ends `count` full rounds (side A's phase, then side B's).
func _rounds(battle: TacticsBattle, count: int) -> Array:
	var events: Array = []
	for round: int in count:
		events.append_array(battle.end_phase())
		events.append_array(battle.end_phase())
	return events


# Moon spear (heading north) at (5,8) with three spearmen moves to (5,6);
# the soldiers start on the follow slots (5,9), (4,8), (6,8).
func _check_order_slots() -> bool:
	var expected := {
		&"order.follow": [Vector2i(5, 7), Vector2i(4, 6), Vector2i(6, 6)],
		&"order.vanguard": [Vector2i(5, 5), Vector2i(4, 5), Vector2i(6, 5)],
		# The third flank slot (3,6) is 5 steps away; (3,7) is the nearest reachable cell.
		&"order.flank": [Vector2i(4, 6), Vector2i(6, 6), Vector2i(3, 7)],
		&"order.hold": [Vector2i(5, 9), Vector2i(4, 8), Vector2i(6, 8)],
	}
	for order: StringName in expected:
		var battle := _kit.new_battle(_kit.plain_rows())
		var leader := _kit.add(battle, A, _spear(), Vector2i(5, 8), _spearmen(3))
		_kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(11, 0))
		battle.start()
		battle.set_order(leader, order)
		var hash_before := battle.get_state_hash()
		var preview := _preview_cells(battle.preview_squad(leader, Vector2i(5, 6)))
		if not Kit.expect("preview changes nothing", battle.get_state_hash(), hash_before):
			return false
		battle.move_leader(leader, Vector2i(5, 6))
		var cells := _soldier_cells(battle, leader)
		if not (Kit.expect("%s preview equals the move" % order, preview, cells) and Kit.expect("%s cells" % order, cells, expected[order])):
			return false
	return true


# Two moves north in a row push the vanguard one cell further ahead; a turn
# east starts a new streak.
func _check_anticipation_shift() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _spear(), Vector2i(5, 10), _spearmen(3))
	_kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(11, 0))
	battle.start()
	battle.set_order(leader, &"order.vanguard")
	battle.move_leader(leader, Vector2i(5, 8))
	if not Kit.expect("first move: no shift", _soldier_cells(battle, leader), [Vector2i(5, 7), Vector2i(4, 7), Vector2i(6, 7)]):
		return false
	_rounds(battle, 1)
	var preview := _preview_cells(battle.preview_squad(leader, Vector2i(5, 6)))
	battle.move_leader(leader, Vector2i(5, 6))
	var shifted := [Vector2i(5, 4), Vector2i(4, 4), Vector2i(6, 4)]
	if not (Kit.expect("second move: shifted", _soldier_cells(battle, leader), shifted) and Kit.expect("preview", preview, shifted) \
			and Kit.expect("streak", battle.get_unit_state(leader)["heading_streak"], 2)):
		return false
	_rounds(battle, 1)
	battle.move_leader(leader, Vector2i(7, 6))
	var state := battle.get_unit_state(leader)
	return Kit.expect("heading east", [state["heading"], state["heading_streak"]], [Vector2i(1, 0), 1]) \
		and Kit.expect("east slots, no shift", battle.get_formation_slots(leader), [Vector2i(8, 6), Vector2i(8, 5), Vector2i(8, 7)])


# Vanguard slots on a river: each soldier takes the reachable cell nearest
# its slot (then the cheaper path), and the preview agrees.
func _check_blocked_slots() -> bool:
	var rows := _kit.plain_rows()
	rows[7] = "rrrrrrrrrrrr"
	var battle := _kit.new_battle(rows)
	var leader := _kit.add(battle, A, _spear(), Vector2i(5, 9), _spearmen(3))
	_kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(11, 0))
	battle.start()
	battle.set_order(leader, &"order.vanguard")
	var preview := _preview_cells(battle.preview_squad(leader, Vector2i(5, 8)))
	battle.move_leader(leader, Vector2i(5, 8))
	var expected := [Vector2i(5, 9), Vector2i(4, 8), Vector2i(6, 8)]
	return Kit.expect("blocked slots", _soldier_cells(battle, leader), expected) and Kit.expect("preview", preview, expected)


# A free rider goes for the enemy nearest by path: the one across the river
# is as near in a straight line but far around the bridge.
func _check_free_seeks() -> bool:
	var rows := _kit.plain_rows()
	rows[7] = "rrrrrrrrrrrb"
	var battle := _kit.new_battle(rows)
	var leader := _kit.add(battle, A, _spear(), Vector2i(5, 9), [_kit.troop(&"troop.rider")])
	_kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(5, 5))
	var near := _kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(10, 10))
	battle.start()
	battle.set_order(leader, &"order.free")
	var events := battle.wait(leader)
	var engagements := Kit.of_type(events, &"engagement_started")
	return Kit.expect("rider cell", Kit.cell_of(battle, leader + 1), Vector2i(9, 10)) \
		and Kit.expect("rider attacked the near enemy", engagements.map(func(event: Dictionary) -> int: return event["target"]), [near])


# A free rider helps an allied soldier attacked since its last move, even
# when another enemy is nearer.
func _check_free_helps() -> bool:
	var targets: Array = []
	for is_attacked: bool in [true, false]:
		var battle := _kit.new_battle(_kit.plain_rows())
		var holder := _kit.add(battle, A, _spear(), Vector2i(2, 8), _spearmen(1))
		var rider_leader := _kit.add(battle, A, _spear(), Vector2i(5, 8), [_kit.troop(&"troop.rider")])
		var attacker := _kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(2, 11))
		var near := _kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(7, 9))
		battle.start()
		battle.set_order(holder, &"order.hold")
		battle.set_order(rider_leader, &"order.hold")
		battle.end_phase()
		if is_attacked:
			battle.move_leader(attacker, Vector2i(2, 10))
			battle.attack(attacker, holder + 1)
		battle.end_phase()
		battle.set_order(rider_leader, &"order.free")
		var events := battle.wait(rider_leader)
		targets.append(Kit.of_type(events, &"engagement_started").map(func(event: Dictionary) -> int: return event["target"]))
		if not Kit.expect("enemies", [attacker, near], [4, 5]):
			return false
	return Kit.expect("helps, else nearest", targets, [[4], [5]])


# A soldier first attacks an enemy that can hit its own leader, then the
# lowest hp.
func _check_soldier_priority() -> bool:
	var targets: Array = []
	for threat_cell: Vector2i in [Vector2i(5, 7), Vector2i(3, 9)]:
		var battle := _kit.new_battle(_kit.plain_rows())
		var leader := _kit.add(battle, A, _spear(), Vector2i(5, 8), [_kit.troop(&"troop.archer")])
		var threat := _kit.add(battle, B, _kit.leader(THIET_NHA), threat_cell)
		var weak := _kit.add(battle, B, _kit.leader(THIET_NHA, [], {"hp_pct": 50}), Vector2i(7, 9))
		battle.start()
		battle.set_order(leader, &"order.hold")
		var events := battle.wait(leader)
		targets.append(Kit.of_type(events, &"engagement_started").map(func(event: Dictionary) -> int: return event["target"]))
		if not Kit.expect("ids", [threat, weak], [2, 3]):
			return false
	return Kit.expect("threat first, else lowest hp", targets, [[2], [3]])


# charge.turns (rally banner, 3): one per own phase; the skill is never
# cast on its own; using it buffs the squad's attack 25% for 2 rounds and
# resets the charge.
func _check_charge_turns() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _kit.leader(LAC_HONG), Vector2i(5, 8), _spearmen(1))
	_kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(11, 0))
	battle.start()
	var values: Array = []
	var events: Array = []
	for round: int in 4:
		values.append(battle.get_skill_charge(leader)["value"])
		events.append_array(_rounds(battle, 1))
	if not (Kit.expect("pips", values, [0, 1, 2, 3]) and Kit.expect("never cast alone", Kit.of_type(events, &"skill_used").size(), 0) \
			and Kit.expect("ready", battle.get_skill_charge(leader)["is_ready"], true)):
		return false
	var used := battle.use_skill(leader, Kit.cell_of(battle, leader))
	var buffs := Kit.of_type(used, &"buff_applied")
	if not (Kit.expect("buffed", buffs.map(func(event: Dictionary) -> Array: return [event["unit"], event["amount"], event["end_round"]]), [[leader + 1, 25, 7]]) \
			and Kit.expect("attack 55 * 125%", battle.get_unit_state(leader + 1)["attack"], 68) \
			and Kit.expect("reset", battle.get_skill_charge(leader)["value"], 0) \
			and Kit.expect("resolved", Kit.of_type(used, &"skill_resolved").size(), 1)):
		return false
	var ended := Kit.of_type(_rounds(battle, 2), &"buff_ended")
	return Kit.expect("buff ends", ended.size(), 1) and Kit.expect("attack back", battle.get_unit_state(leader + 1)["attack"], 55)


# charge.engagements (chain arrows, 2): one per engagement. The chain hits
# three enemies at 120%, 84%, 58% of 66 attack on 25 armor: 63, 44, 30.
func _check_charge_engagements() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _kit.leader(LIEU_MI), Vector2i(5, 8))
	var first := _kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(5, 5))
	_kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(7, 5))
	_kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(9, 5))
	battle.start()
	var values: Array = []
	for round: int in 2:
		battle.attack(leader, first)
		values.append(battle.get_skill_charge(leader)["value"])
		_rounds(battle, 1)
	var events := battle.use_skill(leader, Vector2i(5, 5))
	var used: Dictionary = Kit.of_type(events, &"skill_used")[0]
	var results: Array = Kit.of_type(events, &"skill_resolved")[0]["results"]
	return Kit.expect("pips", values, [1, 2]) and Kit.expect("chain targets", used["targets"], [1, 2, 3]) \
		and Kit.expect("falloff", results.map(func(result: Dictionary) -> int: return result["amount"]), [63, 44, 30]) \
		and Kit.expect("damage caused by the skill", Kit.of_type(events, &"damage_dealt").all(func(event: Dictionary) -> bool: return event["cause"] == used["id"]), true)


# charge.focus (piercing thrust, 2): one per phase without moving; a move
# loses it.
func _check_charge_focus() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _kit.leader(MOON_SPEAR), Vector2i(5, 8))
	_kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(11, 0))
	battle.start()
	var values: Array = []
	for round: int in 2:
		_rounds(battle, 1)
		values.append(battle.get_skill_charge(leader)["value"])
	battle.move_leader(leader, Vector2i(5, 7))
	values.append(battle.get_skill_charge(leader)["value"])
	_rounds(battle, 1)
	values.append(battle.get_skill_charge(leader)["value"])
	return Kit.expect("focus", values, [1, 2, 0, 0])


# charge.damage_taken (fire rain, 300): 4 hits of 6600 / 130 = 50, twice,
# fill it (capped at the threshold).
func _check_charge_damage_taken() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _kit.leader(BA_KHAC), Vector2i(5, 6))
	var enemy := _kit.add(battle, B, _spear(), Vector2i(5, 5))
	battle.start()
	var values: Array = []
	for round: int in 2:
		battle.end_phase()
		battle.attack(enemy, leader)
		values.append(battle.get_skill_charge(leader)["value"])
		battle.end_phase()
	return Kit.expect("damage taken", values, [200, 300]) and Kit.expect("ready", battle.get_skill_charge(leader)["is_ready"], true)


# charge.soldiers_lost (blood oath, 2): one per soldier of the squad lost.
func _check_charge_soldiers_lost() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _kit.leader(THIET_NHA), Vector2i(5, 8), _spearmen(2, {"hp_pct": 1}))
	var archer_a := _kit.add(battle, B, _kit.leader(LIEU_MI), Vector2i(5, 11))
	var archer_b := _kit.add(battle, B, _kit.leader(LIEU_MI), Vector2i(2, 8))
	battle.start()
	battle.end_phase()
	var died: Array = []
	died.append_array(Kit.of_type(battle.attack(archer_a, leader + 1), &"unit_died"))
	died.append_array(Kit.of_type(battle.attack(archer_b, leader + 2), &"unit_died"))
	return Kit.expect("soldiers died", died.size(), 2) and Kit.expect("charge", battle.get_skill_charge(leader)["value"], 2) \
		and Kit.expect("ready", battle.get_skill_charge(leader)["is_ready"], true)


# A copy of a sample leader's skill that charges after one own phase.
func _quick_skill(leader_id: StringName) -> TacticsSkillData:
	var skill := _kit.catalog.get_leader(leader_id).skill.duplicate() as TacticsSkillData
	skill.charge = &"charge.turns"
	skill.charge_threshold = 1
	return skill


# Fire rain: a 3 x 3 square around the cell, 80% magic damage (72 * 80 /
# 120 = 48) to the enemies inside, then a fire zone for 2 rounds that burns
# 60 at the start of each of their phases, and expires.
func _check_area_skill_and_fire() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _kit.leader(BA_KHAC, [], {"skill": _quick_skill(BA_KHAC)}), Vector2i(5, 9))
	var center := _kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(5, 5))
	var corner := _kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(6, 6))
	_kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(8, 5))
	battle.start()
	_rounds(battle, 1)
	var events := battle.use_skill(leader, Vector2i(5, 5))
	var used: Dictionary = Kit.of_type(events, &"skill_used")[0]
	var results: Array = Kit.of_type(events, &"skill_resolved")[0]["results"]
	var zone: Dictionary = Kit.of_type(events, &"zone_created")[0]
	if not (Kit.expect("area", [used["cells"].size(), used["targets"]], [9, [center, corner]]) \
			and Kit.expect("results", results.map(func(result: Dictionary) -> Array: return [result["unit"], result["amount"]]), [[center, 48], [corner, 48]]) \
			and Kit.expect("zone", [zone["zone"], zone["cells"].size(), zone["end_round"], zone["cause"]], [&"zone.fire", 9, 4, used["id"]])):
		return false
	var later := _rounds(battle, 2)
	var burns := Kit.of_type(later, &"damage_dealt").filter(func(event: Dictionary) -> bool: return event["source_id"] == &"zone.fire")
	return Kit.expect("burns twice per unit", burns.size(), 4) and Kit.expect("hp", Kit.hp_of(battle, center), 1275 - 48 - 120) \
		and Kit.expect("expired", Kit.of_type(later, &"zone_expired").size(), 1) and Kit.expect("no zones", battle.get_zones(), [])


# An AI leader whose skill is ready declares it and uses it.
func _check_ai_skill() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows(), true)
	var target := _kit.add(battle, A, _spear(), Vector2i(5, 10))
	var enemy := _kit.add(battle, B, _kit.leader(BA_KHAC, [], {"skill": _quick_skill(BA_KHAC), "move_points": 0}), Vector2i(5, 6))
	battle.start()
	battle.end_phase()
	var intent: Dictionary = battle.get_enemy_intents()[0]
	var events := battle.end_phase()
	var used := Kit.of_type(events, &"skill_used")
	return Kit.expect("declared", [intent["unit"], intent["action"], intent["target"]], [enemy, &"skill", target]) \
		and Kit.expect("used on the target", used.map(func(event: Dictionary) -> Array: return [event["unit"], event["cell"]]), [[enemy, Vector2i(5, 10)]])


# An AI leader casts a ready skill for its own side (rally banner, cast
# range 0) on its own cell instead of waiting, and declares it; a skill of
# its own side that cannot target its cell is never declared.
func _check_ai_own_side_skill() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows(), true)
	_kit.add(battle, A, _spear(), Vector2i(0, 11))
	var banner := _kit.add(battle, B, _kit.leader(LAC_HONG, [], {"skill": _quick_skill(LAC_HONG), "move_points": 0}), Vector2i(11, 0), _spearmen(1))
	battle.start()
	battle.end_phase()
	var intent: Dictionary = battle.get_enemy_intents()[0]
	if not Kit.expect("declared on itself", [intent["unit"], intent["action"], intent["target"], intent["target_cell"]], [banner, &"skill", banner, Vector2i(11, 0)]):
		return false
	var events := battle.end_phase()
	var used := Kit.of_type(events, &"skill_used")
	var buffs := Kit.of_type(events, &"buff_applied")
	if not (Kit.expect("cast on its cell", used.map(func(event: Dictionary) -> Array: return [event["unit"], event["cell"]]), [[banner, Vector2i(11, 0)]]) \
			and Kit.expect("soldier buffed", buffs.map(func(event: Dictionary) -> int: return event["unit"]), [banner + 1])):
		return false
	var single := _quick_skill(LAC_HONG)
	single.target = &"skill_target.single"
	var refused := _kit.new_battle(_kit.plain_rows(), true)
	var spear := _kit.add(refused, A, _spear(), Vector2i(0, 11))
	_kit.add(refused, B, _kit.leader(LAC_HONG, [], {"skill": single, "move_points": 0}), Vector2i(11, 0))
	refused.start()
	refused.end_phase()
	var waiting: Dictionary = refused.get_enemy_intents()[0]
	return Kit.expect("not legal, not declared", [waiting["action"], waiting["target"]], [&"wait", spear]) \
		and Kit.expect("not cast", Kit.of_type(refused.end_phase(), &"skill_used"), [])


# Stat modifiers: iron will (+15 armor on a fort) and pack fury (+20%
# attack with 2 allies next to the leader).
func _check_stat_passives() -> bool:
	var rows := _kit.plain_rows()
	rows[8] = ".....t......"
	var battle := _kit.new_battle(rows)
	var iron_will: Array[TacticsPassiveData] = [_kit.catalog.get_passive(&"tactics_passive.iron_will")]
	var on_fort := _kit.add(battle, A, _kit.leader(LAC_HONG, iron_will), Vector2i(5, 8))
	var on_plain := _kit.add(battle, A, _kit.leader(LAC_HONG, iron_will), Vector2i(1, 8))
	var pack_fury: Array[TacticsPassiveData] = [_kit.catalog.get_passive(&"tactics_passive.pack_fury")]
	var pack := _kit.add(battle, B, _kit.leader(BA_KHAC, pack_fury), Vector2i(5, 2), [_kit.troop(&"troop.rider"), _kit.troop(&"troop.rider")])
	var alone := _kit.add(battle, B, _kit.leader(BA_KHAC, pack_fury), Vector2i(10, 2))
	# Mage armor 10; the fort adds 20 for anyone and the passive 15.
	return Kit.expect("iron will", [battle.get_unit_state(on_fort)["armor"], battle.get_unit_state(on_plain)["armor"]], [45, 10]) \
		and Kit.expect("pack fury", [battle.get_unit_state(pack)["attack"], battle.get_unit_state(alone)["attack"]], [86, 72])


# Squad modifier: drilled ranks gives the soldiers +10% attack and cover,
# and one more soldier of capacity.
func _check_squad_passive() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var drilled: Array[TacticsPassiveData] = [_kit.catalog.get_passive(&"tactics_passive.drilled_ranks")]
	var leader := _kit.add(battle, A, _kit.leader(LAC_HONG, drilled), Vector2i(5, 6), _spearmen(5))
	var soldier := battle.get_unit_state(leader + 1)
	if not (Kit.expect("capacity", battle.get_unit_state(leader)["capacity"], 5) and Kit.expect("attack", soldier["attack"], 60) \
			and Kit.expect("keywords", soldier["keywords"], [&"keyword.long_weapon", &"keyword.cover"])):
		return false
	print("Tactics squad test: the next error (squad over capacity) is expected")
	return Kit.expect("over capacity refused", battle.add_leader_with_squad(A, _kit.leader(LAC_HONG), Vector2i(5, 10), _spearmen(5)), -1)


# Environment: wind trail leaves a wind zone (radius 1) where lieu mi
# stops; ranged hits into it deal half: 66 * 50 / 110 = 30, not 60.
func _check_environment_passive() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var trail: Array[TacticsPassiveData] = [_kit.catalog.get_passive(&"tactics_passive.wind_trail")]
	var leader := _kit.add(battle, A, _kit.leader(LIEU_MI, trail), Vector2i(5, 10))
	var archer := _kit.add(battle, B, _kit.leader(LIEU_MI), Vector2i(5, 6))
	battle.start()
	var before: int = battle.forecast_engagement(archer, leader)["attacker_damage_per_hit"]
	var events := battle.move_leader(leader, Vector2i(5, 8))
	var zone: Dictionary = Kit.of_type(events, &"zone_created")[0]
	var after: int = battle.forecast_engagement(archer, leader)["attacker_damage_per_hit"]
	var expired := Kit.of_type(_rounds(battle, 1), &"zone_expired")
	return Kit.expect("zone", [zone["zone"], zone["cells"].size(), zone["end_round"]], [&"zone.wind", 5, 2]) \
		and Kit.expect("passive event", Kit.of_type(events, &"passive_triggered").size(), 1) \
		and Kit.expect("ranged ward", [before, after], [60, 30]) and Kit.expect("expires next round", expired.size(), 1)


# Special weapon: hook spear pulls the target it hit one cell closer.
func _check_pull_passive() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var hook: Array[TacticsPassiveData] = [_kit.catalog.get_passive(&"tactics_passive.hook_spear")]
	var leader := _kit.add(battle, A, _kit.leader(MOON_SPEAR, hook, {"keywords": _kit.keywords([])}), Vector2i(5, 8))
	var enemy := _kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(5, 6))
	battle.start()
	var events := battle.attack(leader, enemy)
	var pulls := Kit.of_type(events, &"unit_moved").filter(func(event: Dictionary) -> bool: return event["kind"] == &"pull")
	return Kit.expect("pulled", pulls.map(func(event: Dictionary) -> Array: return [event["unit"], event["from"], event["to"]]), [[enemy, Vector2i(5, 6), Vector2i(5, 7)]]) \
		and Kit.expect("cell", Kit.cell_of(battle, enemy), Vector2i(5, 7))


# Skill growth: defeating an enemy leader widens ba khac's skill area.
func _check_growth_passive() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var growth: Array[TacticsPassiveData] = [_kit.catalog.get_passive(&"tactics_passive.warlord_growth")]
	var leader := _kit.add(battle, A, _kit.leader(BA_KHAC, growth), Vector2i(5, 8))
	var weak := _kit.add(battle, B, _kit.leader(THIET_NHA, [], {"hp_pct": 5}), Vector2i(5, 7))
	_kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(11, 0))
	battle.start()
	var events := battle.attack(leader, weak)
	var grew := Kit.of_type(events, &"skill_grew")
	return Kit.expect("grew", grew.map(func(event: Dictionary) -> Array: return [event["unit"], event["area_bonus"]]), [[leader, 1]]) \
		and Kit.expect("area bonus", battle.get_skill_charge(leader)["area_bonus"], 1) and Kit.expect("still running", battle.is_finished(), false)


# A zone works for its side: fire burns only the caster's enemies, and a
# wind trail only wards the leader's allies.
func _check_zone_sides() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _kit.leader(BA_KHAC, [], {"skill": _quick_skill(BA_KHAC)}), Vector2i(5, 9))
	var ally := _kit.add(battle, A, _kit.leader(THIET_NHA), Vector2i(4, 4))
	var enemy := _kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(5, 5))
	battle.start()
	_rounds(battle, 1)
	battle.use_skill(leader, Vector2i(5, 5))
	var burns := Kit.of_type(_rounds(battle, 1), &"damage_dealt").filter(func(event: Dictionary) -> bool: return event["source_id"] == &"zone.fire")
	if not Kit.expect("fire burns the enemy only", burns.map(func(event: Dictionary) -> int: return event["target"]), [enemy]):
		return false
	var wind := _kit.new_battle(_kit.plain_rows())
	var trail: Array[TacticsPassiveData] = [_kit.catalog.get_passive(&"tactics_passive.wind_trail")]
	var walker := _kit.add(wind, A, _kit.leader(LIEU_MI, trail), Vector2i(5, 11))
	var archer := _kit.add(wind, A, _kit.leader(LIEU_MI), Vector2i(7, 6))
	var target := _kit.add(wind, B, _kit.leader(LIEU_MI), Vector2i(5, 8))
	wind.start()
	var before: int = wind.forecast_engagement(archer, target)["attacker_damage_per_hit"]
	wind.move_leader(walker, Vector2i(5, 9))
	var after: int = wind.forecast_engagement(archer, target)["attacker_damage_per_hit"]
	return Kit.expect("wind does not ward the enemy", after, before)


# A zone or buff made by side B for d rounds lasts as long as one made by
# side A: until the start of its own side's phase d rounds later, so a
# one-round wind trail still wards side B through side A's next phase.
func _check_side_b_durations() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var archer := _kit.add(battle, A, _kit.leader(LIEU_MI), Vector2i(5, 2))
	var trail: Array[TacticsPassiveData] = [_kit.catalog.get_passive(&"tactics_passive.wind_trail")]
	var walker := _kit.add(battle, B, _kit.leader(LIEU_MI, trail), Vector2i(5, 8))
	battle.start()
	battle.end_phase()
	battle.move_leader(walker, Vector2i(5, 6))
	var during_own_phase: int = battle.forecast_engagement(archer, walker)["attacker_damage_per_hit"]
	var expired_at_a := Kit.of_type(battle.end_phase(), &"zone_expired")
	var during_a_phase: int = battle.forecast_engagement(archer, walker)["attacker_damage_per_hit"]
	var expired_at_b := Kit.of_type(battle.end_phase(), &"zone_expired")
	return Kit.expect("wind wards through side A's phase", [during_own_phase, during_a_phase], [30, 30]) \
		and Kit.expect("expires at the start of side B's next phase", [expired_at_a.size(), expired_at_b.size()], [0, 1])


# Events name what caused them: the squad's step is caused by the leader's
# move or action, a trail zone by the move, a pull by the engagement.
func _check_causes() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var trail: Array[TacticsPassiveData] = [_kit.catalog.get_passive(&"tactics_passive.wind_trail")]
	var walker := _kit.add(battle, A, _kit.leader(LIEU_MI, trail), Vector2i(2, 10), _spearmen(1))
	var hook: Array[TacticsPassiveData] = [_kit.catalog.get_passive(&"tactics_passive.hook_spear")]
	var hooker := _kit.add(battle, A, _kit.leader(MOON_SPEAR, hook, {"keywords": _kit.keywords([])}), Vector2i(8, 8), _spearmen(1))
	var enemy := _kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(8, 6))
	battle.start()
	var moved := battle.move_leader(walker, Vector2i(2, 8))
	var leader_move: Dictionary = Kit.of_type(moved, &"unit_moved")[0]
	var later_causes: Array = moved.slice(moved.find(leader_move) + 1).map(func(event: Dictionary) -> int: return event["cause"])
	if not Kit.expect("caused by the move", later_causes.has(0), false):
		return false
	battle.wait(walker)
	var attacked := battle.attack(hooker, enemy)
	var engagements := Kit.of_type(attacked, &"engagement_started")
	var pull: Dictionary = Kit.of_type(attacked, &"unit_moved").filter(func(event: Dictionary) -> bool: return event["kind"] == &"pull")[0]
	var squad_move: Array = Kit.of_type(attacked, &"unit_moved").filter(func(event: Dictionary) -> bool: return event["kind"] == &"squad")
	return Kit.expect("pull caused by the engagement", pull["cause"], engagements[0]["id"]) \
		and Kit.expect("squad step caused by the engagement", squad_move.map(func(event: Dictionary) -> int: return event["cause"]), [engagements[0]["id"]]) \
		and Kit.expect_true("enemy is the target", engagements[0]["target"] == enemy)
