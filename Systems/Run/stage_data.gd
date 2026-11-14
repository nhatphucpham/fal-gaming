class_name StageData
extends Resource
## One stage of a run: its name and the enemy line-up (side B, local
## coordinates as in LineupSlot). Files are Data/Stages/stage_01.tres ..
## stage_12.tres, listed in Data/catalog.tres in stage order.

## Stable id, `stage.<two digits>`.
@export var id: StringName = &""
## Translation key of the stage name shown in the top bar.
@export var name_key: String = ""
@export var slots: Array[LineupSlot] = []


## The boss unit of this line-up, or null.
func get_boss_slot(catalog: Catalog) -> LineupSlot:
	for slot: LineupSlot in slots:
		var unit := catalog.get_unit(slot.unit_id) if slot != null else null
		if unit != null and unit.is_boss:
			return slot
	return null


## Problems against the catalog: an empty name_key, unknown units, cells
## off the half or doubled, a unit count other than `expected_units`, and
## a boss count other than `expected_bosses`.
func validate(catalog: Catalog, expected_units: int, expected_bosses: int = 0) -> PackedStringArray:
	var problems := PackedStringArray()
	var where := "%s (%s)" % [id, resource_path]
	if name_key.is_empty():
		problems.append("Run: stage %s has no name_key" % where)
	if slots.size() != expected_units:
		problems.append("Run: stage %s has %d units, expected %d" % [where, slots.size(), expected_units])
	var seen: Dictionary[Vector2i, bool] = {}
	var bosses := 0
	for slot: LineupSlot in slots:
		if slot == null or catalog.get_unit(slot.unit_id) == null:
			problems.append("Run: stage %s has an unknown unit %s" % [where, slot.unit_id if slot != null else &"<empty>"])
			continue
		if not Lineup.is_valid_cell(slot.get_cell()):
			problems.append("Run: stage %s places %s off the board at %s" % [where, slot.unit_id, slot.get_cell()])
		if seen.has(slot.get_cell()):
			problems.append("Run: stage %s places two units at %s" % [where, slot.get_cell()])
		seen[slot.get_cell()] = true
		if slot.star < 1 or slot.star > 3:
			problems.append("Run: stage %s has %s at star %d" % [where, slot.unit_id, slot.star])
		bosses += 1 if catalog.get_unit(slot.unit_id).is_boss else 0
	if bosses != expected_bosses:
		problems.append("Run: stage %s has %d bosses, expected %d" % [where, bosses, expected_bosses])
	return problems
