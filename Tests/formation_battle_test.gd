extends SceneTree

# Headless tests for formation effects in battles, with exact numbers on
# tiny set-ups: each formation's modifier, the human per-formation bonus, a
# formation breaking when a member dies, determinism with synergies, and
# that Synergy.evaluate() matches what Battle activates. add() takes local
# col, rank (A: global row = 4 - rank; B: col = 7 - local col, row = 3 + rank).

const Kit := preload("res://Tests/synergy_test_kit.gd")

var _kit := Kit.new()


func _initialize() -> void:
	var ok := _run()
	_kit.free_battles()
	if ok:
		print("Formation battle test passed")
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
		_check_shield_wall, _check_arrow_rain, _check_spell_guard, _check_spearhead,
		_check_twin_blades, _check_spear_cover, _check_square, _check_crane_wings,
		_check_fish_scales, _check_three_powers, _check_wide_formations, _check_broken,
		_check_determinism, _check_evaluate_matches_battle,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Formation battle test failed in %s" % check.get_method())
			return false
	return true


func _attack(battle: Battle, unit: int) -> int:
	return battle.get_unit_state(unit)["attack"]


func _level(events: Array[Dictionary], side: int, id: StringName) -> int:
	return Kit.activated(events, side, id).get("level", 0)


func _until(battle: Battle, predicate: Callable) -> Array[Dictionary]:
	var events := _kit.run_until(battle, predicate)
	events.append_array(_kit.run_ticks(battle, 1))
	return events


func _is_attack_of(unit: int) -> Callable:
	return func(event: Dictionary) -> bool: return event["type"] == &"unit_attacked" and event["unit"] == unit


# Shield wall: the archer behind the middle shield takes 40% (at level) less
# from a ranged physical hit; four enemy archers pierce the shield into it.
func _check_shield_wall() -> bool:
	var battle := _kit.synergy_battle([["shield_guard", 3, 1], ["iron_guard", 4, 1], ["wolf_shield", 5, 1], ["archer", 4, 2]],
		[["archer", 4, 3], ["wolf_archer", 2, 3], ["wolf_marksman", 6, 3], ["lieu_mi", 7, 3]])
	var events := _until(battle, _is_attack_of(4))
	var attack: Dictionary = Kit.of_type(events, &"unit_attacked").filter(func(event: Dictionary) -> bool: return event["unit"] == 4)[0]
	var hit := Kit.first(Kit.caused_by(events, attack["id"]), func(event: Dictionary) -> bool: return event["target"] == 3)
	var increase := 8 if Kit.activated(events, Battle.SIDE_B, &"hop_luc").get("level", 0) >= 6 else 0
	var decrease := Kit.at_level(40, _level(events, Battle.SIDE_A, &"formation.shield_wall"))
	return Kit.expect("damage behind the wall", hit.get("amount"), Kit.damage(_attack(battle, 4), 10, increase, decrease, 100, hit.get("is_crit", false)))


# Arrow rain: at tick 80 the centre archer volleys 100% (at level) on the
# sword, not a basic attack.
func _check_arrow_rain() -> bool:
	var battle := _kit.synergy_battle([["archer", 3, 4], ["wolf_archer", 4, 4], ["wolf_marksman", 5, 4]], [["blade_wanderer", 4, 4]])
	var events := _until(battle, func(event: Dictionary) -> bool: return event["type"] == &"modifier_triggered" and event["modifier"] == &"mod.volley")
	var volley: Array[Dictionary] = Kit.triggered(events, &"mod.volley")
	var hits: Array[Dictionary] = Kit.caused_by(events, volley[0]["id"])
	var coefficient := Kit.at_level(100, _level(events, Battle.SIDE_A, &"formation.arrow_rain"))
	return (Kit.expect("volley tick", volley[0]["tick"], 80)
		and Kit.expect("volley archer", volley[0]["unit"], 1)
		and Kit.expect("volley damage", hits[0]["amount"], Kit.damage(_attack(battle, 1), 25, 0, 0, coefficient))
		and Kit.expect("volley source", hits[0]["skill"], &"formation.arrow_rain"))


# Spell guard: the mage behind the shield deals 25% (at level) more.
func _check_spell_guard() -> bool:
	var battle := _kit.synergy_battle([["shield_guard", 4, 1], ["fire_adept", 4, 2]], [["blade_wanderer", 4, 1]])
	var events := _until(battle, func(event: Dictionary) -> bool: return event["type"] == &"damage_dealt" and event["source"] == 1)
	var hit: Dictionary = Kit.damage_to(events, 1, 2)[0]
	var increase := Kit.at_level(25, _level(events, Battle.SIDE_A, &"formation.spell_guard"))
	return Kit.expect("guarded mage damage", hit["amount"], Kit.damage(_attack(battle, 1), 20, increase))


