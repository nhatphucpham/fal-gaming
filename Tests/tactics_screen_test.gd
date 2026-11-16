extends SceneTree

# Headless test of the tactics screen on the river crossing, through its
# public methods and the map's signals (the same ones its taps call): a tap
# off the map selection undoes it, dragging a leader shows ghosts without
# changing the battle, a tap on a blue cell moves at once and the leader
# stays selected with the cells its points left reach and says so on its
# card, a second move spends more, and "Hoàn tác" takes them back one at a
# time to the exact state, one tap on the order row changes an order,
# a tap on an enemy shows the forecast from the cell the battle picks and a
# second tap walks there and attacks, a charged skill is aimed, previewed
# and cast, and the battle is then played to victory by a simple scripted
# policy (skill when ready, else strike a leader, else a soldier, else
# march on the nearest enemy leader). Playback runs in instant mode; every
# close-up is still counted. The result banner's button asks for the title.
# The first select, move and order change offer their first-time tip once,
# remembered in the settings.

const SCENARIO_PATH: String = "res://Data/Tactics/Scenarios/river_crossing.tres"
const MAX_PHASES: int = 40
const MAX_FRAMES_IDLE: int = 600
const SETTINGS_PATH: String = "user://settings_tactics_screen_test.json"

var _screen: TacticsScreen
var _went_home: bool = false
var _skills_cast: int = 0
var _attacks: int = 0
var _settled_phases: int = 0


