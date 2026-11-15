extends SceneTree

# Headless tests for the tactics core: data, movement costs and zones of
# control, engagements and the forecast, keywords, terrain, the AI's
# declared intent, victory and defeat, and determinism. Squads, orders,
# skills, passives and zones are in tactics_squad_test.gd. Each check
# returns true only when every step succeeded. Cells are (col, row).

const Kit := preload("res://Tests/tactics_test_kit.gd")
const LAC_HONG: StringName = &"leader.lac_hong"
const MOON_SPEAR: StringName = &"leader.moon_spear"
const LIEU_MI: StringName = &"leader.lieu_mi"
const BA_KHAC: StringName = &"leader.ba_khac"
const THIET_NHA: StringName = &"leader.thiet_nha"
const A: int = TacticsBattle.SIDE_A
const B: int = TacticsBattle.SIDE_B

var _kit := Kit.new()


func _initialize() -> void:
	var ok := _run()
	_kit.free_battles()
	if ok:
		print("Tactics test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not _kit.load_catalog():
		return false
	var checks: Array[Callable] = [
		_check_catalog, _check_scenario, _check_movement_costs, _check_zone_of_control,
		_check_engagement, _check_counter_out_of_range, _check_long_weapon, _check_charge,
		_check_armor_pierce, _check_cover, _check_flying, _check_heavy, _check_terrain_modifiers,
		_check_ai_intent, _check_victory, _check_defeat, _check_time_limit, _check_determinism,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Tactics test failed in %s" % check.get_method())
			return false
	return true


func _check_catalog() -> bool:
	var spearman := _kit.catalog.get_troop(&"troop.spearman")
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _kit.leader(MOON_SPEAR), Vector2i(5, 8), [spearman])
	_kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(5, 1))
	var soldier: Dictionary = battle.get_unit_state(leader + 1)
	# Spear class: 800 hp, 55 attack, 25 armor; soldiers keep 40% of the hp.
	return Kit.expect("soldier hp", soldier["max_hp"], 320) and Kit.expect("soldier attack", soldier["attack"], 55) \
		and Kit.expect("soldier armor", soldier["armor"], 25) and Kit.expect("leader hp", battle.get_unit_state(leader)["max_hp"], 1200) \
		and Kit.expect("soldier keywords", soldier["keywords"], [&"keyword.long_weapon"]) \
		and Kit.expect("soldier slot behind the leader", soldier["cell"], Vector2i(5, 9))


func _check_scenario() -> bool:
	var battle := TacticsBattle.new()
	_kit._battles.append(battle)
	if not battle.load_scenario(_kit.catalog.get_scenario(&"scenario.river_crossing")):
		return false
	var events := battle.start()
	var leaders := battle.get_units().filter(func(unit: Dictionary) -> bool: return unit["role"] == &"leader")
	return Kit.expect("first event", events[0]["type"], &"battle_started") and Kit.expect("leaders", leaders.size(), 5) \
		and Kit.expect("units", battle.get_unit_count(), 5 + 4 + 3 + 3 + 3 + 3) and Kit.expect("active side", battle.get_active_side(), A) \
		and Kit.expect("intents", battle.get_enemy_intents().size(), 2)


# Forest costs 2, a river is impassable but its bridge is not, a ford costs 3.
func _check_movement_costs() -> bool:
	var forest := _reachable_with_row(3, "ffffffffffff", {})
	var river := _reachable_with_row(3, "rrrrrbrrrrrr", {})
	var ford := _reachable_with_row(3, "dddddddddddd", {})
	return Kit.expect_true("forest: (5,2) reachable, (5,1) and (4,2) not", forest.has(Vector2i(5, 2)) and not forest.has(Vector2i(5, 1)) and not forest.has(Vector2i(4, 2))) \
		and Kit.expect_true("river: over the bridge only", river.has(Vector2i(5, 2)) and river.has(Vector2i(4, 2)) and not river.has(Vector2i(4, 3)) and not river.has(Vector2i(3, 2))) \
		and Kit.expect_true("ford: (5,3) reachable, (5,2) not", ford.has(Vector2i(5, 3)) and not ford.has(Vector2i(5, 2)))


