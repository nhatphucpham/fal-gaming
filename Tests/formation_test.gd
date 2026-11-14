extends SceneTree

# Headless tests for Synergy.evaluate() without a battle: every formation's
# pattern (positive, negative, mirrored, at the board edges, overlapping),
# the wolf-folk and human rules, levels, near-misses, milestone counting
# (copies of a unit count once for classes, cost 4-5 twice for races), Hợp
# Lực totals and tiers, the level cap, that evaluating changes nothing, and
# the data validation refuses. Cells are local
# (col 1..7, rank 1..4, rank 1 at the front).

const Kit := preload("res://Tests/synergy_test_kit.gd")

var _kit := Kit.new()
var _synergy: Synergy


func _initialize() -> void:
	var ok := _run()
	_kit.free_battles()
	if ok:
		print("Formation test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not ClassDB.class_exists("Synergy"):
		push_error("Synergy is missing: build the GDExtension (scons) before importing")
		return false
	if not _kit.load_catalog():
		return false
	_synergy = _kit.catalog.get_synergy()
	if _synergy == null or _kit.catalog.formations.size() != 12:
		push_error("Formation test: expected a Synergy and 12 formations")
		return false
	var checks: Array[Callable] = [
		_check_rows, _check_arrow_rain, _check_pairs, _check_spearhead, _check_wide_shapes,
		_check_corners_and_diagonals, _check_three_powers, _check_overlaps, _check_wolf_rules,
		_check_human_levels, _check_level_cap, _check_near_misses, _check_milestones, _check_hop_luc,
		_check_no_mutation, _check_bad_data,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Formation test failed in %s" % check.get_method())
			return false
	return true


func _formations(list: Array) -> Array:
	return Kit.ids(_synergy.evaluate(list)["formations"])


func _has(list: Array, id: StringName) -> bool:
	return _formations(list).has(id)


# Shield wall: three shields side by side in any rank, the right edge too;
# a gap or another class breaks it. Twin blades: two swords; long serpent:
# any five in a row.
func _check_rows() -> bool:
	var wall := [Kit.bare("shield", 1, 2), Kit.bare("shield", 2, 2), Kit.bare("shield", 3, 2)]
	var result: Dictionary = _synergy.evaluate(wall)["formations"][0]
	var edge := [Kit.bare("shield", 5, 4), Kit.bare("shield", 6, 4), Kit.bare("shield", 7, 4)]
	var gap := [Kit.bare("shield", 1, 1), Kit.bare("shield", 2, 1), Kit.bare("shield", 4, 1)]
	var mixed := [Kit.bare("shield", 1, 1), Kit.bare("sword", 2, 1), Kit.bare("shield", 3, 1)]
	var serpent := [Kit.bare("sword", 3, 3), Kit.bare("archer", 4, 3), Kit.bare("mage", 5, 3), Kit.bare("spear", 6, 3), Kit.bare("shield", 7, 3)]
	return (Kit.expect("wall id", result["id"], &"formation.shield_wall")
		and Kit.expect("wall cells", result["cells"], [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)])
		and Kit.expect("wall level", result["level"], 1)
		and Kit.expect("wall at the edge", _has(edge, &"formation.shield_wall"), true)
		and Kit.expect("wall with a gap", _has(gap, &"formation.shield_wall"), false)
		and Kit.expect("wall with a sword", _has(mixed, &"formation.shield_wall"), false)
		and Kit.expect("twin blades", _has([Kit.bare("sword", 6, 1), Kit.bare("sword", 7, 1)], &"formation.twin_blades"), true)
		and Kit.expect("swords in a column", _has([Kit.bare("sword", 6, 1), Kit.bare("sword", 6, 2)], &"formation.twin_blades"), false)
		and Kit.expect("long serpent", _has(serpent, &"formation.long_serpent"), true)
		and Kit.expect("four in a row", _has(serpent.slice(0, 4), &"formation.long_serpent"), false))


# Arrow rain only in the back rank.
func _check_arrow_rain() -> bool:
	var back := [Kit.bare("archer", 2, 4), Kit.bare("archer", 3, 4), Kit.bare("archer", 4, 4)]
	var middle := [Kit.bare("archer", 2, 3), Kit.bare("archer", 3, 3), Kit.bare("archer", 4, 3)]
	return Kit.expect("arrow rain in rank 4", _has(back, &"formation.arrow_rain"), true) and Kit.expect("arrow rain in rank 3", _has(middle, &"formation.arrow_rain"), false)


# Spell guard and spear cover: the first class directly in front of the second.
func _check_pairs() -> bool:
	return (Kit.expect("spell guard", _has([Kit.bare("shield", 4, 1), Kit.bare("mage", 4, 2)], &"formation.spell_guard"), true)
		and Kit.expect("mage in front", _has([Kit.bare("mage", 4, 1), Kit.bare("shield", 4, 2)], &"formation.spell_guard"), false)
		and Kit.expect("diagonal guard", _has([Kit.bare("shield", 4, 1), Kit.bare("mage", 5, 2)], &"formation.spell_guard"), false)
		and Kit.expect("spear cover", _has([Kit.bare("spear", 7, 3), Kit.bare("archer", 7, 4)], &"formation.spear_cover"), true))


# Spearhead: cavalry in rank 1, spears diagonally behind on both sides.
func _check_spearhead() -> bool:
	var head := [Kit.bare("cavalry", 4, 1), Kit.bare("spear", 3, 2), Kit.bare("spear", 5, 2)]
	var deep := [Kit.bare("cavalry", 4, 2), Kit.bare("spear", 3, 3), Kit.bare("spear", 5, 3)]
	var edge := [Kit.bare("cavalry", 1, 1), Kit.bare("spear", 2, 2)]
	var result: Dictionary = _synergy.evaluate(head)["formations"][0]
	return (Kit.expect("spearhead slot cells", result["slot_cells"], [Vector2i(4, 1), Vector2i(3, 2), Vector2i(5, 2)])
		and Kit.expect("spearhead in rank 2", _has(deep, &"formation.spearhead"), false)
		and Kit.expect("spearhead at the edge", _has(edge, &"formation.spearhead"), false))


# Wild geese (a V of five) and the 2x2 square, in a corner.
func _check_wide_shapes() -> bool:
	var geese := [Kit.bare("sword", 4, 1), Kit.bare("archer", 3, 2), Kit.bare("archer", 5, 2), Kit.bare("mage", 2, 3), Kit.bare("mage", 6, 3)]
	var flat := [Kit.bare("sword", 4, 1), Kit.bare("archer", 3, 2), Kit.bare("archer", 5, 2), Kit.bare("mage", 2, 2), Kit.bare("mage", 6, 2)]
	var square := [Kit.bare("sword", 6, 3), Kit.bare("archer", 7, 3), Kit.bare("mage", 6, 4), Kit.bare("spear", 7, 4)]
	return (Kit.expect("wild geese", _has(geese, &"formation.wild_geese"), true)
		and Kit.expect("flat wings", _has(flat, &"formation.wild_geese"), false)
		and Kit.expect("square in the corner", _has(square, &"formation.square"), true)
		and Kit.expect("three of a square", _has(square.slice(0, 3), &"formation.square"), false))


# Crane wings needs both front corners; fish scales a diagonal from rank 1,
# either way.
func _check_corners_and_diagonals() -> bool:
	var scales := [Kit.bare("sword", 1, 1), Kit.bare("archer", 2, 2), Kit.bare("mage", 3, 3)]
	var mirrored := [Kit.bare("sword", 7, 1), Kit.bare("archer", 6, 2), Kit.bare("mage", 5, 3)]
	var late := [Kit.bare("sword", 1, 2), Kit.bare("archer", 2, 3), Kit.bare("mage", 3, 4)]
	return (Kit.expect("crane wings", _has([Kit.bare("cavalry", 1, 1), Kit.bare("cavalry", 7, 1)], &"formation.crane_wings"), true)
		and Kit.expect("crane wings in rank 2", _has([Kit.bare("cavalry", 1, 2), Kit.bare("cavalry", 7, 2)], &"formation.crane_wings"), false)
		and Kit.expect("fish scales", _has(scales, &"formation.fish_scales"), true)
		and Kit.expect("mirrored fish scales", _has(mirrored, &"formation.fish_scales"), true)
		and Kit.expect("fish scales from rank 2", _has(late, &"formation.fish_scales"), false))


# Tam Tài: three classes in one column, never two of one class.
func _check_three_powers() -> bool:
	var column := [Kit.bare("shield", 2, 2), Kit.bare("spear", 2, 3), Kit.bare("archer", 2, 4)]
	var repeated := [Kit.bare("shield", 2, 2), Kit.bare("spear", 2, 3), Kit.bare("shield", 2, 4)]
	return Kit.expect("three powers", _has(column, &"formation.three_powers"), true) and Kit.expect("two shields", _has(repeated, &"formation.three_powers"), false)


# Six shields in a row are two walls on disjoint units; four are one. A
# shield may be in a wall and a spell guard at once.
func _check_overlaps() -> bool:
	var six: Array = []
	for col: int in range(1, 7):
		six.append(Kit.bare("shield", col, 1))
	var walls: Array = _synergy.evaluate(six)["formations"].filter(func(entry: Dictionary) -> bool: return entry["id"] == &"formation.shield_wall")
	var four := six.slice(0, 4)
	var shared := [Kit.bare("shield", 1, 1), Kit.bare("shield", 2, 1), Kit.bare("shield", 3, 1), Kit.bare("mage", 2, 2)]
	return (Kit.expect("walls in six shields", walls.size(), 2)
		and Kit.expect("first wall", walls[0]["cells"], [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)])
		and Kit.expect("second wall", walls[1]["cells"], [Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1)])
		and Kit.expect("walls in four shields", _formations(four).count(&"formation.shield_wall"), 1)
		and Kit.expect("shared shield", _formations(shared), [&"formation.shield_wall", &"formation.spell_guard"]))


