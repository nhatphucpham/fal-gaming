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


## Problems against the catalog: unknown units, cells off the half or
## doubled, and a unit count other than `expected_units`.
func validate(catalog: Catalog, expected_units: int) -> PackedStringArray:
	var problems := PackedStringArray()
	var where := "%s (%s)" % [id, resource_path]
	if slots.size() != expected_units:
		problems.append("Run: stage %s has %d units, expected %d" % [where, slots.size(), expected_units])
	var seen: Dictionary[Vector2i, bool] = {}
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
	return problems
