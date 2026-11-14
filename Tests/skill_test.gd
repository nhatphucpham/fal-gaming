extends SceneTree

# Headless tests for the six class skills: the cast timing, no cast without
# a target, and each skill's core effect and 3-star version on tiny set-ups
# with exact damage numbers. Khí, passives, statuses and the full battle are
# in passive_test.gd. Positions in comments are global (col, row); add()
# takes local col, rank (A: row = 4 - rank; B: col = 7 - local col,
# row = 3 + rank).

const Kit := preload("res://Tests/skill_test_kit.gd")
# Targets that cannot cast, so 3-star arrow rains do not end the test early.
const NO_SKILL: Dictionary = {"skill": null}

var _kit := Kit.new()


func _initialize() -> void:
	var ok := _run()
	_kit.free_battles()
	if ok:
		print("Skill test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not ClassDB.class_exists("SkillData"):
		push_error("SkillData is missing: build the GDExtension (scons) before importing")
		return false
	if not _kit.load_catalog():
		return false
	var checks: Array[Callable] = [
		_check_cast_timing, _check_no_target, _check_sweep, _check_heart_pierce,
		_check_hold_ground, _check_hold_ground_star3, _check_breakthrough,
		_check_arrow_rain, _check_arcane_circle,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Skill test failed in %s" % check.get_method())
			return false
	return true


# Two swords at (3,3) and (3,4): the cast starts the tick after the first
# attack fills the Khí, resolves cast_ticks - 1 ticks later on its last
# tick, and empties the Khí; the caster does not attack meanwhile.
func _check_cast_timing() -> bool:
	var battle := _kit.new_battle(_kit.quick_rules())
	var sword := _kit.add(battle, Battle.SIDE_A, Kit.SWORD, 4, 1)
	_kit.add(battle, Battle.SIDE_B, Kit.SWORD, 4, 1)
	var events := _kit.run_until(battle, Kit.is_resolve_of(sword))
	var started: Array[Dictionary] = Kit.of_type(events, &"skill_cast_started").filter(func(event: Dictionary) -> bool: return event["unit"] == sword)
	var resolved: Dictionary = events.back()
	var first_attack: Dictionary = Kit.of_type(events, &"unit_attacked").filter(func(event: Dictionary) -> bool: return event["unit"] == sword)[0]
	var attacks_during: Array = Kit.of_type(events, &"unit_attacked").filter(func(event: Dictionary) -> bool:
		return event["unit"] == sword and event["tick"] >= started[0]["tick"])
	var emptied: Array[Dictionary] = Kit.caused_by(events, started[0]["id"], &"qi_changed")
	return (Kit.expect("cast start tick", started[0]["tick"], first_attack["tick"] + 1)
		and Kit.expect("cast length", resolved["tick"] - started[0]["tick"], _kit.catalog.battle_rules.cast_ticks - 1)
		and Kit.expect("attacks while casting", attacks_during.size(), 0)
		and Kit.expect("Khí after the cast", emptied.size() == 1 and emptied[0]["qi"] == 0 and emptied[0]["tick"] == resolved["tick"], true)
		and Kit.expect("cast cells", started[0]["cells"], [Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)]))


# A spear at (3,3) with its only enemy diagonal at (4,4): full Khí, but no
# enemy in the column ahead, so it keeps the Khí and never casts.
func _check_no_target() -> bool:
	var battle := _kit.new_battle(_kit.quick_rules())
	var spear := _kit.add(battle, Battle.SIDE_A, Kit.SPEAR, 4, 1)
	_kit.add(battle, Battle.SIDE_B, Kit.SWORD, 3, 1)
	var events := _kit.run_ticks(battle, 80)
	var casts := Kit.of_type(events, &"skill_cast_started").filter(func(event: Dictionary) -> bool: return event["unit"] == spear)
	var state := battle.get_unit_state(spear)
	return Kit.expect("spear casts without a target", casts.size(), 0) and Kit.expect("spear Khí", state["qi"], state["qi_max"])


# A sword at (3,3) sweeps three skill-less archers at (2,4), (3,4), (4,4): 60 * 180%
# * 100 / 110 = 98 each. At 3 stars: attack 194, 450%, 793 each, twice,
# the second 5 ticks later on the same cells.
func _check_sweep() -> bool:
	for star: int in [1, 3]:
		var battle := _kit.new_battle(_kit.quick_rules())
		var sword := _kit.add(battle, Battle.SIDE_A, Kit.SWORD, 4, 1, star)
		for col: int in [5, 4, 3]:
			_kit.add_test_unit(battle, Battle.SIDE_B, Kit.ARCHER, "archer", NO_SKILL, col, 1, star)
		var events := _kit.run_until(battle, Kit.is_resolve_of(sword))
		var first: Dictionary = events.back()
		if not Kit.expect("sweep damage at %d stars" % star, Kit.field(Kit.caused_by(events, first["id"]), "amount"), [98, 98, 98] if star == 1 else [793, 793, 793]):
			return false
		if star == 1:
			continue
		events = _kit.run_until(battle, Kit.is_resolve_of(sword))
		var second: Dictionary = events.back()
		if not (Kit.expect("second sweep", [second["is_after_skill"], second["tick"] - first["tick"], second["cells"]], [true, 5, first["cells"]])
				and Kit.expect("second sweep damage", Kit.field(Kit.caused_by(events, second["id"]), "amount"), [793, 793, 793])):
			return false
	return true


# A spear at (3,3) pierces skill-less archers at (3,4), (3,5), (3,6): 55 * 200% *
# 100 / 110 = 100 each, and breaks their armor for 80 ticks, so its next
# basic hit deals 55 * 100 / 107 = 51 instead of 50. At 3 stars it reaches
# a fourth archer at (3,7): attack 178, 500%, 809 each.
func _check_heart_pierce() -> bool:
	for star: int in [1, 3]:
		var battle := _kit.new_battle(_kit.quick_rules())
		var spear := _kit.add(battle, Battle.SIDE_A, Kit.SPEAR, 4, 1, star)
		var ranks: Array[int] = [1, 2, 3]
		if star == 3:
			ranks.append(4)
		for rank: int in ranks:
			_kit.add_test_unit(battle, Battle.SIDE_B, Kit.ARCHER, "archer", NO_SKILL, 4, rank, star)
		var events := _kit.run_until(battle, Kit.is_resolve_of(spear))
		var resolved: Dictionary = events.back()
		var expected: Array = [100, 100, 100] if star == 1 else [809, 809, 809, 809]
		if not Kit.expect("pierce damage at %d stars" % star, Kit.field(Kit.caused_by(events, resolved["id"]), "amount"), expected):
			return false
		var breaks := Kit.caused_by(events, resolved["id"], &"status_applied")
		if not Kit.expect("armor breaks", Kit.field(breaks, "end_tick"), ranks.map(func(_rank: int) -> int: return resolved["tick"] + 80)):
			return false
		if star == 3:
			continue
		var next_hit := _kit.run_until(battle, func(event: Dictionary) -> bool:
			return event["type"] == &"damage_dealt" and event["source"] == spear and event["skill"] == &"")
		if not Kit.expect("hit on broken armor", next_hit.back()["amount"], 51):
			return false
	return true


# A slow shield (one attack per 67 ticks, so it does not recast and refresh
# the taunt) at (3,3) and a sword at (4,3); the enemy sword at (4,4) first
# fights the sword in its column. Trấn Thủ taunts it for 60 ticks, so its
# next attack goes to the shield, which takes 60 * 100 / 140 * 60% = 25
# under guard; the taunt ends on its end tick.
func _check_hold_ground() -> bool:
	var battle := _kit.new_battle(_kit.quick_rules())
	var shield := _kit.add_test_unit(battle, Battle.SIDE_A, Kit.SHIELD, "slow_shield", {"attacks_per_100s": 30}, 4, 1)
	var ally := _kit.add(battle, Battle.SIDE_A, Kit.SWORD, 5, 1)
	var enemy := _kit.add(battle, Battle.SIDE_B, Kit.SWORD, 3, 1)
	var before := _kit.run_until(battle, Kit.is_resolve_of(shield))
	var first_attack: Dictionary = Kit.of_type(before, &"unit_attacked").filter(func(event: Dictionary) -> bool: return event["unit"] == enemy)[0]
	var resolved: Dictionary = before.back()
	var statuses := Kit.caused_by(before, resolved["id"], &"status_applied")
	var expected_statuses := [[enemy, &"status.taunted", shield, resolved["tick"] + 60], [shield, &"status.guard", shield, resolved["tick"] + 60]]
	var got_statuses := statuses.map(func(event: Dictionary) -> Array: return [event["unit"], event["status"], event["source"], event["end_tick"]])
	if not (Kit.expect("target before the taunt", first_attack["target"], ally) and Kit.expect("statuses", got_statuses, expected_statuses)):
		return false
	var after := _kit.run_until(battle, func(event: Dictionary) -> bool:
		return event["type"] == &"unit_attacked" and event["unit"] == enemy)
	var guarded := Kit.caused_by(after, after.back()["id"])
	if not (Kit.expect("target under taunt", after.back()["target"], shield) and Kit.expect("guarded hit", Kit.field(guarded, "amount"), [25])):
		return false
	var ended := _kit.run_until(battle, func(event: Dictionary) -> bool:
		return event["type"] == &"status_ended" and event["unit"] == enemy)
	return (Kit.expect("taunt end tick", ended.back()["tick"], resolved["tick"] + 60)
		and Kit.expect("taunt over in state", battle.get_unit_state(enemy)["statuses"], []))


# A 3-star shield at (3,3) next to an enemy sword at (3,4): when the taunt
# ends 60 ticks after the cast, the Hậu chiêu pushes the sword to (3,5).
func _check_hold_ground_star3() -> bool:
	var battle := _kit.new_battle(_kit.quick_rules())
	var shield := _kit.add(battle, Battle.SIDE_A, Kit.SHIELD, 4, 1, 3)
	var enemy := _kit.add(battle, Battle.SIDE_B, Kit.SWORD, 4, 1)
	var first: Dictionary = _kit.run_until(battle, Kit.is_resolve_of(shield)).back()
	var events := _kit.run_until(battle, func(event: Dictionary) -> bool:
		return event["type"] == &"skill_resolved" and event["unit"] == shield and event["is_after_skill"])
	var after: Dictionary = events.back()
	events.append_array(_kit.run_ticks(battle, 1))
	var pushes := Kit.caused_by(events, after["id"], &"unit_moved")
	return (Kit.expect("Hậu chiêu", [after["is_after_skill"], after["tick"]], [true, first["tick"] + 60])
		and Kit.expect("push", pushes.map(func(event: Dictionary) -> Array: return [event["unit"], event["kind"], event["to_col"], event["to_row"]]), [[enemy, &"knockback", 3, 5]]))


# A cavalry without its opening at (0,3) fights a shield at (0,4); the
# most crowded column is 5 (shields at (5,6), (5,7)). It repositions to
# (5,0), the free cell nearest to it furthest from the enemy, runs 5 cells
# and hits for 60 * 150% * 175% * 100 / 140 = 112. At 3 stars (attack 194,
# 375%) it then charges column 6 from (6,4) into a shield at (6,7):
# 909 after 5 cells, 675 after 2.
func _check_breakthrough() -> bool:
	for star: int in [1, 3]:
		var battle := _kit.new_battle(_kit.quick_rules(true))
		var cavalry := _kit.add_test_unit(battle, Battle.SIDE_A, Kit.CAVALRY, "rider", {"opening": &""}, 1, 1, star)
		_kit.add(battle, Battle.SIDE_B, Kit.SHIELD, 7, 1)
		var targets: Array[int] = [_kit.add(battle, Battle.SIDE_B, Kit.SHIELD, 2, 3), _kit.add(battle, Battle.SIDE_B, Kit.SHIELD, 2, 4)]
		if star == 3:
			targets = [targets[0], _kit.add(battle, Battle.SIDE_B, Kit.SHIELD, 1, 4)]
		var events := _kit.run_until(battle, Kit.is_resolve_of(cavalry))
		var resolved: Dictionary = events.back()
		events = Kit.caused_by(events, resolved["id"], &"unit_moved") + _kit.run_ticks(battle, 120)
		var moves := Kit.of_type(events, &"unit_moved").filter(func(event: Dictionary) -> bool: return event["unit"] == cavalry)
		var expected: Array = [[targets[0], 112]] if star == 1 else [[targets[0], 909], [targets[1], 675]]
		# Later recasts hit again; only this cast's impacts count.
		var impacts := Kit.of_type(events, &"damage_dealt").filter(func(event: Dictionary) -> bool: return event["skill"] == &"skill.breakthrough").slice(0, expected.size())
		if not (Kit.expect("reposition", [moves[0]["cause"], moves[0]["to_col"], moves[0]["to_row"], moves[0]["duration_ticks"]], [resolved["id"], 5, 0, 5])
				and Kit.expect("impacts at %d stars" % star, impacts.map(func(event: Dictionary) -> Array: return [event["target"], event["amount"]]), expected)):
			return false
	return true


# An archer at (3,0) rains 5 arrows of 55 * 70% * 100 / 140 = 27 into
# column 1, where two shields with 30 hp stand at (1,4) and (1,5): two
# arrows each, front first, then the last one goes to the nearest enemy,
# the shield at (3,4). At 3 stars (attack 178, 175%): 8 arrows of 222; the
# fifth fells the front shield (1100 hp), the last three hit the next one.
func _check_arrow_rain() -> bool:
	for star: int in [1, 3]:
		var battle := _kit.new_battle(_kit.quick_rules(true))
		var archer := _kit.add(battle, Battle.SIDE_A, Kit.ARCHER, 4, 4, star)
		var near := _kit.add(battle, Battle.SIDE_B, Kit.SHIELD, 4, 1)
		var changes := {"max_hp": 30, "attack": 0} if star == 1 else {}
		var front := _kit.add_test_unit(battle, Battle.SIDE_B, Kit.SHIELD, "front", changes, 6, 1)
		var back := _kit.add_test_unit(battle, Battle.SIDE_B, Kit.SHIELD, "back", changes, 6, 2)
		var events := _kit.run_until(battle, Kit.is_resolve_of(archer))
		var arrows := Kit.caused_by(events, events.back()["id"])
		var expected: Array = [[front, 27], [front, 27], [back, 27], [back, 27], [near, 27]]
		if star == 3:
			expected = []
			for arrow: int in 8:
				expected.append([front if arrow < 5 else back, 222])
		if not Kit.expect("arrows at %d stars" % star, arrows.map(func(event: Dictionary) -> Array: return [event["target"], event["amount"]]), expected):
			return false
	return true


# A mage at (3,1); shields stand in a plus around (3,5) (4 cells away).
# Pháp Trận hits all five for 45 * 220% * 130% (counter) * 100 / 130 = 99.
# At 3 stars four more shields fill the 3x3 square: 9 hits of 797.
func _check_arcane_circle() -> bool:
	for star: int in [1, 3]:
		var battle := _kit.new_battle(_kit.quick_rules(true))
		var mage := _kit.add(battle, Battle.SIDE_A, Kit.MAGE, 4, 3, star)
		var cells: Array = [[4, 2], [4, 1], [5, 2], [3, 2], [4, 3]]
		if star == 3:
			cells.append_array([[5, 1], [3, 1], [5, 3], [3, 3]])
		for cell: Array in cells:
			_kit.add(battle, Battle.SIDE_B, Kit.SHIELD, cell[0], cell[1])
		var events := _kit.run_until(battle, Kit.is_resolve_of(mage))
		var hits := Kit.caused_by(events, events.back()["id"])
		var expected: Array = []
		expected.resize(cells.size())
		expected.fill(99 if star == 1 else 797)
		if not (Kit.expect("circle covers (3,5)", events.back()["cells"].has(Vector2i(3, 5)), true) and Kit.expect("circle hits at %d stars" % star, Kit.field(hits, "amount"), expected)):
			return false
	return true