# Wolf 1: a wolf in the middle slot completes a 3-unit formation with a
# member missing; not off-centre. Wolf 5: a 4-unit formation needs only 3.
func _check_wolf_rules() -> bool:
	var middle := [Kit.bare("shield", 1, 1), Kit.bare("shield", 2, 1, "", "race.wolf")]
	var wall: Dictionary = _synergy.evaluate(middle)["formations"][0] if not _synergy.evaluate(middle)["formations"].is_empty() else {}
	var side := [Kit.bare("shield", 1, 1, "", "race.wolf"), Kit.bare("shield", 2, 1)]
	var pack := [Kit.bare("sword", 1, 1, "a", "race.wolf"), Kit.bare("sword", 2, 1, "b", "race.wolf"), Kit.bare("archer", 1, 2, "c", "race.wolf"),
		Kit.bare("mage", 6, 4, "d", "race.wolf"), Kit.bare("spear", 4, 4, "e", "race.wolf")]
	var small_pack := pack.slice(0, 3)
	return (Kit.expect("wolf-held wall", wall.get("id"), &"formation.shield_wall")
		and Kit.expect("missing cell", wall.get("missing_cell"), Vector2i(3, 1))
		and Kit.expect("wolf on the side", _has(side, &"formation.shield_wall"), false)
		and Kit.expect("square of three with 5 wolves", _has(pack, &"formation.square"), true)
		and Kit.expect("square of three with 3 wolves", _has(small_pack, &"formation.square"), false))


