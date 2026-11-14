class_name SandboxData
extends Resource
## Content of the sandbox screen: the enemy line-ups that "Đổi địch" cycles
## through, in order. Lives in Data/Sandbox/sandbox.tres.

@export var enemy_presets: Array[LineupPreset] = []


## Problems in the data against the catalog, one message per problem.
func validate(catalog: Catalog) -> PackedStringArray:
	var problems := PackedStringArray()
	if enemy_presets.is_empty():
		problems.append("Sandbox: %s has no enemy presets" % resource_path)
	for preset: LineupPreset in enemy_presets:
		if preset == null:
			problems.append("Sandbox: %s has an empty preset" % resource_path)
			continue
		var seen: Dictionary[Vector2i, bool] = {}
		for slot: LineupSlot in preset.slots:
			if slot == null or catalog.get_unit(slot.unit_id) == null:
				problems.append("Sandbox: %s has an unknown unit %s" % [preset.id, slot.unit_id if slot != null else &"<empty>"])
				continue
			if seen.has(slot.get_cell()):
				problems.append("Sandbox: %s places two units at %s" % [preset.id, slot.get_cell()])
			seen[slot.get_cell()] = true
	return problems
