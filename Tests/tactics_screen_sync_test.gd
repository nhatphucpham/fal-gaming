extends SceneTree

# Plays random taps through the tactics screen (instant playback) on several
# seeds: map cells, our leaders (often marched to the blue cell nearest
# the enemy, and often again with the points left), drags of a leader's
# ghosts, the enabled panel buttons (undo among them) and the order row,
# legal or not; the phase also ends by itself once every leader is closed
# (it waited, or nothing is left). After every playback, before the screen syncs, the
# map must already show what the battle has (tokens, hp, deaths, charge
# pips, zones), so nothing jumps silently; after every tap the synced screen
# must agree with the battle's queries (marks, buttons, intents, the done
# look, the fog and the last-seen ghosts) and no error may be logged; an
# enemy we do not see has no piece shown. Odd seeds play with the roster and
# incidents (most soldiers seeded): the pieces must also show each unit's
# side, wavering mark and marks as the battle has them. The seeds take the
# five scenarios in turn: the sites shown are those our side knows, a site
# choice or recruit button is enabled only when the battle takes it, the
# objective line names the objective, the exits and the convoy's path are
# the battle's, and units arriving mid-battle get their pieces.

const SCENARIO_PATHS: Array[String] = [
	"res://Data/Tactics/Scenarios/river_crossing.tres", "res://Data/Tactics/Scenarios/night_raid.tres",
	"res://Data/Tactics/Scenarios/city_defense.tres", "res://Data/Tactics/Scenarios/supply_road.tres",
	"res://Data/Tactics/Scenarios/broken_ring.tres",
]
const SEED_COUNT: int = 10
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
## Site and objective steps played (sites used, arrivals, captures...).
var _site_events: Dictionary = {}


func _initialize() -> void:
	TranslationServer.set_locale("vi")
	# First-time tips are remembered here, never in the player's settings.
	RunSettings.path = "user://settings_tactics_screen_sync_test.json"
	DirAccess.remove_absolute(RunSettings.path)
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
	print("%d playbacks checked, %d of %d battles finished, %d incident steps, site steps %s" % [_played, finished, SEED_COUNT, _incident_events, _site_events])
	if _incident_events == 0:
		push_error("Tactics screen sync test: no incident was played")
		return false
	for type: StringName in [&"site_used", &"unit_arrived", &"capture_progressed"]:
		if not _site_events.has(type):
			push_error("Tactics screen sync test: no %s step was played" % type)
			return false
	return true


func _play_seed(seed_value: int) -> bool:
	_rng.seed = seed_value
	_screen = TacticsScreen.new()
	_screen.scenario = load(SCENARIO_PATHS[seed_value % SCENARIO_PATHS.size()]) as TacticsScenarioData
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
		_incident_events += 1 if String(type) in ["soldier_wavered", "incident_fired", "incident_calmed"] else 0
		if String(type) in ["site_used", "site_changed", "capture_progressed", "unit_arrived", "unit_escaped", "unit_healed", "convoy_halted", "general_fleeing", "supplies_gained"]:
			_site_events[type] = int(_site_events.get(type, 0)) + 1)
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
		# An auto end (a short timer, then a playback) is waited out.
		var deadline := Time.get_ticks_msec() + 3000
		while (_screen.is_busy() or _screen.is_auto_end_pending()) and Time.get_ticks_msec() < deadline:
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
			# Often a march: the blue cell nearest the enemy at once, so
			# the fights (and the incidents they stir) come even against
			# an enemy that holds its ground.
			var reachable: Array = _screen.get_map().get_marks().get("reachable", [])
			if not reachable.is_empty() and _rng.randf() < 0.5:
				var cell := _nearest_to_enemy(reachable)
				_screen.tap_cell(cell)
				return "march leader %d to %s" % [leader, cell]
			return "tap leader %d" % leader
	if roll < 55:
		var marked := _marked_cells()
		if not marked.is_empty():
			var cell: Vector2i = marked[_rng.randi_range(0, marked.size() - 1)]
			_screen.tap_cell(cell)
			return "tap marked %s" % cell
	if roll < 62:
		var leaders := _living_leaders(0)
		if not leaders.is_empty():
			var leader: int = leaders[_rng.randi_range(0, leaders.size() - 1)]
			var from: Vector2i = _battle().get_unit_state(leader)["cell"]
			var map := _screen.get_map()
			if not map.hold_cells.has(from):
				return "no drag from %s" % from
			var to := Vector2i(_rng.randi_range(0, _battle().get_map_width() - 1), _rng.randi_range(0, _battle().get_map_height() - 1))
			var marked := _marked_cells()
			if not marked.is_empty() and _rng.randf() < 0.6:
				to = marked[_rng.randi_range(0, marked.size() - 1)]
			map.cell_held.emit(from)
			map.cell_held.emit(to)
			if _rng.randf() < 0.15:
				map.hold_cancelled.emit()
				return "drag %d to %s, cancelled" % [leader, to]
			map.hold_released.emit(to)
			return "drag %d to %s" % [leader, to]
	if _screen.get_panel().is_order_row_shown() and _rng.randf() < 0.25:
		var orders := _screen.get_panel().get_order_buttons().keys()
		var order: StringName = orders[_rng.randi_range(0, orders.size() - 1)]
		_screen.get_panel().get_order_buttons()[order].pressed.emit()
		return "order %s" % order
	if _rng.randf() < 0.06:
		_screen.get_objective_chip().pressed.emit()
		return "objective chip"
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


