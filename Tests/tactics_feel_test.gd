extends SceneTree

# Headless test of how the tactics screen handles on a phone, with input
# pushed through the viewport where it matters: the map opens zoomed so a
# cell is at least 88 layout px (44 px on a 360-px-wide phone); an idle map
# leaves frames undrawn and its layers never redraw while the camera pans;
# one finger drags the map, two pinch it, the "whole map" button shows it
# all; a tap on our leader selects it, a press on it dragged to a blue cell
# shows the ghosts and moves where the finger lifts; once every leader of
# ours is done the phase ends by itself after a beat, and a tap during the
# beat holds it. It also counts the taps a full turn takes: tap the
# leader, tap the enemy, tap it again (or the leader and a cell when no
# enemy is near), and no "Kết lượt". On a 720-px-wide layout no hint,
# card line, order name or button is cut and no text is under the game's
# small font size; every button is at least 88 px tall.

const SCENARIO_PATH: String = "res://Data/Tactics/Scenarios/river_crossing.tres"
const MAX_FRAMES: int = 3000
## On a 360-px-wide phone the 720-px layout is halved.
const MIN_CELL_LAYOUT_PX: float = 88.0


class ErrorLog extends Logger:
	var lines: Array[String] = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			lines.append("%s:%d %s %s" % [file, line, code, rationale])


var _errors := ErrorLog.new()
var _screen: TacticsScreen
var _taps: int = 0


func _initialize() -> void:
	TranslationServer.set_locale("vi")
	OS.add_logger(_errors)
	var ok := await _run()
	if _screen != null:
		_screen.queue_free()
	await process_frame
	OS.remove_logger(_errors)
	if ok and not _errors.lines.is_empty():
		push_error("Tactics feel test: errors were logged:\n%s" % "\n".join(_errors.lines))
		ok = false
	if ok:
		print("Tactics feel test passed")
	quit(0 if ok else 1)


func _run() -> bool:
	if not ClassDB.class_exists("TacticsBattle"):
		push_error("TacticsBattle is missing: build the GDExtension (scons) before importing")
		return false
	var checks: Array[Callable] = [_check_zoom, _check_idle_frames, _check_pan, _check_tap_and_drag, _check_pinch_and_whole_map, _check_auto_end, _check_tap_count, _check_text_fits]
	for check: Callable in checks:
		if not await check.call():
			push_error("Tactics feel test failed in %s" % check.get_method())
			return false
	return true


func _open(is_instant: bool) -> void:
	if _screen != null:
		_screen.queue_free()
		await process_frame
	_screen = TacticsScreen.new()
	_screen.scenario = load(SCENARIO_PATH) as TacticsScenarioData
	_screen.is_instant = is_instant
	_screen.size = Vector2(720, 1280)
	root.add_child(_screen)
	await process_frame
	await _wait_idle()


func _battle() -> TacticsBattle:
	return _screen.get_battle()


func _map() -> TacticsMapView:
	return _screen.get_map()


func _wait_idle() -> bool:
	for frame: int in MAX_FRAMES:
		if not _screen.is_busy():
			return true
		if not _screen.is_instant:
			_screen.get_playback().skip_step()
		await process_frame
	push_error("The screen stayed busy")
	return false


func _our_leaders() -> Array[int]:
	var leaders: Array[int] = []
	for unit: Dictionary in _battle().get_units():
		if unit["role"] == &"leader" and unit["side"] == 0 and unit["alive"]:
			leaders.append(unit["index"])
	return leaders


func _cell(unit: int) -> Vector2i:
	return _battle().get_unit_state(unit)["cell"]


# The screen point (viewport coordinates) of a cell's centre as shown now.
func _cell_point(cell: Vector2i) -> Vector2:
	var map := _map()
	return root.get_final_transform() * (map.get_global_rect().position + map.board_to_view(map.cell_to_local(cell)))


