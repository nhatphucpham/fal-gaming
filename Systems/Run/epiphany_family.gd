class_name EpiphanyFamily
extends Resource
## The Kỳ Ngộ list of one milestone family (one file per family in
## Data/Epiphanies/): what its speaker says in the cutscene and the
## mutations two of which are drawn when it fires. Listed in
## Data/catalog.tres (`epiphanies`). See Docs/systems/epiphany.md.

## The milestone id (`milestone.class_shield`).
@export var family: StringName = &""
## The speaker's 2-3 lines in the cutscene, in order.
@export var line_keys: Array[String] = []
@export var epiphanies: Array[EpiphanyData] = []


## Problems: no lines, fewer than two mutations, doubled ids, and each
## mutation's own problems.
func validate(catalog: Catalog) -> PackedStringArray:
	var problems := PackedStringArray()
	var milestone := catalog.get_milestone(family)
	if milestone == null:
		problems.append("Run: %s names unknown family %s" % [resource_path, family])
		return problems
	if line_keys.is_empty() or epiphanies.size() < 2:
		problems.append("Run: %s needs lines and at least 2 epiphanies" % resource_path)
	var seen: Dictionary[StringName, bool] = {}
	for epiphany: EpiphanyData in epiphanies:
		if epiphany == null or seen.has(epiphany.id):
			problems.append("Run: %s has an empty or doubled epiphany" % resource_path)
			continue
		seen[epiphany.id] = true
		problems.append_array(epiphany.validate(milestone))
	return problems
