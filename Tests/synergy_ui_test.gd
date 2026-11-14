extends SceneTree

# Scene-level synergy test through the real run screen: placing units with
# the same taps the gestures call updates the info row (Hợp Lực, formation
# chips, "+N") and the board outlines; the bar's tap opens the "+N" panel; a
# drag previews the move without changing the run and the outlines come
# back after it; a broken formation shatters its own instance's outline;
# the enemy's formations are outlined; a battle with synergies plays to its end. Saves go to
# TEST_SAVE_PATH (never the player's save) and are deleted.

const SEED: int = 99
const TEST_SAVE_PATH: String = "user://synergy_ui_test.json"
const SLIDE_WAIT_SEC: float = 0.5
const MAX_BATTLE_STEPS: int = 4000
const STEP_SEC: float = 0.25

var _main: Node
var _screen: RunScreen
var _catalog: Catalog


func _initialize() -> void:
	RunSave.path = TEST_SAVE_PATH
	RunSettings.path = "user://settings_synergy_ui_test.json"
	var had_player_save := RunSave.has_save(RunSave.PATH)
	var ok := await _run()
	if _main != null:
		_main.queue_free()
	RunSave.delete()
	await process_frame
	if RunSave.has_save(RunSave.PATH) != had_player_save:
		push_error("The test must not create or delete the player's save")
		ok = false
	if ok:
		print("Synergy UI test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not ClassDB.class_exists("Synergy"):
		push_error("Synergy is missing: build the GDExtension (scons) before importing")
		return false
	_main = (load("res://Scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await process_frame
	_catalog = load("res://Data/catalog.tres")
	_screen = _main._open_run(_make_run())
	_screen.is_saving = false
	await create_timer(SLIDE_WAIT_SEC).timeout
	var checks: Array[Callable] = [_check_empty_row, _check_place, _check_panel, _check_preview, _check_preview_rules, _check_shatter_instance, _check_enemy, _check_battle]
	for check: Callable in checks:
		if not await check.call():
			push_error("Synergy UI test failed in %s" % check.get_method())
			return false
	return true


# Stage 6, an empty board, a shield, a mage and two archers on the bench.
func _make_run() -> RunState:
	var run := RunState.new(_catalog, SEED)
	run.start()
	var data := run.to_save_data()
	data["stage"] = 6
	data["level"] = 6
	data["gold"] = 30
	var rows: Array = []
	for entry: Array in [["shield_guard", 0], ["fire_adept", 1], ["archer", 2], ["wolf_archer", 3]]:
		rows.append({"id": rows.size() + 1, "unit_id": "unit." + entry[0], "star": 1, "bench": entry[1], "col": 0, "rank": 0, "has_fought": true})
	data["pieces"] = rows
	run.load_save_data(data)
	return run


func _check_empty_row() -> bool:
	var bar := _screen.layout.synergy_bar
	return (_expect("empty Hợp Lực", _screen.synergy_hud.result.get("hop_luc", -1), 0)
		and _expect("empty chips", bar.get_chip_ids(), [])
		and _expect("empty outlines", _screen.layout.outlines.get_formation_ids(Battle.SIDE_A), []))


# Shield at local (4, 1), mage behind it at (4, 2): Hộ Pháp turns on.
func _check_place() -> bool:
	var before: int = _screen.synergy_hud.result["hop_luc"]
	_screen.controller.tap_bench_slot(0)
	_screen.controller.tap_cell(_global(4, 1))
	_screen.controller.tap_bench_slot(1)
	_screen.controller.tap_cell(_global(4, 2))
	await process_frame
	var bar := _screen.layout.synergy_bar
	return (_expect("pieces placed", _screen.run.get_board_count(), 2)
		and _expect("chips", bar.get_chip_ids(), [&"formation.spell_guard"])
		and _expect("outlines", _screen.layout.outlines.get_formation_ids(Battle.SIDE_A), [&"formation.spell_guard"])
		and _expect("Hợp Lực rose", _screen.synergy_hud.result["hop_luc"] > before, true)
		and _expect("+N counts milestones", bar.get_more_count(), _reached_milestones(_screen.synergy_hud.result)))


# A press on the bar opens the "+N" panel listing the formation.
func _check_panel() -> bool:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	_screen.layout.synergy_bar._gui_input(press)
	await create_timer(0.3).timeout
	var panel := _screen.layout.synergy_panel
	var name := TranslationServer.translate(_catalog.get_formation(&"formation.spell_guard").name_key)
	var listed := Array(panel.get_lines()).any(func(line: String) -> bool: return line.contains(name))
	var ok := _expect("panel open", panel.visible, true) and _expect("panel lists Hộ Pháp", listed, true)
	panel.close()
	await create_timer(0.2).timeout
	return ok


# Dragging an archer over a cell previews; the run and the shown result
# stay as they were, and the preview ends with the drag.
func _check_preview() -> bool:
	var run := _screen.run
	var shown: Dictionary = _screen.synergy_hud.result.duplicate(true)
	var outlines := _screen.layout.outlines
	var drawn := [outlines.get_formation_ids(Battle.SIDE_A), outlines.get_near_ids()]
	var cells := run.get_board_pieces().map(func(piece: RunPiece) -> Vector2i: return piece.cell)
	var archer := run.get_bench_piece(2)
	var board := _screen.layout.board
	_screen.controller._start_piece_drag(archer, board.cell_to_global(_global(1, 1)))
	_screen.controller._on_drag_moved(board.cell_to_global(_global(3, 4)))
	_screen.controller._on_drag_moved(board.cell_to_global(_global(4, 4)))
	await process_frame
	var previewing := _screen.layout.synergy_bar.is_previewing() and _screen.layout.outlines.is_previewing()
	var unchanged := (run.get_board_count() == 2 and archer.is_on_bench()
		and run.get_board_pieces().map(func(piece: RunPiece) -> Vector2i: return piece.cell) == cells
		and _screen.synergy_hud.result == shown)
	_screen.controller._cancel_drag()
	await process_frame
	return (_expect("previewing", previewing, true)
		and _expect("preview changed nothing", unchanged, true)
		and _expect("preview ended", [_screen.layout.synergy_bar.is_previewing(), outlines.is_previewing()], [false, false])
		and _expect("outlines back after the preview", [outlines.get_formation_ids(Battle.SIDE_A), outlines.get_near_ids()], drawn))


# The drag preview follows RunState: a card whose purchase merges previews
# the board after the merge (even over a taken cell), and a legend past the
# board limit previews as refused.
func _check_preview_rules() -> bool:
	var run := _run_with([["archer", 1, 4], ["archer", 2, 4], ["shield_guard", 4, 1]])
	var archer := _catalog.get_unit(&"unit.archer")
	# The kept copy is the first in board order; the second and the bought one go.
	var merged := [[&"unit.archer", Vector2i(1, 4)], [&"unit.shield_guard", Vector2i(4, 1)]]
	var on_free := _rows(LineupSynergy.preview_pieces(run, 0, archer, Vector2i(5, 4)))
	var on_taken := _rows(LineupSynergy.preview_pieces(run, 0, archer, Vector2i(4, 1)))
	var bought := run.buy_to(_offer(run, &"unit.archer"), RunPiece.NO_BENCH, Vector2i(4, 1))
	var legends := _run_with([["lac_hong", 1, 1], ["lieu_mi", 2, 1]])
	var third := LineupSynergy.preview_pieces(legends, 0, _catalog.get_unit(&"unit.ba_khac"), Vector2i(3, 1))
	var refused := legends.buy_to(_offer(legends, &"unit.ba_khac"), RunPiece.NO_BENCH, Vector2i(3, 1))
	return (_expect("merging card on a free cell", on_free, merged)
		and _expect("merging card on a taken cell", on_taken, merged)
		and _expect("the buy agrees", [bought, _rows(LineupSynergy.run_pieces(run))], [RunState.Result.OK, merged])
		and _expect("third legend refused", [third, refused], [[], RunState.Result.LEGEND_LIMIT]))


# A level-6 run in PREP with these [name, col, rank] pieces on the board and
# a shop of the units the preview checks need.
func _run_with(board: Array) -> RunState:
	var run := RunState.new(_catalog, SEED)
	run.start()
	var data := run.to_save_data()
	data["level"] = 6
	data["gold"] = 30
	var rows: Array = []
	for entry: Array in board:
		rows.append({"id": rows.size() + 1, "unit_id": "unit." + entry[0], "star": 1, "bench": RunPiece.NO_BENCH, "col": entry[1], "rank": entry[2], "has_fought": true})
	data["pieces"] = rows
	data["shop"] = ["unit.archer", "unit.ba_khac", "unit.spearman", "unit.fire_adept", "unit.shield_guard"]
	if not run.load_save_data(data):
		push_error("Synergy UI test: the test run did not load")
	return run


func _offer(run: RunState, unit_id: StringName) -> int:
	return run.get_shop_offers().find(unit_id)


# evaluate() pieces as sorted [unit id, cell] rows.
func _rows(pieces: Array) -> Array:
	var rows: Array = pieces.map(func(piece: Dictionary) -> Array: return [(piece["unit"] as UnitData).id, Vector2i(piece["col"], piece["rank"])])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]) < String(b[0]))
	return rows


