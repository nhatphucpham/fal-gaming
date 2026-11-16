extends SceneTree

# Headless test of touch gestures that compete on the tactics map, pushed
# through the viewport as a phone sends them (the first finger's touch
# with the mouse event the engine makes from it, a second finger as a
# touch only), with real camera glides: a finger that lands on a leader
# of ours that is not selected and slides pans the map and moves no one;
# a tap on something in view never moves the camera, so a fast double
# tap on an enemy near the edge of the view strikes that enemy; a drag of
# the selected leader lifted over the panel or on a cell it cannot reach
# moves nothing; a pinch begun on the selected leader zooms and moves
# nothing.

const SCENARIO_PATH: String = "res://Data/Tactics/Scenarios/river_crossing.tres"
const MAX_FRAMES: int = 6000


class ErrorLog extends Logger:
	var lines: Array[String] = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			lines.append("%s:%d %s %s" % [file, line, code, rationale])


var _errors := ErrorLog.new()
var _screen: TacticsScreen


func _initialize() -> void:
	TranslationServer.set_locale("vi")
	OS.add_logger(_errors)
	var ok := await _run()
	if _screen != null:
		_screen.queue_free()
	await process_frame
	OS.remove_logger(_errors)
	if ok and not _errors.lines.is_empty():
		push_error("Tactics touch test: errors were logged:\n%s" % "\n".join(_errors.lines))
		ok = false
	if ok:
		print("Tactics touch test passed")
	quit(0 if ok else 1)


func _run() -> bool:
	if not ClassDB.class_exists("TacticsBattle"):
		push_error("TacticsBattle is missing: build the GDExtension (scons) before importing")
		return false
	var checks: Array[Callable] = [_check_pan_from_leader, _check_drag_lifted_away, _check_pinch_on_leader, _check_double_tap_at_edge]
	for check: Callable in checks:
		if not await check.call():
			push_error("Tactics touch test failed in %s" % check.get_method())
			return false
	return true


func _open() -> void:
	if _screen != null:
		_screen.queue_free()
		await process_frame
	_screen = TacticsScreen.new()
	_screen.scenario = load(SCENARIO_PATH) as TacticsScenarioData
	_screen.auto_end = false
	_screen.size = Vector2(720, 1280)
	root.add_child(_screen)
	await process_frame
	await _wait_idle()


func _wait_idle() -> bool:
	for frame: int in MAX_FRAMES:
		if _screen.get_close_up().is_playing:
			_screen.get_close_up().skip()
		elif _screen.is_busy():
			_screen.get_playback().skip_step()
		else:
			return true
		await process_frame
	push_error("The screen stayed busy")
	return false


func _frames(count: int) -> void:
	for frame: int in count:
		await process_frame


func _battle() -> TacticsBattle:
	return _screen.get_battle()


func _map() -> TacticsMapView:
	return _screen.get_map()


func _cell(unit: int) -> Vector2i:
	return _battle().get_unit_state(unit)["cell"]


func _our_leaders() -> Array[int]:
	var leaders: Array[int] = []
	for unit: Dictionary in _battle().get_units():
		if unit["role"] == &"leader" and unit["side"] == 0 and unit["alive"]:
			leaders.append(unit["index"])
	return leaders


func _unit_at(cell: Vector2i) -> int:
	for unit: Dictionary in _battle().get_units():
		if unit["alive"] and unit["cell"] == cell:
			return unit["index"]
	return -1


# The viewport point of a cell's centre as drawn now.
func _point(cell: Vector2i) -> Vector2:
	var map := _map()
	return root.get_final_transform() * (map.get_global_rect().position + map.board_to_view(map.cell_to_local(cell)))


# The first finger: the engine sends the mouse event it makes from the
# touch, then the touch.
func _finger(at: Vector2, is_pressed: bool) -> void:
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = is_pressed
	button.button_mask = MOUSE_BUTTON_MASK_LEFT if is_pressed else 0
	button.position = at
	button.global_position = at
	root.push_input(button)
	_touch(0, at, is_pressed)


