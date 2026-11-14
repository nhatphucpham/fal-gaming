class_name LineupPreset
extends Resource
## A named, ready-made formation, such as a sandbox enemy line-up. Loaded
## into a Lineup with [method Lineup.load_slots].

## Stable id, `preset.<name>`.
@export var id: StringName = &""
## Translation key of the name shown to the player.
@export var name_key: String = ""
@export var slots: Array[LineupSlot] = []
