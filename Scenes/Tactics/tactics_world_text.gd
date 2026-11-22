class_name TacticsWorldText
extends RefCounted
## Player-facing lines of the world map, shared by the world screen, the
## region card, the Auto result and the after-battle summary: the enemy's
## declared push and what ignoring it costs, a region's pressure, and what
## a finished region changed. All text comes from Locale/strings.csv.
## [codeblock]
## for line: String in TacticsWorldText.threat_lines(roster.world): ...
## [/codeblock]


static func region_name(world: TacticsWorld, id: StringName) -> String:
	var region := world.data.get_region(id)
	return TranslationServer.translate(region.name_key) if region != null else String(id)


## Two lines: where the enemy strikes next, and what ignoring it costs.
static func threat_lines(world: TacticsWorld) -> PackedStringArray:
	var id := world.get_threat()
	if id == &"":
		return PackedStringArray([TranslationServer.translate("WORLD_THREAT_NONE")])
	var name := region_name(world, id)
	if world.get_threat_kind() == TacticsWorld.THREAT_TAKE:
		var market := TranslationServer.translate(world.data.get_region(id).market_name_key)
		return PackedStringArray([
			TranslationServer.translate("WORLD_THREAT_TAKE_FORMAT") % name,
			TranslationServer.translate("WORLD_THREAT_TAKE_IF_FORMAT") % [name, market],
		])
	var level := world.get_pressure(id)
	var cost: String = TranslationServer.translate("WORLD_THREAT_HARDEN_MAX") if level >= world.data.max_pressure \
			else TranslationServer.translate("WORLD_THREAT_HARDEN_IF_FORMAT") % [world.data.pressure_step_pct, level + 1, world.data.max_pressure]
	return PackedStringArray([TranslationServer.translate("WORLD_THREAT_HARDEN_FORMAT") % name, cost])


## The enemy's pressure on a region: its level and what it adds.
static func pressure_line(world: TacticsWorld, id: StringName) -> String:
	var level := world.get_pressure(id)
	if level == 0:
		return TranslationServer.translate("REGION_NO_PRESSURE") % world.data.max_pressure
	return TranslationServer.translate("REGION_PRESSURE_FORMAT") % [level, world.data.max_pressure, world.get_enemy_power_pct(id) - 100]


## What a finished region changed (TacticsWorld.finish_region()), then the
## enemy's next push.
static func change_lines(world: TacticsWorld, change: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	if change.is_empty():
		return lines
	var name := region_name(world, change["region"])
	if change["taken"]:
		lines.append(TranslationServer.translate("CHANGE_TAKEN_FORMAT") % name)
	elif change["won"]:
		lines.append(TranslationServer.translate("CHANGE_KEPT_FORMAT") % name)
	elif not (change["lost"] as Array).has(change["region"]):
		lines.append(TranslationServer.translate("CHANGE_NOT_TAKEN_FORMAT") % name)
	for id: StringName in change["lost"]:
		lines.append(TranslationServer.translate("CHANGE_LOST_FORMAT") % region_name(world, id))
	if change["hardened"] != &"":
		lines.append(TranslationServer.translate("CHANGE_HARDENED_FORMAT") % [region_name(world, change["hardened"]), change["pressure"], world.data.max_pressure])
	if change.get("threat", &"") != &"":
		lines.append(TranslationServer.translate("CHANGE_NEXT_THREAT_FORMAT") % region_name(world, change["threat"]))
	return lines