func _press(at: Vector2, is_pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = is_pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if is_pressed else 0
	event.position = at
	event.global_position = at
	root.push_input(event)


func _drag(from: Vector2, to: Vector2, steps: int) -> void:
	for step: int in range(1, steps + 1):
		var event := InputEventMouseMotion.new()
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		var at := from.lerp(to, float(step) / steps)
		var before := from.lerp(to, float(step - 1) / steps)
		event.position = at
		event.global_position = at
		event.relative = at - before
		root.push_input(event)


# Frames over `seconds` that changed what would be drawn: [changed, frames].
func _count_changed_frames(seconds: float) -> Array[int]:
	var changed := 0
	var frames := 0
	var end_msec := Time.get_ticks_msec() + roundi(seconds * 1000.0)
	RenderingServer.force_draw(false)
	while Time.get_ticks_msec() < end_msec:
		await process_frame
		frames += 1
		if RenderingServer.has_changed():
			changed += 1
			RenderingServer.force_draw(false)
	return [changed, frames]


func _check_zoom() -> bool:
	await _open(true)
	var map := _map()
	if map.get_cell_px() < MIN_CELL_LAYOUT_PX:
		push_error("A cell shows at %.1f layout px, below %.0f" % [map.get_cell_px(), MIN_CELL_LAYOUT_PX])
		return false
	if not map.is_in_view(map.cell_to_local(_cell(_our_leaders()[0]))):
		push_error("The map should open on our leaders")
		return false
	print("Default zoom: %.2f, a cell is %.0f layout px (%.0f px on a 360-px phone); whole map %.2f" % [map.get_zoom(), map.get_cell_px(), map.get_cell_px() / 2.0, map.get_whole_zoom()])
	return true


# Idle with a leader selected: nothing is drawn again, no layer redraws.
func _check_idle_frames() -> bool:
	await _open(false)
	_screen.select_unit(_our_leaders()[0])
	await create_timer(0.6).timeout
	var draws := _map().get_layer_draw_count()
	var counts := await _count_changed_frames(1.0)
	if counts[0] > 0:
		push_error("An idle tactics map changed %d of %d frames" % [counts[0], counts[1]])
		return false
	if _map().get_layer_draw_count() != draws:
		push_error("An idle tactics map redrew its layers")
		return false
	print("Idle map: %d of %d frames changed" % counts)
	return true


# One finger on an empty cell drags the board; nothing is selected and no
# layer redraws (the board moves as one).
func _check_pan() -> bool:
	await _open(true)
	var map := _map()
	var draws := map.get_layer_draw_count()
	var offset := map.get_camera_offset()
	var empty := Vector2i(-1, -1)
	for row: int in map.map_height:
		for col: int in map.map_width:
			var cell := Vector2i(col, row)
			if empty.x < 0 and _unit_at(cell) < 0 and map.is_in_view(map.cell_to_local(cell)) and map.is_in_view(map.cell_to_local(cell) + Vector2(0, 150) / map.get_zoom()):
				empty = cell
	var from := _cell_point(empty)
	# Towards the far side of the board, whichever way it can go.
	var push := root.get_final_transform().basis_xform(Vector2(-160 if offset.x >= 0.0 else 160, -160 if offset.y >= 0.0 else 160))
	_press(from, true)
	_drag(from, from + push, 6)
	_press(from + push, false)
	await process_frame
	if map.get_camera_offset() == offset:
		push_error("A one-finger drag should pan the map (offset %s)" % offset)
		return false
	if _screen.get_mode() != TacticsScreen.Mode.IDLE:
		push_error("A drag should not select anything")
		return false
	if map.get_layer_draw_count() != draws:
		push_error("Panning should not redraw the map's layers")
		return false
	return true


func _unit_at(cell: Vector2i) -> int:
	for unit: Dictionary in _battle().get_units():
		if unit["alive"] and unit["cell"] == cell:
			return unit["index"]
	return -1


# A tap on our leader selects it; a press on it dragged to a blue cell
# shows the ghosts, and the leader moves where the finger lifts.
func _check_tap_and_drag() -> bool:
	await _open(true)
	var leader := _our_leaders()[0]
	_map().follow(_map().cell_to_local(_cell(leader)))
	var at := _cell_point(_cell(leader))
	_press(at, true)
	_press(at, false)
	await process_frame
	if _screen.get_selected() != leader or _screen.get_mode() != TacticsScreen.Mode.SELECTED:
		push_error("A tap on our leader should select it")
		return false
	var goal := Vector2i(-1, -1)
	for cell: Vector2i in _battle().get_reachable_cells(leader):
		if _unit_at(cell) < 0 and _map().is_in_view(_map().cell_to_local(cell)) and (goal.x < 0 or absi(cell.y - _cell(leader).y) > absi(goal.y - _cell(leader).y)):
			goal = cell
	if goal.x < 0:
		push_error("No reachable cell is in view")
		return false
	var hash_before := _battle().get_state_hash()
	var to := _cell_point(goal)
	_press(at, true)
	_drag(at, to, 5)
	await process_frame
	if _screen.get_mode() != TacticsScreen.Mode.MOVE_PREVIEW or (_map().get_marks().get("ghosts", []) as Array).is_empty():
		push_error("Dragging our leader should show its ghosts")
		return false
	if _battle().get_state_hash() != hash_before:
		push_error("Dragging must not change the battle")
		return false
	_press(to, false)
	await process_frame
	if not await _wait_idle():
		return false
	if _cell(leader) != goal:
		push_error("The leader should move where the finger lifted (%s), it is on %s" % [goal, _cell(leader)])
		return false
	return true


func _check_pinch_and_whole_map() -> bool:
	await _open(true)
	var map := _map()
	var zoom := map.get_zoom()
	var middle := root.get_final_transform() * map.get_global_rect().get_center()
	var unit := root.get_final_transform().basis_xform(Vector2(1, 0))
	var touches := [middle - unit * 60.0, middle + unit * 60.0]
	for index: int in 2:
		var touch := InputEventScreenTouch.new()
		touch.index = index
		touch.pressed = true
		touch.position = touches[index]
		root.push_input(touch)
	for step: int in range(1, 6):
		for index: int in 2:
			var drag := InputEventScreenDrag.new()
			drag.index = index
			drag.position = touches[index] + unit * float((-1 if index == 0 else 1) * 12 * step)
			root.push_input(drag)
	for index: int in 2:
		var lift := InputEventScreenTouch.new()
		lift.index = index
		lift.pressed = false
		lift.position = touches[index]
		root.push_input(lift)
	await process_frame
	if map.get_zoom() <= zoom:
		push_error("Spreading two fingers should zoom in (%.2f to %.2f)" % [zoom, map.get_zoom()])
		return false
	if map.get_zoom() > map.get_max_zoom() + 0.001:
		push_error("The pinch went past the closest zoom")
		return false
	map.get_whole_map_button().pressed.emit()
	await process_frame
	if not map.is_whole_map() or absf(map.get_zoom() - map.get_whole_zoom()) > 0.001:
		push_error("The whole-map button should show the whole board")
		return false
	if map.get_whole_map_button().text != "TACTICS_ZOOM_IN":
		push_error("At the whole map the button should offer to zoom in")
		return false
	map.get_whole_map_button().pressed.emit()
	await process_frame
	if map.is_whole_map() or absf(map.get_zoom() - map.get_default_zoom()) > 0.001:
		push_error("The button again should go back to the default zoom")
		return false
	return true


# Round 1: every leader done, a tap in the beat holds the end; round 2:
# the phase ends by itself and round 3 begins without "Kết lượt".
func _check_auto_end() -> bool:
	await _open(true)
	if not await _play_our_turn():
		return false
	if _battle().is_finished():
		return true
	if not _screen.is_auto_end_pending():
		push_error("With every leader done the phase should be about to end")
		return false
	if _screen.get_hint() != tr("TACTICS_HINT_AUTO_END"):
		push_error("The hint should say the turn is ending, not \"%s\"" % _screen.get_hint())
		return false
	_screen.tap_cell(Vector2i(0, 0))
	await create_timer(0.3).timeout
	if _screen.is_auto_end_pending() or _battle().get_active_side() != 0 or _screen.is_busy():
		push_error("A tap in the beat should hold the end of the phase")
		return false
	_screen.press_button(&"end_turn")
	if not await _wait_idle():
		return false
	if _battle().get_round() != 2 or _battle().get_active_side() != 0:
		push_error("Kết lượt should lead to our phase of round 2")
		return false
	if not await _play_our_turn():
		return false
	for frame: int in MAX_FRAMES:
		if _battle().is_finished() or (_battle().get_round() == 3 and _battle().get_active_side() == 0 and not _screen.is_busy()):
			break
		await process_frame
	if not _battle().is_finished() and (_battle().get_round() != 3 or _battle().get_active_side() != 0):
		push_error("The phase should have ended by itself (round %d, side %d)" % [_battle().get_round(), _battle().get_active_side()])
		return false
	return true


# Every leader of ours: strike if it can (tap it, tap the enemy, tap it
# again), else walk towards the enemy (tap it, tap the cell) and, if that
# still leaves it something to do, wait. Counts the taps.
func _play_our_turn() -> bool:
	for leader: int in _our_leaders():
		if _battle().is_finished():
			return true
		if not _battle().can_act(leader):
			continue
		_tap_cell(_cell(leader))
		var targets := _battle().get_strike_targets(leader)
		if not targets.is_empty():
			var target: int = targets[0]
			_tap_cell(_cell(target))
			if _screen.get_mode() != TacticsScreen.Mode.FORECAST:
				push_error("A tap on a red-ringed enemy should show the forecast")
				return false
			_tap_cell(_cell(target))
		elif _battle().can_move(leader):
			_tap_cell(_toward_enemy(leader))
		if not await _wait_idle():
			return false
		if _battle().is_finished():
			return true
		if _battle().can_act(leader) and _screen.get_selected() == leader and _screen.get_map().get_piece(leader).is_done == false:
			_taps += 1
			_screen.press_button(&"wait")
			if not await _wait_idle():
				return false
	return true


func _tap_cell(cell: Vector2i) -> void:
	_taps += 1
	_screen.tap_cell(cell)


func _toward_enemy(leader: int) -> Vector2i:
	var from := _cell(leader)
	var goal := from
	for unit: Dictionary in _battle().get_units():
		if unit["role"] == &"leader" and unit["side"] == 1 and unit["alive"]:
			goal = unit["cell"]
	var best := from
	for cell: Vector2i in _battle().get_reachable_cells(leader):
		if _unit_at(cell) < 0 and absi(cell.x - goal.x) + absi(cell.y - goal.y) < absi(best.x - goal.x) + absi(best.y - goal.y):
			best = cell
	return best


# Full turns of three leaders until one where each strikes an enemy: the
# taps it took (the old screen took 5 a leader and 1 for "Hết lượt").
func _check_tap_count() -> bool:
	await _open(true)
	_screen.auto_end = true
	for turn: int in 8:
		if _battle().is_finished():
			break
		var leaders := _our_leaders()
		var all_strike := leaders.size() == 3
		for leader: int in leaders:
			if _battle().get_strike_targets(leader).is_empty():
				all_strike = false
		_taps = 0
		var round_number := _battle().get_round()
		if not await _play_our_turn():
			return false
		for frame: int in MAX_FRAMES:
			if _battle().is_finished() or (_battle().get_round() > round_number and _battle().get_active_side() == 0 and not _screen.is_busy()):
				break
			await process_frame
		print("Round %d: %d leaders, %s, %d taps for the whole turn" % [round_number, leaders.size(), "each strikes" if all_strike else "some only walk", _taps])
		if all_strike:
			if _taps != 9:
				push_error("Three move-and-attack orders should take 9 taps, took %d" % _taps)
				return false
			return true
	print("No turn had all three leaders able to strike; counts above")
	return true


# Nothing on the screen is cut or too small: every hint fits the top bar,
# every unit's card shows its first two lines whole (a wavering soldier's
# line included), order names fit their buttons, every visible label is at
# least GameTheme.SMALL_FONT_SIZE and every button at least 88 px tall.
func _check_text_fits() -> bool:
	await _open(true)
	var hint_keys: Array[String] = []
	var file := FileAccess.open("res://Locale/strings.csv", FileAccess.READ)
	while not file.eof_reached():
		var key := file.get_csv_line()[0]
		if key.begins_with("TACTICS_HINT_") or key.begins_with("TACTICS_END_") or key == "TACTICS_RETREAT_CONFIRM":
			hint_keys.append(key)
	var hint := _hint_label()
	for key: String in hint_keys:
		if not _fits_one_line(hint, tr(key)):
			return _fail("the hint %s fits the top bar: %s" % [key, tr(key)])
	var panel := _screen.get_panel()
	for unit: Dictionary in _battle().get_units():
		_screen.select_unit(unit["index"])
		await process_frame
		var shown := panel.get_shown_card_lines()
		var texts := panel.get_card_texts()
		if shown.size() < 2 or shown[0] != texts[2] or shown[1] != texts[3]:
			return _fail("unit %d's card shows its first two lines whole: %s" % [unit["index"], texts])
		if not await _check_labels():
			return false
	var lines: Array[String] = [tr("TACTICS_SOLDIER_OF_FORMAT") % "Nguyệt Thương", "", tr("KEYWORD_LONG_WEAPON") + ": " + tr("KEYWORD_LONG_WEAPON_DESC"), tr("TACTICS_TERRAIN_FORMAT") % "Đồng bằng (Đi 1)"]
	for incident: TacticsIncidentData in _screen.catalog.incident_rules.incidents:
		lines[1] = tr("TACTICS_WAVERING_LINE_FORMAT") % [tr(incident.name_key), tr(String(incident.name_key) + "_HINT")]
		panel.show_card("Binh khiên", Color.WHITE, "Máu 284/440 · Dấu: 2", lines)
		await process_frame
		var shown := panel.get_shown_card_lines()
		if shown.size() < 2 or shown[1] != lines[1]:
			return _fail("the wavering line shows whole: %s" % lines[1])
	return await _check_labels()


func _hint_label() -> Label:
	for label: Label in _screen.find_children("*", "Label", true, false):
		if label.text == _screen.get_hint():
			return label
	return null


func _fits_one_line(label: Label, text: String) -> bool:
	var font := label.get_theme_font(&"font")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size(&"font_size")).x <= label.size.x + 0.5


