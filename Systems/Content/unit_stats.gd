class_name UnitStats
extends RefCounted
## The stats shown to the player for a unit, as a Dictionary. Hp and attack
## come from the Battle bridge (it owns the cost and star scaling), never from
## a copy of the formula; the rest comes from the unit's ClassData.
## Keys: hp, max_hp, attack, attacks_per_second, range_cells, armor,
## magic_resist, class_name_key.


## Stats of a fresh unit at `star`, derived by a throwaway Battle.
static func derive(catalog: Catalog, unit: UnitData, star: int) -> Dictionary:
	var class_data := catalog.get_class_data(unit.class_id)
	var battle := Battle.new()
	battle.set_rules(catalog.battle_rules)
	battle.register_class(class_data)
	var index := battle.add_unit(Battle.SIDE_A, unit, star, 1, 1)
	var state: Dictionary = battle.get_unit_state(index) if index >= 0 else {}
	battle.free()
	if state.is_empty():
		push_error("UnitStats: could not derive stats for %s" % unit.id)
		return {}
	return from_state(catalog, state)


## Stats of a unit in a running battle, from Battle.get_unit_state().
static func from_state(catalog: Catalog, state: Dictionary) -> Dictionary:
	var class_data := catalog.get_class_data(state["class_id"])
	return {
		"hp": state["hp"],
		"max_hp": state["max_hp"],
		"attack": state["attack"],
		"attacks_per_second": class_data.attacks_per_100s / 100.0,
		"range_cells": class_data.range_cells,
		"armor": class_data.armor,
		"magic_resist": class_data.magic_resist,
		"class_name_key": class_data.name_key,
	}
