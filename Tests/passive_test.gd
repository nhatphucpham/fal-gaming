extends SceneTree

# Headless tests for Khí, the class passives, data validation, unit
# overrides, determinism with skills and the 8v8 length with casts per unit.
# The six skills are in skill_test.gd. Positions in comments are global
# (col, row); add() takes local col, rank.

const Kit := preload("res://Tests/skill_test_kit.gd")

var _kit := Kit.new()


func _initialize() -> void:
	var ok := _run()
	_kit.free_battles()
	if ok:
		print("Passive test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not ClassDB.class_exists("PassiveData"):
		push_error("PassiveData is missing: build the GDExtension (scons) before importing")
		return false
	if not _kit.load_catalog():
		return false
	var checks: Array[Callable] = [
		_check_qi_gain, _check_riposte, _check_brace, _check_momentum,
		_check_steady_aim, _check_bedrock, _check_rejected_data,
		_check_override, _check_determinism, _check_full_battle,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Passive test failed in %s" % check.get_method())
			return false
	return true


# Swords at (3,3) and (3,4) trade blows on tick 25 (B first on odd ticks):
# A takes a hit (+5), then attacks (+10). With quick rules the Khí stops at
# full (100), not at 1000.
func _check_qi_gain() -> bool:
	var battle := _kit.new_battle()
	var sword := _kit.add(battle, Battle.SIDE_A, Kit.SWORD, 4, 1)
	var enemy := _kit.add(battle, Battle.SIDE_B, Kit.SWORD, 4, 1)
	var events := _kit.run_ticks(battle, 25)
	var gains := Kit.of_type(events, &"qi_changed").filter(func(event: Dictionary) -> bool: return event["unit"] == sword)
	var causes := gains.map(func(event: Dictionary) -> StringName: return _event_by_id(events, event["cause"])["type"])
	if not (Kit.expect("A's Khí on tick 25", Kit.field(gains, "qi"), [5, 15]) and Kit.expect("Khí causes", causes, [&"damage_dealt", &"unit_attacked"])
			and Kit.expect("B's Khí", battle.get_unit_state(enemy)["qi"], 15) and Kit.expect("Khí max", gains[0]["qi_max"], 100)):
		return false
	battle = _kit.new_battle(_kit.quick_rules())
	sword = _kit.add(battle, Battle.SIDE_A, Kit.SWORD, 4, 1)
	_kit.add(battle, Battle.SIDE_B, Kit.SWORD, 4, 1)
	var capped := Kit.of_type(_kit.run_ticks(battle, 25), &"qi_changed").filter(func(event: Dictionary) -> bool: return event["unit"] == sword)
	return Kit.expect("capped Khí", Kit.field(capped, "qi"), [100])


# The same duel: B's third melee hit on A (tick 75) makes A strike back at
# once for 60 * 100 / 125 = 48, not on the first two.
func _check_riposte() -> bool:
	var battle := _kit.new_battle()
	var sword := _kit.add(battle, Battle.SIDE_A, Kit.SWORD, 4, 1)
	var enemy := _kit.add(battle, Battle.SIDE_B, Kit.SWORD, 4, 1)
	var events := _kit.run_until(battle, func(event: Dictionary) -> bool:
		return event["type"] == &"passive_triggered" and event["unit"] == sword)
	var hits_taken := Kit.of_type(events, &"damage_dealt").filter(func(event: Dictionary) -> bool: return event["target"] == sword and event["skill"] == &"")
	var strike := Kit.caused_by(events, events.back()["id"])
	return (Kit.expect("riposte", [events.back()["passive"], events.back()["tick"], hits_taken.size()], [&"passive.riposte", 75, 3])
		and Kit.expect("riposte strike", strike.map(func(event: Dictionary) -> Array: return [event["target"], event["amount"], event["skill"]]), [[enemy, 48, &"passive.riposte"]]))


# A cavalry at (3,3) charges a spear that steps to (3,5): the spear strikes
# first (55 * 130% * 100 / 130 = 55), then the impact lands. The cavalry's
# Đột Trận right after charges the same spear: no second brace.
func _check_brace() -> bool:
	var battle := _kit.new_battle(_kit.quick_rules())
	var cavalry := _kit.add(battle, Battle.SIDE_A, Kit.CAVALRY, 4, 1)
	var spear := _kit.add(battle, Battle.SIDE_B, Kit.SPEAR, 4, 3)
	var events := _kit.run_until(battle, func(event: Dictionary) -> bool:
		return event["type"] == &"charge_ended" and event["unit"] == cavalry)
	events.append_array(_kit.run_until(battle, func(event: Dictionary) -> bool:
		return event["type"] == &"charge_ended" and event["unit"] == cavalry))
	var braces := Kit.of_type(events, &"passive_triggered").filter(func(event: Dictionary) -> bool: return event["passive"] == &"passive.brace")
	var impacts := Kit.of_type(events, &"damage_dealt").filter(func(event: Dictionary) -> bool: return event["source"] == cavalry and event["target"] == spear)
	if not (Kit.expect("braces", Kit.field(braces, "unit"), [spear]) and Kit.expect("impacts", impacts.size() >= 2, true)):
		return false
	var strike := Kit.caused_by(events, braces[0]["id"])
	return (Kit.expect("brace strike", strike.map(func(event: Dictionary) -> Array: return [event["target"], event["amount"]]), [[cavalry, 55]])
		and Kit.expect("brace before the impact", strike[0]["id"] < impacts[0]["id"], true))


# A cavalry at (3,3) runs 2 cells into an archer at (3,6): 60 * 130% * 100
# / 110 = 70 instead of 54.
func _check_momentum() -> bool:
	var battle := _kit.new_battle()
	var cavalry := _kit.add(battle, Battle.SIDE_A, Kit.CAVALRY, 4, 1)
	_kit.add(battle, Battle.SIDE_B, Kit.ARCHER, 4, 3)
	var events := _kit.run_until(battle, func(event: Dictionary) -> bool:
		return event["type"] == &"charge_ended" and event["unit"] == cavalry)
	var momentum := Kit.of_type(events, &"passive_triggered").filter(func(event: Dictionary) -> bool: return event["unit"] == cavalry)
	var impact := Kit.caused_by(events, events.back()["cause"])
	return Kit.expect("momentum", Kit.field(momentum, "passive"), [&"passive.momentum"]) and Kit.expect("impact", Kit.field(impact, "amount"), [70])


# An archer at (3,0) shoots a shield at (3,4): 55 * 100 / 140 = 39, and the
# fourth arrow is a critical hit, 55 * 150% * 100 / 140 = 58.
func _check_steady_aim() -> bool:
	var battle := _kit.new_battle()
	var archer := _kit.add(battle, Battle.SIDE_A, Kit.ARCHER, 4, 4)
	_kit.add(battle, Battle.SIDE_B, Kit.SHIELD, 4, 1)
	var hits: Array[Dictionary] = []
	for attack: int in 4:
		var events := _kit.run_until(battle, func(event: Dictionary) -> bool:
			return event["type"] == &"damage_dealt" and event["source"] == archer)
		hits.append(events.back())
	return (Kit.expect("arrow damage", Kit.field(hits, "amount"), [39, 39, 39, 58])
		and Kit.expect("crits", Kit.field(hits, "is_crit"), [false, false, false, true]))


# A test archer aiming at the densest row shoots past the enemy shield at
# (3,4), which blocks the arrow: +5 for the hit and +10 from Bàn Thạch.
func _check_bedrock() -> bool:
	var battle := _kit.new_battle()
	var archer := _kit.add_test_unit(battle, Battle.SIDE_A, Kit.ARCHER, "row_archer", {"targeting": &"target.densest_row3"}, 4, 3)
	for col: int in [3, 4, 5]:
		_kit.add(battle, Battle.SIDE_B, Kit.ARCHER, col, 2)
	var shield := _kit.add(battle, Battle.SIDE_B, Kit.SHIELD, 4, 1)
	var events := _kit.run_until(battle, func(event: Dictionary) -> bool:
		return event["type"] == &"unit_attacked" and event["unit"] == archer)
	var bedrock := Kit.of_type(events, &"passive_triggered").filter(func(event: Dictionary) -> bool: return event["unit"] == shield)
	return (Kit.expect("bedrock", [Kit.field(bedrock, "passive"), bedrock[0]["cause"] if not bedrock.is_empty() else -1], [[&"passive.bedrock"], events.back()["id"]])
		and Kit.expect("shield Khí", battle.get_unit_state(shield)["qi"], 15))


# Unknown handler ids are refused with a Battle: error; a skill missing from
# the catalog's list is reported by Catalog.validate().
func _check_rejected_data() -> bool:
	print("Passive test: the next errors are expected")
	var battle := _kit.new_battle()
	var bad_skill := _kit.catalog.get_class_data(&"class.sword").duplicate() as ClassData
	bad_skill.id = &"class.test_bad_skill"
	bad_skill.skill = bad_skill.skill.duplicate(true) as SkillData
	bad_skill.skill.selector = &"select.nope"
	var bad_passive := _kit.catalog.get_class_data(&"class.sword").duplicate() as ClassData
	bad_passive.id = &"class.test_bad_passive"
	bad_passive.passive = bad_passive.passive.duplicate(true) as PassiveData
	bad_passive.passive.trigger = &"trigger.nope"
	var catalog := _kit.catalog.duplicate() as Catalog
	catalog.skills = catalog.skills.slice(1)
	var problems := catalog.validate()
	return (Kit.expect("bad selector accepted", battle.register_class(bad_skill), false)
		and Kit.expect("bad trigger accepted", battle.register_class(bad_passive), false)
		and Kit.expect("unlisted skill reported", problems.size() == 1 and problems[0].begins_with("Catalog: ") and problems[0].contains("skill.hold_ground"), true))


# A sword with skill_override = Tiễn Vũ casts arrows instead of a sweep.
func _check_override() -> bool:
	var battle := _kit.new_battle(_kit.quick_rules())
	var unit := _kit.catalog.get_unit(Kit.SWORD).duplicate() as UnitData
	unit.skill_override = _kit.catalog.get_skill(&"skill.arrow_rain")
	var sword := battle.add_unit(Battle.SIDE_A, unit, 1, 4, 1)
	_kit.add(battle, Battle.SIDE_B, Kit.SWORD, 4, 1)
	var events := _kit.run_until(battle, func(event: Dictionary) -> bool:
		return event["type"] == &"skill_cast_started" and event["unit"] == sword)
	return Kit.expect("override skill", [events.back()["skill"], battle.get_unit_state(sword)["qi_max"]], [&"skill.arrow_rain", 100])


func _check_determinism() -> bool:
	var first := _setup_8v8(_kit.new_battle(), [1, 2, 3])
	var second := _setup_8v8(_kit.new_battle(), [1, 2, 3])
	var other := _setup_8v8(_kit.new_battle(), [2, 2, 3])
	var hashes := [first.run_to_end(Kit.MAX_TICKS), second.run_to_end(Kit.MAX_TICKS), other.run_to_end(Kit.MAX_TICKS)]
	return Kit.expect("same battle, same hash", hashes[0], hashes[1]) and Kit.expect("other stars, other hash", hashes[0] != hashes[2], true)


# The design wants 30-45 s and 2-3 casts per unit; printed, not enforced.
func _check_full_battle() -> bool:
	var battle := _setup_8v8(_kit.new_battle(), [1])
	var events := _kit.run_ticks(battle, Kit.MAX_TICKS)
	var casts := Kit.of_type(events, &"skill_resolved").filter(func(event: Dictionary) -> bool: return not event["is_after_skill"])
	var seconds := float(battle.get_tick()) / _kit.catalog.battle_rules.ticks_per_second
	print("8v8 with skills ended at tick %d (%.2f s), winner %d; %d casts, %.2f per unit" % [battle.get_tick(), seconds, battle.get_winner(), casts.size(), casts.size() / float(battle.get_unit_count())])
	return Kit.expect("8v8 ended", battle.is_finished(), true)


# The battle_test 8v8 line-up on both sides; side A's stars cycle through
# `a_stars`, side B is all 1 star.
func _setup_8v8(battle: Battle, a_stars: Array) -> Battle:
	var lineup: Array = [
		[Kit.CAVALRY, 2, 1], [Kit.SHIELD, 3, 1], [Kit.SWORD, 4, 1], [&"unit.wolf_shield", 5, 1],
		[Kit.SPEAR, 4, 2], [Kit.ARCHER, 3, 3], [Kit.MAGE, 5, 3], [&"unit.ice_mage", 4, 4],
	]
	for side: int in [Battle.SIDE_A, Battle.SIDE_B]:
		for index: int in lineup.size():
			var entry: Array = lineup[index]
			_kit.add(battle, side, entry[0], entry[1], entry[2], a_stars[index % a_stars.size()] if side == Battle.SIDE_A else 1)
	return battle


func _event_by_id(events: Array[Dictionary], id: int) -> Dictionary:
	for event: Dictionary in events:
		if event["id"] == id:
			return event
	return {}