# The cell of `cells` nearest to any living enemy.
func _nearest_to_enemy(cells: Array) -> Vector2i:
	var best: Vector2i = cells[0]
	var best_distance := 1 << 30
	for cell: Vector2i in cells:
		for unit: Dictionary in _battle().get_units():
			var at: Vector2i = unit["cell"]
			var distance := absi(at.x - cell.x) + absi(at.y - cell.y)
			if unit["alive"] and unit["side"] != 0 and distance < best_distance:
				best = cell
				best_distance = distance
	return best


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
	_check_fog("before the sync")
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
	_check_fog(what)
	_check_intents(what)
	_check_marks(what)
	_check_buttons(what)
	_check_objective(what)


func _check_pieces(what: String, is_synced: bool) -> void:
	var map := _screen.get_map()
	for state: Dictionary in _battle().get_units():
		var unit: int = state["index"]
		var piece := map.get_piece(unit)
		if piece == null:
			_problems.append("%s: unit %d has no piece" % [what, unit])
			continue
		var is_alive: bool = state["alive"]
		# Under fog an enemy we do not see is off the board.
		var is_seen: bool = int(state["side"]) == 0 or _battle().is_unit_seen(0, unit)
		if piece.visible != (is_alive and is_seen) or piece.is_dead == is_alive:
			_problems.append("%s: unit %d alive=%s seen=%s but its piece visible=%s dead=%s" % [what, unit, is_alive, is_seen, piece.visible, piece.is_dead])
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
				# Closed: it waited, or no point reaches a cell, no strike is left
				# (moving first with the points left) and no skill cell.
				var has_nothing: bool = not _battle().can_move(unit) and _battle().get_strike_targets(unit).is_empty() and _battle().get_skill_cells(unit).is_empty() and not _has_site_choice(unit)
				var is_done: bool = state["side"] == 0 and _battle().get_active_side() == 0 and (not _battle().can_act(unit) or has_nothing)
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


# The fog and the last-seen ghosts are what our side sees and remembers.
func _check_fog(what: String) -> void:
	var map := _screen.get_map()
	if not _battle().has_fog_of_war():
		_problems.append("%s: every scenario should have fog of war" % what)
		return
	if map.get_fog() != _battle().get_fog_cells(0):
		_problems.append("%s: the fog shown differs from what side 0 sees" % what)
	var shown: Array[String] = []
	for ghost: Dictionary in map.get_last_seen():
		shown.append("%d %s" % [ghost["unit"], ghost["cell"]])
	var real: Array[String] = []
	for ghost: Dictionary in _battle().get_last_seen(0):
		real.append("%d %s" % [ghost["unit"], ghost["cell"]])
	shown.sort()
	real.sort()
	if shown != real:
		_problems.append("%s: ghosts shown %s, battle remembers %s" % [what, shown, real])


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
	for target: int in _battle().get_strike_targets(leader):
		attackable.append(_battle().get_unit_state(target)["cell"])
	if Array(marks.get("attackable", [])) != attackable:
		_problems.append("%s: leader %d attack marks %s, battle %s" % [what, leader, marks.get("attackable"), attackable])
	if Array(marks.get("slots", [])) != _battle().get_formation_slots(leader):
		_problems.append("%s: leader %d slot marks %s, battle %s" % [what, leader, marks.get("slots"), _battle().get_formation_slots(leader)])
	if not _screen.get_panel().is_order_row_shown() or _screen.get_panel().get_current_order() != state["order"]:
		_problems.append("%s: leader %d order row missing or not on %s" % [what, leader, state["order"]])
	for button: PressButton in _screen.get_panel().get_order_buttons().values():
		if button.disabled == _battle().can_act(leader):
			_problems.append("%s: leader %d order buttons disabled=%s, can_act=%s" % [what, leader, button.disabled, _battle().can_act(leader)])
			break
	# The card says what the leader can still do: points left, the attack.
	var turn_line: String = tr("TACTICS_TURN_WAITED") if state["has_waited"] else tr("TACTICS_TURN_FORMAT") % [_battle().get_move_points_left(leader), state["move_points"], tr("TACTICS_TURN_ATTACK_USED") if _battle().has_attacked(leader) else tr("TACTICS_TURN_ATTACK_READY")]
	if not _screen.get_panel().get_shown_card_lines().has(turn_line):
		_problems.append("%s: leader %d card lacks \"%s\": %s" % [what, leader, turn_line, _screen.get_panel().get_shown_card_lines()])