# Cells moon_spear (4 move points, at (5,5)) can reach when map row p_row
# is p_line; `changes` modifies the leader.
func _reachable_with_row(row: int, line: String, changes: Dictionary) -> Array:
	var rows := _kit.plain_rows()
	rows[row] = line
	var battle := _kit.new_battle(rows)
	var leader := _kit.add(battle, A, _kit.leader(MOON_SPEAR, [], changes), Vector2i(5, 5))
	_kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(11, 11))
	battle.start()
	return battle.get_reachable_cells(leader)


func _check_zone_of_control() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _kit.leader(MOON_SPEAR), Vector2i(4, 7))
	var ally := _kit.add(battle, A, _kit.leader(LIEU_MI), Vector2i(1, 10))
	_kit.add(battle, A, _kit.leader(LAC_HONG), Vector2i(2, 10))
	var enemy := _kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(5, 5))
	battle.start()
	var cells := battle.get_reachable_cells(leader)
	var ally_cells := battle.get_reachable_cells(ally)
	if not (Kit.expect_true("stops next to the enemy", cells.has(Vector2i(4, 5)) and cells.has(Vector2i(6, 5)) and cells.has(Vector2i(5, 6))) \
			and Kit.expect_true("cannot pass the enemy's zone", not cells.has(Vector2i(4, 4))) \
			and Kit.expect_true("cannot enter the enemy", not cells.has(battle.get_unit_state(enemy)["cell"])) \
			and Kit.expect_true("passes through an ally but does not stop on it", ally_cells.has(Vector2i(3, 10)) and not ally_cells.has(Vector2i(2, 10)))):
		return false
	print("Tactics test: the next error (move onto an ally) is expected")
	return Kit.expect("move onto an ally refused", battle.move_leader(ally, Vector2i(2, 10)), [])


# moon_spear (66 attack) hits a sword leader (25 armor) 4 times for
# 6600 / 125 = 52, then takes 4 counters of 7200 / 125 = 57.
func _check_engagement() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _kit.leader(MOON_SPEAR, [], {"keywords": _kit.keywords([])}), Vector2i(5, 6))
	var enemy := _kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(5, 5))
	battle.start()
	var forecast := battle.forecast_engagement(leader, enemy)
	var hash_before := battle.get_state_hash()
	if not (Kit.expect("forecast changes nothing", battle.get_state_hash(), hash_before) \
			and Kit.expect("per hit", [forecast["attacker_damage_per_hit"], forecast["defender_damage_per_hit"]], [52, 57]) \
			and Kit.expect("hits", [forecast["attacker_hits"], forecast["defender_hits"]], [4, 4]) \
			and Kit.expect("forecast hp", [forecast["attacker_hp_after"], forecast["defender_hp_after"]], [1200 - 228, 1275 - 208])):
		return false
	var events := battle.attack(leader, enemy)
	var damage := Kit.of_type(events, &"damage_dealt")
	var counters := damage.map(func(event: Dictionary) -> bool: return event["is_counter"])
	return Kit.expect("damage order", counters, [false, false, false, false, true, true, true, true]) \
		and Kit.expect("actual hp equals forecast", [Kit.hp_of(battle, leader), Kit.hp_of(battle, enemy)], [forecast["attacker_hp_after"], forecast["defender_hp_after"]]) \
		and _matches_forecast(events, forecast)


