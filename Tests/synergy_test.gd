extends SceneTree

# Headless tests for class and race milestones and Hợp Lực in battles, with
# exact numbers on tiny set-ups: each class milestone's modifier, the wolf
# kill Khí and the Hợp Lực tiers. Formation effects are in
# formation_battle_test.gd, matching in formation_test.gd. add() takes local
# col, rank (A: global row = 4 - rank; B: col = 7 - local col, row = 3 + rank).

const Kit := preload("res://Tests/synergy_test_kit.gd")

var _kit := Kit.new()


func _initialize() -> void:
	var ok := _run()
	_kit.free_battles()
	if ok:
		print("Synergy test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not ClassDB.class_exists("Synergy"):
		push_error("Synergy is missing: build the GDExtension (scons) before importing")
		return false
	if not _kit.load_catalog():
		return false
	var checks: Array[Callable] = [
		_check_shield_armor, _check_shield_block, _check_block_skips_passives, _check_sword_damage, _check_sword_qi,
		_check_sword_reflect, _check_spear_range, _check_spear_pierce, _check_cavalry,
		_check_archer_speed_and_crit, _check_archer_pierce, _check_mage_shape, _check_mage_skill,
		_check_wolf_kill, _check_hop_luc, _check_no_synergy,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Synergy test failed in %s" % check.get_method())
			return false
	return true


func _attack(battle: Battle, unit: int) -> int:
	return battle.get_unit_state(unit)["attack"]


func _until_damage(battle: Battle, source: int, target: int) -> Array[Dictionary]:
	return _kit.run_until(battle, func(event: Dictionary) -> bool: return event["type"] == &"damage_dealt" and event["source"] == source and event["target"] == target)


# Shield 2: +20 armor. Shields at (1,3) and (3,3), a sword at (3,4).
func _check_shield_armor() -> bool:
	var battle := _kit.synergy_battle([["shield_guard", 4, 1], ["wolf_shield", 2, 1]], [["blade_wanderer", 4, 1]])
	var hit: Dictionary = _until_damage(battle, 2, 0).back()
	return Kit.expect("damage with armor +20", hit["amount"], Kit.damage(_attack(battle, 2), 60))


# Shield 4: the first hit each shield takes is blocked (0, flagged), the
# next one is not. The blocked hit is not damage taken: the shield gains no
# Khí for it (the next hit gives qi_per_hit_taken, 5), while the attacker
# still gains its 10 Khí for the attack.
func _check_shield_block() -> bool:
	var battle := _kit.synergy_battle([["shield_guard", 1, 1], ["wolf_shield", 2, 1], ["iron_guard", 3, 1], ["wolf_king_shield", 4, 1]], [["blade_wanderer", 4, 1]])
	var events := _until_damage(battle, 4, 3)
	var first_hit: Dictionary = events.back()
	var blocks := Kit.triggered(events, &"mod.block_first_hit")
	events.append_array(_kit.run_ticks(battle, 1))
	var later := _until_damage(battle, 4, 3)
	var second: Dictionary = later.back()
	events.append_array(later)
	events.append_array(_kit.run_ticks(battle, 1))
	return (Kit.expect("blocked amount", first_hit["amount"], 0)
		and Kit.expect("blocked flag", first_hit["is_blocked_by_modifier"], true)
		and Kit.expect("block event", blocks.size() == 1 and blocks[0]["unit"] == 3, true)
		and Kit.expect("second hit", second["amount"], Kit.damage(_attack(battle, 4), 60))
		and Kit.expect("no Khí for the blocked hit", _gains(events, first_hit["id"]), [])
		and Kit.expect("attacker's Khí for the attack", _gains(events, first_hit["cause"]), [[4, 10]])
		and Kit.expect("Khí for the next hit", _gains(events, second["id"]), [[3, 5]]))


# A blocked hit fires no on-hit passive: with a test-only "every sword
# blocks its first hit" milestone, a sword's riposte (every 3rd melee hit
# taken) answers the 4th hit, the 3rd that landed.
func _check_block_skips_passives() -> bool:
	var block := ModifierData.new()
	block.handler = &"mod.block_first_hit"
	block.scope = &"scope.counted"
	block.count = 1
	var tier := SynergyTierData.new()
	tier.at = 1
	tier.description_key = "TEST"
	var modifiers: Array[ModifierData] = [block]
	tier.modifiers = modifiers
	var milestone := MilestoneData.new()
	milestone.id = &"milestone.test_sword_block"
	milestone.name_key = "TEST"
	milestone.counted_kind = &"class"
	milestone.counted_id = &"class.sword"
	var tiers: Array[SynergyTierData] = [tier]
	milestone.tiers = tiers
	var synergy := Synergy.new()
	var problems := synergy.setup([], [milestone], _kit.catalog.hop_luc)
	var battle := _kit.new_battle()
	battle.set_synergy(synergy)
	_kit.add(battle, Battle.SIDE_A, &"unit.blade_wanderer", 4, 1)
	_kit.add(battle, Battle.SIDE_B, &"unit.shield_guard", 4, 1)
	var events := _kit.run_until(battle, func(event: Dictionary) -> bool: return event["type"] == &"passive_triggered" and event["unit"] == 0)
	var hits: Array[Dictionary] = Kit.damage_to(events, 1, 0).filter(func(event: Dictionary) -> bool: return event["skill"] == &"")
	var riposte: Dictionary = events.back()
	return (Kit.expect("test milestone valid", problems, PackedStringArray())
		and Kit.expect("first hit blocked", hits.map(func(hit: Dictionary) -> bool: return hit["is_blocked_by_modifier"]), [true, false, false, false])
		and Kit.expect("riposte answers the 4th hit", riposte.get("cause"), hits[3]["id"] if hits.size() == 4 else -2))


# [unit, Khí gained] for each qi_changed caused by `cause`, sorted.
func _gains(events: Array[Dictionary], cause: int) -> Array:
	var gains: Array = []
	for event: Dictionary in Kit.caused_by(events, cause, &"qi_changed"):
		var before := 0
		for earlier: Dictionary in events:
			if earlier["id"] < event["id"] and earlier["type"] == &"qi_changed" and earlier["unit"] == event["unit"]:
				before = earlier["qi"]
		gains.append([event["unit"], event["qi"] - before])
	gains.sort()
	return gains


# Sword 2: +15% damage.
func _check_sword_damage() -> bool:
	var battle := _kit.synergy_battle([["blade_wanderer", 4, 1], ["wolf_blade", 6, 2]], [["shield_guard", 4, 1]])
	var hit: Dictionary = _until_damage(battle, 0, 2).back()
	return Kit.expect("sword damage +15%", hit["amount"], Kit.damage(_attack(battle, 0), 40, 15))


# Sword 3: a landed attack gives 10 + 5 Khí.
func _check_sword_qi() -> bool:
	var battle := _kit.synergy_battle([["blade_wanderer", 4, 1], ["wolf_blade", 2, 2], ["blood_wolf", 6, 2]], [["shield_guard", 4, 1]])
	var events := _kit.run_until(battle, func(event: Dictionary) -> bool: return event["type"] == &"unit_attacked" and event["unit"] == 0)
	events.append_array(_kit.run_ticks(battle, 1))
	var attack_id: int = Kit.of_type(events, &"unit_attacked").filter(func(event: Dictionary) -> bool: return event["unit"] == 0)[0]["id"]
	var before := 0
	for event: Dictionary in events:
		if event["type"] == &"qi_changed" and event["unit"] == 0 and event["id"] < attack_id:
			before = event["qi"]
	var gained: Array[Dictionary] = Kit.caused_by(events, attack_id, &"qi_changed").filter(func(event: Dictionary) -> bool: return event["unit"] == 0)
	return Kit.expect("Khí after the attack", gained[0]["qi"] if not gained.is_empty() else -1, before + 15)


# Sword 4: 30% of a melee hit goes back to the attacker as its own event.
func _check_sword_reflect() -> bool:
	var battle := _kit.synergy_battle([["blade_wanderer", 4, 1], ["wolf_blade", 1, 3], ["blood_wolf", 7, 3], ["thiet_nha", 1, 4]], [["blade_wanderer", 4, 1]])
	var events := _until_damage(battle, 4, 0)
	var hit: Dictionary = events.back()
	events.append_array(_kit.run_ticks(battle, 1))
	var trigger := Kit.first(Kit.triggered(events, &"mod.reflect_melee_pct"), func(event: Dictionary) -> bool: return event["cause"] == hit["id"])
	var reflected: Array[Dictionary] = Kit.caused_by(events, trigger.get("id", -1))
	return (Kit.expect("reflect trigger", trigger.get("unit"), 0)
		and Kit.expect("reflected amount", reflected[0]["amount"] if not reflected.is_empty() else -1, hit["amount"] * 30 / 100)
		and Kit.expect("reflected target", reflected[0]["target"] if not reflected.is_empty() else -1, 4))


# Spear 2: +1 range for spears in rank 1 at the start only.
func _check_spear_range() -> bool:
	var battle := _kit.synergy_battle([["spearman", 4, 1], ["wolf_spear", 2, 3]], [["shield_guard", 4, 4]])
	_kit.run_ticks(battle, 1)
	return Kit.expect("front spear range", battle.get_unit_state(0)["range_cells"], 3) and Kit.expect("back spear range", battle.get_unit_state(1)["range_cells"], 2)


# Spear 4: the hit also lands on the enemy right behind the target.
func _check_spear_pierce() -> bool:
	var battle := _kit.synergy_battle([["wolf_spear", 4, 1], ["spearman", 1, 3], ["pike_guard", 7, 3], ["moon_spear", 2, 4]], [["shield_guard", 4, 1], ["archer", 4, 2]])
	var events := _kit.run_until(battle, func(event: Dictionary) -> bool: return event["type"] == &"unit_attacked" and event["unit"] == 0)
	var attack: Dictionary = events.back()
	events.append_array(_kit.run_ticks(battle, 1))
	return Kit.expect("pierced targets", Kit.field(Kit.caused_by(events, attack["id"]), "target"), [4, 5])


# Cavalry 2 and 3: the opening impact +30% and a 2-cell push. The rider at
# (3,3) hits the sword at (3,4) at once (no cell run) and pushes it to (3,6).
func _check_cavalry() -> bool:
	var battle := _kit.synergy_battle([["wolf_rider", 4, 1], ["light_rider", 2, 1], ["heavy_rider", 6, 1]], [["blade_wanderer", 4, 1]])
	var events := _until_damage(battle, 0, 3)
	var hit: Dictionary = events.back()
	events.append_array(_kit.run_ticks(battle, 1))
	var push := Kit.first(events, func(event: Dictionary) -> bool: return event["type"] == &"unit_moved" and event["kind"] == &"knockback" and event["unit"] == 3)
	return (Kit.expect("impact damage", hit["amount"], Kit.damage(_attack(battle, 0), 25, 30))
		and Kit.expect("push row", push.get("to_row"), 6)
		and Kit.expect("push ticks", push.get("duration_ticks"), 2 * _kit.catalog.battle_rules.charge_ticks_per_cell))


# Archer 2 and 3: 20% faster (the first attack comes earlier by the charge
# arithmetic) and the first attack is a critical hit.
func _check_archer_speed_and_crit() -> bool:
	var battle := _kit.synergy_battle([["archer", 4, 4], ["wolf_archer", 1, 4], ["wolf_marksman", 7, 4]], [["shield_guard", 4, 1]])
	var hit: Dictionary = _until_damage(battle, 0, 3).back()
	var rate: int = _kit.catalog.get_class_data(&"class.archer").attacks_per_100s
	var per_tick := rate * 120 / 100
	var full := _kit.catalog.battle_rules.ticks_per_second * 100
	return (Kit.expect("first attack tick", hit["tick"], ceili(float(full) / per_tick))
		and Kit.expect("first attack crit", hit["is_crit"], true)
		and Kit.expect("crit damage", hit["amount"], Kit.damage(_attack(battle, 0), 40, 0, 0, 100, true)))


# Archer 4: arrows also hit the enemy behind the target.
func _check_archer_pierce() -> bool:
	var battle := _kit.synergy_battle([["archer", 4, 4], ["wolf_archer", 1, 4], ["wolf_marksman", 7, 4], ["lieu_mi", 2, 3]], [["shield_guard", 4, 1], ["archer", 4, 2]])
	var events := _kit.run_until(battle, func(event: Dictionary) -> bool: return event["type"] == &"unit_attacked" and event["unit"] == 0)
	var attack: Dictionary = events.back()
	events.append_array(_kit.run_ticks(battle, 1))
	return Kit.expect("pierced targets", Kit.field(Kit.caused_by(events, attack["id"]), "target"), [4, 5])


# Mage 2: the basic attack also hits the cell behind its target.
func _check_mage_shape() -> bool:
	var battle := _kit.synergy_battle([["fire_adept", 4, 3], ["ice_mage", 1, 4]], [["blade_wanderer", 4, 1], ["wolf_blade", 4, 2]])
	var events := _kit.run_until(battle, func(event: Dictionary) -> bool: return event["type"] == &"unit_attacked" and event["unit"] == 0)
	var attack: Dictionary = events.back()
	events.append_array(_kit.run_ticks(battle, 1))
	return Kit.expect("row and behind", Kit.field(Kit.caused_by(events, attack["id"]), "target"), [2, 3])


# Mage 4: skills deal +30%: 220% magic with +30.
func _check_mage_skill() -> bool:
	var battle := _kit.synergy_battle([["fire_adept", 4, 3], ["ice_mage", 1, 4], ["wind_mage", 7, 4], ["thunder_mage", 2, 2]], [["blade_wanderer", 4, 1]], _kit.quick_rules())
	var events := _kit.run_until(battle, Kit.is_resolve_of(0))
	events.append_array(_kit.run_ticks(battle, 1))
	var hits: Array[Dictionary] = Kit.caused_by(events, events.filter(func(event: Dictionary) -> bool: return event["type"] == &"skill_resolved" and event["unit"] == 0)[0]["id"])
	return Kit.expect("skill damage", hits[0]["amount"], Kit.damage(_attack(battle, 0), 20, 30, 0, 220))


# Wolf 3: a wolf-folk kill gives every living wolf-folk (units 0-2) exactly
# 10 Khí, and the human shield (unit 3) none.
func _check_wolf_kill() -> bool:
	var battle := _kit.synergy_battle([["wolf_blade", 4, 1], ["wolf_spear", 3, 2], ["wolf_archer", 6, 4], ["shield_guard", 1, 4]], [["fire_adept", 4, 1]])
	var events := _kit.run_until(battle, func(event: Dictionary) -> bool: return event["type"] == &"unit_died")
	var trigger: Array[Dictionary] = Kit.triggered(events, &"mod.qi_on_ally_kill")
	events.append_array(_kit.run_ticks(battle, 1))
	var gains := _gains(events, trigger[0]["id"] if not trigger.is_empty() else -1)
	return Kit.expect("kill trigger", trigger.size(), 1) and Kit.expect("every wolf +10, no one else", gains, [[0, 10], [1, 10], [2, 10]])


# Hợp Lực 9 points: +10 Khí at the start (tier 3) and +12% max hp (tier 9).
func _check_hop_luc() -> bool:
	var line := [["shield_guard", 3, 1], ["iron_guard", 4, 1], ["wolf_shield", 5, 1], ["archer", 3, 4], ["wolf_archer", 4, 4], ["fire_adept", 4, 2], ["spearman", 1, 3]]
	var battle := _kit.synergy_battle(line, [["blade_wanderer", 4, 4]])
	var events := _kit.run_ticks(battle, 1)
	var hop_luc := Kit.activated(events, Battle.SIDE_A, &"hop_luc")
	var plain := _kit.new_battle()
	_kit.add(plain, Battle.SIDE_A, &"unit.shield_guard", 3, 1)
	return (Kit.expect("points", hop_luc.get("level"), 9)
		and Kit.expect("max hp", battle.get_unit_state(0)["max_hp"], plain.get_unit_state(0)["max_hp"] * 112 / 100)
		and Kit.expect("starting Khí", battle.get_unit_state(0)["qi"], 10))


# A battle without set_synergy() has none of it.
func _check_no_synergy() -> bool:
	var battle := _kit.new_battle()
	_kit.add(battle, Battle.SIDE_A, &"unit.shield_guard", 1, 1)
	_kit.add(battle, Battle.SIDE_A, &"unit.wolf_shield", 2, 1)
	_kit.add(battle, Battle.SIDE_B, &"unit.blade_wanderer", 4, 4)
	var events := _kit.run_ticks(battle, 2)
	return Kit.expect("no synergy events", Kit.of_type(events, &"synergy_activated").size(), 0)