# Human 1: a formation with a human is level 2; human 5: with two humans
# level 3. Cost 4-5 count twice toward the five.
func _check_human_levels() -> bool:
	var one := _kit.pieces([["blade_wanderer", 4, 1], ["wolf_blade", 5, 1]])
	var five := _kit.pieces([["blade_wanderer", 4, 1], ["wolf_blade", 5, 1], ["heavy_rider", 1, 3], ["archer", 7, 4], ["fire_adept", 1, 4]])
	var two_humans := _kit.pieces([["blade_wanderer", 4, 1], ["thiet_nha", 5, 1], ["shield_guard", 1, 1], ["shield_guard", 2, 1], ["shield_guard", 3, 1], ["heavy_rider", 7, 4]])
	var none := _kit.pieces([["wolf_blade", 4, 1], ["blood_wolf", 5, 1]])
	var level := func(list: Array, id: StringName) -> int:
		for entry: Dictionary in _synergy.evaluate(list)["formations"]:
			if entry["id"] == id:
				return entry["level"]
		return 0
	return (Kit.expect("no human", level.call(none, &"formation.twin_blades"), 1)
		and Kit.expect("one human", level.call(one, &"formation.twin_blades"), 2)
		and Kit.expect("one human of five", level.call(five, &"formation.twin_blades"), 2)
		and Kit.expect("three humans of five", level.call(two_humans, &"formation.shield_wall"), 3)
		and Kit.expect("one human with human 5", level.call(two_humans, &"formation.twin_blades"), 2))


