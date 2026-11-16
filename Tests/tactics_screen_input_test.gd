extends SceneTree

# Headless test of the tactics screen with real playback (not instant) and
# taps pushed through the viewport like a phone's: taps while a playback
# runs change nothing but the step, a tap skips a close-up (and a second
# one does no harm), "Rút" works while the enemy plays, the skill close-up
# says what a support skill did to allies for our side and for the enemy,
# the enemy's phase and intents read right, our phase starts with a leader
# of ours on screen wherever the camera was, and so do the skill outcome
# lines and the growth float. With a campaign, "Rút" during the enemy's
# phase shows the summary and nothing plays on behind it. No error may be
# logged, also after the screen is freed in the middle of a playback.

const SCENARIO_PATH: String = "res://Data/Tactics/Scenarios/river_crossing.tres"
const RALLY_SKILL: StringName = &"tactics_skill.rally_banner"
const MAX_FRAMES: int = 6000


class ErrorLog extends Logger:
	var lines: Array[String] = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			lines.append("%s:%d %s %s" % [file, line, code, rationale])


var _errors := ErrorLog.new()
var _screen: TacticsScreen
var _went_home: int = 0
## Close-up title and subtitle pairs seen while waiting.
var _close_ups: Array[PackedStringArray] = []


func _initialize() -> void:
	TranslationServer.set_locale("vi")
	# First-time tips are remembered here, never in the player's settings.
	RunSettings.path = "user://settings_tactics_screen_input_test.json"
	DirAccess.remove_absolute(RunSettings.path)
	OS.add_logger(_errors)
	var ok := await _run()
	if _screen != null:
		_screen.queue_free()
	# Long enough for the retreat's 3 s timer to fire on a freed screen.
	await create_timer(TacticsScreen.RETREAT_ARM_SEC + 0.3).timeout
	OS.remove_logger(_errors)
	if ok and not _errors.lines.is_empty():
		push_error("Tactics screen input test: errors were logged:\n%s" % "\n".join(_errors.lines))
		ok = false
	if ok:
		print("Tactics screen input test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not ClassDB.class_exists("TacticsBattle"):
		push_error("TacticsBattle is missing: build the GDExtension (scons) before importing")
		return false
	var checks: Array[Callable] = [_check_outcome_lines, _check_enemy_phase_texts, _check_our_phase_in_view, _check_busy_taps, _check_our_rally, _check_enemy_rally, _check_retreat_while_busy, _check_campaign_retreat_stops_playback]
	for check: Callable in checks:
		if not await check.call():
			push_error("Tactics screen input test failed in %s" % check.get_method())
			return false
	return true


func _open(player_side: int) -> void:
	if _screen != null:
		_screen.queue_free()
	_close_ups.clear()
	_screen = TacticsScreen.new()
	_screen.scenario = load(SCENARIO_PATH) as TacticsScenarioData
	_screen.player_side = player_side
	_screen.size = Vector2(720, 1280)
	_screen.home_requested.connect(func() -> void: _went_home += 1)
	root.add_child(_screen)
	await process_frame


func _battle() -> TacticsBattle:
	return _screen.get_battle()


# A press and release on the control's centre, through the viewport.
func _tap(control: Control) -> void:
	var at := root.get_final_transform() * control.get_global_rect().get_center()
	for is_pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = is_pressed
		event.position = at
		event.global_position = at
		root.push_input(event)


# Waits for the screen to take taps again, tapping through every step and
# close-up (recording what each close-up said).
func _wait_idle() -> bool:
	for frame: int in MAX_FRAMES:
		var close_up := _screen.get_close_up()
		if close_up.is_playing:
			var seen := PackedStringArray([close_up.get_title(), close_up.get_subtitle()])
			if not _close_ups.has(seen):
				_close_ups.append(seen)
			_tap(close_up)
		elif _screen.is_busy():
			_tap(_screen.get_map())
		else:
			return true
		await process_frame
	push_error("The screen stayed busy")
	return false


func _our_leader_with_skill(skill: StringName, side: int) -> int:
	for unit: Dictionary in _battle().get_units():
		if unit["role"] == &"leader" and unit["side"] == side and _battle().get_skill_charge(unit["index"])["skill"] == skill:
			return unit["index"]
	return -1


func _check_outcome_lines() -> bool:
	var text := TacticsText.new(load(TacticsScreen.CATALOG_PATH) as TacticsCatalog)
	var cases: Dictionary[String, String] = {
		text.skill_outcome(true, 2, 0, &""): "Trúng 2 địch",
		text.skill_outcome(false, 3, 0, &""): "Trúng 3 quân ta",
		text.skill_outcome(true, 0, 4, &""): "4 binh ta được tăng công",
		text.skill_outcome(false, 0, 4, &""): "4 binh địch được tăng công",
		text.skill_outcome(true, 0, 0, &""): "Chiêu không tác động đến ai",
		text.skill_outcome(true, 0, 0, &"zone.fire"): "Để lại Lửa",
		text.skill_outcome(false, 5, 0, &"zone.fire"): "Trúng 5 quân ta · Để lại Lửa",
		tr("TACTICS_FLOAT_SKILL_GREW_FORMAT") % 2: "Chiêu rộng thêm 2 ô",
	}
	for got: String in cases:
		if got != cases[got]:
			push_error("A skill outcome reads \"%s\", expected \"%s\"" % [got, cases[got]])
			return false
	return true


# The enemy's card says it marches when its intent arrow moves; while the
# enemy plays, the top bar and the panel say it is the enemy's phase.
func _check_enemy_phase_texts() -> bool:
	await _open(0)
	if not await _wait_idle():
		return false
	var marches := 0
	for intent: Dictionary in _battle().get_enemy_intents():
		if intent["action"] != &"wait":
			continue
		_screen.select_unit(intent["unit"])
		var is_march: bool = intent["to"] != _battle().get_unit_state(intent["unit"])["cell"]
		var line: String = _screen.get_panel().get_card_texts()[3]
		if line.begins_with(tr("INTENT_MARCH")) != is_march or line.begins_with(tr("INTENT_WAIT")) == is_march:
			push_error("Enemy %d's intent (to %s) reads \"%s\"" % [intent["unit"], intent["to"], line])
			return false
		marches += 1 if is_march else 0
	if marches == 0:
		push_error("The river crossing should open with an enemy marching")
		return false
	_screen.cancel()
	_screen.press_button(&"end_turn")
	for frame: int in 30:
		await process_frame
	if not _screen.is_busy():
		push_error("The enemy's phase should still be playing")
		return false
	var enemy := tr("TACTICS_PHASE_ENEMY")
	if not _screen.get_round_text().ends_with(enemy) or _screen.get_panel().get_card_texts()[0] != enemy:
		push_error("During the enemy's phase the top bar reads \"%s\" and the panel \"%s\"" % [_screen.get_round_text(), _screen.get_panel().get_card_texts()[0]])
		return false
	return await _wait_idle()


# Our phase starts with a leader of ours on screen, wherever the camera was
# left (the enemy's moves, or the player's own drag) when it began: the
# hint asks to tap one.
func _check_our_phase_in_view() -> bool:
	await _open(0)
	if not await _wait_idle():
		return false
	var map := _screen.get_map()
	var far := Vector2i(map.map_width - 1, 0)
	var ours: Array[int] = []
	for unit: Dictionary in _battle().get_units():
		if unit["role"] == &"leader" and unit["side"] == 0:
			ours.append(unit["index"])
			if (unit["cell"] - far).length() < 6.0:
				push_error("The far corner %s should be away from our leaders" % far)
				return false
	_screen.press_button(&"end_turn")
	for round_number: int in 2:
		map.center_on(map.cell_to_local(far))
		if not await _wait_idle():
			return false
		for frame: int in 60:
			if not map.is_camera_moving():
				break
			await process_frame
		var seen := false
		for unit: int in ours:
			var piece := map.get_piece(unit)
			seen = seen or (piece.visible and map.is_in_view(piece.position))
		if not seen:
			push_error("Round %d: our phase began with no leader of ours on screen (camera at %s)" % [_battle().get_round(), map.get_camera_offset()])
			return false
		_screen.press_button(&"end_turn")
	return await _wait_idle()


# While a playback runs, taps on the map, leaders and buttons change nothing.
func _check_busy_taps() -> bool:
	await _open(0)
	if not await _wait_idle():
		return false
	_screen.press_button(&"end_turn")
	if not _screen.is_busy():
		push_error("Ending the turn should start a playback")
		return false
	var hash_before := _battle().get_state_hash()
	var other := _our_leader_with_skill(&"tactics_skill.chain_arrows", 0)
	_screen.tap_cell(_battle().get_unit_state(other)["cell"])
	_screen.select_unit(other)
	for action: StringName in [&"end_turn", &"wait", &"skill", &"order", &"confirm_move", &"attack", &"cast"]:
		_screen.press_button(action)
	_screen.confirm()
	_screen.choose_order(&"order.hold")
	for button: Dictionary in _screen.get_panel().get_buttons():
		_tap(button["button"])
	await process_frame
	if _battle().get_state_hash() != hash_before or not _screen.is_busy():
		push_error("Taps during a playback must not send commands (hash same=%s busy=%s mode=%d)" % [_battle().get_state_hash() == hash_before, _screen.is_busy(), _screen.get_mode()])
		return false
	return await _wait_idle()


# Lạc Hồng's rally (after 3 of our phases) says how many of our soldiers it
# strengthened, never "0 enemies hit".
func _check_our_rally() -> bool:
	await _open(0)
	var leader := _our_leader_with_skill(RALLY_SKILL, 0)
	for phase: int in 4:
		if not await _wait_idle():
			return false
		if not _battle().get_skill_cells(leader).is_empty():
			break
		_screen.press_button(&"end_turn")
	if _battle().get_skill_cells(leader).is_empty():
		push_error("The rally should be ready after three phases")
		return false
	var soldiers := 0
	for soldier: int in _battle().get_unit_state(leader)["soldiers"]:
		if _battle().get_unit_state(soldier)["alive"]:
			soldiers += 1
	_screen.select_unit(leader)
	_screen.press_button(&"skill")
	if _screen.get_mode() != TacticsScreen.Mode.SKILL_PREVIEW:
		push_error("A rally cast on the leader's own cell should go straight to its preview")
		return false
	_close_ups.clear()
	_screen.press_button(&"cast")
	var close_up := _screen.get_close_up()
	for frame: int in 60:
		if close_up.is_playing:
			break
		await process_frame
	var seen := PackedStringArray([close_up.get_title(), close_up.get_subtitle()])
	_close_ups.append(seen)
	# One tap ends the close-up; a second, as it closes, does no harm.
	_tap(close_up)
	_tap(close_up)
	await process_frame
	if close_up.is_playing or close_up.visible:
		push_error("A tap should end the close-up")
		return false
	if not await _wait_idle():
		return false
	return _expect_subtitle("%d binh ta được tăng công" % soldiers)


# Played from side B, the enemy's rally says it strengthened enemy soldiers.
func _check_enemy_rally() -> bool:
	await _open(1)
	for phase: int in 6:
		if not await _wait_idle():
			return false
		for seen: PackedStringArray in _close_ups:
			if seen[1].contains("binh địch được tăng công"):
				return _expect_subtitle(seen[1])
		if _battle().is_finished():
			break
		_screen.press_button(&"end_turn")
	push_error("The enemy's rally close-up should say enemy soldiers were strengthened, saw %s" % [_close_ups])
	return false


func _expect_subtitle(expected: String) -> bool:
	for seen: PackedStringArray in _close_ups:
		if seen[0].contains(tr("TACTICS_SKILL_RALLY_BANNER")):
			if seen[1] != expected:
				push_error("The rally close-up says \"%s\", expected \"%s\"" % [seen[1], expected])
				return false
			return true
	push_error("No rally close-up was seen in %s" % [_close_ups])
	return false


# "Rút" answers while the enemy plays: two taps on it leave the battle,
# and the screen can be freed mid-playback without errors.
func _check_retreat_while_busy() -> bool:
	await _open(0)
	if not await _wait_idle():
		return false
	# Unanswered, the question goes away and the hint of the moment is back.
	_screen.select_unit(_our_leader_with_skill(RALLY_SKILL, 0))
	var hint := _screen.get_hint()
	_screen.retreat()
	if _screen.get_hint() == hint:
		push_error("The first tap on Rút should ask")
		return false
	await create_timer(TacticsScreen.RETREAT_ARM_SEC + 0.2).timeout
	if _screen.get_hint() != hint:
		push_error("After Rút times out the hint should read \"%s\" again, not \"%s\"" % [hint, _screen.get_hint()])
		return false
	_screen.press_button(&"end_turn")
	await process_frame
	if not _screen.is_busy():
		push_error("Ending the turn should play the enemy's phase")
		return false
	var home_before := _went_home
	_tap(_screen.get_retreat_button())
	await process_frame
	if _went_home != home_before or not _screen.is_busy():
		push_error("The first tap on Rút should only ask")
		return false
	_tap(_screen.get_retreat_button())
	await process_frame
	if _went_home != home_before + 1:
		push_error("A second tap on Rút during the enemy's phase should leave the battle")
		return false
	_screen.queue_free()
	_screen = null
	await process_frame
	return true


# With a campaign, a double "Rút" while the enemy plays opens the summary
# and stops the playback: no step starts behind the summary.
func _check_campaign_retreat_stops_playback() -> bool:
	TacticsRoster.path = "user://tactics_roster_input_test.json"
	var catalog := load("res://Data/Tactics/tactics_catalog.tres") as TacticsCatalog
	var campaign := TacticsCampaign.new(TacticsRoster.create(5), catalog, load(SCENARIO_PATH) as TacticsScenarioData)
	_screen = TacticsScreen.new()
	_screen.scenario = campaign.scenario
	_screen.squads = campaign.squads
	_screen.campaign = campaign
	_screen.size = Vector2(720, 1280)
	root.add_child(_screen)
	await process_frame
	if not await _wait_idle():
		return false
	_screen.press_button(&"end_turn")
	await create_timer(0.3).timeout
	var steps := [0]
	_screen.get_playback().step_started.connect(func(_type: StringName) -> void: steps[0] += 1)
	_tap(_screen.get_retreat_button())
	_tap(_screen.get_retreat_button())
	await process_frame
	var ok := _screen.get_summary() != null
	var at: int = steps[0]
	await create_timer(2.0).timeout
	if not ok or steps[0] != at or _screen.get_playback().is_playing:
		push_error("After Rút the summary should show and the playback stop (summary %s, %d steps after it, playing %s)" % [ok, steps[0] - at, _screen.get_playback().is_playing])
		ok = false
	_screen.queue_free()
	_screen = null
	await process_frame
	TacticsRoster.delete()
	return ok