# The engagement in `events` landed what `forecast` said.
func _matches_forecast(events: Array, forecast: Dictionary) -> bool:
	var started: Dictionary = Kit.of_type(events, &"engagement_started")[0]
	var damage := Kit.of_type(events, &"damage_dealt").filter(func(event: Dictionary) -> bool: return event["cause"] == started["id"])
	var attacker_hits := damage.filter(func(event: Dictionary) -> bool: return not event["is_counter"])
	return Kit.expect("first strike", started["is_first_strike"], forecast["is_first_strike"]) \
		and Kit.expect("hit counts", [attacker_hits.size(), damage.size() - attacker_hits.size()], [forecast["attacker_hits"], forecast["defender_hits"]])


func _check_counter_out_of_range() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var archer := _kit.add(battle, A, _kit.leader(LIEU_MI), Vector2i(5, 8))
	var enemy := _kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(5, 5))
	battle.start()
	var forecast := battle.forecast_engagement(archer, enemy)
	var events := battle.attack(archer, enemy)
	return Kit.expect("no counter at range 3", [forecast["can_counter"], forecast["defender_hits"]], [false, 0]) \
		and Kit.expect("four hits of 52", Kit.of_type(events, &"damage_dealt").map(func(event: Dictionary) -> int: return event["amount"]), [52, 52, 52, 52]) \
		and Kit.expect("hp", Kit.hp_of(battle, enemy), forecast["defender_hp_after"])


# keyword.long_weapon: attacked in melee, the spear's counter comes first;
# against a ranged attack it does not.
func _check_long_weapon() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var sword := _kit.add(battle, A, _kit.leader(THIET_NHA), Vector2i(5, 6))
	var archer := _kit.add(battle, A, _kit.leader(LIEU_MI), Vector2i(7, 5))
	var spear := _kit.add(battle, B, _kit.leader(MOON_SPEAR), Vector2i(5, 5))
	battle.start()
	var ranged := battle.forecast_engagement(archer, spear)
	var forecast := battle.forecast_engagement(sword, spear)
	var events := battle.attack(sword, spear)
	var first: Dictionary = Kit.of_type(events, &"damage_dealt")[0]
	return Kit.expect("melee first strike", forecast["is_first_strike"], true) and Kit.expect("ranged: no first strike", ranged["is_first_strike"], false) \
		and Kit.expect("first hit is the counter", [first["source"], first["is_counter"]], [spear, true]) \
		and _matches_forecast(events, forecast) and Kit.expect("hp", Kit.hp_of(battle, sword), forecast["attacker_hp_after"])


# keyword.charge: 3 straight cells right before the attack add 30%:
# ba_khac (72 attack) on 25 armor deals 72 * 130 / 125 = 74, not 57.
func _check_charge() -> bool:
	var per_hit: Array[int] = []
	for start_row: int in [8, 7]:
		var battle := _kit.new_battle(_kit.plain_rows())
		var rider := _kit.add(battle, A, _kit.leader(BA_KHAC), Vector2i(5, start_row))
		var enemy := _kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(5, 4))
		battle.start()
		battle.move_leader(rider, Vector2i(5, 5))
		var forecast := battle.forecast_engagement(rider, enemy)
		var events := battle.attack(rider, enemy)
		per_hit.append(forecast["attacker_damage_per_hit"])
		if not Kit.expect("hit equals forecast", Kit.of_type(events, &"damage_dealt")[0]["amount"], forecast["attacker_damage_per_hit"]):
			return false
	return Kit.expect("charge after 3 cells, none after 2", per_hit, [74, 57])


# keyword.armor_pierce: a swordsman (60 attack) ignores half of 25 armor:
# 6000 / 112 = 53 instead of 6000 / 125 = 48.
func _check_armor_pierce() -> bool:
	var per_hit: Array[int] = []
	for squad: Array in [[_kit.troop(&"troop.swordsman")], [_kit.troop(&"troop.swordsman", {"keywords": _kit.keywords([])})]]:
		var battle := _kit.new_battle(_kit.plain_rows())
		var leader := _kit.add(battle, A, _kit.leader(MOON_SPEAR), Vector2i(5, 8), squad)
		var enemy := _kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(5, 10))
		battle.start()
		per_hit.append(battle.forecast_engagement(leader + 1, enemy)["attacker_damage_per_hit"])
	return Kit.expect("armor pierce", per_hit, [53, 48])


