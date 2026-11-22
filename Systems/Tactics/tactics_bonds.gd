class_name TacticsBonds
extends RefCounted
## Duyên qua kề vai: bonds between two of our leaders, kept in the roster
## (`TacticsRoster.bonds`, by leader id). A Thủ công battle counts the
## phases each pair ended close together (TacticsBattle's "bond_tallies");
## at most `bond_points_per_battle` of them become points, and the points
## give the level (`bond_level_points`). A bond of level n gives each of
## the two n × `bond_attack_pct_per_level` % attack while they stand within
## `bond_radius_cells` (in C++). See Docs/systems/tactics_world.md.
## [codeblock]
## TacticsBonds.set_up_battle(battle, roster, world_data)
## var rows := TacticsBonds.apply_tallies(roster, world_data, battle.get_battle_report())
## [/codeblock]


## The level `points` reach: 0 below the first threshold.
static func level_of(points: int, data: TacticsWorldData) -> int:
	var level := 0
	for threshold: int in data.bond_level_points:
		if points >= threshold:
			level += 1
	return level


## The roster's bond between two leader ids, or an empty Dictionary.
static func find_bond(roster: TacticsRoster, a: StringName, b: StringName) -> Dictionary:
	var pair := _pair(a, b)
	for bond: Dictionary in roster.bonds:
		if bond["a"] == pair[0] and bond["b"] == pair[1]:
			return bond
	return {}


static func level_between(roster: TacticsRoster, data: TacticsWorldData, a: StringName, b: StringName) -> int:
	var bond := find_bond(roster, a, b)
	return level_of(int(bond["points"]), data) if not bond.is_empty() else 0


## Bonds of level 1 or more that name this leader: [{partner, level}], by
## level then partner id.
static func bonds_of(roster: TacticsRoster, data: TacticsWorldData, leader_id: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for bond: Dictionary in roster.bonds:
		var level := level_of(int(bond["points"]), data)
		if level > 0 and (bond["a"] == leader_id or bond["b"] == leader_id):
			found.append({"partner": bond["b"] if bond["a"] == leader_id else bond["a"], "level": level})
	found.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return left["level"] > right["level"] or (left["level"] == right["level"] and String(left["partner"]) < String(right["partner"])))
	return found


## Gives a loaded, not started battle our leaders' bonds (and turns its
## tallies on); false when the battle refused them.
static func set_up_battle(battle: TacticsBattle, roster: TacticsRoster, data: TacticsWorldData) -> bool:
	var leaders := _our_leaders(battle.get_units())
	var bonds: Array = []
	for first: int in leaders.size():
		for second: int in range(first + 1, leaders.size()):
			var level := level_between(roster, data, leaders[first]["id"], leaders[second]["id"])
			if level > 0:
				bonds.append({"a": leaders[first]["index"], "b": leaders[second]["index"], "level": level})
	return battle.set_bonds(bonds, data.get_bond_rules())


## Adds a finished (or left) battle's tallies to the roster's bonds; returns
## a row per pair that gained points: {a, b, points, gained, level_before,
## level}, level-ups first.
static func apply_tallies(roster: TacticsRoster, data: TacticsWorldData, report: Dictionary) -> Array[Dictionary]:
	var ids := {}
	for entry: Dictionary in report["units"]:
		if entry["role"] == &"leader" and entry["start_side"] == 0:
			ids[int(entry["unit"])] = StringName(entry["id"])
	var rows: Array[Dictionary] = []
	for tally: Dictionary in report.get("bond_tallies", []):
		var gained := mini(int(tally["phases"]), data.bond_points_per_battle)
		if gained <= 0 or not ids.has(int(tally["a"])) or not ids.has(int(tally["b"])):
			continue
		var bond := _get_or_add(roster, ids[int(tally["a"])], ids[int(tally["b"])])
		var before := level_of(int(bond["points"]), data)
		bond["points"] = int(bond["points"]) + gained
		rows.append({"a": bond["a"], "b": bond["b"], "points": bond["points"], "gained": gained, "level_before": before, "level": level_of(int(bond["points"]), data)})
	rows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return (left["level"] > left["level_before"]) and not (right["level"] > right["level_before"]))
	return rows


# Our leaders of a loaded battle: [{index, id}] in unit order.
static func _our_leaders(units: Array) -> Array[Dictionary]:
	var leaders: Array[Dictionary] = []
	for state: Dictionary in units:
		if state["role"] == &"leader" and state["start_side"] == 0:
			leaders.append({"index": state["index"], "id": StringName(state["id"])})
	return leaders


static func _get_or_add(roster: TacticsRoster, a: StringName, b: StringName) -> Dictionary:
	var bond := find_bond(roster, a, b)
	if bond.is_empty():
		var pair := _pair(a, b)
		bond = {"a": pair[0], "b": pair[1], "points": 0}
		roster.bonds.append(bond)
	return bond


static func _pair(a: StringName, b: StringName) -> Array[StringName]:
	var pair: Array[StringName] = [a, b]
	if String(b) < String(a):
		pair.reverse()
	return pair
