class_name EpiphanyBattle
extends RefCounted
## What a battle gives the Kỳ Ngộ meters: which of the player's milestone
## families had a tier reached (the board as it fought, with the run's
## mutations) and how much damage each family's units dealt. Used by
## RunState.finish_battle(); see Docs/systems/epiphany.md.


## {"active": Array[StringName] of family ids, "damage": {family: int}}.
## `piece_damage` maps a board piece id to the damage it dealt.
static func read_families(run: RunState, piece_damage: Dictionary) -> Dictionary:
	var catalog := run.catalog
	var pieces: Array = []
	for piece: RunPiece in run.get_board_pieces():
		pieces.append({"unit": catalog.get_unit(piece.unit_id), "col": piece.cell.x, "rank": piece.cell.y})
	var active: Array[StringName] = []
	var synergy := catalog.get_synergy()
	if synergy != null and not pieces.is_empty():
		var result := synergy.evaluate(pieces, run.get_synergy_overrides())
		for entry: Dictionary in result["class_milestones"] + result["race_milestones"]:
			if entry["reached"] > 0:
				active.append(entry["id"])
	var damage := {}
	for piece: RunPiece in run.get_board_pieces():
		var unit := catalog.get_unit(piece.unit_id)
		var dealt: int = piece_damage.get(piece.id, 0)
		for milestone: MilestoneData in catalog.milestones:
			var counted := unit.race_id if milestone.counted_kind == &"race" else unit.class_id
			if milestone.counted_id == counted:
				damage[milestone.id] = damage.get(milestone.id, 0) + dealt
	return {"active": active, "damage": damage}
