class_name TacticsSkillLook
extends Resource
## How one leader skill looks in the close-up: its signature (a colour pair
## and a motif shape) and the painter of each of its three layers, the
## caster's aura, the path of the skill and the impact, with their
## durations. TacticsSkillFx draws any look from a small shared set of
## pieces, so a new skill needs a new file here, not new code. Files live
## in Data/Tactics/Looks/ and are listed in skill_looks.tres.

## The tactics skill this look belongs to (`tactics_skill.fire_rain`).
@export var skill_id: StringName
@export var color_main: Color = Color.WHITE
@export var color_accent: Color = Color.GOLD
## The signature shape: `motif.feather`, `motif.crescent`, `motif.flame`,
## `motif.fang` or `motif.chevron`.
@export var motif: StringName = &"motif.chevron"
## Layer a: `aura.swirl` (motifs spiral in), `aura.sigil` (a ring on the
## ground) or `aura.rise` (motifs rising).
@export var aura: StringName = &"aura.rise"
## Layer b: `path.arc` (a volley arcing over), `path.fall` (from the sky),
## `path.beam` (a straight thrust), `path.dash` (the caster's afterimage)
## or `path.wave` (rings along the ground).
@export var path: StringName = &"path.arc"
## `together`: every target at once; `chain`: one after another, each from
## the previous target.
@export var path_order: StringName = &"together"
## Layer c: `impact.burst` (motifs fly out), `impact.slash` (crossing
## cuts) or `impact.marks` (support marks over allies).
@export var impact: StringName = &"impact.burst"
@export_range(0.2, 2.0, 0.05) var cast_sec: float = 0.8
@export_range(0.2, 2.0, 0.05) var path_sec: float = 0.7
@export_range(0.2, 2.0, 0.05) var impact_sec: float = 1.0
## Motifs drawn by the aura and the impact.
@export_range(1, 16) var motif_count: int = 8
## Screen shake at each impact, in pixels (0 for none).
@export_range(0.0, 12.0, 0.5) var shake_px: float = 0.0
## Sound ids (Data/Audio/sounds.tres) when the path starts and at each impact.
@export var path_sound: StringName = &"spell"
@export var impact_sound: StringName = &"hit_heavy"


## Seconds from the start to the first impact.
func get_impact_start() -> float:
	return cast_sec + path_sec


func get_total_sec() -> float:
	return cast_sec + path_sec + impact_sec
