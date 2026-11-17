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
# small font size; every button is at least 88 px tall. A float over a
# piece at the edge of the view stays in the view and is never smaller
# than the small font.

const SCENARIO_PATH: String = "res://Data/Tactics/Scenarios/river_crossing.tres"
const NIGHT_SCENARIO_PATH: String = "res://Data/Tactics/Scenarios/night_raid.tres"
const ROAD_SCENARIO_PATH: String = "res://Data/Tactics/Scenarios/supply_road.tres"
const RING_SCENARIO_PATH: String = "res://Data/Tactics/Scenarios/broken_ring.tres"
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
## Taps that closed a leader that struck with move points left.
var _closing_taps: int = 0


func _initialize() -> void:
	TranslationServer.set_locale("vi")
	# First-time tips are remembered here, never in the player's settings.
	RunSettings.path = "user://settings_tactics_feel_test.json"
	DirAccess.remove_absolute(RunSettings.path)
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
	var checks: Array[Callable] = [_check_zoom, _check_idle_frames, _check_fog_redraws, _check_night_objective, _check_pan, _check_tap_and_drag, _check_pinch_and_whole_map, _check_corner_buttons, _check_auto_end, _check_tap_count, _check_text_fits, _check_site_text, _check_banner_titles, _check_floats, _check_hidden_steps, _check_tip_place, _check_convoy_tap, _check_framing]
	for check: Callable in checks:
		if not await check.call():
			push_error("Tactics feel test failed in %s" % check.get_method())
			return false
	return true


func _open(is_instant: bool, path: String = SCENARIO_PATH) -> void:
	if _screen != null:
		_screen.queue_free()
		await process_frame
	_screen = TacticsScreen.new()
	_screen.scenario = load(path) as TacticsScenarioData
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


# A first-time tip never covers a unit of ours on screen (the supply road
# and the broken ring start with our squads on the map's bottom rows, where
# the tip used to sit, and with the selected leader there), and the next tap
# anywhere lets it go.
func _check_tip_place() -> bool:
	for path: String in [ROAD_SCENARIO_PATH, RING_SCENARIO_PATH]:
		DirAccess.remove_absolute(RunSettings.path)
		await _open(true, path)
		var tips := _screen.get_tips()
		if tips.get_shown() != &"fog":
			return _fail("%s: the fog tip should show at the start, not \"%s\"" % [path, tips.get_shown()])
		await create_timer(TacticsTip.IN_SEC + 0.05).timeout
		if not _is_tip_clear(path + " at the start"):
			return false
		var leader := _our_leaders()[0]
		_screen.select_unit(leader)
		await create_timer(TacticsMapView.CAMERA_SEC + TacticsTip.MOVE_SEC + 0.1).timeout
		if not _is_tip_clear(path + " with a leader selected"):
			return false
		var shown := tips.get_shown()
		var press_at := root.get_final_transform() * (_screen.get_tips().get_box_rect().get_center())
		_press(press_at, true)
		_press(press_at, false)
		await create_timer(TacticsTip.DISMISS_SEC + 0.05).timeout
		if tips.get_shown() == shown:
			return _fail("%s: a tap should let the \"%s\" tip go" % [path, shown])
	return true


# A tap on the cart shows how it rolls, the road left and this phase's
# walk, with "Xe dừng"; pressed, the cart waits, stays selected and the
# button turns to "Xe đi".
func _check_convoy_tap() -> bool:
	await _open(true, ROAD_SCENARIO_PATH)
	var cart: int = _battle().get_objective_state()["convoy"]
	var at := _cell_point(_cell(cart))
	_press(at, true)
	_press(at, false)
	await process_frame
	if _screen.get_selected() != cart:
		return _fail("a tap on the cart should select it")
	var road := tr("TACTICS_CONVOY_ROAD_FORMAT") % ((_battle().get_objective_state()["road_cells"] as Array).size() - 1 - (_battle().get_objective_state()["road_cells"] as Array).find(_cell(cart)))
	var walk := tr("TACTICS_CONVOY_WILL_GO_FORMAT") % (_battle().get_convoy_path().size() - 1)
	var lines := _screen.get_panel().get_shown_card_lines()
	if not (road in lines) or not (walk in lines):
		return _fail("the cart's card should say \"%s\" and \"%s\", got %s" % [road, walk, lines])
	if not _screen.get_panel().get_buttons().any(func(entry: Dictionary) -> bool: return entry["action"] == &"convoy_hold"):
		return _fail("the cart should offer \"Xe dừng\"")
	_screen.press_button(&"convoy_hold")
	await _wait_idle()
	if not _battle().get_objective_state()["convoy_holds"] or _screen.get_selected() != cart:
		return _fail("\"Xe dừng\" should hold the cart and keep it selected")
	if not _screen.get_panel().get_buttons().any(func(entry: Dictionary) -> bool: return entry["action"] == &"convoy_go"):
		return _fail("a held cart should offer \"Xe đi\"")
	if not (tr("TACTICS_CONVOY_HELD") in _screen.get_panel().get_shown_card_lines()):
		return _fail("a held cart's card should say it waits")
	return true