# Some site within the leader's reach takes a choice now.
func _has_site_choice(unit: int) -> bool:
	for site: Dictionary in _battle().get_site_actions(unit):
		for choice: Dictionary in site["choices"]:
			if choice["can"]:
				return true
	return false


func _can_take(leader: int, site: int, choice: StringName) -> bool:
	for option: int in 4:
		if _battle().can_use_site(leader, site, choice, option):
			return true
	return false


# The sites shown are the battle's for our side; the objective's line, its
# exits and the convoy's path are the battle's too.
func _check_objective(what: String) -> void:
	var map := _screen.get_map()
	if map.get_sites() != _battle().get_sites(0):
		_problems.append("%s: the sites shown differ from what side 0 knows" % what)
	var objective := _battle().get_objective_state()
	var kind: StringName = objective["kind"]
	var name := tr("OBJECTIVE_KIND_" + String(kind).trim_prefix("objective_kind.").to_upper())
	if not _screen.get_objective_chip_text().begins_with(name + ":"):
		_problems.append("%s: the objective line reads \"%s\" for %s" % [what, _screen.get_objective_chip_text(), kind])
	var marks := map.get_objective_marks()
	if kind == &"objective_kind.break_siege" and Array(marks.get("exits", [])) != Array(objective["exit_cells"]):
		_problems.append("%s: exits shown %s, battle %s" % [what, marks.get("exits"), objective["exit_cells"]])
	if kind == &"objective_kind.escort":
		var path: Array = _battle().get_convoy_path() if _battle().get_active_side() == 0 and not _battle().is_finished() else []
		if Array(marks.get("convoy_path", [])) != path:
			_problems.append("%s: convoy path shown %s, battle %s" % [what, marks.get("convoy_path"), path])


# Buttons that would send a command are enabled only when the battle takes it.
func _check_buttons(what: String) -> void:
	var leader := _screen.get_selected()
	var site := _screen.get_shown_site()
	for entry: Dictionary in _screen.get_panel().get_buttons():
		var action: StringName = entry["action"]
		var enabled: bool = entry["enabled"]
		if action == &"site" and enabled != (leader >= 0 and _has_site_choice(leader)):
			_problems.append("%s: site button enabled=%s for leader %d" % [what, enabled, leader])
		if String(action).begins_with("site_"):
			var choice := StringName(String(action).trim_prefix("site_"))
			if site < 0 or enabled != _can_take(leader, site, choice):
				_problems.append("%s: %s enabled=%s at site %d for leader %d" % [what, action, enabled, site, leader])
		if String(action).begins_with("recruit_"):
			if site < 0 or enabled != _battle().can_use_site(leader, site, &"recruit", int(String(action).trim_prefix("recruit_"))):
				_problems.append("%s: %s enabled=%s at site %d" % [what, action, enabled, site])
		if action in [&"convoy_hold", &"convoy_go"] and (_battle().get_active_side() != 0 or _battle().get_objective_state()["convoy_holds"] != (action == &"convoy_go")):
			_problems.append("%s: %s offered out of turn or the wrong way round" % [what, action])
		if action == &"undo" and (leader < 0 or not _battle().can_undo_move(leader)):
			_problems.append("%s: undo offered with no move to take back" % what)
		if action in [&"wait", &"skill", &"undo"] and leader < 0:
			_problems.append("%s: %s offered with nothing selected" % [what, action])
			continue
		if action == &"end_turn" and enabled and (_battle().get_active_side() != 0 or _battle().is_finished()):
			_problems.append("%s: end turn is enabled outside our phase" % what)
		if action == &"wait" and enabled != _battle().can_act(leader):
			_problems.append("%s: wait enabled=%s for leader %d" % [what, enabled, leader])
		if action == &"skill" and enabled != (_battle().can_act(leader) and not _battle().get_skill_cells(leader).is_empty()):
			_problems.append("%s: skill enabled=%s for leader %d" % [what, enabled, leader])