func _initialize() -> void:
	TranslationServer.set_locale("vi")
	RunSettings.path = SETTINGS_PATH
	DirAccess.remove_absolute(SETTINGS_PATH)
	var ok := await _run()
	if _screen != null:
		_screen.queue_free()
	await process_frame
	DirAccess.remove_absolute(SETTINGS_PATH)
	if ok:
		print("Tactics screen test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not ClassDB.class_exists("TacticsBattle"):
		push_error("TacticsBattle is missing: build the GDExtension (scons) before importing")
		return false
	_screen = TacticsScreen.new()
	_screen.scenario = load(SCENARIO_PATH) as TacticsScenarioData
	_screen.is_instant = true
	# The scripted policy ends each phase itself.
	_screen.auto_end = false
	_screen.size = Vector2(720, 1280)
	_screen.home_requested.connect(func() -> void: _went_home = true)
	root.add_child(_screen)
	await process_frame
	if not await _idle():
		return false
	var checks: Array[Callable] = [_check_start, _check_undo, _check_move, _check_forecast_and_order, _check_tips, _check_moved_out_of_reach, _check_battle_to_victory]
	for check: Callable in checks:
		if not await check.call():
			push_error("Tactics screen test failed in %s" % check.get_method())
			return false
	return true


func _idle() -> bool:
	for frame: int in MAX_FRAMES_IDLE:
		if not _screen.is_busy():
			return true
		await process_frame
	push_error("The screen stayed busy")
	return false


func _battle() -> TacticsBattle:
	return _screen.get_battle()


func _our_leaders() -> Array[int]:
	var leaders: Array[int] = []
	for unit: Dictionary in _battle().get_units():
		if unit["role"] == &"leader" and unit["side"] == 0 and unit["alive"]:
			leaders.append(unit["index"])
	return leaders


func _cell(unit: int) -> Vector2i:
	return _battle().get_unit_state(unit)["cell"]


# Round 1, our phase, a piece per unit and the enemy's intents shown.
func _check_start() -> bool:
	if _battle().get_round() != 1 or _battle().get_active_side() != 0:
		push_error("The battle should start in round 1 on our side")
		return false
	if _screen.get_map().get_pieces().size() != _battle().get_unit_count():
		push_error("Every unit should have a piece")
		return false
	# The river crossing has fog of war: the intents shown are those of the
	# enemy leaders we see, and every hidden enemy is off the board. The
	# intents of a clear battle are checked in the input test.
	if _screen.get_map().get_intents().size() != _battle().get_enemy_intents().size():
		push_error("The enemy's known intents should be shown in our phase: %d shown, %d known" % [_screen.get_map().get_intents().size(), _battle().get_enemy_intents().size()])
		return false
	if _screen.get_map().get_fog() != _battle().get_fog_cells(0):
		push_error("The fog on the map should be the battle's")
		return false
	if not _screen.get_map().get_fog().has(0):
		push_error("The river crossing should open with cells never seen")
		return false
	for piece: TacticsPieceView in _screen.get_map().get_pieces():
		var unit := piece.unit_index
		var seen: bool = _battle().get_unit_state(unit)["side"] == 0 or _battle().is_unit_seen(0, unit)
		if piece.visible != seen:
			push_error("Unit %d is seen=%s but its piece visible=%s" % [unit, seen, piece.visible])
			return false
	# Nobody has walked yet: even with no enemy in reach the screen does not
	# invite ending the turn.
	if not _check_end_turn_look() or _settled_phases != 0:
		push_error("At the start of the battle Kết lượt should not be the button to press")
		return false
	return _screen.get_mode() == TacticsScreen.Mode.IDLE


func _check_undo() -> bool:
	var leader := _our_leaders()[0]
	_screen.tap_cell(_cell(leader))
	if _screen.get_mode() != TacticsScreen.Mode.SELECTED or _screen.get_selected() != leader:
		push_error("A tap on our leader should select it")
		return false
	if (_screen.get_map().get_marks().get("reachable", []) as Array).is_empty():
		push_error("A selected leader should show where it can go")
		return false
	var labels := _button_actions()
	if not (labels.has(&"skill") and labels.has(&"wait") and labels.has(&"end_turn")) or labels.has(&"undo"):
		push_error("A selected leader should offer skill, wait and end turn (no undo yet), got %s" % [labels])
		return false
	if not _screen.get_panel().is_order_row_shown() or _screen.get_panel().get_order_buttons().size() != 5:
		push_error("A selected leader should show the row of five orders")
		return false
	if _screen.get_panel().get_current_order() != _battle().get_unit_state(leader)["order"]:
		push_error("The order row should outline the current order")
		return false
	# A plain cell it cannot reach: the selection goes away.
	var far := Vector2i(11, 0)
	_screen.tap_cell(far)
	if _screen.get_mode() != TacticsScreen.Mode.IDLE:
		push_error("A tap elsewhere should undo the selection")
		return false
	return true


# A leader that walked all its points away from the enemy, with nobody to
# strike: the hint offers only Undo or Wait, never "tap an enemy". Undone
# after, so the battle goes on as it was.
func _check_moved_out_of_reach() -> bool:
	var leader := _our_leaders()[1]
	var home := _cell(leader)
	var hash_before := _battle().get_state_hash()
	var enemy := _nearest_enemy_leader(leader)
	for hop: int in 4:
		if not _battle().can_move(leader):
			break
		_screen.tap_cell(_cell(leader))
		_screen.tap_cell(_farthest_reachable(leader, enemy))
		if not await _idle():
			return false
	if _battle().can_move(leader) or not _battle().get_strike_targets(leader).is_empty() or not _battle().can_undo_move(leader):
		return _fail("Leader %d should have walked out its points, out of reach, undoable" % leader)
	if _screen.get_selected() != leader:
		_screen.tap_cell(_cell(leader))
	if not _expect_hint("TACTICS_HINT_MOVED_NO_TARGET"):
		return false
	while _battle().can_undo_move(leader):
		_screen.press_button(&"undo")
		if not await _idle():
			return false
	if _cell(leader) != home or _battle().get_state_hash() != hash_before:
		return _fail("Undoing every step should bring leader %d home" % leader)
	_screen.cancel()
	return true


func _farthest_reachable(leader: int, from: Vector2i) -> Vector2i:
	var best := _cell(leader)
	for cell: Vector2i in _battle().get_reachable_cells(leader):
		if absi(cell.x - from.x) + absi(cell.y - from.y) > absi(best.x - from.x) + absi(best.y - from.y):
			best = cell
	return best


func _check_move() -> bool:
	var leader := _our_leaders()[0]
	var hash_before := _battle().get_state_hash()
	var home := _cell(leader)
	var target := _closest_reachable(leader, _nearest_enemy_leader(leader))
	# Press on the leader and drag: ghosts follow the finger, nothing moves.
	_screen.get_map().cell_held.emit(home)
	_screen.get_map().cell_held.emit(target)
	if _screen.get_mode() != TacticsScreen.Mode.MOVE_PREVIEW:
		push_error("Dragging a leader should preview the move")
		return false
	var ghosts: Array = _screen.get_map().get_marks().get("ghosts", [])
	if ghosts.size() != 1 + (_battle().get_unit_state(leader)["soldiers"] as Array).size():
		push_error("The preview should show a ghost for the leader and each soldier, got %d" % ghosts.size())
		return false
	if _battle().get_state_hash() != hash_before:
		push_error("A preview must not change the battle")
		return false
	_screen.get_map().hold_released.emit(home)
	if _screen.get_mode() != TacticsScreen.Mode.SELECTED or _battle().get_state_hash() != hash_before:
		push_error("Lifting the finger on the leader should keep it selected and still")
		return false
	# A tap on a blue cell next to the leader moves at once; the leader stays
	# selected with the blue cells its points left reach.
	var step := _step_toward(leader, target)
	_screen.tap_cell(step)
	if not await _idle():
		return false
	if _cell(leader) != step:
		push_error("The leader should stand on %s, not %s" % [step, _cell(leader)])
		return false
	var piece := _screen.get_map().get_piece(leader)
	if piece.position != _screen.get_map().cell_to_local(step):
		push_error("The leader's piece should be on its new cell")
		return false
	var left := _battle().get_move_points_left(leader)
	var reachable: Array = _screen.get_map().get_marks().get("reachable", [])
	if _screen.get_selected() != leader or not _expect_hint(_move_on_hint(leader)) or not _button_actions().has(&"undo") \
			or reachable != _battle().get_reachable_cells(leader) or reachable.is_empty() or piece.is_done:
		push_error("A leader with points left should stay selected, open, with its blue cells and undo")
		return false
	var turn_line: String = tr("TACTICS_TURN_FORMAT") % [left, _battle().get_unit_state(leader)["move_points"], tr("TACTICS_TURN_ATTACK_READY")]
	if not _screen.get_panel().get_shown_card_lines().has(turn_line):
		push_error("The card should say \"%s\", got %s" % [turn_line, _screen.get_panel().get_shown_card_lines()])
		return false
	# A second move with the points left, then two undos, one step each.
	var hash_mid := _battle().get_state_hash()
	var second := _closest_reachable(leader, _nearest_enemy_leader(leader))
	_screen.tap_cell(second)
	if not await _idle():
		return false
	if _cell(leader) != second or _battle().get_move_points_left(leader) >= left:
		push_error("A second tap on a blue cell should move on to %s with fewer points" % second)
		return false
	_screen.press_button(&"undo")
	if not await _idle():
		return false
	if _battle().get_state_hash() != hash_mid or _cell(leader) != step or not _button_actions().has(&"undo"):
		push_error("The first undo should go back one step, with one more to take back")
		return false
	_screen.press_button(&"undo")
	if not await _idle():
		return false
	if _battle().get_state_hash() != hash_before or _cell(leader) != home:
		push_error("Undo should give back the state before the move")
		return false
	if piece.position != _screen.get_map().cell_to_local(home) or not _battle().can_move(leader) or _button_actions().has(&"undo"):
		push_error("After undo the leader's piece should be home and free to move, nothing left to undo")
		return false
	# A drag released on the cell moves there.
	_screen.get_map().cell_held.emit(home)
	_screen.get_map().cell_held.emit(target)
	_screen.get_map().hold_released.emit(target)
	if not await _idle():
		return false
	if _cell(leader) != target:
		push_error("Releasing a drag on a blue cell should move there")
		return false
	# Moved as far as it goes toward the enemy: the hint speaks of moving on,
	# or (no points left) of attacking, undoing or waiting.
	if _screen.get_selected() != leader or not _expect_hint(_move_on_hint(leader) if _battle().can_move(leader) else _moved_hint(leader)):
		return false
	return true


# After a move with points left: red rings are only promised when there
# is an enemy to strike.
func _move_on_hint(leader: int) -> String:
	return "TACTICS_HINT_MOVE_ON" if not _battle().get_strike_targets(leader).is_empty() else "TACTICS_HINT_WALK_ONLY"


# After a move with no points left: "tap an enemy" only with one to strike.
func _moved_hint(leader: int) -> String:
	return "TACTICS_HINT_MOVED" if not _battle().get_strike_targets(leader).is_empty() else "TACTICS_HINT_MOVED_NO_TARGET"


# The free cell next to the leader closest to `goal`.
func _step_toward(leader: int, goal: Vector2i) -> Vector2i:
	var from := _cell(leader)
	var best := Vector2i(-1, -1)
	for cell: Vector2i in _battle().get_reachable_cells(leader):
		if absi(cell.x - from.x) + absi(cell.y - from.y) == 1 and (best.x < 0 or absi(cell.x - goal.x) + absi(cell.y - goal.y) < absi(best.x - goal.x) + absi(best.y - goal.y)):
			best = cell
	return best


func _expect_hint(key: String) -> bool:
	if _screen.get_hint() != tr(key):
		push_error("The hint should read \"%s\", not \"%s\"" % [tr(key), _screen.get_hint()])
		return false
	return true


# One tap on the order row sets an order: no picker in between, the
# leader stays selected and the map shows the new slots.
func _check_forecast_and_order() -> bool:
	var leader := _our_leaders()[0]
	_screen.select_unit(leader)
	_screen.get_panel().get_order_buttons()[&"order.flank"].pressed.emit()
	if not await _idle():
		return false
	if _battle().get_unit_state(leader)["order"] != &"order.flank":
		push_error("The order should now be flank")
		return false
	if _screen.get_selected() != leader or _screen.get_panel().get_current_order() != &"order.flank":
		push_error("The leader should stay selected with flank outlined")
		return false
	if _screen.get_panel().get_order_note() != tr("ORDER_FLANK_DESC"):
		push_error("The order row should describe flank, not \"%s\"" % _screen.get_panel().get_order_note())
		return false
	var slots: Array = _screen.get_map().get_marks().get("slots", [])
	if slots != _battle().get_formation_slots(leader):
		push_error("The map should show the flank slots %s, not %s" % [_battle().get_formation_slots(leader), slots])
		return false
	return true


# The commands above met three tips: the first on screen with its sound
# and text, the others waiting; each is saved when it shows and a new
# screen never offers a saved one again.
func _check_tips() -> bool:
	var tips := _screen.get_tips()
	var met: Array = RunSettings.load_seen_tips().map(func(id: String) -> StringName: return StringName(id.trim_prefix(TacticsTip.SETTINGS_PREFIX)))
	met.append_array(tips.get_pending())
	# The river crossing has fog of war: its tip comes with our first phase.
	if met != [&"fog", &"select", &"move", &"order"]:
		push_error("The fog, then the first select, move and order should each offer their tip once, got %s" % [met])
		return false
	if tr("TACTICS_TIP_FOG") == "TACTICS_TIP_FOG":
		return _fail("The fog tip has no text")
	if tips.get_shown() == &"fog" and tips.get_text() != tr("TACTICS_TIP_FOG"):
		push_error("The fog tip should read \"%s\", not \"%s\"" % [tr("TACTICS_TIP_FOG"), tips.get_text()])
		return false
	if tips.get_shown() == &"select" and tips.get_text() != tr("TACTICS_TIP_SELECT"):
		push_error("The select tip should read \"%s\", not \"%s\"" % [tr("TACTICS_TIP_SELECT"), tips.get_text()])
		return false
	var again := TacticsTip.new()
	root.add_child(again)
	# The first tip has been shown (and saved) by now.
	again.offer(met[0])
	var shown := again.get_shown()
	again.free()
	if shown != &"":
		push_error("A tip already shown should not show again")
		return false
	return tr("TACTICS_TIP_WAVER") != "TACTICS_TIP_WAVER" or _fail("The waver tip has no text")


func _fail(message: String) -> bool:
	push_error(message)
	return false


func _check_battle_to_victory() -> bool:
	var phases := 0
	while not _battle().is_finished() and phases < MAX_PHASES:
		for leader: int in _our_leaders():
			if _battle().is_finished():
				break
			if not await _command(leader):
				return false
		if _battle().is_finished():
			break
		if not _check_end_turn_look():
			return false
		_screen.press_button(&"end_turn")
		if not await _idle():
			return false
		phases += 1
	if not _battle().is_finished() or _battle().get_winner() != 0:
		push_error("The scripted battle should be won, finished=%s winner=%d reason=%s round=%d" % [_battle().is_finished(), _battle().get_winner(), _battle().get_end_reason(), _battle().get_round()])
		return false
	if _screen.get_mode() != TacticsScreen.Mode.ENDED:
		push_error("The screen should end with the battle")
		return false
	if _skills_cast == 0 or _attacks == 0:
		push_error("The battle should have used a skill and an attack (%d, %d)" % [_skills_cast, _attacks])
		return false
	if _settled_phases == 0:
		push_error("Some phase should end with only walks left")
		return false
	if _screen.get_playback().close_up_count == 0:
		push_error("A skill should open the close-up")
		return false
	print("Won by %s in round %d with %d skills, %d attacks, %d close-ups" % [_battle().get_end_reason(), _battle().get_round(), _skills_cast, _attacks, _screen.get_playback().close_up_count])
	_screen.get_result_banner().button_pressed.emit()
	if not _went_home:
		push_error("The result button should ask for the title")
		return false
	return true


# One leader's turn, through the screen: skill, attack or march.
func _command(leader: int) -> bool:
	if not _battle().can_act(leader):
		return true
	var skill_cells := _battle().get_skill_cells(leader)
	if not skill_cells.is_empty():
		var best := _best_skill_cell(leader, skill_cells)
		if best != Vector2i(-1, -1):
			return await _cast(leader, best)
	var target := _attack_target(leader)
	if target >= 0:
		return await _attack(leader, target)
	if _battle().can_move(leader):
		var goal := _closest_reachable(leader, _nearest_enemy_leader(leader))
		if goal != _cell(leader):
			_screen.select_unit(leader)
			_screen.tap_cell(goal)
			if not await _idle():
				return false
			if _battle().is_finished():
				return true
			target = _attack_target(leader)
			if target >= 0 and _battle().can_act(leader):
				return await _attack(leader, target)
	if _battle().can_act(leader):
		_screen.select_unit(leader)
		_screen.press_button(&"wait")
		return await _idle()
	return true


func _cast(leader: int, cell: Vector2i) -> bool:
	_screen.select_unit(leader)
	_screen.press_button(&"skill")
	if _screen.get_mode() == TacticsScreen.Mode.SKILL_TARGET:
		_screen.tap_cell(cell)
	if _screen.get_mode() != TacticsScreen.Mode.SKILL_PREVIEW:
		push_error("Aiming the skill should preview it")
		return false
	if not _expect_hint("TACTICS_HINT_SKILL_CONFIRM"):
		return false
	var preview := _battle().preview_skill(leader, _screen.get_map().get_marks()["target"])
	var hash_before := _battle().get_state_hash()
	_screen.press_button(&"cast")
	if not await _idle():
		return false
	if _battle().get_state_hash() == hash_before:
		push_error("The cast should change the battle")
		return false
	for result: Dictionary in preview["results"]:
		if _battle().get_unit_state(result["unit"])["hp"] > result["hp_after"] and not _battle().is_finished():
			push_error("The skill preview promised more damage than the cast did")
			return false
	_skills_cast += 1
	return true


# Tap the enemy, then tap it again (every other strike presses "Đánh").
func _attack(leader: int, target: int) -> bool:
	_screen.select_unit(leader)
	_screen.tap_cell(_cell(target))
	if _screen.get_mode() != TacticsScreen.Mode.FORECAST:
		push_error("A tap on an enemy within a walk and a strike should show the forecast (mode %d, target %d at %s, strike cell %s, strike targets %s)" % [_screen.get_mode(), target, _cell(target), _battle().get_strike_cell(leader, target), _battle().get_strike_targets(leader)])
		return false
	var cell := _battle().get_strike_cell(leader, target)
	var forecast := _battle().forecast_move_attack(leader, cell, target)
	if not _expect_hint("TACTICS_HINT_ATTACK_CONFIRM"):
		return false
	var buttons := _button_actions()
	if not buttons.has(&"attack") or not buttons.has(&"cancel") or not buttons.has(&"end_turn"):
		push_error("The forecast should offer attack, cancel and end turn")
		return false
	if cell != _cell(leader) and (_screen.get_map().get_marks().get("ghosts", []) as Array).is_empty():
		push_error("A strike after a walk should show the ghosts")
		return false
	if _attacks % 2 == 0:
		_screen.tap_cell(_cell(target))
	else:
		_screen.press_button(&"attack")
	if not await _idle():
		return false
	if _cell(leader) != cell and _battle().get_unit_state(leader)["alive"]:
		push_error("The leader should strike from %s, it stands on %s" % [cell, _cell(leader)])
		return false
	var hp_after: int = _battle().get_unit_state(target)["hp"]
	# The squad may fight on after the leader, so the target can only be lower.
	if not forecast.get("target_gone", false) and hp_after > int(forecast["defender_hp_after"]):
		push_error("The forecast said hp %d after, the battle has %d" % [forecast["defender_hp_after"], hp_after])
		return false
	_attacks += 1
	# Struck with points left: no red rings, so the hint no longer asks to
	# tap one.
	if _screen.get_selected() == leader and _battle().can_move(leader) and not _expect_hint("TACTICS_HINT_MOVE_ON_STRUCK"):
		return false
	return true


# With every leader done, or with no strike and no skill left, only walks
# remain: "Kết lượt" is the primary button and the hint says so, before
# any leader waits. Otherwise it is not primary.
func _check_end_turn_look() -> bool:
	_screen.cancel()
	_screen.cancel()
	var is_settled := true
	for leader: int in _our_leaders():
		var state := _battle().get_unit_state(leader)
		var has_acted: bool = state["has_moved"] or state["has_attacked"] or state["has_cast"]
		var is_walk_only := _battle().get_strike_targets(leader).is_empty() and _battle().get_skill_cells(leader).is_empty()
		is_settled = is_settled and (_battle().is_closed(leader) or (is_walk_only and has_acted))
	var is_primary := false
	for entry: Dictionary in _screen.get_panel().get_buttons():
		if entry["action"] == &"end_turn":
			is_primary = entry.get("primary", false)
	if is_primary != is_settled:
		push_error("Kết lượt should be primary exactly when only walks are left (%s, %s) mode %d buttons %s" % [is_primary, is_settled, _screen.get_mode(), _screen.get_panel().get_buttons()])
		return false
	if is_settled and not _screen.get_hint() in [tr("TACTICS_HINT_ONLY_WALKS"), tr("TACTICS_HINT_ALL_DONE"), tr("TACTICS_HINT_WAVERING"), tr("TACTICS_HINT_WAVERING_UNSEEN"), tr("TACTICS_HINT_WAVERING_GOOD")]:
		push_error("With only walks left the hint should say Kết lượt, got %s" % _screen.get_hint())
		return false
	_settled_phases += 1 if is_settled else 0
	return true


# A leader if one can be struck (after a walk too), else the first enemy.
func _attack_target(leader: int) -> int:
	var targets := _battle().get_strike_targets(leader)
	var best := -1
	for target: int in targets:
		var state := _battle().get_unit_state(target)
		if state["role"] == &"leader":
			return target
		if best < 0:
			best = target
	return best


# The skill cell that hits the most enemies (or any cell for a support skill).
func _best_skill_cell(leader: int, cells: Array) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_hits := 0
	for cell: Vector2i in cells:
		var preview := _battle().preview_skill(leader, cell)
		if not preview["is_valid"]:
			continue
		var hits: int = (preview["results"] as Array).size()
		if (preview["results"] as Array).is_empty() and not (preview["buffed"] as Array).is_empty():
			hits = 1
		if hits > best_hits:
			best_hits = hits
			best = cell
	return best


func _nearest_enemy_leader(leader: int) -> Vector2i:
	var from := _cell(leader)
	var best := Vector2i(-1, -1)
	var best_distance := 1 << 30
	for unit: Dictionary in _battle().get_units():
		if unit["role"] == &"leader" and unit["side"] == 1 and unit["alive"]:
			var cell: Vector2i = unit["cell"]
			var distance := absi(cell.x - from.x) + absi(cell.y - from.y)
			if distance < best_distance:
				best_distance = distance
				best = cell
	return best


func _closest_reachable(leader: int, goal: Vector2i) -> Vector2i:
	var best := _cell(leader)
	var best_distance := absi(best.x - goal.x) + absi(best.y - goal.y)
	for cell: Vector2i in _battle().get_reachable_cells(leader):
		var distance := absi(cell.x - goal.x) + absi(cell.y - goal.y)
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best


func _button_actions() -> Array[StringName]:
	var actions: Array[StringName] = []
	for entry: Dictionary in _screen.get_panel().get_buttons():
		actions.append(entry["action"])
	return actions
