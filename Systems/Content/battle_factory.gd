class_name BattleFactory
extends RefCounted
## Builds Battle nodes from the catalog and line-ups, so every screen, test
## and tool sets a battle up the same way.
## [codeblock]
## var battle := BattleFactory.create(catalog)
## add_child(battle)
## var indexes := BattleFactory.add_slots(battle, catalog, Battle.SIDE_A, slots)
## [/codeblock]


## A new Battle with the catalog's rules, classes and synergies (class and
## race milestones, formations, Hợp Lực); the caller owns it.
static func create(catalog: Catalog) -> Battle:
	var battle := Battle.new()
	battle.name = &"Battle"
	battle.set_rules(catalog.battle_rules)
	battle.set_synergy(catalog.get_synergy())
	for class_data: ClassData in catalog.classes:
		battle.register_class(class_data)
	return battle


## Adds every slot to `side`; returns the battle index per slot (-1 when
## the battle refused one, with its own error).
static func add_slots(battle: Battle, catalog: Catalog, side: int, slots: Array[LineupSlot]) -> Array[int]:
	var indexes: Array[int] = []
	for slot: LineupSlot in slots:
		indexes.append(battle.add_unit(side, catalog.get_unit(slot.unit_id), slot.star, slot.local_col, slot.local_rank))
	return indexes


## Living units of `side` at the end of a battle.
static func count_alive(battle: Battle, side: int) -> int:
	var alive := 0
	for state: Dictionary in battle.get_units():
		if state["side"] == side and state["alive"]:
			alive += 1
	return alive
