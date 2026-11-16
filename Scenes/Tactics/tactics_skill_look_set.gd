class_name TacticsSkillLookSet
extends Resource
## Every skill look, listed explicitly (nothing scans folders at runtime),
## and the fallback for a skill without one.
## [codeblock]
## var looks := load("res://Data/Tactics/Looks/skill_looks.tres") as TacticsSkillLookSet
## var look := looks.get_look(&"tactics_skill.fire_rain")
## [/codeblock]

@export var looks: Array[TacticsSkillLook] = []
@export var fallback: TacticsSkillLook


## The look of a skill, or the fallback.
func get_look(skill_id: StringName) -> TacticsSkillLook:
	for look: TacticsSkillLook in looks:
		if look.skill_id == skill_id:
			return look
	return fallback