# Spearhead: impact +50% (at level), a push of 2 cells, and the spears walk
# at charge speed until their first attack.
func _check_spearhead() -> bool:
	var battle := _kit.synergy_battle([["wolf_rider", 4, 1], ["wolf_spear", 3, 2], ["spearman", 5, 2]], [["blade_wanderer", 4, 1]])
	var events := _until(battle, func(event: Dictionary) -> bool: return event["type"] == &"unit_moved" and event["unit"] == 1)
	var hit: Dictionary = Kit.damage_to(events, 0, 3)[0]
	var push := Kit.first(events, func(event: Dictionary) -> bool: return event["type"] == &"unit_moved" and event["kind"] == &"knockback")
	var walk := Kit.first(events, func(event: Dictionary) -> bool: return event["type"] == &"unit_moved" and event["unit"] == 1)
	var rules := _kit.catalog.battle_rules
	return (Kit.expect("impact damage", hit["amount"], Kit.damage(_attack(battle, 0), 25, Kit.at_level(50, _level(events, Battle.SIDE_A, &"formation.spearhead"))))
		and Kit.expect("push ticks", push.get("duration_ticks"), 2 * rules.charge_ticks_per_cell)
		and Kit.expect("spear walk ticks", walk.get("duration_ticks"), rules.charge_ticks_per_cell))


# Twin blades: every third attack deals double (+100% at level); sword 2
# adds 15% to all of them.
func _check_twin_blades() -> bool:
	var battle := _kit.synergy_battle([["blade_wanderer", 4, 1], ["wolf_blade", 5, 1]], [["shield_guard", 4, 1]])
	var events: Array[Dictionary] = []
	for attack: int in 3:
		events.append_array(_until(battle, func(event: Dictionary) -> bool: return event["type"] == &"damage_dealt" and event["source"] == 0 and event["target"] == 2))
	var hits := Kit.damage_to(events, 0, 2)
	var bonus := Kit.at_level(100, _level(events, Battle.SIDE_A, &"formation.twin_blades"))
	return (Kit.expect("first hit", hits[0]["amount"], Kit.damage(_attack(battle, 0), 40, 15))
		and Kit.expect("third hit", hits[2]["amount"], Kit.damage(_attack(battle, 0), 40, 15 + bonus))
		and Kit.expect("double hit events", Kit.triggered(events, &"mod.nth_attack_bonus_pct").size() >= 1, true))


# Spear cover: a charge into the spear stops dead, no impact damage.
func _check_spear_cover() -> bool:
	var battle := _kit.synergy_battle([["spearman", 4, 1], ["archer", 4, 2]], [["wolf_rider", 4, 1]])
	var events := _until(battle, func(event: Dictionary) -> bool: return event["type"] == &"charge_ended" and event["unit"] == 2)
	var ended: Dictionary = Kit.of_type(events, &"charge_ended")[0]
	var stopped := Kit.triggered(events, &"mod.charge_immunity")
	var impact := events.filter(func(event: Dictionary) -> bool: return event["type"] == &"damage_dealt" and event["source"] == 2 and event["id"] < ended["id"])
	return (Kit.expect("stopped by", stopped[0]["unit"] if not stopped.is_empty() else -1, 0)
		and Kit.expect("charge hit", ended["hit"], 0)
		and Kit.expect("impact damage events", impact.size(), 0))


# Square: members take 15% (at level) less; human 3 gives the side +5% per
# active formation.
func _check_square() -> bool:
	var battle := _kit.synergy_battle([["blade_wanderer", 4, 1], ["spearman", 5, 1], ["archer", 4, 2], ["fire_adept", 5, 2]], [["blade_wanderer", 4, 1]])
	var events := _until(battle, func(event: Dictionary) -> bool: return event["type"] == &"damage_dealt" and event["source"] == 4 and event["target"] == 0)
	events.append_array(_until(battle, func(event: Dictionary) -> bool: return event["type"] == &"damage_dealt" and event["source"] == 0 and event["target"] == 4))
	var taken: Dictionary = Kit.damage_to(events, 4, 0)[0]
	var dealt: Dictionary = Kit.damage_to(events, 0, 4)[0]
	var decrease := Kit.at_level(15, _level(events, Battle.SIDE_A, &"formation.square"))
	return (Kit.expect("damage taken", taken["amount"], Kit.damage(_attack(battle, 4), 25, 0, decrease))
		and Kit.expect("damage dealt", dealt["amount"], Kit.damage(_attack(battle, 0), 25, 5)))


