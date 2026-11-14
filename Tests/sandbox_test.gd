extends SceneTree

# Headless test for the sandbox screen: places units through the same
# functions the gestures call (no faked touches), checks the 8-unit cap,
# move, swap and remove, then plays a battle to its end at full speed and
# checks that "Xếp lại" restores the line-up. Cells are global (col, row).

const MAX_FRAMES: int = 3000
const STEP_SEC: float = 0.25
const FIRST_UNITS: Array[StringName] = [
	&"unit.shield_guard", &"unit.iron_guard", &"unit.wolf_shield", &"unit.spearman",
	&"unit.archer", &"unit.fire_adept", &"unit.light_rider", &"unit.blade_wanderer",
]

var _main: Node
var _sandbox: SandboxScreen
var _setup: SetupController
var _lineup: Lineup


func _initialize() -> void:
	var ok := await _run()
	if _main != null:
		_main.queue_free()
	await process_frame
	if ok:
		print("Sandbox test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not ClassDB.class_exists("Battle"):
		push_error("Battle is missing: build the GDExtension (scons) before importing")
		return false
	var scene := load("res://Scenes/main.tscn") as PackedScene
	_main = scene.instantiate()
	root.add_child(_main)
	await process_frame
	_sandbox = _main.get_node("UI/SandboxScreen") as SandboxScreen
	_setup = _sandbox.setup_controller
	_lineup = _sandbox.player_lineup
	var checks: Array[Callable] = [_check_impact_order, _check_cap, _check_move_swap_remove, _check_drops, _check_enemy_presets]
	for check: Callable in checks:
		if not check.call():
			push_error("Sandbox test failed in %s" % check.get_method())
			return false
	# Leave one cell free so the gesture and battle checks have room.
	_lineup.remove(_lineup.get_entry_ids()[0])
	var async_checks: Array[Callable] = [_check_gesture_cancel, _check_battle]
	for check: Callable in async_checks:
		if not await check.call():
			push_error("Sandbox test failed in %s" % check.get_method())
			return false
	return true


# Delayed impacts may land out of order; only newer ones may set the hp bar.
func _check_impact_order() -> bool:
	var order := ImpactOrder.new()
	var steps: Array[Array] = [[1, 10, true], [1, 5, false], [2, 5, true], [1, 10, false], [1, 11, true], [2, 4, false]]
	for step: Array in steps:
		if order.accept(step[0], step[1]) != step[2]:
			push_error("ImpactOrder.accept(%d, %d) should be %s" % [step[0], step[1], step[2]])
			return false
	return true


func _check_cap() -> bool:
	# Tap a card once, then tap cells: the card stays selected.
	_setup.tap_roster_card(FIRST_UNITS[0])
	for index: int in FIRST_UNITS.size():
		if index > 0:
			_setup.tap_roster_card(FIRST_UNITS[index])
		_setup.tap_cell(Vector2i(index % 7, index / 7))
	_setup.tap_cell(Vector2i(3, 2))
	if _lineup.size() != 8 or _lineup.get_entry_at(Vector2i(4, 2)) != Lineup.NO_ENTRY:
		push_error("Expected 8 units and no ninth, got %d" % _lineup.size())
		return false
	# Tapping the selected card again deselects it: no placement after that.
	_setup.deselect()
	return true


func _check_move_swap_remove() -> bool:
	var first := _lineup.get_entry_at(Vector2i(1, 4))
	var second := _lineup.get_entry_at(Vector2i(2, 4))
	# Move: tap the unit at (0,0), then an empty cell (0,2).
	_setup.tap_cell(Vector2i(0, 0))
	_setup.tap_cell(Vector2i(0, 2))
	if _lineup.get_slot(first).get_cell() != Vector2i(1, 2):
		push_error("Move failed: %s" % _lineup.get_slot(first).get_cell())
		return false
	# Swap: tap the moved unit, then the one at (1,0).
	_setup.tap_cell(Vector2i(0, 2))
	_setup.tap_cell(Vector2i(1, 0))
	if _lineup.get_slot(first).get_cell() != Vector2i(2, 4) or _lineup.get_slot(second).get_cell() != Vector2i(1, 2):
		push_error("Swap failed")
		return false
	# Tapping a unit twice deselects it, so the next empty tap does nothing.
	_setup.tap_cell(Vector2i(1, 0))
	_setup.tap_cell(Vector2i(1, 0))
	_setup.tap_cell(Vector2i(6, 3))
	if _lineup.get_slot(first).get_cell() != Vector2i(2, 4):
		push_error("A deselected unit still moved")
		return false
	# Remove: drag a unit off the board.
	if not _setup.drop_piece(first, BoardView.INVALID_CELL) or _lineup.size() != 7:
		push_error("Removing by dragging off the board failed")
		return false
	return true


func _check_drops() -> bool:
	if _setup.drop_card(&"unit.archer", Vector2i(3, 5)):
		push_error("A card was dropped on the enemy half")
		return false
	if not _setup.drop_card(&"unit.archer", Vector2i(1, 0)) or _lineup.size() != 8:
		push_error("Dropping a card on a free cell failed")
		return false
	if _setup.drop_card(&"unit.archer", Vector2i(6, 3)):
		push_error("A ninth unit was dropped")
		return false
	# Drag a placed unit onto another: swap.
	var mover := _lineup.get_entry_at(Vector2i(3, 4))
	var other := _lineup.get_entry_at(Vector2i(1, 3))
	if not _setup.drop_piece(mover, Vector2i(0, 1)) or _lineup.get_slot(other).get_cell() != Vector2i(3, 4):
		push_error("Dropping a unit on another did not swap")
		return false
	return true


func _check_enemy_presets() -> bool:
	_sandbox.next_enemy()
	_sandbox.next_enemy()
	if _sandbox.enemy_lineup.size() != 8:
		push_error("The third enemy preset has %d units, expected 8" % _sandbox.enemy_lineup.size())
		return false
	return true


# Pushes real pointer events through the viewport: a right click during a
# drag is ignored, and a second finger or the mouse leaving the window
# cancels the drag and puts everything back.
func _check_gesture_cancel() -> bool:
	var board := _sandbox.board
	var entry := _lineup.get_entry_ids()[0]
	var from_cell := _board_cell(entry)
	var free_cell := _free_player_cell()
	var free_point := board.cell_to_global(free_cell) - DragGhost.LIFT + UnitView.FEET
	# Right click mid-drag: ignored, the left release still drops the unit.
	_press(board.cell_to_global(from_cell), true)
	_move(free_point)
	_push_button(free_point, MOUSE_BUTTON_RIGHT, true)
	_push_button(free_point, MOUSE_BUTTON_RIGHT, false)
	if not _setup.is_dragging():
		push_error("A right click ended the drag")
		return false
	_press(free_point, false)
	if _board_cell(entry) != free_cell or _setup.is_dragging():
		push_error("The drop after a right click did not move the unit")
		return false
	# A second finger cancels; so does the mouse leaving the window.
	for cancel_kind: int in 2:
		var cell := _board_cell(entry)
		_press(board.cell_to_global(cell), true)
		_move(board.cell_to_global(cell) + Vector2(180, 0))
		if cancel_kind == 0:
			var touch := InputEventScreenTouch.new()
			touch.index = 1
			touch.pressed = true
			touch.position = Vector2(10, 10)
			root.push_input(touch, true)
		else:
			root.propagate_notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
		await create_timer(0.3).timeout
		var view: UnitView = _sandbox.board.get_piece_layer().get_children().filter(
			func(node: Node) -> bool: return node is UnitView and node.position == board.cell_to_local(cell)).front()
		if _setup.is_dragging() or _sandbox.get_node("%Ghost").visible or view.modulate.a < 0.99:
			push_error("Drag cancel %d left the drag, ghost or faded unit behind" % cancel_kind)
			return false
		_press(board.cell_to_global(_free_player_cell()), false)
		if _board_cell(entry) != cell:
			push_error("A release after a cancelled drag still moved the unit")
			return false
	return true


func _check_battle() -> bool:
	var before := _describe(_lineup)
	_sandbox.cycle_speed()
	_sandbox.cycle_speed()
	if not _sandbox.start_battle() or _sandbox.phase != SandboxScreen.Phase.BATTLE:
		push_error("The battle did not start")
		return false
	# Setup input must be ignored: a selected card and a free cell, a drag.
	var free_cell := _free_player_cell()
	_setup.tap_roster_card(&"unit.archer")
	_setup.tap_cell(free_cell)
	if _setup.drop_card(&"unit.archer", free_cell) or _setup.drop_piece(_lineup.get_entry_ids()[0], BoardView.INVALID_CELL):
		push_error("A drop was accepted during the battle")
		return false
	if _describe(_lineup) != before:
		push_error("Setup input changed the line-up during the battle")
		return false
	var frames := 0
	while _sandbox.phase != SandboxScreen.Phase.RESULT and frames < MAX_FRAMES:
		_sandbox.playback.advance(STEP_SEC)
		await process_frame
		frames += 1
	if _sandbox.phase != SandboxScreen.Phase.RESULT or _sandbox.last_winner < 0:
		push_error("No result after %d frames" % frames)
		return false
	print("Sandbox battle ended: winner %d, reason %s" % [_sandbox.last_winner, _sandbox.last_reason])
	_sandbox.return_to_setup()
	await process_frame
	if _sandbox.phase != SandboxScreen.Phase.SETUP or _describe(_lineup) != before:
		push_error("Xếp lại did not restore the line-up: %s vs %s" % [_describe(_lineup), before])
		return false
	var shown := 0
	for child: Node in _sandbox.board.get_piece_layer().get_children():
		var view := child as UnitView
		if view != null and not view.is_queued_for_deletion() and view.side == Battle.SIDE_A and not view.is_dead:
			shown += 1
	if shown != _lineup.size():
		push_error("Expected %d player units shown after Xếp lại, found %d" % [_lineup.size(), shown])
		return false
	# The speed button after Xếp lại must not touch the freed battle views.
	await process_frame
	await process_frame
	for press: int in 3:
		_sandbox.cycle_speed()
	if _sandbox.playback.get_view_count() != 0:
		push_error("The playback still refers to %d views after Xếp lại" % _sandbox.playback.get_view_count())
		return false
	return true


func _board_cell(entry_id: int) -> Vector2i:
	return Battle.local_to_global(Battle.SIDE_A, _lineup.get_slot(entry_id).local_col, _lineup.get_slot(entry_id).local_rank)


func _free_player_cell() -> Vector2i:
	for row: int in 4:
		for col: int in 7:
			var local := Battle.global_to_local(Battle.SIDE_A, col, row)
			if _lineup.get_entry_at(local) == Lineup.NO_ENTRY:
				return Vector2i(col, row)
	return BoardView.INVALID_CELL


func _press(at: Vector2, pressed: bool) -> void:
	_push_button(at, MOUSE_BUTTON_LEFT, pressed)


func _push_button(at: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed or button != MOUSE_BUTTON_LEFT else 0
	root.push_input(event, true)


# Moves a held left button in a few steps, past the drag threshold.
func _move(to: Vector2) -> void:
	for step: int in 3:
		var event := InputEventMouseMotion.new()
		event.position = to
		event.global_position = to
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event, true)


func _describe(lineup: Lineup) -> Array[String]:
	var parts: Array[String] = []
	for slot: LineupSlot in lineup.to_slots():
		parts.append("%s@%s" % [slot.unit_id, slot.get_cell()])
	return parts