# keyword.cover: a shieldman next to its leader cuts ranged damage by 30%:
# 66 * 70 / 125 = 36 instead of 52; melee is not covered.
func _check_cover() -> bool:
	var per_hit: Array[int] = []
	for squad: Array in [[_kit.troop(&"troop.shieldman")], []]:
		var battle := _kit.new_battle(_kit.plain_rows())
		var archer := _kit.add(battle, A, _kit.leader(LIEU_MI), Vector2i(5, 6))
		var sword := _kit.add(battle, A, _kit.leader(THIET_NHA), Vector2i(4, 3))
		var enemy := _kit.add(battle, B, _kit.leader(MOON_SPEAR, [], {"keywords": _kit.keywords([])}), Vector2i(5, 3), squad)
		battle.start()
		per_hit.append(battle.forecast_engagement(archer, enemy)["attacker_damage_per_hit"])
		per_hit.append(battle.forecast_engagement(sword, enemy)["attacker_damage_per_hit"])
	# Spear leader: 25 armor. Archer 66 attack, sword 72 attack.
	return Kit.expect("cover", per_hit, [36, 57, 52, 57])


# keyword.flying: rivers, terrain costs and zones of control do not stop it.
func _check_flying() -> bool:
	var flying := {"keywords": _kit.keywords([&"keyword.flying"])}
	var river := _reachable_with_row(3, "rrrrrrrrrrrr", flying)
	var forest := _reachable_with_row(4, "ffffffffffff", flying)
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _kit.leader(MOON_SPEAR, [], flying), Vector2i(4, 7))
	_kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(5, 5))
	battle.start()
	return Kit.expect_true("flies over the river", river.has(Vector2i(5, 2)) and river.has(Vector2i(5, 3))) \
		and Kit.expect_true("forest costs 1", forest.has(Vector2i(5, 1))) \
		and Kit.expect_true("ignores the zone of control", battle.get_reachable_cells(leader).has(Vector2i(4, 4)))


# keyword.heavy: forest costs 2 + 1, so (5,2) beyond the forest row is out
# of reach for a heavy leader.
func _check_heavy() -> bool:
	var heavy := _reachable_with_row(3, "ffffffffffff", {"keywords": _kit.keywords([&"keyword.heavy"])})
	return Kit.expect_true("heavy in forest", heavy.has(Vector2i(5, 3)) and not heavy.has(Vector2i(5, 2)))


# Ford: +25% taken (66). Fort: +20 armor (6600 / 145 = 45). Forest: -30%
# ranged (36), melee unchanged (52). Hill: +1 range for a ranged unit.
func _check_terrain_modifiers() -> bool:
	var results: Array = []
	for symbol: String in ["d", "t", "f"]:
		var rows := _kit.plain_rows()
		rows[5] = "....." + symbol + "......"
		var battle := _kit.new_battle(rows)
		var spear := _kit.add(battle, A, _kit.leader(MOON_SPEAR, [], {"keywords": _kit.keywords([])}), Vector2i(5, 6))
		var archer := _kit.add(battle, A, _kit.leader(LIEU_MI), Vector2i(5, 8))
		var enemy := _kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(5, 5))
		battle.start()
		results.append([battle.forecast_engagement(spear, enemy)["attacker_damage_per_hit"], battle.forecast_engagement(archer, enemy)["attacker_damage_per_hit"]])
	var rows := _kit.plain_rows()
	rows[8] = ".....h......"
	var hill := _kit.new_battle(rows)
	var on_hill := _kit.add(hill, A, _kit.leader(LIEU_MI), Vector2i(5, 8))
	_kit.add(hill, B, _kit.leader(THIET_NHA), Vector2i(5, 1))
	return Kit.expect("ford, fort, forest", results, [[66, 66], [45, 45], [52, 36]]) \
		and Kit.expect("hill range", hill.get_unit_state(on_hill)["max_range"], 5)