# Every visible label is big enough and, if it is one line, shows its text
# whole; every visible button is tall enough and fits its text.
func _check_labels() -> bool:
	await process_frame
	for node: Node in _screen.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree() or control.get_global_rect().size.x <= 0.0:
			continue
		var label := control as Label
		if label != null and label.text != "":
			var font_px := label.get_theme_font_size(&"font_size")
			if font_px < GameTheme.SMALL_FONT_SIZE:
				return _fail("%s is %d px, under %d" % [label.text, font_px, GameTheme.SMALL_FONT_SIZE])
			if label.autowrap_mode == TextServer.AUTOWRAP_OFF and not _fits_one_line(label, label.text):
				return _fail("%s fits its label" % label.text)
			if label.autowrap_mode != TextServer.AUTOWRAP_OFF and label.max_lines_visible > 0 and label.get_line_count() > label.max_lines_visible:
				return _fail("%s fits in %d lines" % [label.text, label.max_lines_visible])
			var clip := _clipping_parent(label)
			if clip != null and not clip.get_global_rect().grow(1.0).encloses(label.get_global_rect()):
				return _fail("%s is cut by %s (%s outside %s)" % [label.text, clip.name, label.get_global_rect(), clip.get_global_rect()])
		var button := control as Button
		if button != null:
			if button.size.y < 88.0:
				return _fail("the button %s is %.0f px tall, under 88" % [button.text, button.size.y])
			var font := button.get_theme_font(&"font")
			if button.text != "" and font.get_string_size(tr(button.text), HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size(&"font_size")).x > button.size.x - 8.0:
				return _fail("the button %s shows its text whole" % tr(button.text))
	for order: StringName in _screen.get_panel().get_order_buttons():
		var button := _screen.get_panel().get_order_buttons()[order]
		var name := tr("ORDER_" + String(order).get_slice(".", 1).to_upper())
		if button.is_visible_in_tree() and button.get_theme_default_font().get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, GameTheme.SMALL_FONT_SIZE).x > button.size.x - 8.0:
			return _fail("the order %s fits its button" % name)
	return true


func _fail(message: String) -> bool:
	push_error("Tactics feel test: " + message)
	return false


func _clipping_parent(control: Control) -> Control:
	var parent := control.get_parent() as Control
	while parent != null and not parent.clip_contents:
		parent = parent.get_parent() as Control
	return parent
