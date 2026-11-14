class_name SynergyHud
extends RefCounted
## Keeps the run screen's synergy views in step with the board: evaluates
## the player's and the enemy's line-ups with Synergy.evaluate() and shows
## them in the info row (SynergyBar), as board outlines (FormationOutlines),
## in the "+N" panel and as shop card badges. It previews a drag (evaluated
## only when the hovered cell changes, on a copied line-up), plays the roll
## call at battle start and shatters outlines the battle breaks. It never
## changes the run. The player's side is evaluated with the run's Kỳ Ngộ
## mutations, the enemy's without. See Docs/systems/synergy.md.

var result: Dictionary = {}
var enemy_result: Dictionary = {}

var _run: RunState
var _layout: RunLayout
var _catalog: Catalog
var _synergy: Synergy
var _enemy_lineup: Lineup


func _init(run: RunState, layout: RunLayout, enemy_lineup: Lineup) -> void:
	_run = run
	_layout = layout
	_catalog = run.catalog
	_synergy = _catalog.get_synergy()
	_enemy_lineup = enemy_lineup
	layout.synergy_bar.setup(_catalog)
	layout.outlines.setup(_catalog)
	layout.synergy_bar.opened.connect(open_panel)
	run.piece_bought.connect(refresh.unbind(2))
	run.piece_moved.connect(refresh.unbind(1))
	run.piece_sold.connect(refresh.unbind(3))
	run.pieces_merged.connect(refresh.unbind(2))
	run.shop_rolled.connect(_refresh_shop_hints)


## Evaluates the player's board and shows it; a formation that just
## completed runs its light and stamps its name when `animate`.
func refresh(animate: bool = true) -> void:
	if _synergy == null:
		return
	var evaluated := _synergy.evaluate(LineupSynergy.run_pieces(_run), _run.get_synergy_overrides())
	if evaluated.is_empty():
		# Synergy refused the line-up or the mutations; it logged why.
		push_error("SynergyHud: evaluate() gave no result for stage %d" % _run.stage)
		return
	var before := _formation_ids(result)
	result = evaluated
	if animate and _formation_ids(result).any(func(id: StringName) -> bool: return not before.has(id)):
		Sound.play(&"formation_on")
	_layout.synergy_bar.end_preview()
	_layout.synergy_bar.show_result(result)
	_layout.outlines.show_side(Battle.SIDE_A, result, animate)
	_refresh_shop_hints()


## Evaluates the stage's enemy line-up and outlines its formations.
func refresh_enemy() -> void:
	if _synergy == null:
		return
	enemy_result = _synergy.evaluate(LineupSynergy.lineup_pieces(_catalog, _enemy_lineup))
	_layout.outlines.show_side(Battle.SIDE_B, enemy_result, false)


## Shows what dropping `piece_id` (or buying `shop_unit`) on `local_cell`
## would make; a move RunState would refuse shows the board as it is.
func preview(piece_id: int, shop_unit: UnitData, local_cell: Vector2i) -> void:
	if _synergy == null:
		return
	var pieces := LineupSynergy.preview_pieces(_run, piece_id, shop_unit, local_cell)
	if pieces.is_empty():
		end_preview()
		return
	var preview_result := _synergy.evaluate(pieces, _run.get_synergy_overrides())
	if preview_result.is_empty():
		end_preview()
		return
	_layout.synergy_bar.show_preview(preview_result)
	_layout.outlines.show_preview(preview_result)


func end_preview() -> void:
	_layout.synergy_bar.end_preview()
	_layout.outlines.end_preview()


## Battle start: outlines flash and stamp their names, the ring bounces;
## then the outlines fade, since the units walk off their cells.
func roll_call() -> void:
	end_preview()
	_layout.outlines.is_battle = true
	_layout.outlines.roll_call()
	_layout.synergy_bar.bounce()


## Back to the preparation: full outlines and near-misses again.
func end_battle() -> void:
	_layout.outlines.is_battle = false


func on_formation_broken(side: int, formation_id: StringName, cells: Array) -> void:
	_layout.outlines.shatter(side, formation_id, cells)
	Sound.play(&"formation_break")


func open_panel() -> void:
	_layout.synergy_panel.open(result, _catalog, "", _run.epiphanies)


## Milestone counts of a side's line-up by counted id (class or race), for
## the unit info panel.
func get_counts(side: int) -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {}
	var evaluated := result if side == Battle.SIDE_A else enemy_result
	for entry: Dictionary in evaluated.get("class_milestones", []) + evaluated.get("race_milestones", []):
		counts[entry["counted_id"]] = entry["count"]
	return counts


# A card earns a badge when buying it onto a free cell would reach a new
# milestone tier, or it is the class a near-miss formation is waiting for.
func _refresh_shop_hints() -> void:
	if _synergy == null or result.is_empty():
		return
	var free := _free_cell()
	var reached := _reached(result)
	var hints: Array[bool] = []
	for unit_id: StringName in _run.get_shop_offers():
		var unit := _catalog.get_unit(unit_id) if unit_id != &"" else null
		var hint := false
		if unit != null and free != LineupSynergy.NO_CELL:
			for entry: Dictionary in result["near_formations"]:
				hint = hint or entry["needed_class"] == unit.class_id
			if not hint:
				var pieces := LineupSynergy.run_pieces(_run)
				pieces.append({"unit": unit, "col": free.x, "rank": free.y})
				var trial := _synergy.evaluate(pieces, _run.get_synergy_overrides())
				hint = not trial.is_empty() and _reached(trial) > reached
		hints.append(hint)
	_layout.shop.update_synergy_hints(hints)


func _formation_ids(evaluated: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: Dictionary in evaluated.get("formations", []):
		ids.append(entry["id"])
	return ids


func _reached(evaluated: Dictionary) -> int:
	var total := 0
	for entry: Dictionary in evaluated["class_milestones"] + evaluated["race_milestones"]:
		total += entry["reached"]
	return total


# A free local cell when the board has room, else NO_CELL.
func _free_cell() -> Vector2i:
	if _run.get_board_count() >= _run.get_capacity():
		return LineupSynergy.NO_CELL
	for rank: int in range(Lineup.RANKS, 0, -1):
		for col: int in range(1, Lineup.COLS + 1):
			if _run.get_board_piece(Vector2i(col, rank)) == null:
				return Vector2i(col, rank)
	return LineupSynergy.NO_CELL
