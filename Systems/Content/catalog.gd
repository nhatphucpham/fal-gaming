class_name Catalog
extends Resource
## Every class, skill, passive, unit, formation, milestone and stage of the
## game and the battle, run and Hợp Lực rules,
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
## One entry per Data/Skills/ file.
@export var skills: Array[SkillData] = []
## One entry per Data/Passives/ file.
@export var passives: Array[PassiveData] = []
## One entry per Data/Units/ file.
@export var units: Array[UnitData] = []
@export var battle_rules: BattleRulesData
@export var run_rules: RunRules
## One entry per Data/Stages/ file, in stage order (stage 1 first).
@export var stages: Array[StageData] = []
## One entry per Data/Formations/ file; formations match in this order.
@export var formations: Array[FormationData] = []
## One entry per Data/Synergies/ file (class and race milestones).
@export var milestones: Array[MilestoneData] = []
@export var hop_luc: HopLucData
## One entry per Data/Epiphanies/ file (a family's Kỳ Ngộ list).
@export var epiphanies: Array[EpiphanyFamily] = []
## One entry per Data/Encounters/ file (road encounters).
@export var encounters: Array[EncounterData] = []
## The sound ids and their files (Data/Audio/sounds.tres).
@export var sounds: SoundBank

var _synergy: Synergy


## The Synergy built from the formations, milestones and Hợp Lực rules
## (made once, shared by every battle and the prep screen); null with an
## error when the data is bad.
func get_synergy() -> Synergy:
	if _synergy == null:
		var synergy := Synergy.new()
		var problems := synergy.setup(formations, milestones, hop_luc)
		if not problems.is_empty():
			push_error("Catalog: %s" % ", ".join(problems))
			return null
		_synergy = synergy
	return _synergy


## The formation with this id, or null.
func get_formation(id: StringName) -> FormationData:
	for formation: FormationData in formations:
		if formation != null and formation.id == id:
			return formation
	return null


## The milestone with this id, or null.
func get_milestone(id: StringName) -> MilestoneData:
	for milestone: MilestoneData in milestones:
		if milestone != null and milestone.id == id:
			return milestone
	return null


## The Kỳ Ngộ list of a milestone family, or null.
func get_epiphany_family(family: StringName) -> EpiphanyFamily:
	for entry: EpiphanyFamily in epiphanies:
		if entry != null and entry.family == family:
			return entry
	return null


## The Kỳ Ngộ mutation with this id, or null.
## The road encounter with this id, or null.
func get_encounter(id: StringName) -> EncounterData:
	for entry: EncounterData in encounters:
		if entry != null and entry.id == id:
			return entry
	return null


func get_epiphany(id: StringName) -> EpiphanyData:
	for entry: EpiphanyFamily in epiphanies:
		if entry == null:
			continue
		for epiphany: EpiphanyData in entry.epiphanies:
			if epiphany != null and epiphany.id == id:
				return epiphany
	return null


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


## The skill with this id, or null.
func get_skill(id: StringName) -> SkillData:
	for skill: SkillData in skills:
		if skill != null and skill.id == id:
			return skill
	return null


## The passive with this id, or null.
func get_passive(id: StringName) -> PassiveData:
	for passive: PassiveData in passives:
		if passive != null and passive.id == id:
			return passive
	return null


## The skill a unit uses: its override, else its class's; null if none.
func get_unit_skill(unit: UnitData) -> SkillData:
	if unit.skill_override != null:
		return unit.skill_override
	var class_data := get_class_data(unit.class_id)
	return class_data.skill if class_data != null else null


## The passive a unit uses: its override, else its class's; null if none.
func get_unit_passive(unit: UnitData) -> PassiveData:
	if unit.passive_override != null:
		return unit.passive_override
	var class_data := get_class_data(unit.class_id)
	return class_data.passive if class_data != null else null


## Problems in the data, one message per problem; empty when the data is
## valid. Handler ids are checked by Battle.register_class().
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if battle_rules == null:
		problems.append("Catalog: battle_rules is not set in %s" % resource_path)
	problems.append_array(_validate_skills())
	problems.append_array(_validate_classes())
	problems.append_array(_validate_units())
	problems.append_array(_validate_run())
	problems.append_array(_validate_synergy())
	problems.append_array(_validate_epiphanies())
	problems.append_array(_validate_encounters())
	if sounds == null:
		problems.append("Catalog: sounds is not set in %s" % resource_path)
	else:
		problems.append_array(sounds.validate())
	return problems


# Each encounter's own checks, doubled ids, and enough of them that no
# encounter stage repeats one.
func _validate_encounters() -> PackedStringArray:
	var problems := PackedStringArray()
	var ids: Dictionary[StringName, bool] = {}
	for entry: EncounterData in encounters:
		if entry == null or ids.has(entry.id):
			problems.append("Catalog: an encounters entry is empty or doubled")
			continue
		ids[entry.id] = true
		problems.append_array(entry.validate(self))
	if run_rules != null and encounters.size() < run_rules.encounter_stages.size():
		problems.append("Catalog: %d encounters for %d encounter stages" % [encounters.size(), run_rules.encounter_stages.size()])
	return problems