# Every map opens on a line between columns (the broken ring used to cut
# its left column of tokens in half) with our leaders in view, and the
# broken ring points at its exits out of view without a mark on a leader
# (its south exits' mark sat on Lạc Hồng).
func _check_framing() -> bool:
	for path: String in [SCENARIO_PATH, NIGHT_SCENARIO_PATH, ROAD_SCENARIO_PATH, RING_SCENARIO_PATH]:
		await _open(true, path)
		var map := _map()
		var cell_px := map.get_cell_px()
		var offset := map.get_camera_offset().x
		if absf(offset / cell_px - roundf(offset / cell_px)) > 0.01:
			return _fail("%s opens with a column cut in half (offset %.1f, cell %.1f)" % [path, offset, cell_px])
		for leader: int in _our_leaders():
			if not map.is_in_view(map.cell_to_local(_cell(leader))):
				return _fail("%s opens with leader %d out of view" % [path, leader])
		if path == RING_SCENARIO_PATH:
			var exits: Array = _battle().get_objective_state()["exit_cells"]
			var pointed := map.get_edge_marks().filter(func(mark: Dictionary) -> bool: return exits.has(mark["cell"]))
			var out_of_view := exits.filter(func(cell: Vector2i) -> bool: return not map.is_in_view(map.cell_to_local(cell)))
			if not out_of_view.is_empty() and pointed.is_empty():
				return _fail("the broken ring's exits out of view should get an edge mark")
		# A mark on the view's edge never sits on one of our leaders.
		for mark: Dictionary in map.get_edge_marks():
			for leader: int in _our_leaders():
				var at := map.board_to_view(map.get_piece(leader).position)
				if at.distance_to(mark["at"]) < TacticsMapView.EDGE_MARK_PX + cell_px * 0.3:
					return _fail("%s opens with an edge mark at %s on leader %d at %s" % [path, mark["at"], leader, at])
	return true


func _is_tip_clear(label: String) -> bool:
	var box := _screen.get_tips().get_box_rect()
	var map := _map()
	var view := Rect2(map.position, map.size)
	for piece: TacticsPieceView in map.get_pieces():
		if not piece.visible or piece.side != 0:
			continue
		var cell := Vector2.ONE * map.get_cell_px()
		var rect := Rect2(map.position + map.board_to_view(piece.position) - cell / 2.0, cell).intersection(view)
		if rect.has_area() and rect.grow(-4.0).intersects(box):
			return _fail("%s: the tip %s covers unit %d at %s" % [label, box, piece.unit_index, rect])
	return true


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
	# The new maps, their sites, road, exits and wave marks drawn, with the
	# objective card open: still too, once the banners are gone.
	for path: String in ["res://Data/Tactics/Scenarios/city_defense.tres", "res://Data/Tactics/Scenarios/supply_road.tres", "res://Data/Tactics/Scenarios/broken_ring.tres"]:
		await _open(false, path)
		var banner: Control = _screen.find_children("*", "TacticsBanner", true, false)[0]
		for frame: int in MAX_FRAMES:
			if not banner.visible:
				break
			await process_frame
		_screen.show_objective()
		await create_timer(0.6).timeout
		draws = _map().get_layer_draw_count()
		counts = await _count_changed_frames(1.0)
		if counts[0] > 0 or _map().get_layer_draw_count() != draws:
			push_error("An idle %s changed %d of %d frames (%d layer draws)" % [path.get_file(), counts[0], counts[1], _map().get_layer_draw_count() - draws])
			return false
	return true


