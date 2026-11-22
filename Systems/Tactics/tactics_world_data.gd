class_name TacticsWorldData
extends Resource
## The Chiến Dịch world (Data/Tactics/World/world.tres): its regions, the
## items its markets sell, and the numbers of the world's rules (enemy
## pressure, wounds, bonds). Checked once by validate(). See
## Docs/systems/tactics_world.md.
## [codeblock]
## var data := load(TacticsWorldData.PATH) as TacticsWorldData
## for problem: String in data.validate(): push_error(problem)
## [/codeblock]

const PATH: String = "res://Data/Tactics/World/world.tres"

@export var regions: Array[TacticsRegionData] = []
@export var items: Array[TacticsItemData] = []
@export var home_region: StringName = &"region.home"
## Enemy hp and attack, in % added per level of pressure on a region.
@export_range(0, 100) var pressure_step_pct: int = 15
@export_range(1, 5) var max_pressure: int = 3
## Each new campaign (after every region is ours) starts every region at
## this many more levels of pressure, up to max_pressure.
@export_range(0, 5) var cycle_pressure: int = 1
## A soldier wounded in Auto sits out this many battles.
@export_range(1, 5) var wound_rest_battles: int = 1
## Auto's fortune of war: the enemy's hp and attack in an Auto battle move
## by a roll in -this..+this % from the battle seed, so a region under
## pressure is a worse bet, not a sure loss.
@export_range(0, 50) var auto_fortune_pct: int = 25
## Bonds (Duyên): two leaders closer than this many cells (Manhattan) at
## the end of our phase count that phase; a bond adds this % attack per
## level while they stand that close.
@export_range(0, 8) var bond_radius_cells: int = 2
@export_range(0, 100) var bond_attack_pct_per_level: int = 5
## Points a bond needs for levels 1, 2, 3...; a battle adds its counted
## phases, at most bond_points_per_battle.
@export var bond_level_points: PackedInt32Array = PackedInt32Array([3, 7, 12])
@export_range(1, 20) var bond_points_per_battle: int = 3


func get_region(id: StringName) -> TacticsRegionData:
	for region: TacticsRegionData in regions:
		if region.id == id:
			return region
	return null


func get_item(id: StringName) -> TacticsItemData:
	for item: TacticsItemData in items:
		if item.id == id:
			return item
	return null


## The rules TacticsBattle.set_bonds() takes.
func get_bond_rules() -> Dictionary:
	return {"radius_cells": bond_radius_cells, "attack_pct_per_level": bond_attack_pct_per_level, "max_level": bond_level_points.size()}


## Problems with the data, each naming the region, offer or field; empty
## when it is fine.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var ids: Dictionary = {}
	for region: TacticsRegionData in regions:
		if region == null or not String(region.id).begins_with("region.") or ids.has(region.id):
			problems.append("TacticsWorld: region %s is missing, misnamed or listed twice" % (region.id if region != null else &"null"))
			continue
		ids[region.id] = true
	if not ids.has(home_region) or not get_region(home_region).is_home():
		problems.append("TacticsWorld: home_region %s is not a region without a scenario" % home_region)
	for region: TacticsRegionData in regions:
		if region == null:
			continue
		for neighbour: StringName in region.neighbours:
			if not ids.has(neighbour) or neighbour == region.id:
				problems.append("TacticsWorld: %s names an unknown neighbour %s" % [region.id, neighbour])
		if not region.is_home() and region.id != home_region and region.scenario.objective == null:
			problems.append("TacticsWorld: %s has a scenario without an objective" % region.id)
		for index: int in region.offers.size():
			problems.append_array(_offer_problems(region, index))
	if bond_level_points.is_empty():
		problems.append("TacticsWorld: bond_level_points is empty")
	for index: int in range(1, bond_level_points.size()):
		if bond_level_points[index] <= bond_level_points[index - 1]:
			problems.append("TacticsWorld: bond_level_points must rise, got %s" % bond_level_points)
	return problems


func _offer_problems(region: TacticsRegionData, index: int) -> Array[String]:
	var offer := region.offers[index]
	var where := "%s offer %d" % [region.id, index]
	if offer == null:
		return ["TacticsWorld: %s is empty" % where]
	if not TacticsMarket.KINDS.has(offer.kind):
		return ["TacticsWorld: %s has an unknown kind %s" % [where, offer.kind]]
	if offer.kind == &"offer.hire" and offer.troop == null:
		return ["TacticsWorld: %s hires no troop" % where]
	if offer.kind == &"offer.item" and (offer.item == null or get_item(offer.item.id) == null):
		return ["TacticsWorld: %s sells an item not in the world's items" % where]
	return []
