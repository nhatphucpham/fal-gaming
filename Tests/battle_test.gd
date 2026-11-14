extends SceneTree

# Headless tests for the battle core: data, stats, determinism, damage, the
# class rules and the end of battle. The node's API (signals, refused calls,
# bad input) is tested in battle_api_test.gd. Each check returns true only
# when every step succeeded; a GDScript runtime error returns false and fails
# the test.
# Positions in comments are global (col, row); add_unit takes local col, rank.

const CATALOG_PATH: String = "res://Data/catalog.tres"
const MAX_TICKS: int = 5000
const SHIELD: StringName = &"unit.shield_guard"
const SWORD: StringName = &"unit.blade_wanderer"
const SPEAR: StringName = &"unit.wolf_spear"
const CAVALRY: StringName = &"unit.wolf_rider"
const ARCHER: StringName = &"unit.archer"
const MAGE: StringName = &"unit.fire_adept"

var _catalog: Catalog
var _battles: Array[Battle] = []
# Every event of the tick in which _first_event() found its event.
var _found_tick_events: Array = []


func _initialize() -> void:
	var ok := _run()
	for battle: Battle in _battles:
		battle.free()
	if ok:
		print("Battle test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not ClassDB.class_exists("Battle"):
		push_error("Battle is missing: build the GDExtension (scons) before importing")
		return false
	if not _check_catalog():
		return false
	var checks: Array[Callable] = [
		_check_stats, _check_determinism, _check_damage, _check_arrow_block,
		_check_charge, _check_hold_line, _check_target_in_range, _check_mage_row3,
		_check_move_durations, _check_time_limit, _check_full_battle,
		_check_coordinates,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Battle test failed in %s" % check.get_method())
			return false
	return true


func _check_catalog() -> bool:
	_catalog = load(CATALOG_PATH) as Catalog
	if _catalog == null:
		push_error("Catalog did not load from %s" % CATALOG_PATH)
		return false
	var problems := _catalog.validate()
	if not problems.is_empty():
		push_error("Catalog is invalid: %s" % ", ".join(problems))
		return false
	if _catalog.classes.size() != 6 or _catalog.units.size() != 25:
		push_error("Catalog has %d classes and %d units, expected 6 and 25" % [_catalog.classes.size(), _catalog.units.size()])
		return false
	return true


func _check_stats() -> bool:
	var battle := _new_battle()
	var shield := _add(battle, Battle.SIDE_A, SHIELD, 1, 1)
	var iron_guard := _add(battle, Battle.SIDE_A, &"unit.iron_guard", 2, 1, 2)
	var thiet_nha := _add(battle, Battle.SIDE_A, &"unit.thiet_nha", 3, 1, 3)
	# 1100*155/100 = 1705, *180/100 = 3069; 40*155/100 = 62, *180/100 = 111.
	# 850*230/100 = 1955, then 3519, then 6334; 60*230/100 = 138, 248, 446.
	return (_expect_stats(battle, shield, 1100, 40)
		and _expect_stats(battle, iron_guard, 3069, 111)
		and _expect_stats(battle, thiet_nha, 6334, 446))


func _check_determinism() -> bool:
	var first := _setup_5v5(_new_battle(), 4)
	var second := _setup_5v5(_new_battle(), 4)
	var moved := _setup_5v5(_new_battle(), 6)
	var first_hash := first.run_to_end(MAX_TICKS)
	var second_hash := second.run_to_end(MAX_TICKS)
	var moved_hash := moved.run_to_end(MAX_TICKS)
	if not first.is_finished() or first_hash != second_hash or first.get_winner() != second.get_winner():
		push_error("Same 5v5 gave different results: %s/%d and %s/%d" % [first_hash, first.get_winner(), second_hash, second.get_winner()])
		return false
	if first_hash == moved_hash:
		push_error("Moving one unit did not change the final hash %s" % first_hash)
		return false
	return true


func _check_damage() -> bool:
	# Two swords face each other at (3,3) and (3,4): 60*100/(100+25) = 48.
	var battle := _new_battle()
	var sword := _add(battle, Battle.SIDE_A, SWORD, 4, 1)
	_add(battle, Battle.SIDE_B, SWORD, 4, 1)
	var hit := _first_event(battle, &"damage_dealt", sword)
	if hit.get("amount", 0) != 48 or hit.get("is_counter", true):
		push_error("Sword vs sword dealt %s, expected 48 without counter" % hit)
		return false
	# A spear counters a sword: 55*130/100*100/125 = 57.
	battle = _new_battle()
	var spear := _add(battle, Battle.SIDE_A, SPEAR, 4, 1)
	_add(battle, Battle.SIDE_B, SWORD, 4, 1)
	hit = _first_event(battle, &"damage_dealt", spear)
	if hit.get("amount", 0) != 57 or not hit.get("is_counter", false):
		push_error("Spear vs sword dealt %s, expected 57 with counter" % hit)
		return false
	return true


func _check_arrow_block() -> bool:
	# A test archer that aims at the densest row (three archers in row 5)
	# shoots down column 3; the enemy shield at (3,4) is in the way.
	var battle := _new_battle()
	var archer := _add_test_archer(battle)
	for col: int in [3, 4, 5]:
		_add(battle, Battle.SIDE_B, ARCHER, col, 2)
	var shield := _add(battle, Battle.SIDE_B, SHIELD, 4, 1)
	var attack := _first_event(battle, &"unit_attacked", archer)
	var hit := _event_caused_by(attack)
	if hit.get("target", -1) != shield or hit.get("blocked_by", -1) != shield or attack.get("target", -1) == shield:
		push_error("Arrow was not blocked by the shield: %s then %s" % [attack, hit])
		return false
	return true


func _check_charge() -> bool:
	# Cavalry at (3,3) charges up column 3 into an archer at (3,6).
	var battle := _new_battle()
	var cavalry := _add(battle, Battle.SIDE_A, CAVALRY, 4, 1)
	var archer := _add(battle, Battle.SIDE_B, ARCHER, 4, 3)
	var events := _events_until(battle, &"charge_ended")
	if not _has_event(events, &"damage_dealt", "source", cavalry) or not _has_event(events, &"unit_moved", "kind", &"knockback"):
		push_error("Charge did not hit and knock back the archer: %s" % [events])
		return false
	if battle.get_unit_state(archer)["row"] != 7 or events.back()["hit"] != archer:
		push_error("Archer was not pushed to row 7: %s" % battle.get_unit_state(archer))
		return false
	# A shield takes the hit but is not pushed.
	battle = _new_battle()
	cavalry = _add(battle, Battle.SIDE_A, CAVALRY, 4, 1)
	var shield := _add(battle, Battle.SIDE_B, SHIELD, 4, 3)
	events = _events_until(battle, &"charge_ended")
	if events.back()["hit"] != shield or _has_event(events, &"unit_moved", "kind", &"knockback") or battle.get_unit_state(shield)["row"] != 6:
		push_error("Shield was knocked back by a charge: %s" % [events])
		return false
	# A spear (stops_charge) is hit where it stands and not pushed. It walks
	# toward the cavalry first, so compare with the cell the impact hit.
	battle = _new_battle()
	cavalry = _add(battle, Battle.SIDE_A, CAVALRY, 4, 1)
	var spear := _add(battle, Battle.SIDE_B, SPEAR, 4, 3)
	events = _events_until(battle, &"charge_ended")
	var impact: Dictionary = events.filter(func(event: Dictionary) -> bool: return event["type"] == &"unit_attacked").back()
	if events.back()["hit"] != spear or not _has_event(events, &"damage_dealt", "target", spear) or _has_event(events, &"unit_moved", "kind", &"knockback") or battle.get_unit_state(spear)["row"] != impact["to_row"]:
		push_error("Spear was knocked back by a charge: %s" % [events])
		return false
	return true


func _check_hold_line() -> bool:
	# A shield at (3,3) with its only enemy far away at (6,7) still holds.
	var battle := _new_battle()
	var shield := _add(battle, Battle.SIDE_A, SHIELD, 4, 1)
	_add(battle, Battle.SIDE_B, SWORD, 1, 4)
	battle.start()
	for tick: int in 20:
		if _has_event(battle.step(), &"unit_moved", "unit", shield):
			push_error("Shield moved at tick %d while holding the line" % battle.get_tick())
			return false
	var state := battle.get_unit_state(shield)
	return state["col"] == 3 and state["row"] == 3


func _check_target_in_range() -> bool:
	# A shield at (3,3) first targets the nearer archer at (3,5), out of its
	# reach. When the sword from (1,7) arrives next to it, the shield switches
	# to the sword and hits it while still holding the line.
	var battle := _new_battle()
	var shield := _add(battle, Battle.SIDE_A, SHIELD, 4, 1)
	_add(battle, Battle.SIDE_B, ARCHER, 4, 2)
	var sword := _add(battle, Battle.SIDE_B, SWORD, 6, 4)
	var hit := _first_event(battle, &"damage_dealt", shield)
	if hit.get("target", -1) != sword or battle.get_tick() > 3 * _catalog.battle_rules.ticks_per_second:
		push_error("Shield did not hit the adjacent sword early: %s at tick %d" % [hit, battle.get_tick()])
		return false
	return true


func _check_move_durations() -> bool:
	var rules := _catalog.battle_rules
	# Walking: two swords at (3,0) and (3,7) step toward each other.
	var battle := _new_battle()
	var sword := _add(battle, Battle.SIDE_A, SWORD, 4, 4)
	_add(battle, Battle.SIDE_B, SWORD, 4, 4)
	var walk_ticks := _move_ticks(_events_until(battle, &"unit_attacked"), sword, &"walk")
	# Charging: cavalry at (3,3) into an archer at (3,6).
	battle = _new_battle()
	var cavalry := _add(battle, Battle.SIDE_A, CAVALRY, 4, 1)
	_add(battle, Battle.SIDE_B, ARCHER, 4, 3)
	var charge_ticks := _move_ticks(_events_until(battle, &"charge_ended"), cavalry, &"charge")
	if walk_ticks.size() < 3 or charge_ticks.size() < 2:
		push_error("Too few moves to time: walk %s, charge %s" % [walk_ticks, charge_ticks])
		return false
	for index: int in range(1, walk_ticks.size()):
		if walk_ticks[index] - walk_ticks[index - 1] != rules.move_ticks_per_cell:
			push_error("Walk steps at ticks %s are not %d apart" % [walk_ticks, rules.move_ticks_per_cell])
			return false
	if charge_ticks[1] - charge_ticks[0] != rules.charge_ticks_per_cell:
		push_error("Charge steps at ticks %s are not %d apart" % [charge_ticks, rules.charge_ticks_per_cell])
		return false
	# Knockback lasts its event's duration whether the victim acts before
	# (B victim on odd tick 15) or after (A victim) the cavalry.
	return _check_knockback_duration(Battle.SIDE_A) and _check_knockback_duration(Battle.SIDE_B)


func _check_knockback_duration(cavalry_side: int) -> bool:
	var battle := _new_battle()
	_add(battle, cavalry_side, CAVALRY, 4, 1)
	var archer := _add(battle, 1 - cavalry_side, ARCHER, 4, 3)
	var events := _events_until(battle, &"charge_ended")
	var pushes := events.filter(func(event: Dictionary) -> bool: return event["type"] == &"unit_moved" and event["kind"] == &"knockback")
	if pushes.size() != 1:
		push_error("No knockback for a side %d charge: %s" % [cavalry_side, events])
		return false
	var duration: int = pushes[0]["duration_ticks"]
	for remaining: int in range(duration, 0, -1):
		if battle.get_unit_state(archer)["move_ticks_left"] != remaining:
			push_error("Knocked-back archer has %s ticks left, expected %d" % [battle.get_unit_state(archer)["move_ticks_left"], remaining])
			return false
		battle.step()
	return battle.get_unit_state(archer)["move_ticks_left"] == 0


func _check_mage_row3() -> bool:
	# A mage at (3,1) and three enemy archers side by side in row 4.
	var battle := _new_battle()
	var mage := _add(battle, Battle.SIDE_A, MAGE, 4, 3)
	var victims: Array[int] = []
	for col: int in [3, 4, 5]:
		victims.append(_add(battle, Battle.SIDE_B, ARCHER, col, 1))
	var attack := _first_event(battle, &"unit_attacked", mage)
	var hit_targets: Array[int] = []
	for event: Dictionary in _found_tick_events:
		if event["type"] == &"damage_dealt" and event["cause"] == attack["id"]:
			hit_targets.append(event["target"])
	hit_targets.sort()
	if hit_targets != victims or attack["kind"] != &"magic":
		push_error("Mage hit %s, expected %s" % [hit_targets, victims])
		return false
	return true


func _check_time_limit() -> bool:
	var rules := _catalog.battle_rules.duplicate() as BattleRulesData
	rules.time_limit_ticks = 10
	# Equal hp and unit counts: side B wins the tie.
	var battle := _new_battle(rules)
	_add(battle, Battle.SIDE_A, SHIELD, 4, 4)
	_add(battle, Battle.SIDE_B, SHIELD, 4, 4)
	var ended := _end_event(battle)
	if ended.get("reason") != &"time_limit" or ended.get("winner") != Battle.SIDE_B or battle.get_tick() != 10:
		push_error("Tied time limit ended as %s at tick %d" % [ended, battle.get_tick()])
		return false
	return _check_unit_count_tie()


# Equal hp share, more living units: two A units with max_hp 2 each lose 1 hp
# to one mage hit (5000 + 5000) against the full-hp mage (10000). The mage's
# first attack lands on tick 34, the time limit.
func _check_unit_count_tie() -> bool:
	var rules := _catalog.battle_rules.duplicate() as BattleRulesData
	rules.time_limit_ticks = 34
	rules.hold_line_grace_ticks = 1000
	rules.hold_line_max_ticks = 1000
	var battle := _new_battle(rules)
	var fragile := _catalog.get_class_data(&"class.shield").duplicate() as ClassData
	fragile.id = &"class.test_fragile"
	fragile.max_hp = 2
	fragile.attack = 0
	fragile.magic_resist = 10000
	battle.register_class(fragile)
	var a_units: Array[int] = [
		_add_test_unit(battle, Battle.SIDE_A, fragile, 4, 3),
		_add_test_unit(battle, Battle.SIDE_A, fragile, 5, 3),
	]
	_add(battle, Battle.SIDE_B, MAGE, 4, 1)
	var ended := _end_event(battle)
	for index: int in a_units:
		if battle.get_unit_state(index)["hp"] != 1:
			push_error("Unit-count tie setup broke: %s" % battle.get_unit_state(index))
			return false
	if ended.get("reason") != &"time_limit" or ended.get("winner") != Battle.SIDE_A or battle.get_tick() != 34:
		push_error("Score tie with more A units ended as %s at tick %d" % [ended, battle.get_tick()])
		return false
	return true


func _check_full_battle() -> bool:
	var battle := _new_battle()
	var lineup: Array = [
		[CAVALRY, 2, 1], [SHIELD, 3, 1], [SWORD, 4, 1], [&"unit.wolf_shield", 5, 1],
		[SPEAR, 4, 2], [ARCHER, 3, 3], [MAGE, 5, 3], [&"unit.ice_mage", 4, 4],
	]
	for side: int in [Battle.SIDE_A, Battle.SIDE_B]:
		for entry: Array in lineup:
			_add(battle, side, entry[0], entry[1], entry[2])
	var ended := _end_event(battle)
	var seconds := float(battle.get_tick()) / _catalog.battle_rules.ticks_per_second
	print("8v8 battle ended at tick %d (%.2f s), winner %d, reason %s" % [battle.get_tick(), seconds, battle.get_winner(), ended.get("reason")])
	if ended.get("reason") != &"elimination":
		push_error("8v8 battle did not end by elimination: %s" % ended)
		return false
	return true


func _check_coordinates() -> bool:
	if Battle.local_to_global(Battle.SIDE_A, 1, 1) != Vector2i(0, 3) or Battle.local_to_global(Battle.SIDE_B, 1, 1) != Vector2i(6, 4):
		push_error("local_to_global maps the front-left cells wrongly")
		return false
	for side: int in [Battle.SIDE_A, Battle.SIDE_B]:
		for col: int in range(1, 8):
			for rank: int in range(1, 5):
				var cell := Battle.local_to_global(side, col, rank)
				if Battle.global_to_local(side, cell.x, cell.y) != Vector2i(col, rank):
					push_error("Coordinates do not round-trip for side %d col %d rank %d" % [side, col, rank])
					return false
	return true


func _new_battle(rules: BattleRulesData = null) -> Battle:
	var battle := Battle.new()
	_battles.append(battle)
	battle.set_rules(rules if rules != null else _catalog.battle_rules)
	for class_data: ClassData in _catalog.classes:
		battle.register_class(class_data)
	return battle


func _add(battle: Battle, side: int, unit_id: StringName, col: int, rank: int, star: int = 1) -> int:
	var index := battle.add_unit(side, _catalog.get_unit(unit_id), star, col, rank)
	assert(index >= 0, "Battle test: could not add %s at col %d rank %d" % [unit_id, col, rank])
	return index


# An archer that uses target.densest_row3, so it aims past a nearer shield.
func _add_test_archer(battle: Battle) -> int:
	var class_data := _catalog.get_class_data(&"class.archer").duplicate() as ClassData
	class_data.id = &"class.test_archer"
	class_data.targeting = &"target.densest_row3"
	battle.register_class(class_data)
	var unit := _catalog.get_unit(ARCHER).duplicate() as UnitData
	unit.id = &"unit.test_archer"
	unit.class_id = class_data.id
	return battle.add_unit(Battle.SIDE_A, unit, 1, 4, 3)


# Adds a unit of a test class that is already registered.
func _add_test_unit(battle: Battle, side: int, class_data: ClassData, col: int, rank: int) -> int:
	var unit := _catalog.get_unit(SHIELD).duplicate() as UnitData
	unit.id = StringName(String(class_data.id).replace("class.", "unit."))
	unit.class_id = class_data.id
	var index := battle.add_unit(side, unit, 1, col, rank)
	assert(index >= 0, "Battle test: could not add %s" % unit.id)
	return index


# Ticks at which `unit` started a move of this kind.
func _move_ticks(events: Array[Dictionary], unit: int, kind: StringName) -> Array[int]:
	var ticks: Array[int] = []
	for event: Dictionary in events:
		if event["type"] == &"unit_moved" and event["unit"] == unit and event["kind"] == kind:
			ticks.append(event["tick"])
	return ticks


func _setup_5v5(battle: Battle, a_archer_col: int) -> Battle:
	var lineup: Array = [[SHIELD, 4, 1], [SWORD, 3, 1], [SPEAR, 5, 2], [MAGE, 3, 4]]
	for side: int in [Battle.SIDE_A, Battle.SIDE_B]:
		for entry: Array in lineup:
			_add(battle, side, entry[0], entry[1], entry[2])
	_add(battle, Battle.SIDE_A, ARCHER, a_archer_col, 4)
	_add(battle, Battle.SIDE_B, ARCHER, 4, 4)
	return battle


func _expect_stats(battle: Battle, index: int, hp: int, attack: int) -> bool:
	var state := battle.get_unit_state(index)
	if state["max_hp"] != hp or state["hp"] != hp or state["attack"] != attack:
		push_error("Unit %s has hp %d attack %d, expected %d and %d" % [state["unit_id"], state["max_hp"], state["attack"], hp, attack])
		return false
	return true


# Steps until an event of this type whose actor is `unit`; stops that tick.
func _first_event(battle: Battle, type: StringName, unit: int) -> Dictionary:
	var key := "source" if type == &"damage_dealt" else "unit"
	battle.start()
	while not battle.is_finished() and battle.get_tick() < MAX_TICKS:
		var tick_events: Array = battle.step()
		for event: Dictionary in tick_events:
			if event["type"] == type and event[key] == unit:
				_found_tick_events = tick_events
				return event
	return {}


# Steps until an event of this type and returns every event up to it.
func _events_until(battle: Battle, type: StringName) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	battle.start()
	while not battle.is_finished() and battle.get_tick() < MAX_TICKS:
		for event: Dictionary in battle.step():
			events.append(event)
			if event["type"] == type:
				return events
	return events


func _end_event(battle: Battle) -> Dictionary:
	var events := _events_until(battle, &"battle_ended")
	return events.back() if not events.is_empty() and events.back()["type"] == &"battle_ended" else {}


# The first event of the found tick caused by `cause`.
func _event_caused_by(cause: Dictionary) -> Dictionary:
	for event: Dictionary in _found_tick_events:
		if event["cause"] == cause.get("id", -1):
			return event
	return {}


func _has_event(events: Array, type: StringName, key: String, value: Variant) -> bool:
	for event: Dictionary in events:
		if event["type"] == type and event.get(key) == value:
			return true
	return false