# The fog texture is written only when what we see changes: a tap or an
# idle map writes nothing; a walk that reveals blends once, in the walk's
# own frames, then the map is still again.
func _check_fog_redraws() -> bool:
	await _open(false)
	var map := _map()
	for frame: int in MAX_FRAMES:
		if not map.is_fog_blending():
			break
		await process_frame
	if map.get_fog().is_empty() or map.get_fog() != _battle().get_fog_cells(0):
		push_error("The river crossing should open with the battle's fog")
		return false
	var writes := map.fog_write_count
	var changes := map.fog_change_count
	var leader := _our_leaders()[0]
	_screen.select_unit(leader)
	await create_timer(0.6).timeout
	var counts := await _count_changed_frames(0.5)
	if map.fog_write_count != writes or counts[0] > 0:
		push_error("A selection on an idle map wrote the fog %d times and changed %d frames" % [map.fog_write_count - writes, counts[0]])
		return false
	var before := _battle().get_fog_cells(0)
	var far := _cell(leader)
	for cell: Vector2i in _battle().get_reachable_cells(leader):
		if _unit_at(cell) < 0 and cell.y < far.y:
			far = cell
	_screen.move_to(far)
	# The reveal blends within the walk's own frames: when the walk (and its
	# squad) has played, the fog is still.
	var is_blending_after := false
	for frame: int in MAX_FRAMES:
		if not _screen.is_busy():
			is_blending_after = map.is_fog_blending()
			break
		await process_frame
	for frame: int in MAX_FRAMES:
		if not map.is_fog_blending():
			break
		await process_frame
	if _battle().get_fog_cells(0) == before:
		push_error("The walk to %s should have revealed cells" % far)
		return false
	# One blend for the whole walk, however many pieces' sight changed.
	var blend_writes := map.fog_write_count - writes
	var blends := map.fog_change_count - changes
	if blends != 1 or blend_writes < 2 or is_blending_after:
		push_error("A walk's reveal should blend once within the walk, got %d blends (%d writes), still blending after it: %s" % [blends, blend_writes, is_blending_after])
		return false
	if map.get_fog() != _battle().get_fog_cells(0):
		push_error("After the walk the fog shown should be the battle's")
		return false
	writes = map.fog_write_count
	await create_timer(0.6).timeout
	counts = await _count_changed_frames(0.5)
	if map.fog_write_count != writes or counts[0] > 0:
		push_error("After the reveal the map should be still: %d fog writes, %d frames changed" % [map.fog_write_count - writes, counts[0]])
		return false
	print("Fog: %d blend in the walk (%d writes, headless frames), none idle" % [blends, blend_writes])
	return true


# At the night raid's start the objective lies in the dark, out of view: it
# is never covered as never seen, and a gold mark on the view's edge points
# at it; the idle map still draws nothing.
func _check_night_objective() -> bool:
	await _open(false, NIGHT_SCENARIO_PATH)
	var map := _map()
	for frame: int in MAX_FRAMES:
		if not map.is_fog_blending():
			break
		await process_frame
	var objective: Vector2i = _battle().get_objective_state()["cell"]
	if _battle().get_fog_cells(0)[objective.y * map.map_width + objective.x] != 0:
		push_error("The night raid's objective should start unseen")
		return false
	if map.get_fog_color(objective).is_equal_approx(TacticsMapView.FOG_NEVER_COLOR):
		push_error("The objective is known from the map: it should not be covered as never seen")
		return false
	if map.is_in_view(map.cell_to_local(objective)):
		push_error("The night raid should open with the objective out of view")
		return false
	var pointing := map.get_edge_marks().filter(func(mark: Dictionary) -> bool: return mark["is_objective"])
	if pointing.size() != 1 or pointing[0]["cell"] != objective:
		push_error("A mark on the view's edge should point at the objective, got %s" % [map.get_edge_marks()])
		return false
	# The bubble's pointer reaches 12 px past it: it stays inside the map,
	# not under the top bar.
	var room := Rect2(Vector2.ZERO, map.size).grow(-TacticsMapView.EDGE_MARK_PX - 12.0)
	if not room.has_point(pointing[0]["at"]):
		push_error("The objective's edge mark at %s would poke out of the %s map" % [pointing[0]["at"], map.size])
		return false
	_screen.select_unit(_our_leaders()[0])
	await create_timer(0.6).timeout
	var draws := map.get_layer_draw_count()
	var counts := await _count_changed_frames(0.5)
	if counts[0] > 0 or map.get_layer_draw_count() != draws:
		push_error("An idle night map changed %d frames and redrew %d layers" % [counts[0], map.get_layer_draw_count() - draws])
		return false
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
			if empty.x < 0 and _unit_at(cell) < 0 and map.is_in_view(map.cell_to_local(cell)) and map.is_in_view(map.cell_to_local(cell) + Vector2(0, 150) / map.get_zoom()) and not _is_under_button(cell):
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