# Each family's own checks, doubled ids, then each mutation through the
# native synergy rules (a Biến Dị's modifiers must be legal on a milestone).
func _validate_epiphanies() -> PackedStringArray:
	var problems := PackedStringArray()
	var families: Dictionary[StringName, bool] = {}
	var ids: Dictionary[StringName, bool] = {}
	var synergy := _make_checked_synergy()
	for entry: EpiphanyFamily in epiphanies:
		if entry == null or families.has(entry.family):
			problems.append("Catalog: an epiphanies entry is empty or doubled")
			continue
		families[entry.family] = true
		var family_problems := entry.validate(self)
		problems.append_array(family_problems)
		for epiphany: EpiphanyData in entry.epiphanies:
			if epiphany == null:
				continue
			if ids.has(epiphany.id):
				problems.append("Catalog: epiphany id %s is used twice" % epiphany.id)
			ids[epiphany.id] = true
			# to_override() trusts the tier, so only clean families reach it.
			if synergy != null and family_problems.is_empty():
				var override := epiphany.to_override(get_milestone(epiphany.family))
				if synergy.evaluate([], [override]).is_empty():
					problems.append("Catalog: epiphany %s in %s is refused by the synergy rules (see the Synergy error above)" % [epiphany.id, entry.resource_path])
	return problems


# A fresh Synergy set up from this data, or null when the data is bad
# (_validate_synergy() reports why). Not cached: validate() must see edits.
func _make_checked_synergy() -> Synergy:
	if hop_luc == null:
		return null
	var synergy := Synergy.new()
	if not synergy.setup(formations, milestones, hop_luc).is_empty():
		return null
	return synergy


# Ids, text keys, the class and race ids they name, then the native checks
# (handler ids, scopes, ranges) through Synergy.setup().
func _validate_synergy() -> PackedStringArray:
	var problems := PackedStringArray()
	var races: Dictionary[StringName, bool] = {}
	for unit: UnitData in units:
		if unit != null:
			races[unit.race_id] = true
	var seen: Dictionary[StringName, bool] = {}
	for formation: FormationData in formations:
		if formation == null:
			problems.append("Catalog: a formations entry is empty")
			continue
		if not String(formation.id).begins_with("formation.") or seen.has(formation.id):
			problems.append("Catalog: %s has a bad or duplicate id '%s'" % [formation.resource_path, formation.id])
		seen[formation.id] = true
		if formation.name_key.is_empty() or formation.description_key.is_empty():
			problems.append("Catalog: %s needs name_key and description_key" % formation.resource_path)
		for class_id: String in formation.slot_classes:
			if not class_id.is_empty() and get_class_data(StringName(class_id)) == null:
				problems.append("Catalog: %s needs unknown class %s" % [formation.resource_path, class_id])
	for milestone: MilestoneData in milestones:
		if milestone == null:
			problems.append("Catalog: a milestones entry is empty")
			continue
		if not String(milestone.id).begins_with("milestone.") or seen.has(milestone.id) or milestone.name_key.is_empty():
			problems.append("Catalog: %s has a bad or duplicate id '%s' or no name_key" % [milestone.resource_path, milestone.id])
		seen[milestone.id] = true
		var is_known := races.has(milestone.counted_id) if milestone.counted_kind == &"race" else get_class_data(milestone.counted_id) != null
		if not is_known:
			problems.append("Catalog: %s counts unknown %s" % [milestone.resource_path, milestone.counted_id])
	if hop_luc == null:
		problems.append("Catalog: hop_luc is not set in %s" % resource_path)
		return problems
	if problems.is_empty():
		problems.append_array(Synergy.new().setup(formations, milestones, hop_luc))
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
		problems.append_array(_validate_loadout(class_data.resource_path, class_data.skill, class_data.passive))
	return problems


# Skills and passives: well-formed, unique ids and the text keys the info
# panel shows.
func _validate_skills() -> PackedStringArray:
	var problems := PackedStringArray()
	var entries: Array[Resource] = []
	entries.append_array(skills)
	entries.append_array(passives)
	var seen: Dictionary[StringName, bool] = {}
	for index: int in entries.size():
		var entry: Resource = entries[index]
		if entry == null:
			problems.append("Catalog: skills/passives entry %d is empty" % index)
			continue
		var prefix := "skill." if entry is SkillData else "passive."
		var id: StringName = entry.get(&"id")
		if not String(id).begins_with(prefix) or seen.has(id):
			problems.append("Catalog: %s has a bad or duplicate id '%s', expected %s<name>" % [entry.resource_path, id, prefix])
		seen[id] = true
		if String(entry.get(&"name_key")).is_empty() or String(entry.get(&"description_key")).is_empty():
			problems.append("Catalog: %s needs name_key and description_key" % entry.resource_path)
	return problems


# A class or unit may only use skills and passives listed in the catalog.
func _validate_loadout(where: String, skill: SkillData, passive: PassiveData) -> PackedStringArray:
	var problems := PackedStringArray()
	if skill != null and get_skill(skill.id) != skill:
		problems.append("Catalog: %s uses skill %s, which is not listed in skills" % [where, skill.id])
	if passive != null and get_passive(passive.id) != passive:
		problems.append("Catalog: %s uses passive %s, which is not listed in passives" % [where, passive.id])
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
		problems.append_array(_validate_loadout(where, unit.skill_override, unit.passive_override))
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
		problems.append_array(stage.validate(self, run_rules.get_enemy_count(index + 1), 1 if index + 1 == run_rules.boss_stage else 0))
	return problems
