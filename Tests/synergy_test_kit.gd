extends "res://Tests/skill_test_kit.gd"
## Shared set-up for the synergy tests (formation_test.gd, synergy_test.gd,
## formation_battle_test.gd): battles with the catalog's synergies, line-ups
## written as [unit name, local col, rank] rows, the damage formula of
## Docs/systems/battle.md, and event finders.


## A battle with the catalog's rules, classes and synergies; side A and B
## line-ups as [name, col, rank] rows (name without `unit.`).
func synergy_battle(side_a: Array, side_b: Array, rules: BattleRulesData = null) -> Battle:
	var battle := new_battle(rules)
	battle.set_synergy(catalog.get_synergy())
	for row: Array in side_a:
		add(battle, Battle.SIDE_A, StringName("unit." + row[0]), row[1], row[2])
	for row: Array in side_b:
		add(battle, Battle.SIDE_B, StringName("unit." + row[0]), row[1], row[2])
	return battle


## Pieces for Synergy.evaluate() from [name, col, rank] rows.
func pieces(rows: Array) -> Array:
	var list: Array = []
	for row: Array in rows:
		list.append({"unit": catalog.get_unit(StringName("unit." + row[0])), "col": row[1], "rank": row[2]})
	return list


## A piece of a bare class and race, for pattern tests without race rules.
static func bare(class_name_: String, col: int, rank: int, unit_name: String = "", race: String = "") -> Dictionary:
	var id := unit_name if unit_name != "" else "%s_%d_%d" % [class_name_, col, rank]
	return {"unit_id": "unit." + id, "class_id": "class." + class_name_, "race_id": race, "cost": 1, "col": col, "rank": rank}


## Damage of one hit, as compute_damage() does it: all products, one division.
static func damage(attack: int, mitigation: int, increase: int = 0, decrease: int = 0, coefficient: int = 100, is_crit: bool = false, is_counter: bool = false) -> int:
	var numerator: int = attack * coefficient * (130 if is_counter else 100) * (150 if is_crit else 100)
	numerator *= (100 + mini(increase, 200)) * (100 - mini(decrease, 100))
	return maxi(1, numerator / (100 * 100 * 100 * 100 * (100 + mitigation)))


## A formation value at a level (+40% per level above 1).
static func at_level(value: int, level: int) -> int:
	return value * (100 + 40 * (level - 1)) / 100


static func first(events: Array[Dictionary], predicate: Callable) -> Dictionary:
	for event: Dictionary in events:
		if predicate.call(event):
			return event
	return {}


static func damage_to(events: Array[Dictionary], source: int, target: int) -> Array[Dictionary]:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == &"damage_dealt" and event["source"] == source and event["target"] == target)


static func activated(events: Array[Dictionary], side: int, source_id: StringName) -> Dictionary:
	return first(events, func(event: Dictionary) -> bool: return event["type"] == &"synergy_activated" and event["side"] == side and event["source_id"] == source_id)


static func triggered(events: Array[Dictionary], modifier: StringName) -> Array[Dictionary]:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == &"modifier_triggered" and event["modifier"] == modifier)


## Ids of a result's entries (formations, near-misses).
static func ids(entries: Array) -> Array:
	return entries.map(func(entry: Dictionary) -> StringName: return entry["id"])


## The milestone entry with this id from an evaluate() result.
static func milestone(result: Dictionary, id: StringName) -> Dictionary:
	for entry: Dictionary in result["class_milestones"] + result["race_milestones"]:
		if entry["id"] == id:
			return entry
	return {}