# Is the cell's centre under a button laid over the map?
func _is_under_button(cell: Vector2i) -> bool:
	var map := _map()
	var at := map.get_global_rect().position + map.board_to_view(map.cell_to_local(cell))
	for button: Control in [_screen.get_environment_chip(), map.get_whole_map_button()]:
		if button.is_visible_in_tree() and button.get_global_rect().grow(8.0).has_point(at):
			return true
	return false


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


# With weather and a time of day the chip that tells them and the
# whole-map button both sit over the map: neither covers the other, and a
# finger on the whole-map button shows the whole map.
func _check_corner_buttons() -> bool:
	await _open(true, NIGHT_SCENARIO_PATH)
	var map := _map()
	var chip := _screen.get_environment_chip()
	var whole := map.get_whole_map_button()
	if not chip.is_visible_in_tree() or not whole.is_visible_in_tree():
		return _fail("The night raid should show the weather chip and the whole-map button")
	if chip.get_global_rect().intersects(whole.get_global_rect()):
		return _fail("The weather chip %s covers the whole-map button %s" % [chip.get_global_rect(), whole.get_global_rect()])
	var at := root.get_final_transform() * whole.get_global_rect().get_center()
	_press(at, true)
	_press(at, false)
	await process_frame
	if not map.is_whole_map():
		return _fail("A tap on the whole-map button should show the whole map")
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
			# A leader that struck with move points left may still walk
			# (the open turn): closing it is one more tap.
			if _battle().has_attacked(leader) and _battle().can_move(leader):
				_closing_taps += 1
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
		_closing_taps = 0
		var round_number := _battle().get_round()
		# Under fog a strike's walk may stop at a hidden enemy (an ambush):
		# that turn is not a plain three-strike turn.
		var ambushes := [0]
		var count_ambush := func(type: StringName) -> void: ambushes[0] += 1 if type == &"ambushed" else 0
		_screen.get_playback().step_started.connect(count_ambush)
		if not await _play_our_turn():
			return false
		_screen.get_playback().step_started.disconnect(count_ambush)
		all_strike = all_strike and ambushes[0] == 0
		for frame: int in MAX_FRAMES:
			if _battle().is_finished() or (_battle().get_round() > round_number and _battle().get_active_side() == 0 and not _screen.is_busy()):
				break
			await process_frame
		print("Round %d: %d leaders, %s, %d taps for the whole turn%s" % [round_number, leaders.size(), "each strikes" if all_strike else "some only walk", _taps, ", ambushed" if ambushes[0] > 0 else ""])
		if all_strike:
			if _taps != 9 + _closing_taps:
				push_error("Three move-and-attack orders should take 9 taps (and %d to close leaders with points left), took %d" % [_closing_taps, _taps])
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
		# Its own reason, and the one for a soldier its leader does not see.
		for why: String in [tr(String(incident.name_key) + "_HINT"), tr("TACTICS_WAVERING_UNSEEN_HINT")]:
			lines[1] = tr("TACTICS_WAVERING_LINE_FORMAT") % [tr(incident.name_key), why]
			panel.show_card("Binh khiên", Color.WHITE, "Máu 284/440 · Dấu: 2", lines)
			await process_frame
			var shown := panel.get_shown_card_lines()
			if shown.size() < 2 or shown[1] != lines[1]:
				return _fail("the wavering line shows whole: %s" % lines[1])
	return await _check_labels()