# The AI declares its destination and action at the start of the player's
# phase and carries them out; a blocked destination falls back to the
# nearest legal cell.
func _check_ai_intent() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows(), true)
	var leader := _kit.add(battle, A, _kit.leader(MOON_SPEAR, [], {"keywords": _kit.keywords([])}), Vector2i(5, 10))
	var enemy := _kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(5, 2))
	battle.start()
	var intent: Dictionary = battle.get_enemy_intents()[0]
	if not Kit.expect("round 1 intent", [intent["unit"], intent["to"], intent["action"], intent["target"]], [enemy, Vector2i(5, 7), &"wait", leader]):
		return false
	var events := battle.end_phase()
	if not (Kit.expect("went where it said", Kit.cell_of(battle, enemy), Vector2i(5, 7)) and Kit.expect("waited", Kit.of_type(events, &"leader_waited").size(), 1)):
		return false
	intent = battle.get_enemy_intents()[0]
	if not Kit.expect("round 2 intent", [intent["to"], intent["action"]], [Vector2i(5, 9), &"attack"]):
		return false
	# Taking the declared cell makes the enemy stop one cell short and attack.
	battle.move_leader(leader, Vector2i(5, 9))
	events = battle.end_phase()
	var engagement := Kit.of_type(events, &"engagement_started").filter(func(event: Dictionary) -> bool: return event["unit"] == enemy)
	return Kit.expect("nearest legal cell", Kit.cell_of(battle, enemy), Vector2i(5, 8)) \
		and Kit.expect("attacked as declared", engagement.map(func(event: Dictionary) -> int: return event["target"]), [leader])


func _check_victory() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows(), false, null, Vector2i(5, 2))
	var leader := _kit.add(battle, A, _kit.leader(MOON_SPEAR), Vector2i(5, 5))
	_kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(11, 11))
	var ended: Array = []
	battle.battle_ended.connect(func(winner: int, reason: StringName) -> void: ended.append([winner, reason]))
	battle.start()
	battle.move_leader(leader, Vector2i(5, 2))
	if not Kit.expect("objective", ended, [[A, &"objective"]]):
		return false
	var rout := _kit.new_battle(_kit.plain_rows())
	var spear := _kit.add(rout, A, _kit.leader(MOON_SPEAR, [], {"keywords": _kit.keywords([])}), Vector2i(5, 6))
	var weak := _kit.add(rout, B, _kit.leader(THIET_NHA, [], {"hp_pct": 5}), Vector2i(5, 5))
	rout.start()
	var events := rout.attack(spear, weak)
	return Kit.expect("one hit kills", Kit.of_type(events, &"damage_dealt").size(), 1) \
		and Kit.expect("died", Kit.of_type(events, &"unit_died").size(), 1) \
		and Kit.expect("rout", [rout.is_finished(), rout.get_winner(), rout.get_end_reason()], [true, A, &"rout"]) \
		and Kit.expect("ended right after the death", events[events.find(Kit.of_type(events, &"unit_died")[0]) + 1]["type"], &"battle_ended")


func _check_defeat() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var weak := _kit.add(battle, A, _kit.leader(THIET_NHA, [], {"hp_pct": 5}), Vector2i(5, 6))
	var spear := _kit.add(battle, B, _kit.leader(MOON_SPEAR, [], {"keywords": _kit.keywords([])}), Vector2i(5, 5))
	battle.start()
	battle.end_phase()
	battle.attack(spear, weak)
	return Kit.expect("defeat", [battle.is_finished(), battle.get_winner(), battle.get_end_reason()], [true, B, &"rout"]) \
		and Kit.expect("no commands after the end", battle.get_active_side(), B)