# The level cap: rules give at most +3, so a +3 rule reaches the catalog's
# cap of 4 exactly; a lower max_formation_level clamps the same line-up.
func _check_level_cap() -> bool:
	var human := _kit.catalog.milestones.filter(func(entry: MilestoneData) -> bool: return entry.id == &"milestone.race_human")[0].duplicate(true) as MilestoneData
	(human.tiers[0].modifiers[0] as ModifierData).value = 3
	var milestones: Array = _kit.catalog.milestones.map(func(entry: MilestoneData) -> MilestoneData: return human if entry.id == human.id else entry)
	var at_cap := Synergy.new()
	var capped := Synergy.new()
	var low_cap := _kit.catalog.hop_luc.duplicate(true) as HopLucData
	low_cap.max_formation_level = 3
	var problems := at_cap.setup(_kit.catalog.formations, milestones, _kit.catalog.hop_luc) + capped.setup(_kit.catalog.formations, milestones, low_cap)
	var line := _kit.pieces([["blade_wanderer", 4, 1], ["wolf_blade", 5, 1]])
	var level := func(synergy: Synergy) -> int:
		var formations: Array = synergy.evaluate(line)["formations"]
		return formations[0]["level"] if formations.size() == 1 else 0
	return (Kit.expect("test configs valid", problems, PackedStringArray())
		and Kit.expect("catalog cap", _kit.catalog.hop_luc.max_formation_level, 4)
		and Kit.expect("+3 reaches the cap of 4", level.call(at_cap), 4)
		and Kit.expect("cap of 3 clamps", level.call(capped), 3))


# Two shields with a free cell beside: a near-miss naming the class. A
# taken cell or a lone unit gives none.
func _check_near_misses() -> bool:
	var two := [Kit.bare("shield", 1, 1), Kit.bare("shield", 2, 1)]
	var near: Array = _synergy.evaluate(two)["near_formations"]
	var walls := near.filter(func(entry: Dictionary) -> bool: return entry["id"] == &"formation.shield_wall")
	var blocked := [Kit.bare("shield", 1, 1), Kit.bare("shield", 2, 1), Kit.bare("sword", 3, 1)]
	var blocked_walls: Array = _synergy.evaluate(blocked)["near_formations"].filter(func(entry: Dictionary) -> bool: return entry["id"] == &"formation.shield_wall")
	return (Kit.expect("near walls", walls.size(), 1)
		and Kit.expect("missing cell", walls[0]["missing_cell"], Vector2i(3, 1))
		and Kit.expect("needed class", walls[0]["needed_class"], &"class.shield")
		and Kit.expect("taken cell", blocked_walls.size(), 0)
		and Kit.expect("lone shield", _synergy.evaluate([Kit.bare("shield", 1, 1)])["near_formations"].size(), 0))


# Classes count different units (two copies are one); races count every
# unit, cost 4-5 twice.
func _check_milestones() -> bool:
	var result: Dictionary = _synergy.evaluate(_kit.pieces([["shield_guard", 1, 1], ["shield_guard", 3, 1], ["wolf_shield", 5, 1], ["heavy_rider", 7, 3]]))
	var shield := Kit.milestone(result, &"milestone.class_shield")
	var human := Kit.milestone(result, &"milestone.race_human")
	var wolf := Kit.milestone(result, &"milestone.race_wolf")
	return (Kit.expect("shield count", shield["count"], 2)
		and Kit.expect("shield reached", shield["reached"], 1)
		and Kit.expect("shield thresholds", Array(shield["thresholds"]), [2, 4])
		and Kit.expect("human count", human["count"], 4)
		and Kit.expect("human reached", human["reached"], 2)
		and Kit.expect("wolf count", wolf["count"], 1))