# The site choices, a recruit's pick and the objective card's buttons fit
# whole in a row of four: first a village's choices on the supply road
# opened by its button, then every site's row and the cart's.
func _check_site_text() -> bool:
	await _open(true, "res://Data/Tactics/Scenarios/supply_road.tres")
	var opened := false
	for unit: Dictionary in _battle().get_units():
		if opened or unit["side"] != 0 or unit["role"] != &"leader":
			continue
		for site: Dictionary in _battle().get_sites(0):
			if opened or site["kind"] != &"site_kind.village":
				continue
			for cell: Vector2i in _battle().get_reachable_cells(unit["index"]):
				if absi(cell.x - site["cell"].x) + absi(cell.y - site["cell"].y) > int(site["reach_cells"]):
					continue
				_screen.select_unit(unit["index"])
				_screen.move_to(cell)
				await _wait_idle()
				_screen.press_button(&"site")
				await process_frame
				opened = _screen.get_shown_site() >= 0
				if opened:
					break
				_screen.undo()
				await _wait_idle()
	if not opened:
		return _fail("a leader on the supply road reaches the village and opens its choices")
	if not await _check_labels():
		return false
	var rows: Array = [["site_heal", "SITE_CHOICE_HEAL", "site_recruit", "SITE_CHOICE_RECRUIT", "site_loot", "SITE_CHOICE_LOOT"],
		["site_charge", "SITE_CHOICE_CHARGE", "site_calm", "SITE_CHOICE_CALM", "site_bless", "SITE_CHOICE_BLESS"],
		["site_capture", "SITE_CHOICE_CAPTURE"], ["recruit_0", "TROOP_MILITIA", "recruit_1", "TROOP_HUNTER"],
		["convoy_hold", "BUTTON_CONVOY_HOLD"], ["convoy_go", "BUTTON_CONVOY_GO"]]
	for row: Array in rows:
		var buttons: Array[Dictionary] = []
		for index: int in range(0, row.size(), 2):
			buttons.append({"action": StringName(row[index]), "text": row[index + 1]})
		buttons.append({"action": &"cancel" if not String(row[0]).begins_with("convoy") else &"end_turn", "text": "BUTTON_CANCEL" if not String(row[0]).begins_with("convoy") else "BUTTON_END_TURN", "primary": String(row[0]).begins_with("convoy")})
		_screen.get_panel().set_buttons(buttons)
		await process_frame
		await process_frame
		if not await _check_labels():
			return false
	return true


# Every banner title fits across the map (the wave warning's ran off both
# edges), at no less than the small font size.
func _check_banner_titles() -> bool:
	await _open(true)
	var banner: TacticsBanner = _screen.find_children("*", "TacticsBanner", true, false)[0]
	var titles: Array[String] = [tr("TACTICS_PHASE_PLAYER"), tr("TACTICS_PHASE_ENEMY")]
	var file := FileAccess.open("res://Locale/strings.csv", FileAccess.READ)
	while not file.eof_reached():
		var key := file.get_csv_line()[0]
		if key.begins_with("TACTICS_BANNER_") and not key.ends_with("_FORMAT") and not key.ends_with("_DETAIL"):
			titles.append(tr(key))
	for weather: StringName in [&"weather.clear", &"weather.rain", &"weather.fog", &"weather.wind"]:
		titles.append(tr("TACTICS_WEATHER_SOON_FORMAT") % TacticsText.new(_screen.catalog).environment_name(&"weather", weather))
	for title: String in titles:
		banner.present(title, "", true)
		await process_frame
		for label: Label in banner.find_children("*", "Label", true, false):
			if label.text != title:
				continue
			var font_px := label.get_theme_font_size(&"font_size")
			if font_px < GameTheme.SMALL_FONT_SIZE or label.get_theme_font(&"font").get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x > banner.size.x - 16.0:
				return _fail("the banner title %s fits across the map (%d px)" % [title, font_px])
	banner.dismiss()
	return true


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
			# The text is drawn inside the style's margins (16 px a side).
			var box := button.get_theme_stylebox(&"disabled" if button.disabled else &"normal")
			var room := minf(button.size.x - 8.0, button.size.x - box.get_margin(SIDE_LEFT) - box.get_margin(SIDE_RIGHT))
			if button.text != "" and font.get_string_size(tr(button.text), HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size(&"font_size")).x > room:
				return _fail("the button %s shows its text whole" % tr(button.text))
	for order: StringName in _screen.get_panel().get_order_buttons():
		var button := _screen.get_panel().get_order_buttons()[order]
		var name := tr("ORDER_" + String(order).get_slice(".", 1).to_upper())
		if button.is_visible_in_tree() and button.get_theme_default_font().get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, GameTheme.SMALL_FONT_SIZE).x > button.size.x - 8.0:
			return _fail("the order %s fits its button" % name)
	return true


