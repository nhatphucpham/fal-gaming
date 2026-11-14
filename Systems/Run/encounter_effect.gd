class_name EncounterEffect
extends Resource
## One effect of a road encounter option: a handler kind from
## EncounterEffects.KINDS and its amount. Gold, supply and morale amounts
## are signed (a cost is negative); `gain.free_unit` gives one unit of the
## cost tier `amount`; `gain.free_refreshes` gives `amount` free refreshes
## in the next preparation; `gain.bet` pays `amount` gold after the next
## battle if it is won. See Docs/systems/encounter.md.

@export var kind: StringName = &""
@export var amount: int = 0