# Crane wings: corner riders charge 40% (at level) harder, plus cavalry 2.
func _check_crane_wings() -> bool:
	var battle := _kit.synergy_battle([["wolf_rider", 1, 1], ["light_rider", 7, 1]], [["blade_wanderer", 7, 1]])
	var events := _until(battle, func(event: Dictionary) -> bool: return event["type"] == &"damage_dealt" and event["source"] == 0)
	var increase := Kit.at_level(40, _level(events, Battle.SIDE_A, &"formation.crane_wings")) + 30
	return Kit.expect("corner impact", Kit.damage_to(events, 0, 2)[0]["amount"], Kit.damage(_attack(battle, 0), 25, increase))


# Fish scales: the first hit on a member is split evenly among the three;
# the member hit takes the rounding remainder.
func _check_fish_scales() -> bool:
	var battle := _kit.synergy_battle([["blade_wanderer", 1, 1], ["archer", 2, 2], ["fire_adept", 3, 3]], [["blade_wanderer", 7, 1]])
	var events := _until(battle, func(event: Dictionary) -> bool: return event["type"] == &"damage_dealt" and event["source"] == 3)
	var full := Kit.damage(_attack(battle, 3), 25)
	var shares: Array = Kit.of_type(events, &"damage_dealt").filter(func(event: Dictionary) -> bool: return event["source"] == 3).map(func(event: Dictionary) -> Array: return [event["target"], event["amount"]])
	var victim: int = shares[0][0] if not shares.is_empty() else -1
	var others := [0, 1, 2].filter(func(unit: int) -> bool: return unit != victim).map(func(unit: int) -> Array: return [unit, full / 3])
	var expected: Array = [[victim, full - 2 * (full / 3)]] + others
	var sorted_shares := shares.slice(1)
	sorted_shares.sort()
	return (Kit.expect("split hits", [shares[0]] + sorted_shares if not shares.is_empty() else [], expected)
		and Kit.expect("split event", Kit.triggered(events, &"mod.split_first_hit").size(), 1))


# Tam Tài: +10 Khí at the start, plus Hợp Lực 3's 10.
func _check_three_powers() -> bool:
	var battle := _kit.synergy_battle([["wolf_blade", 4, 1], ["wolf_spear", 4, 2], ["wolf_archer", 4, 3]], [["blade_wanderer", 4, 4]])
	_kit.run_ticks(battle, 1)
	return Kit.expect("starting Khí", [battle.get_unit_state(0)["qi"], battle.get_unit_state(1)["qi"], battle.get_unit_state(2)["qi"]], [20, 20, 20])


# Wild geese and long serpent activate with their five members; the
# event's nested arrays are read-only like the event itself.
func _check_wide_formations() -> bool:
	var geese := _kit.synergy_battle([["blade_wanderer", 4, 1], ["archer", 3, 2], ["wolf_archer", 5, 2], ["fire_adept", 2, 3], ["ice_mage", 6, 3]], [["blade_wanderer", 4, 4]])
	var serpent := _kit.synergy_battle([["blade_wanderer", 2, 3], ["archer", 3, 3], ["fire_adept", 4, 3], ["spearman", 5, 3], ["shield_guard", 6, 3]], [["blade_wanderer", 4, 4]])
	var geese_event := Kit.activated(_kit.run_ticks(geese, 1), Battle.SIDE_A, &"formation.wild_geese")
	var serpent_event := Kit.activated(_kit.run_ticks(serpent, 1), Battle.SIDE_A, &"formation.long_serpent")
	return (Kit.expect("wild geese units", geese_event.get("units"), [0, 1, 2, 3, 4])
		and Kit.expect("long serpent units", serpent_event.get("units"), [0, 1, 2, 3, 4])
		and Kit.expect("read-only units and cells", [(geese_event["units"] as Array).is_read_only(), (geese_event["cells"] as Array).is_read_only()], [true, true]))