# Zoomed in with the board's left and top edges out of view, a float over
# a piece on the left column and the top row is drawn inside the view;
# more text there stacks down instead of covering it; a float asked for
# at 18 px is drawn at the small font size.
func _check_floats() -> bool:
	await _open(true)
	var map := _map()
	map.zoom_to(map.get_whole_zoom() * 1.4, map.cell_to_local(Vector2i(map.map_width / 2, map.map_height / 2)), false)
	await process_frame
	var view_left := map.view_to_board(Vector2.ZERO)
	if view_left.x <= 0.0 or view_left.y <= 0.0:
		return _fail("the zoomed view should hide the board's left and top edges, got %s" % view_left)
	var label := map.float_text(Vector2(map.view_to_board(Vector2.ZERO).x, view_left.y + 4.0), "Tẩu thoát", Color.WHITE, 30, 44.0, 1.4)
	var small := map.float_text(map.cell_to_local(Vector2i(map.map_width / 2, map.map_height / 2)), "Đã yên", Color.WHITE, 18)
	var view_rect := Rect2(view_left, map.size / map.get_zoom())
	var is_inside := view_rect.encloses(Rect2(label.position, label.size))
	var font_px := small.get_theme_font_size(&"font_size")
	# More text at the same corner stacks down, never over the first.
	var stacked: Array[Label] = [label]
	for text: String in ["Dấu: Tẩu thoát", "-220"]:
		stacked.append(map.float_text(Vector2(view_left.x + 30.0, view_left.y + 4.0), text, Color.WHITE, 22))
	var is_apart := true
	for index: int in stacked.size():
		for other: int in range(index + 1, stacked.size()):
			is_apart = is_apart and not Rect2(stacked[index].position, stacked[index].size).grow(-5.0).intersects(Rect2(stacked[other].position, stacked[other].size).grow(-5.0))
	for each: Label in stacked:
		each.free()
	small.free()
	if not is_apart:
		return _fail("floats at the top of the view should stack, not cover each other")
	if not is_inside:
		return _fail("a float at the view's corner should be drawn inside the view %s" % view_rect)
	if font_px < GameTheme.SMALL_FONT_SIZE:
		return _fail("a float is %d px, under %d" % [font_px, GameTheme.SMALL_FONT_SIZE])
	return true


# An enemy we do not see gives nothing away while the enemy plays: its
# incident, charge, wait or death plays no step (no ring, word, sound or
# pause), while the same steps of a unit we see play.
func _check_hidden_steps() -> bool:
	await _open(true)
	var hidden := -1
	var seen := -1
	for unit: int in _battle().get_unit_count():
		var state := _battle().get_unit_state(unit)
		if state["side"] == 0 or not state["alive"] or state["role"] == &"leader":
			continue
		if hidden < 0 and not _battle().is_unit_seen(0, unit):
			hidden = unit
		if seen < 0 and _battle().is_unit_seen(0, unit):
			seen = unit
	if hidden < 0:
		return _fail("the river crossing should open with an enemy soldier out of sight")
	var playback := _screen.get_playback()
	var played: Array[StringName] = []
	var on_step := func(type: StringName) -> void: played.append(type)
	playback.step_started.connect(on_step)
	var fx_before := _map().get_fx_layer().get_child_count()
	await playback.play(_private_steps(hidden))
	var hidden_played := played.duplicate()
	var fx_after := _map().get_fx_layer().get_child_count()
	played.clear()
	if seen >= 0:
		await playback.play(_private_steps(seen))
	playback.step_started.disconnect(on_step)
	if not hidden_played.is_empty() or fx_after != fx_before:
		return _fail("a hidden enemy's steps played %s and added %d effects" % [hidden_played, fx_after - fx_before])
	if seen >= 0 and played.is_empty():
		return _fail("a seen enemy's steps should play")
	return true


func _private_steps(unit: int) -> Array:
	return [
		{"type": &"incident_fired", "unit": unit, "incident": &"incident.flee", "is_good": false},
		{"type": &"leader_waited", "unit": unit},
		{"type": &"damage_dealt", "source": -1, "target": unit, "amount": 5, "hp_after": 10, "source_id": &"zone.fire"},
	]


func _fail(message: String) -> bool:
	push_error("Tactics feel test: " + message)
	return false


func _clipping_parent(control: Control) -> Control:
	var parent := control.get_parent() as Control
	while parent != null and not parent.clip_contents:
		parent = parent.get_parent() as Control
	return parent
