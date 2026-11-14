class_name Catalog
extends Resource
## Every class, unit and stage of the game and the battle and run rules,
## listed explicitly so nothing scans directories at runtime (that breaks in
## exported and web builds).
## [codeblock]
## var catalog := load("res://Data/catalog.tres") as Catalog
## assert(catalog.validate().is_empty())
## var archer := catalog.get_unit(&"unit.archer")
## [/codeblock]

const MIN_COST: int = 1
const MAX_COST: int = 5

## One entry per Data/Classes/ file.
@export var classes: Array[ClassData] = []
## One entry per Data/Units/ file.
@export var units: Array[UnitData] = []
@export var battle_rules: BattleRulesData
@export var run_rules: RunRules
## One entry per Data/Stages/ file, in stage order (stage 1 first).
@export var stages: Array[StageData] = []


## The unit with this id, or null.
func get_unit(id: StringName) -> UnitData:
	for unit: UnitData in units:
		if unit != null and unit.id == id:
			return unit
	return null


## The class with this id, or null.
func get_class_data(id: StringName) -> ClassData:
	for class_data: ClassData in classes:
		if class_data != null and class_data.id == id:
			return class_data
	return null


## Problems in the data, one message per problem; empty when the data is
## valid. Handler ids are checked by Battle.register_class().
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if battle_rules == null:
		problems.append("Catalog: battle_rules is not set in %s" % resource_path)
	problems.append_array(_validate_classes())
	problems.append_array(_validate_units())
	problems.append_array(_validate_run())
	return problems


func _validate_classes() -> PackedStringArray:
	var problems := PackedStringArray()
	var seen: Dictionary[StringName, bool] = {}
	for index: int in classes.size():
		var class_data: ClassData = classes[index]
		if class_data == null:
			problems.append("Catalog: classes[%d] is empty" % index)
			continue
		if not String(class_data.id).begins_with("class."):
			problems.append("Catalog: %s has id '%s', expected class.<name>" % [class_data.resource_path, class_data.id])
		if seen.has(class_data.id):
			problems.append("Catalog: duplicate class id %s in %s" % [class_data.id, class_data.resource_path])
		seen[class_data.id] = true
	return problems


func _validate_units() -> PackedStringArray:
	var problems := PackedStringArray()
	var seen: Dictionary[StringName, bool] = {}
	for index: int in units.size():
		var unit: UnitData = units[index]
		if unit == null:
			problems.append("Catalog: units[%d] is empty" % index)
			continue
		var where: String = unit.resource_path
		if not String(unit.id).begins_with("unit."):
			problems.append("Catalog: %s has id '%s', expected unit.<name>" % [where, unit.id])
		if seen.has(unit.id):
			problems.append("Catalog: duplicate unit id %s in %s" % [unit.id, where])
		seen[unit.id] = true
		if get_class_data(unit.class_id) == null:
			problems.append("Catalog: %s has unknown class_id %s" % [where, unit.class_id])
		if unit.cost < MIN_COST or unit.cost > MAX_COST:
			problems.append("Catalog: %s has cost %d, expected %d..%d" % [where, unit.cost, MIN_COST, MAX_COST])
	return problems


func _validate_run() -> PackedStringArray:
	var problems := PackedStringArray()
	if run_rules == null:
		problems.append("Catalog: run_rules is not set in %s" % resource_path)
		return problems
	problems.append_array(run_rules.validate())
	if stages.size() != run_rules.stage_count:
		problems.append("Catalog: %d stages listed, expected %d" % [stages.size(), run_rules.stage_count])
	var seen: Dictionary[StringName, bool] = {}
	for index: int in stages.size():
		var stage: StageData = stages[index]
		if stage == null:
			problems.append("Catalog: stages[%d] is empty" % index)
			continue
		if not String(stage.id).begins_with("stage.") or seen.has(stage.id):
			problems.append("Catalog: %s has a bad or duplicate id '%s'" % [stage.resource_path, stage.id])
		seen[stage.id] = true
		problems.append_array(stage.validate(self, run_rules.get_enemy_count(index + 1)))
	return problems