func _check_time_limit() -> bool:
	var rules := _kit.catalog.rules.duplicate() as TacticsRulesData
	rules.max_rounds = 2
	var battle := _kit.new_battle(_kit.plain_rows(), true, rules)
	_kit.add(battle, A, _kit.leader(MOON_SPEAR), Vector2i(0, 11))
	_kit.add(battle, B, _kit.leader(THIET_NHA, [], {"move_points": 0}), Vector2i(11, 0))
	battle.start()
	battle.end_phase()
	battle.end_phase()
	return Kit.expect("time limit", [battle.is_finished(), battle.get_winner(), battle.get_end_reason(), battle.get_round()], [true, B, &"time_limit", 2])


# The sample scenario played by a fixed policy and recorded, then the
# recorded commands replayed on a fresh battle: the hash after every
# command matches. Another policy ends with another hash.
func _check_determinism() -> bool:
	var first := _play_scenario([], true)
	var commands: Array = first[0]
	var replay := _play_scenario(commands, true)
	var other := _play_scenario([], false)
	print("Tactics test: determinism over %d commands, final hash %s" % [commands.size(), first[1].back()])
	return Kit.expect("replay hashes", replay[1], first[1]) and Kit.expect_true("enough commands", commands.size() >= 10) \
		and Kit.expect_true("another policy changes the hash", other[1].back() != first[1].back())


# Plays scenario.river_crossing (side B is the AI) for up to 6 rounds. With
# `commands` empty a policy picks them: each leader moves to its
# north-most reachable cell (`north` true) or its south-most one, then attacks
# the first enemy in range or waits. Otherwise `commands` are replayed.
# Returns [commands, hashes after each command].
func _play_scenario(commands: Array, north: bool) -> Array:
	var battle := TacticsBattle.new()
	_kit._battles.append(battle)
	battle.load_scenario(_kit.catalog.get_scenario(&"scenario.river_crossing"))
	battle.start()
	var played: Array = []
	var hashes: Array[String] = [battle.get_state_hash()]
	if not commands.is_empty():
		for command: Array in commands:
			_apply(battle, command, played, hashes)
		return [played, hashes]
	while not battle.is_finished() and battle.get_round() <= 6:
		for unit: Dictionary in battle.get_units():
			if unit["side"] == A and unit["role"] == &"leader":
				_play_leader(battle, unit["index"], north, played, hashes)
		if not battle.is_finished():
			_apply(battle, [&"end_phase", -1, null], played, hashes)
	return [played, hashes]


func _play_leader(battle: TacticsBattle, leader: int, north: bool, played: Array, hashes: Array[String]) -> void:
	if battle.is_finished() or not battle.get_unit_state(leader)["alive"]:
		return
	var cells := battle.get_reachable_cells(leader)
	if not cells.is_empty():
		# Cells come in row-major order: first is north-most, last south-most.
		var best: Vector2i = cells[0] if north else cells.back()
		_apply(battle, [&"move", leader, best], played, hashes)
	if battle.is_finished() or not battle.get_unit_state(leader)["alive"]:
		return
	for unit: Dictionary in battle.get_units():
		if unit["side"] == B and unit["alive"] and battle.forecast_engagement(leader, unit["index"])["is_valid"]:
			_apply(battle, [&"attack", leader, unit["index"]], played, hashes)
			return
	_apply(battle, [&"wait", leader, null], played, hashes)


func _apply(battle: TacticsBattle, command: Array, played: Array, hashes: Array[String]) -> void:
	match command[0]:
		&"move":
			battle.move_leader(command[1], command[2])
		&"attack":
			battle.attack(command[1], command[2])
		&"wait":
			battle.wait(command[1])
		_:
			battle.end_phase()
	played.append(command)
	hashes.append(battle.get_state_hash())
