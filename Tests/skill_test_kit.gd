extends RefCounted
## Shared set-up for the skill tests (skill_test.gd, passive_test.gd): the
## catalog, battles that are freed at the end, rules that make casts quick,
## test classes and event filters. Positions in comments are global
## (col, row); add() takes local col, rank.

const CATALOG_PATH: String = "res://Data/catalog.tres"
const MAX_TICKS: int = 5000
const SHIELD: StringName = &"unit.shield_guard"
const SWORD: StringName = &"unit.blade_wanderer"
const SPEAR: StringName = &"unit.wolf_spear"
const CAVALRY: StringName = &"unit.wolf_rider"
const ARCHER: StringName = &"unit.archer"
const MAGE: StringName = &"unit.fire_adept"

var catalog: Catalog
var _battles: Array[Battle] = []
# "<battle id>:<class id>" of the test classes already registered.
var _test_classes: Dictionary[String, bool] = {}


func load_catalog() -> bool:
	catalog = load(CATALOG_PATH) as Catalog
	if catalog == null:
		push_error("Catalog did not load from %s" % CATALOG_PATH)
		return false
	var problems := catalog.validate()
	if not problems.is_empty():
		push_error("Catalog is invalid: %s" % ", ".join(problems))
		return false
	return true


func free_battles() -> void:
	for battle: Battle in _battles:
		battle.free()
	_battles.clear()


func new_battle(rules: BattleRulesData = null) -> Battle:
	var battle := Battle.new()
	_battles.append(battle)
	battle.set_rules(rules if rules != null else catalog.battle_rules)
	for class_data: ClassData in catalog.classes:
		battle.register_class(class_data)
	return battle


func add(battle: Battle, side: int, unit_id: StringName, col: int, rank: int, star: int = 1) -> int:
	var index := battle.add_unit(side, catalog.get_unit(unit_id), star, col, rank)
	assert(index >= 0, "Skill test: could not add %s at col %d rank %d" % [unit_id, col, rank])
	return index


## Rules where one basic attack fills the Khí and taking hits gives none, so
## a unit casts right after its first attack. `holding` keeps shields
## holding the line for the whole battle.
func quick_rules(holding: bool = false) -> BattleRulesData:
	var rules := catalog.battle_rules.duplicate() as BattleRulesData
	rules.qi_per_attack = 1000
	rules.qi_per_hit_taken = 0
	if holding:
		rules.hold_line_grace_ticks = 1000
		rules.hold_line_max_ticks = 1000
	return rules


## Registers a copy of a class under `class.test_<name>` with `changes`
## applied (once per battle and name), and adds a unit of it.
func add_test_unit(battle: Battle, side: int, base_unit: StringName, name: String, changes: Dictionary, col: int, rank: int, star: int = 1) -> int:
	var unit := catalog.get_unit(base_unit).duplicate() as UnitData
	var class_data := catalog.get_class_data(unit.class_id).duplicate() as ClassData
	class_data.id = StringName("class.test_" + name)
	for key: String in changes:
		class_data.set(key, changes[key])
	var key := "%d:%s" % [battle.get_instance_id(), class_data.id]
	if not _test_classes.has(key):
		battle.register_class(class_data)
		_test_classes[key] = true
	unit.id = StringName("unit.test_" + name)
	unit.class_id = class_data.id
	var index := battle.add_unit(side, unit, star, col, rank)
	assert(index >= 0, "Skill test: could not add test unit %s" % name)
	return index


## Steps `ticks` ticks (starting the battle if needed) and returns the events.
func run_ticks(battle: Battle, ticks: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not battle.is_started():
		battle.start()
	for step: int in ticks:
		if battle.is_finished():
			break
		for event: Dictionary in battle.step():
			events.append(event)
	return events


## Steps until an event matches `predicate`; returns every event of the
## ticks up to and including that one, with the match moved last, so
## `events.back()` is the match and its consequences are in `events`.
func run_until(battle: Battle, predicate: Callable) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not battle.is_started():
		battle.start()
	while not battle.is_finished() and battle.get_tick() < MAX_TICKS:
		var found: Dictionary = {}
		for event: Dictionary in battle.step():
			if found.is_empty() and predicate.call(event):
				found = event
			else:
				events.append(event)
		if not found.is_empty():
			events.append(found)
			return events
	return events


static func of_type(events: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == type)


static func caused_by(events: Array[Dictionary], cause_id: int, type: StringName = &"damage_dealt") -> Array[Dictionary]:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == type and event["cause"] == cause_id)


static func is_resolve_of(unit: int) -> Callable:
	return func(event: Dictionary) -> bool: return event["type"] == &"skill_resolved" and event["unit"] == unit


static func field(events: Array[Dictionary], key: String) -> Array:
	return events.map(func(event: Dictionary) -> Variant: return event[key])


## Logs and returns false when `actual` differs from `expected`.
static func expect(what: String, actual: Variant, expected: Variant) -> bool:
	if actual == expected:
		return true
	push_error("%s: got %s, expected %s" % [what, actual, expected])
	return false