# A member's death breaks its formation once: formation_broken, caused by
# the death, with the formation's cells.
func _check_broken() -> bool:
	var battle := _kit.synergy_battle([["blade_wanderer", 4, 1], ["spearman", 5, 1], ["archer", 4, 2], ["fire_adept", 5, 2]],
		[["thiet_nha", 4, 1], ["ba_khac", 3, 1], ["lieu_mi", 4, 4], ["lac_hong", 5, 4]])
	var events := _kit.run_until(battle, func(event: Dictionary) -> bool: return event["type"] == &"formation_broken" and event["side"] == Battle.SIDE_A)
	var broken: Dictionary = events.back()
	var death := Kit.first(events, func(event: Dictionary) -> bool: return event["id"] == broken.get("cause"))
	events.append_array(_kit.run_ticks(battle, 2000))
	var count := events.filter(func(event: Dictionary) -> bool: return event["type"] == &"formation_broken" and event["side"] == Battle.SIDE_A and event["source_id"] == &"formation.square").size()
	return (Kit.expect("broken formation", broken.get("source_id"), &"formation.square")
		and Kit.expect("caused by a death", death.get("type"), &"unit_died")
		and Kit.expect("cells", broken.get("cells"), [Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 2), Vector2i(4, 2)])
		and Kit.expect("broken once", count, 1)
		and Kit.expect("read-only broken units", (broken["units"] as Array).is_read_only(), true))


# The same line-ups give the same hash; moving one unit changes it.
func _check_determinism() -> bool:
	var line := [["shield_guard", 3, 1], ["iron_guard", 4, 1], ["wolf_shield", 5, 1], ["archer", 3, 4], ["wolf_archer", 4, 4], ["fire_adept", 4, 2], ["wolf_rider", 1, 1]]
	var enemy := [["wolf_blade", 3, 1], ["blood_wolf", 4, 1], ["wolf_spear", 4, 2], ["wolf_marksman", 4, 4], ["light_rider", 7, 1]]
	var first := _kit.synergy_battle(line, enemy).run_to_end(Kit.MAX_TICKS)
	var second := _kit.synergy_battle(line, enemy).run_to_end(Kit.MAX_TICKS)
	var moved := line.duplicate(true)
	moved[5] = ["fire_adept", 6, 2]
	var third := _kit.synergy_battle(moved, enemy).run_to_end(Kit.MAX_TICKS)
	print("Formation battle test: hash %s, moved %s" % [first, third])
	return Kit.expect("same hash", second, first) and Kit.expect("moved hash differs", third != first, true)


# What evaluate() shows is what the battle turns on, for both sides:
# formations, levels, milestones and Hợp Lực.
func _check_evaluate_matches_battle() -> bool:
	var lines: Array = [
		[["shield_guard", 3, 1], ["iron_guard", 4, 1], ["wolf_shield", 5, 1], ["archer", 3, 4], ["wolf_archer", 4, 4], ["fire_adept", 4, 2], ["spearman", 1, 3]],
		[["wolf_blade", 3, 1], ["blood_wolf", 4, 1], ["wolf_spear", 4, 2], ["wolf_marksman", 4, 4], ["light_rider", 7, 1], ["thiet_nha", 1, 2]],
	]
	var events := _kit.run_ticks(_kit.synergy_battle(lines[Battle.SIDE_A], lines[Battle.SIDE_B]), 1)
	for side: int in [Battle.SIDE_A, Battle.SIDE_B]:
		var result: Dictionary = _kit.catalog.get_synergy().evaluate(_kit.pieces(lines[side]))
		var own := events.filter(func(event: Dictionary) -> bool: return event["type"] == &"synergy_activated" and event["side"] == side)
		var shown: Array = result["formations"].map(func(entry: Dictionary) -> Array: return [entry["id"], entry["level"]])
		var applied: Array = own.filter(func(event: Dictionary) -> bool: return event["kind"] == &"formation").map(func(event: Dictionary) -> Array: return [event["source_id"], event["level"]])
		var milestones := 0
		for entry: Dictionary in result["class_milestones"] + result["race_milestones"]:
			milestones += entry["reached"]
		var applied_milestones := own.filter(func(event: Dictionary) -> bool: return event["kind"] == &"class" or event["kind"] == &"race").size()
		var what := "side %d " % side
		if not (Kit.expect(what + "has formations", shown.is_empty(), false)
				and Kit.expect(what + "formations", applied, shown)
				and Kit.expect(what + "milestones", applied_milestones, milestones)
				and Kit.expect(what + "hop luc", Kit.activated(events, side, &"hop_luc").get("level"), result["hop_luc"])):
			return false
	return true
