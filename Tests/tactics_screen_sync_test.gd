extends SceneTree

# Plays random taps through the tactics screen (instant playback) on several
# seeds: map cells, our leaders, the enabled panel buttons and the order
# picker, legal or not. After every playback, before the screen syncs, the
# map must already show what the battle has (tokens, hp, deaths, charge
# pips, zones), so nothing jumps silently; after every tap the synced screen
# must agree with the battle's queries (marks, buttons, intents, the done
# look) and no error may be logged. Odd seeds play with the roster and
# incidents (most soldiers seeded): the pieces must also show each unit's
# side, wavering mark and marks as the battle has them.

const SCENARIO_PATH: String = "res://Data/Tactics/Scenarios/river_crossing.tres"
const SEED_COUNT: int = 6
const MAX_TAPS: int = 500
const CATALOG_PATH: String = "res://Data/Tactics/tactics_catalog.tres"
const INCIDENTS: Array[StringName] = [
	&"incident.rescue", &"incident.stand", &"incident.surge", &"incident.discontent", &"incident.riot", &"incident.flee", &"incident.betray",
]


class ErrorLog extends Logger:
	var lines: Array[String] = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			lines.append("%s:%d %s %s" % [file, line, code, rationale])


var _errors := ErrorLog.new()
var _screen: TacticsScreen
var _rng := RandomNumberGenerator.new()
var _problems: Array[String] = []
var _played: int = 0
var _phase_began: bool = false
## Unit index -> marks its roster person carried in (campaign seeds).
var _carried: Dictionary = {}
var _incident_events: int = 0