# Two Song Kiếm on one side: formation_broken's cells pick the instance
# that shatters, not the first with that id.
func _check_shatter_instance() -> bool:
	var outlines := FormationOutlines.new()
	outlines.setup(_catalog)
	var id := &"formation.twin_blades"
	var left: Array = [Vector2i(1, 1), Vector2i(2, 1)]
	var right: Array = [Vector2i(5, 1), Vector2i(6, 1)]
	outlines.show_side(Battle.SIDE_A, {"formations": [{"id": id, "cells": left}, {"id": id, "cells": right}]}, false)
	var right_global: Array[Vector2i] = [_global(6, 1), _global(5, 1)]
	outlines.shatter(Battle.SIDE_A, id, right_global)
	var broken := outlines.get_broken(Battle.SIDE_A)
	outlines.free()
	var expected: Array[Vector2i] = [_global(5, 1), _global(6, 1)]
	expected.sort()
	return _expect("the right instance shatters", broken, [[id, expected]])


func _check_enemy() -> bool:
	var expected: Array = _screen.synergy_hud.enemy_result["formations"].map(func(entry: Dictionary) -> StringName: return entry["id"])
	return _expect("enemy outlines", _screen.layout.outlines.get_formation_ids(Battle.SIDE_B), expected)


# The battle starts with the roll call and plays to its end.
func _check_battle() -> bool:
	_screen.cycle_speed()
	_screen.cycle_speed()
	if not _screen.start_battle():
		push_error("The battle did not start")
		return false
	var steps := 0
	while _screen.run.phase == RunState.Phase.BATTLE and steps < MAX_BATTLE_STEPS:
		_screen.playback.advance(STEP_SEC)
		await process_frame
		steps += 1
	return _expect("outlines in battle mode", _screen.layout.outlines.is_battle, true) and _expect("battle over", _screen.run.phase != RunState.Phase.BATTLE, true)


func _reached_milestones(result: Dictionary) -> int:
	var count := 0
	for entry: Dictionary in result["class_milestones"] + result["race_milestones"]:
		if entry["reached"] > 0:
			count += 1
	return count


func _global(col: int, rank: int) -> Vector2i:
	return Battle.local_to_global(Battle.SIDE_A, col, rank)


func _expect(what: String, actual: Variant, expected: Variant) -> bool:
	if actual == expected:
		return true
	push_error("%s: got %s, expected %s" % [what, actual, expected])
	return false
