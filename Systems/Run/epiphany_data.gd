class_name EpiphanyData
extends Resource
## One Kỳ Ngộ mutation of a milestone family: Hạ Mốc (`lower`, one tier's
## threshold drops by 1) or Biến Dị (`variant`, one tier's modifiers are
## replaced). It belongs to an EpiphanyFamily file in Data/Epiphanies/ and
## becomes a Synergy override (Docs/systems/epiphany.md):
## [codeblock]
## var override := epiphany.to_override(catalog.get_milestone(epiphany.family))
## synergy.evaluate(pieces, [override])
## [/codeblock]

const KIND_LOWER: StringName = &"lower"
const KIND_VARIANT: StringName = &"variant"

## Stable id, `epiphany.<family>_<name>`.
@export var id: StringName = &""
## The milestone id it mutates (`milestone.class_shield`).
@export var family: StringName = &""
## `lower` or `variant`.
@export var kind: StringName = KIND_LOWER
## Name on the choice card ("Hạ Mốc", "Biến Dị: ...").
@export var name_key: String = ""
## One line: what it does ("Khiên 4 chỉ cần 3"); the panel shows it on the
## mutated tier.
@export var description_key: String = ""
## Index of the tier it changes (0 is the first threshold).
@export var tier: int = 0
## `variant` only: the tier's new modifiers.
@export var modifiers: Array[ModifierData] = []


## The override Synergy.evaluate() and Battle.set_synergy_overrides() take.
func to_override(milestone: MilestoneData) -> Dictionary:
	var override := {"milestone": family, "tier": tier}
	if kind == KIND_LOWER:
		override["at"] = (milestone.tiers[tier] as SynergyTierData).at - 1
	else:
		override["modifiers"] = modifiers
	return override


## Problems against its milestone: unknown kind or tier, a lowered
## threshold that would not stay above the previous tier, an empty variant.
func validate(milestone: MilestoneData) -> PackedStringArray:
	var problems := PackedStringArray()
	var where := "Run: epiphany %s (%s)" % [id, resource_path]
	if not String(id).begins_with("epiphany.") or name_key.is_empty() or description_key.is_empty():
		problems.append("%s needs an epiphany.<name> id, name_key and description_key" % where)
	if milestone == null or milestone.id != family:
		problems.append("%s names unknown family %s" % [where, family])
		return problems
	if tier < 0 or tier >= milestone.tiers.size():
		problems.append("%s has tier %d, %s has %d" % [where, tier, family, milestone.tiers.size()])
		return problems
	match kind:
		KIND_LOWER:
			var previous: int = (milestone.tiers[tier - 1] as SynergyTierData).at if tier > 0 else 0
			if (milestone.tiers[tier] as SynergyTierData).at - 1 <= previous:
				problems.append("%s lowers tier %d to the previous tier's threshold" % [where, tier])
		KIND_VARIANT:
			if modifiers.is_empty() or modifiers.has(null):
				problems.append("%s is a variant without modifiers" % where)
		_:
			problems.append("%s has unknown kind %s" % [where, kind])
	return problems