func _initialize() -> void:
	TranslationServer.set_locale("vi")
	TacticsRoster.path = "user://tactics_roster_sync_test.json"
	TacticsRoster.delete()
	OS.add_logger(_errors)
	var ok := await _run()
	OS.remove_logger(_errors)
	TacticsRoster.delete()
	if ok:
		print("Tactics screen sync test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not ClassDB.class_exists("TacticsBattle"):
		push_error("TacticsBattle is missing: build the GDExtension (scons) before importing")
		return false
	var finished := 0
	for seed_value: int in SEED_COUNT:
		if not await _play_seed(seed_value):
			for problem: String in _problems.slice(0, 12):
				printerr(problem)
			for line: String in _errors.lines.slice(0, 12):
				printerr(line)
			push_error("Tactics screen sync test failed on seed %d" % seed_value)
			return false
		if _battle().is_finished():
			finished += 1
		_screen.queue_free()
		await process_frame
	print("%d playbacks checked, %d of %d battles finished, %d incident steps" % [_played, finished, SEED_COUNT, _incident_events])
	if _incident_events == 0:
		push_error("Tactics screen sync test: no incident was played")
		return false
	return true


func _play_seed(seed_value: int) -> bool:
	_rng.seed = seed_value
	_screen = TacticsScreen.new()
	_screen.scenario = load(SCENARIO_PATH) as TacticsScenarioData
	_carried.clear()
	if seed_value % 2 == 1:
		var campaign := TacticsCampaign.new(TacticsRoster.load_roster(), load(CATALOG_PATH) as TacticsCatalog, _screen.scenario)
		for ids: Array in campaign.people:
			for id: int in ids:
				if _rng.randf() < 0.8:
					campaign.forced_seeds[id] = INCIDENTS[_rng.randi_range(0, INCIDENTS.size() - 1)]
		_screen.scenario = campaign.scenario
		_screen.squads = campaign.squads
		_screen.campaign = campaign
	_screen.is_instant = true
	_screen.size = Vector2(720, 1280)
	root.add_child(_screen)
	await process_frame
	_screen.get_playback().played.connect(_check_played)
	_screen.get_playback().step_started.connect(func(type: StringName) -> void:
		_incident_events += 1 if String(type) in ["soldier_wavered", "incident_fired", "incident_calmed"] else 0)
	if _screen.campaign != null:
		for state: Dictionary in _battle().get_units():
			var person := _screen.campaign.get_person(state["record_id"])
			_carried[state["index"]] = (person["marks"] as Array).size() if not person.is_empty() else 0
	_screen.get_playback().phase_shown.connect(func(_side: int, _round_number: int) -> void: _phase_began = true)
	_check_synced("start")
	for tap: int in MAX_TAPS:
		if _battle().is_finished():
			break
		var what := _random_tap()
		await process_frame
		_check_synced(what)
		if not _problems.is_empty() or not _errors.lines.is_empty():
			printerr("Seed %d, tap %d: %s" % [seed_value, tap, what])
			return false
	if _battle().is_finished() and _screen.get_mode() != TacticsScreen.Mode.ENDED:
		_problems.append("The screen should end with the battle")
	return _problems.is_empty() and _errors.lines.is_empty()


func _battle() -> TacticsBattle:
	return _screen.get_battle()


# One tap a player could make now; returns what it was.
func _random_tap() -> String:
	var roll := _rng.randi_range(0, 99)
	if roll < 30:
		var cell := Vector2i(_rng.randi_range(0, _battle().get_map_width() - 1), _rng.randi_range(0, _battle().get_map_height() - 1))
		_screen.tap_cell(cell)
		return "tap %s" % cell
	if roll < 45:
		var leaders := _living_leaders(0)
		if not leaders.is_empty():
			var leader: int = leaders[_rng.randi_range(0, leaders.size() - 1)]
			_screen.tap_cell(_battle().get_unit_state(leader)["cell"])
			return "tap leader %d" % leader
	if roll < 55:
		var marked := _marked_cells()
		if not marked.is_empty():
			var cell: Vector2i = marked[_rng.randi_range(0, marked.size() - 1)]
			_screen.tap_cell(cell)
			return "tap marked %s" % cell
	if _screen.get_mode() == TacticsScreen.Mode.ORDER_PICK and _rng.randf() < 0.7:
		var orders := _screen.get_panel().get_order_buttons().keys()
		var order: StringName = orders[_rng.randi_range(0, orders.size() - 1)]
		_screen.get_panel().get_order_buttons()[order].pressed.emit()
		return "order %s" % order
	var buttons: Array[Dictionary] = []
	for entry: Dictionary in _screen.get_panel().get_buttons():
		# End turn less often, so leaders get to act.
		if entry["enabled"] and (entry["action"] != &"end_turn" or _rng.randf() < 0.35):
			buttons.append(entry)
	if buttons.is_empty():
		return "nothing"
	var entry: Dictionary = buttons[_rng.randi_range(0, buttons.size() - 1)]
	(entry["button"] as PressButton).pressed.emit()
	return "button %s" % entry["action"]


func _living_leaders(side: int) -> Array[int]:
	var leaders: Array[int] = []
	for unit: Dictionary in _battle().get_units():
		if unit["role"] == &"leader" and unit["side"] == side and unit["alive"]:
			leaders.append(unit["index"])
	return leaders


# Cells the marks invite a tap on (reachable, attackable, skill cells).
func _marked_cells() -> Array:
	var marks := _screen.get_map().get_marks()
	var cells: Array = []
	for key: String in ["reachable", "attackable", "skill_cells"]:
		cells.append_array(marks.get(key, []))
	return cells


# Right after a playback, before the sync: the map must show the battle.
func _check_played() -> void:
	_played += 1
	_check_pieces("before the sync", false)
	_check_zones("before the sync")
	var phase := tr("TACTICS_PHASE_PLAYER") if _battle().get_active_side() == 0 else tr("TACTICS_PHASE_ENEMY")
	var round_text := "%s · %s" % [tr("TACTICS_ROUND_FORMAT") % [_battle().get_round(), _screen.scenario.rules.max_rounds], phase]
	if not _battle().is_finished() and _screen.get_round_text() != round_text:
		_problems.append("before the sync: the top bar reads \"%s\", the battle is in \"%s\"" % [_screen.get_round_text(), round_text])
	# A playback that began a phase leaves the panel on that phase's card.
	if _phase_began and not _battle().is_finished() and _screen.get_panel().get_card_texts()[0] != phase:
		_problems.append("before the sync: the panel reads \"%s\" in \"%s\"" % [_screen.get_panel().get_card_texts()[0], phase])
	_phase_began = false


func _check_synced(what: String) -> void:
	if _screen.is_busy():
		_problems.append("%s: the screen stayed busy in instant mode" % what)
		return
	_check_pieces(what, true)
	_check_zones(what)
	_check_intents(what)
	_check_marks(what)
	_check_buttons(what)


func _check_pieces(what: String, is_synced: bool) -> void:
	var map := _screen.get_map()
	for state: Dictionary in _battle().get_units():
		var unit: int = state["index"]
		var piece := map.get_piece(unit)
		if piece == null:
			_problems.append("%s: unit %d has no piece" % [what, unit])
			continue
		var is_alive: bool = state["alive"]
		if piece.visible != is_alive or piece.is_dead == is_alive:
			_problems.append("%s: unit %d alive=%s but its piece visible=%s dead=%s" % [what, unit, is_alive, piece.visible, piece.is_dead])
		if not is_alive:
			continue
		if piece.position != map.cell_to_local(state["cell"]):
			_problems.append("%s: unit %d is on %s but its piece at %s" % [what, unit, state["cell"], map.local_to_cell(piece.position)])
		if piece.hp != int(state["hp"]):
			_problems.append("%s: unit %d has hp %d but its piece shows %d" % [what, unit, state["hp"], piece.hp])
		if piece.scale != Vector2.ONE or piece.modulate.a < 1.0:
			_problems.append("%s: living unit %d is drawn fallen" % [what, unit])
		if piece.side != int(state["side"]):
			_problems.append("%s: unit %d fights for side %d but its piece shows %d" % [what, unit, state["side"], piece.side])
		var wavering := TacticsPieceView.Wavering.NONE
		if state["wavering"] != &"":
			wavering = TacticsPieceView.Wavering.GOOD if state["is_wavering_good"] else TacticsPieceView.Wavering.BAD
		if piece.wavering != wavering:
			_problems.append("%s: unit %d wavering %s but its piece shows %d" % [what, unit, state["wavering"], piece.wavering])
		if piece.mark_count != int(_carried.get(unit, 0)) + int(state["marks"]):
			_problems.append("%s: unit %d has %d marks but its piece shows %d" % [what, unit, int(_carried.get(unit, 0)) + int(state["marks"]), piece.mark_count])
		if state["role"] == &"leader":
			var charge := _battle().get_skill_charge(unit)
			if piece.charge_value != int(charge.get("value", 0)) or piece.charge_threshold != int(charge.get("threshold", 0)):
				_problems.append("%s: leader %d charge %s/%s, pips %d/%d" % [what, unit, charge.get("value"), charge.get("threshold"), piece.charge_value, piece.charge_threshold])
			if is_synced:
				var is_done: bool = state["side"] == 0 and _battle().get_active_side() == 0 and not _battle().can_act(unit) and not _battle().can_move(unit)
				if piece.is_done != is_done:
					_problems.append("%s: leader %d done=%s, piece done=%s" % [what, unit, is_done, piece.is_done])


func _check_zones(what: String) -> void:
	var shown: Array[String] = []
	for zone: Dictionary in _screen.get_map().get_zones():
		shown.append("%s %s" % [zone["zone"], zone["cells"]])
	var real: Array[String] = []
	for zone: Dictionary in _battle().get_zones():
		real.append("%s %s" % [zone["zone"], zone["cells"]])
	shown.sort()
	real.sort()
	if shown != real:
		_problems.append("%s: zones shown %s, battle has %s" % [what, shown, real])


func _check_intents(what: String) -> void:
	var shown: Array[String] = []
	for intent: Dictionary in _screen.get_map().get_intents():
		shown.append("%d %s %s %s" % [intent["unit"], intent["to"], intent["action"], intent["target_cell"]])
	var real: Array[String] = []
	if _battle().get_active_side() == 0 and not _battle().is_finished():
		for intent: Dictionary in _battle().get_enemy_intents():
			real.append("%d %s %s %s" % [intent["unit"], intent["to"], intent["action"], intent["target_cell"]])
	if shown != real:
		_problems.append("%s: intents shown %s, battle has %s" % [what, shown, real])


# The selected leader's marks are the battle's lists for it.
func _check_marks(what: String) -> void:
	var leader := _screen.get_selected()
	var marks := _screen.get_map().get_marks()
	if _screen.get_mode() == TacticsScreen.Mode.IDLE and marks.has("reachable"):
		_problems.append("%s: idle but reachable cells are marked" % what)
	if _screen.get_mode() != TacticsScreen.Mode.SELECTED or leader < 0:
		return
	var state := _battle().get_unit_state(leader)
	if not state["alive"]:
		_problems.append("%s: a dead unit %d is selected" % [what, leader])
		return
	if marks.get("selected") != state["cell"]:
		_problems.append("%s: the selection mark is not on unit %d" % [what, leader])
	if state["side"] != 0 or state["role"] != &"leader" or _battle().get_active_side() != 0:
		return
	var reachable: Array = _battle().get_reachable_cells(leader) if _battle().can_move(leader) else []
	if Array(marks.get("reachable", [])) != reachable:
		_problems.append("%s: leader %d reachable marks differ from the battle" % [what, leader])
	var attackable: Array = []
	for target: int in _battle().get_attack_targets(leader):
		attackable.append(_battle().get_unit_state(target)["cell"])
	if Array(marks.get("attackable", [])) != attackable:
		_problems.append("%s: leader %d attack marks %s, battle %s" % [what, leader, marks.get("attackable"), attackable])


# Buttons that would send a command are enabled only when the battle takes it.
func _check_buttons(what: String) -> void:
	var leader := _screen.get_selected()
	for entry: Dictionary in _screen.get_panel().get_buttons():
		var action: StringName = entry["action"]
		var enabled: bool = entry["enabled"]
		if action in [&"wait", &"skill"] and leader < 0:
			_problems.append("%s: %s offered with nothing selected" % [what, action])
			continue
		if action == &"end_turn" and enabled and (_battle().get_active_side() != 0 or _battle().is_finished()):
			_problems.append("%s: end turn is enabled outside our phase" % what)
		if action == &"wait" and enabled != _battle().can_act(leader):
			_problems.append("%s: wait enabled=%s for leader %d" % [what, enabled, leader])
		if action == &"skill" and enabled != (_battle().can_act(leader) and not _battle().get_skill_cells(leader).is_empty()):
			_problems.append("%s: skill enabled=%s for leader %d" % [what, enabled, leader])
