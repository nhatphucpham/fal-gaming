class_name Shop
extends RefCounted
## The run's shop: a row of offers (unit ids, empty after a purchase) rolled
## from the catalog by the level's cost odds. Randomness comes only from the
## RandomNumberGenerator passed in, which RunState owns, so a seeded run
## always offers the same units. No shared pool: every roll is independent.
## [codeblock]
## var shop := Shop.new(catalog, rules)
## shop.roll(level, rng)
## var unit_id := shop.get_offer(0)
## [/codeblock]

var _rules: RunRules
var _offers: Array[StringName] = []
## Unit ids by cost 1..5, in catalog order.
var _pools: Dictionary[int, Array] = {}


func _init(catalog: Catalog, rules: RunRules) -> void:
	_rules = rules
	for cost: int in range(Catalog.MIN_COST, Catalog.MAX_COST + 1):
		_pools[cost] = []
	for unit: UnitData in catalog.units:
		if unit != null and _pools.has(unit.cost):
			_pools[unit.cost].append(unit.id)
	_offers.resize(rules.shop_slots)
	_offers.fill(&"")


## Replaces every offer with a fresh roll at `level` (1 slot = 1 cost roll,
## then a uniform unit of that cost).
func roll(level: int, rng: RandomNumberGenerator) -> void:
	var odds := _rules.get_shop_odds(level)
	for index: int in _offers.size():
		_offers[index] = _roll_unit(odds, rng)


## The unit offered in `slot`, or an empty id when bought or out of range.
func get_offer(slot: int) -> StringName:
	if slot < 0 or slot >= _offers.size():
		return &""
	return _offers[slot]


## A copy of all offers, in slot order.
func get_offers() -> Array[StringName]:
	return _offers.duplicate()


func take(slot: int) -> void:
	_offers[slot] = &""


## Restores offers from a save; unknown slots stay empty.
func set_offers(offers: Array[StringName]) -> void:
	for index: int in _offers.size():
		_offers[index] = offers[index] if index < offers.size() else &""


func _roll_unit(odds: PackedInt32Array, rng: RandomNumberGenerator) -> StringName:
	var roll_value := rng.randi_range(1, 100)
	var cost := Catalog.MIN_COST
	var running := 0
	for index: int in odds.size():
		running += odds[index]
		if roll_value <= running:
			cost = index + 1
			break
	# A cost with no unit in the catalog falls back to the nearest cheaper one.
	while cost > Catalog.MIN_COST and _pools[cost].is_empty():
		cost -= 1
	var pool: Array = _pools[cost]
	if pool.is_empty():
		return &""
	return pool[rng.randi_range(0, pool.size() - 1)]
