extends SceneTree

# Headless test of the tactics screen on the river crossing, through its
# public methods only (the same ones its taps call): a tap off the map
# selection undoes it, a move is previewed with ghosts and confirmed, an
# enemy in range shows the forecast before the attack, the order picker
# changes an order, a charged skill is aimed, previewed and cast, and the
# battle is then played to victory by a simple scripted policy (skill when
# ready, else attack a leader, else a soldier, else march on the nearest
# enemy leader). Playback runs in instant mode; every close-up is still
# counted. The result banner's button asks for the title.

const SCENARIO_PATH: String = "res://Data/Tactics/Scenarios/river_crossing.tres"
const MAX_PHASES: int = 40
const MAX_FRAMES_IDLE: int = 600

var _screen: TacticsScreen
var _went_home: bool = false
var _skills_cast: int = 0
var _attacks: int = 0


func _initialize() -> void:
	TranslationServer.set_locale("vi")
	var ok := await _run()
	if _screen != null:
		_screen.queue_free()
	await process_frame
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
	_screen.size = Vector2(720, 1280)
	_screen.home_requested.connect(func() -> void: _went_home = true)
	root.add_child(_screen)
	await process_frame
	if not await _idle():
		return false
	var checks: Array[Callable] = [_check_start, _check_undo, _check_move, _check_forecast_and_order, _check_battle_to_victory]
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
	if _screen.get_map().get_intents().is_empty():
		push_error("The enemy's intents should be shown in our phase")
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
	if not (labels.has(&"skill") and labels.has(&"order") and labels.has(&"wait") and labels.has(&"end_turn")):
		push_error("A selected leader should offer skill, order, wait and end turn, got %s" % [labels])
		return false
	# A plain cell it cannot reach: the selection goes away.
	var far := Vector2i(11, 0)
	_screen.tap_cell(far)
	if _screen.get_mode() != TacticsScreen.Mode.IDLE:
		push_error("A tap elsewhere should undo the selection")
		return false
	return true


func _check_move() -> bool:
	var leader := _our_leaders()[0]
	var hash_before := _battle().get_state_hash()
	_screen.tap_cell(_cell(leader))
	var target := _closest_reachable(leader, _nearest_enemy_leader(leader))
	_screen.tap_cell(target)
	if _screen.get_mode() != TacticsScreen.Mode.MOVE_PREVIEW:
		push_error("A tap on a reachable cell should preview the move")
		return false
	var ghosts: Array = _screen.get_map().get_marks().get("ghosts", [])
	if ghosts.size() != 1 + (_battle().get_unit_state(leader)["soldiers"] as Array).size():
		push_error("The preview should show a ghost for the leader and each soldier, got %d" % ghosts.size())
		return false
	if _battle().get_state_hash() != hash_before:
		push_error("A preview must not change the battle")
		return false
	if not _button_actions().has(&"confirm_move"):
		push_error("The preview should offer a confirm button")
		return false
	_screen.press_button(&"confirm_move")
	if not await _idle():
		return false
	if _cell(leader) != target:
		push_error("The leader should stand on %s, not %s" % [target, _cell(leader)])
		return false
	var piece := _screen.get_map().get_piece(leader)
	if piece.position != _screen.get_map().cell_to_local(target):
		push_error("The leader's piece should be on its new cell")
		return false
	return true


# The order picker sets an order; an enemy in range of anyone shows a
# forecast that matches the battle's (checked when one comes up below).
func _check_forecast_and_order() -> bool:
	var leader := _our_leaders()[0]
	_screen.select_unit(leader)
	_screen.press_button(&"order")
	if _screen.get_mode() != TacticsScreen.Mode.ORDER_PICK or _screen.get_panel().get_order_buttons().size() != 5:
		push_error("The order button should show the five orders")
		return false
	_screen.choose_order(&"order.flank")
	if not await _idle():
		return false
	if _battle().get_unit_state(leader)["order"] != &"order.flank":
		push_error("The order should now be flank")
		return false
	return true


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
	if _screen.get_playback().close_up_count == 0:
		push_error("A leader's attack or skill should open the close-up")
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


func _attack(leader: int, target: int) -> bool:
	_screen.select_unit(leader)
	_screen.tap_cell(_cell(target))
	if _screen.get_mode() != TacticsScreen.Mode.FORECAST:
		push_error("A tap on an enemy in range should show the forecast")
		return false
	var forecast := _battle().forecast_engagement(leader, target)
	var buttons := _button_actions()
	if not buttons.has(&"attack") or not buttons.has(&"cancel"):
		push_error("The forecast should offer attack and cancel")
		return false
	_screen.press_button(&"attack")
	if not await _idle():
		return false
	var hp_after: int = _battle().get_unit_state(target)["hp"]
	# The squad may fight on after the leader, so the target can only be lower.
	if hp_after > int(forecast["defender_hp_after"]):
		push_error("The forecast said hp %d after, the battle has %d" % [forecast["defender_hp_after"], hp_after])
		return false
	_attacks += 1
	return true


func _attack_target(leader: int) -> int:
	var targets := _battle().get_attack_targets(leader)
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