# Points: milestones reached plus formation instances; the tier reached and
# the next one.
func _check_hop_luc() -> bool:
	var result: Dictionary = _synergy.evaluate(_kit.pieces([["shield_guard", 3, 1], ["iron_guard", 4, 1], ["wolf_shield", 5, 1], ["archer", 3, 4], ["wolf_archer", 4, 4], ["fire_adept", 4, 2], ["spearman", 1, 3]]))
	# shield 2, archer 2, human 1/3/5, wolf 1, shield wall, arrow rain, spell guard.
	var empty: Dictionary = _synergy.evaluate([])
	return (Kit.expect("points", result["hop_luc"], 9)
		and Kit.expect("tier", result["hop_luc_tier"], 9)
		and Kit.expect("next tier", result["next_tier"], 12)
		and Kit.expect("empty points", empty["hop_luc"], 0)
		and Kit.expect("empty tier", empty["hop_luc_tier"], 0)
		and Kit.expect("empty next tier", empty["next_tier"], 3))


# Evaluating a preview twice gives the same answer and leaves its input as it was.
func _check_no_mutation() -> bool:
	var list := [Kit.bare("shield", 1, 1), Kit.bare("shield", 2, 1), Kit.bare("shield", 3, 1)]
	var copy := list.duplicate(true)
	var first: Dictionary = _synergy.evaluate(list)
	return Kit.expect("same result", _synergy.evaluate(list), first) and Kit.expect("input unchanged", list, copy)


# Bad data is refused with a message naming it.
func _check_bad_data() -> bool:
	var bad := _kit.catalog.formations[0].duplicate(true) as FormationData
	(bad.modifiers[0] as ModifierData).handler = &"mod.nope"
	var problems := Synergy.new().setup([bad], _kit.catalog.milestones, _kit.catalog.hop_luc)
	var shape := _kit.catalog.formations[0].duplicate(true) as FormationData
	shape.pattern = &"pattern.nope"
	var shape_problems := Synergy.new().setup([shape], [], _kit.catalog.hop_luc)
	print("Formation test: refused as expected: %s; %s" % [problems, shape_problems])
	return (Kit.expect("bad handler refused", problems.size(), 1)
		and Kit.expect("message names it", String(problems[0]).contains("mod.nope"), true)
		and Kit.expect("bad pattern refused", shape_problems.size(), 1)
		and _check_refused_formations())


# Formations refuse what a broken formation could not take back: stats
# fixed at the start (max hp, front-rank range, attack shape), also as a
# per-formation milestone modifier; scope.side; one offset for two slots.
func _check_refused_formations() -> bool:
	var cases: Array = []
	for handler: StringName in [&"mod.max_hp_pct", &"mod.range_add_if_front", &"mod.attack_shape"]:
		var fixed := _kit.catalog.get_formation(&"formation.square").duplicate(true) as FormationData
		var modifier := fixed.modifiers[0] as ModifierData
		modifier.handler = handler
		modifier.param = &"shape.row3_behind" if handler == &"mod.attack_shape" else &""
		cases.append([String(handler), [fixed], _kit.catalog.milestones, "never reverted"])
	var human := _kit.catalog.milestones.filter(func(entry: MilestoneData) -> bool: return entry.id == &"milestone.race_human")[0].duplicate(true) as MilestoneData
	(human.tiers[1].modifiers[0] as ModifierData).handler = &"mod.max_hp_pct"
	cases.append(["per_formation max hp", [], [human], "never reverted"])
	var side := _kit.catalog.get_formation(&"formation.square").duplicate(true) as FormationData
	(side.modifiers[0] as ModifierData).scope = &"scope.side"
	cases.append(["formation scope.side", [side], [], "scope.side"])
	var twice := _kit.catalog.get_formation(&"formation.shield_wall").duplicate(true) as FormationData
	var offsets: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 0), Vector2i(1, 0)]
	twice.cells = offsets
	cases.append(["repeated offset", [twice], [], "share the offset"])
	for entry: Array in cases:
		var problems := Synergy.new().setup(entry[1], entry[2], _kit.catalog.hop_luc)
		if not Kit.expect("%s refused" % entry[0], problems.size() == 1 and String(problems[0]).contains(entry[3]), true):
			push_error("Formation test: %s gave %s" % [entry[0], problems])
			return false
	return true
