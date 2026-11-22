class_name TacticsRegionData
extends Resource
## One region (vùng) of the Chiến Dịch world map: where it sits on the map,
## which regions it touches, the scenario fought there and, for a region
## with a city or town, its market. The home region has no scenario: it is
## ours from the start. See Docs/systems/tactics_world.md.
## [codeblock]
## var region := world_data.get_region(&"region.ferry")
## var campaign := TacticsCampaign.new(roster, catalog, region.scenario)
## [/codeblock]

## Stable id, `region.<name>`.
@export var id: StringName = &""
@export var name_key: String = ""
## Null for the home region.
@export var scenario: TacticsScenarioData
## Where the region's node sits on the world map, 0..1 of its width and height.
@export var map_position: Vector2 = Vector2(0.5, 0.5)
## Region ids it touches; the world makes the links both ways.
@export var neighbours: Array[StringName] = []
## Empty: no market. Otherwise the market's name ("Chợ Bến").
@export var market_name_key: String = ""
@export var offers: Array[TacticsOfferData] = []
## Enemy hp and attack in Auto, in % (the auto battle has no objective,
## waves or terrain; this stands in for them, tuned so Auto wins about as
## often as Thủ công: Tools/tactics_world_probe.gd).
@export_range(10, 400) var auto_enemy_pct: int = 100
## Supplies an Auto win pays (a Thủ công win pays what the battle gives).
@export_range(0, 99) var auto_supplies: int = 1


func has_market() -> bool:
	return not offers.is_empty()


func is_home() -> bool:
	return scenario == null