func _touch(index: int, at: Vector2, is_pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.pressed = is_pressed
	touch.position = at
	root.push_input(touch)


func _slide(index: int, from: Vector2, to: Vector2) -> void:
	if index == 0:
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.position = to
		motion.global_position = to
		motion.relative = to - from
		root.push_input(motion)
	var drag := InputEventScreenDrag.new()
	drag.index = index
	drag.position = to
	drag.relative = to - from
	root.push_input(drag)


func _swipe(from: Vector2, to: Vector2, steps: int) -> void:
	_finger(from, true)
	await process_frame
	for step: int in range(1, steps + 1):
		_slide(0, from.lerp(to, float(step - 1) / steps), from.lerp(to, float(step) / steps))
		await process_frame
	_finger(to, false)
	await process_frame


func _tap(at: Vector2) -> void:
	_finger(at, true)
	await process_frame
	_finger(at, false)
	await process_frame


# With one leader selected, a finger that lands on another leader of ours
# and slides pans the board: no leader moves, no ghost shows.
func _check_pan_from_leader() -> bool:
	await _open()
	var leaders := _our_leaders()
	_screen.select_unit(leaders[1])
	await _frames(20)
	var other := leaders[0]
	var home := _cell(other)
	var hash_before := _battle().get_state_hash()
	var offset := _map().get_camera_offset()
	var from := _point(home)
	await _swipe(from, from + root.get_final_transform().basis_xform(Vector2(0, 240)), 8)
	await _frames(5)
	if not await _wait_idle():
		return false
	if _battle().get_state_hash() != hash_before or _cell(other) != home:
		return _fail("A pan that starts on a leader that is not selected moved it")
	if _map().get_camera_offset() == offset:
		return _fail("A finger sliding from a leader that is not selected should pan the map")
	return true


# The selected leader dragged and lifted over the panel, or on a cell it
# cannot reach, stays; the ghosts go.
func _check_drag_lifted_away() -> bool:
	await _open()
	var leader := _our_leaders()[0]
	_screen.select_unit(leader)
	await _frames(20)
	var hash_before := _battle().get_state_hash()
	var from := _point(_cell(leader))
	var over_panel := Vector2(from.x, root.get_final_transform().origin.y + root.get_final_transform().get_scale().y * 1200.0)
	for lift: Vector2 in [over_panel, _point(_cell(leader) + Vector2i(0, -7))]:
		await _swipe(from, lift, 8)
		await _frames(3)
		if _battle().get_state_hash() != hash_before:
			return _fail("A drag lifted at %s moved the leader" % lift)
		if _map().get_marks().has("ghosts") or _screen.get_mode() != TacticsScreen.Mode.SELECTED:
			return _fail("A drag lifted where it cannot move should go back to the selection")
	return true


# Two fingers, the first on the selected leader: a zoom, no move.
func _check_pinch_on_leader() -> bool:
	await _open()
	var leader := _our_leaders()[0]
	_screen.select_unit(leader)
	await _frames(20)
	var hash_before := _battle().get_state_hash()
	var zoom := _map().get_zoom()
	var first := _point(_cell(leader))
	var spread := root.get_final_transform().basis_xform(Vector2(40, 40))
	var second := first + spread
	_finger(first, true)
	await process_frame
	_touch(1, second, true)
	await process_frame
	for step: int in range(1, 7):
		_slide(0, first - spread * (step - 1) * 0.2, first - spread * step * 0.2)
		_slide(1, second + spread * (step - 1) * 0.2, second + spread * step * 0.2)
		await process_frame
	_touch(1, second + spread * 1.2, false)
	await process_frame
	_finger(first - spread * 1.2, false)
	await _frames(3)
	if _battle().get_state_hash() != hash_before:
		return _fail("A pinch begun on the selected leader moved it")
	if is_equal_approx(_map().get_zoom(), zoom):
		return _fail("A pinch should zoom the map")
	if _map().get_marks().has("ghosts"):
		return _fail("A pinch should drop the drag's ghosts")
	return true


# Our leaders march until one can strike an enemy; the enemy is put in the
# outer cell row of the view; two taps a few frames apart strike it.
func _check_double_tap_at_edge() -> bool:
	await _open()
	var pair := await _find_contact()
	if pair.is_empty():
		return _fail("No leader of ours came within reach of an enemy")
	var leader: int = pair[0]
	var target: int = pair[1]
	_screen.select_unit(leader)
	await _frames(30)
	var map := _map()
	var target_cell := _cell(target)
	# Into the outer row of the view, where a glide used to start.
	map.zoom_to(map.get_zoom(), map.cell_to_local(target_cell) + Vector2(0, map.size.y / 2.0 - map.get_cell_px() * 0.6) / map.get_zoom(), false)
	if not map.is_in_view(map.cell_to_local(target_cell)) or map.board_to_view(map.cell_to_local(target_cell)).y > map.get_cell_px():
		return _fail("The enemy should be in the view's outer row, at %s" % map.board_to_view(map.cell_to_local(target_cell)))
	var offset := map.get_camera_offset()
	var hp_before: int = _battle().get_unit_state(target)["hp"]
	var at := _point(target_cell)
	await _tap(at)
	if map.get_camera_offset() != offset or map.is_camera_moving():
		return _fail("A tap on an enemy in view should not move the camera")
	await _frames(6)
	await _tap(at)
	if not await _wait_idle():
		return false
	var state := _battle().get_unit_state(target)
	if _battle().can_act(leader) or (state["alive"] and int(state["hp"]) >= hp_before):
		return _fail("A double tap on the enemy should strike it (leader can act %s, hp %d -> %d)" % [_battle().can_act(leader), hp_before, state["hp"]])
	return true


# Marches every leader of ours north each phase until one can strike.
func _find_contact() -> Array:
	for phase: int in 12:
		for leader: int in _our_leaders():
			var targets: Array = _battle().get_strike_targets(leader)
			if _battle().can_move(leader) and not targets.is_empty():
				return [leader, targets[0]]
		for leader: int in _our_leaders():
			if not _battle().can_move(leader):
				continue
			var best := _cell(leader)
			for cell: Vector2i in _battle().get_reachable_cells(leader):
				if _unit_at(cell) < 0 and cell.y < best.y:
					best = cell
			if best != _cell(leader):
				_screen.select_unit(leader)
				_screen.move_to(best)
				if not await _wait_idle():
					return []
		_screen.press_button(&"end_turn")
		if not await _wait_idle():
			return []
		if _battle().is_finished():
			return []
	return []


func _fail(message: String) -> bool:
	push_error("Tactics touch test: " + message)
	return false
