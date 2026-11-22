class_name TacticsItemData
extends Resource
## A one-use battle item bought at a city market (Docs/systems/tactics_world.md):
## used on the region card before a battle, it gives every leader of ours
## `amount` % of one stat for that battle (Thủ công or Auto), then is gone.
## Listed in the world's `items` (Data/Tactics/World/world.tres).
## [codeblock]
## var drum := world_data.get_item(&"item.war_drum")
## [/codeblock]

## Stable id, `item.<name>`.
@export var id: StringName = &""
@export var name_key: String = ""
## What it does, for the market and the region card.
@export var desc_key: String = ""
## `stat.attack_pct` or `stat.hp_pct`: which of the leaders' percents it raises.
@export var stat: StringName = &"stat.attack_pct"
@export_range(1, 100) var amount: int = 10
