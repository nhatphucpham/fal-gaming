class_name TacticsScreen
extends Control
## The tactics battle screen: a top bar (round, phase, hint, "Rút"), the
## map (zoomed so cells are big, dragged to pan, pinched to zoom), and the
## bottom panel with a card or forecast, the selected leader's row of
## orders and one row of buttons ("Kết lượt" always among them). A tap on
## one of our leaders selects it; a tap on a blue cell moves it at once
## ("Hoàn tác" takes the move back); a tap on a red-ringed enemy shows the
## forecast from the safest cell that can strike it, and a second tap (or
## "Đánh") walks there and attacks. Pressing on the selected leader and dragging shows
## the ghosts under the finger and moves where it lifts. Once every leader
## of ours is done, the phase ends by itself after a short beat. The screen
## sends commands to its TacticsBattle and plays the events back through
## TacticsPlayback, then brings the map in line with the battle. It holds
## no rules: every list of cells, target, strike cell and forecast comes
## from the battle. With a TacticsCampaign the battle has incidents and
## roster records, and the end shows the after-battle summary.
## See Docs/systems/tactics_screen.md.
## [codeblock]
## var screen := TacticsScreen.new()
## screen.scenario = load("res://Data/Tactics/Scenarios/river_crossing.tres")
## screen.home_requested.connect(show_title)
## [/codeblock]

signal home_requested()
## The after-battle summary's "Tiếp tục" (only with a campaign).
signal campaign_continue_requested()
## Every time the screen is ready for the next tap (after a playback).
signal became_idle()

## MOVE_PREVIEW: a finger is dragging a leader's ghosts.
enum Mode {IDLE, SELECTED, MOVE_PREVIEW, FORECAST, SKILL_TARGET, SKILL_PREVIEW, BUSY, ENDED}

const CATALOG_PATH: String = "res://Data/Tactics/tactics_catalog.tres"
const LOOKS_PATH: String = "res://Data/Tactics/Looks/skill_looks.tres"
const TOP_BAR_PX: float = 92.0
const PANEL_PX: float = 430.0
const RETREAT_ARM_SEC: float = 3.0
## The beat between the last leader being done and the phase ending.
const AUTO_END_SEC: float = 1.0
## The beat is longer while the last move can still be taken back.
const AUTO_END_UNDO_SEC: float = 1.8
const UNDO_SEC: float = 0.25
const NO_CELL := Vector2i(-1, -1)

var scenario: TacticsScenarioData
## One Array of TacticsTroopData per leader of the player's side, from the
## muster screen; empty keeps the scenario's squads.
var squads: Array = []
var catalog: TacticsCatalog
## The roster around this battle; null plays it without incidents.
var campaign: TacticsCampaign
## Person ids per leader of ours, in the order of `squads`; empty takes
## the campaign's.
var squad_people: Array = []
## Tests: playback steps end at once and close-ups are skipped.
var is_instant: bool = false
## Ends our phase by itself once every leader of ours is done.
var auto_end: bool = true
var player_side: int = 0

var _battle: TacticsBattle
var _text: TacticsText
var _map: TacticsMapView
var _panel: TacticsPanel
var _banner: TacticsBanner
var _close_up: TacticsCloseUp
var _result: ResultBanner
var _playback: TacticsPlayback
var _skip_catcher: Control
var _round_label: Label
var _hint_label: Label
var _retreat_button: PressButton
var _mode: Mode = Mode.IDLE
var _selected: int = -1
var _pending_cell := NO_CELL
var _pending_target: int = -1
## The finger's cell while dragging a leader, and whether the leader was
## selected before the press.
var _drag_cell := NO_CELL
var _was_selected_before_drag: bool = false
## Bumped by every tap; a pending auto end goes ahead only if unchanged.
var _auto_end_ticket: int = 0
var _is_auto_end_pending: bool = false
var _is_order_change: bool = false
var _units: Array = []
var _zones: Array = []
var _intents: Array = []
var _is_retreat_armed: bool = false
var _hint_key: String = "TACTICS_HINT_IDLE"
var _retreat_arm_count: int = 0
var _summary: TacticsSummaryView
## Unit index -> marks its roster person carried in.
var _carried_marks: Dictionary = {}


func _ready() -> void:
	theme = GameTheme.create()
	if catalog == null:
		catalog = load(CATALOG_PATH) as TacticsCatalog
	_text = TacticsText.new(catalog)
	_battle = TacticsBattle.new()
	_battle.name = "Battle"
	add_child(_battle)
	var is_loaded := _battle.load_scenario_with_squads(scenario, player_side, squads) if not squads.is_empty() else _battle.load_scenario(scenario)
	if not is_loaded:
		push_error("TacticsScreen: the scenario %s did not load" % scenario.id)
		return
	# The other side plays itself, whichever side we are.
	_battle.set_side_ai(player_side, false)
	_battle.set_side_ai(1 - player_side, true)
	if campaign != null:
		campaign.fill_text(_text)
		if not campaign.prepare_battle(_battle, _people()):
			push_error("TacticsScreen: the campaign could not set up %s" % scenario.id)
	_build()
	_map.setup(_battle, scenario.map.objective_cell if scenario.map.objective_side == player_side else NO_CELL)
	_banner.max_rounds = scenario.rules.max_rounds
	_units = _battle.get_units()
	for state: Dictionary in _units:
		var piece := TacticsPieceView.new()
		var data := _text.unit_data(state["id"])
		piece.setup(state, TacticsPainter.glyph_for(data.base_class.id if data != null else &"", state["keywords"]))
		var person := campaign.get_person(state["record_id"]) if campaign != null else {}
		_carried_marks[state["index"]] = (person["marks"] as Array).size() if not person.is_empty() else 0
		_map.add_piece(piece, state["cell"])
	_map.center_on(_map.cell_to_local(_first_leader_cell()))
	_sync()
	Sound.play_music(&"music_battle")
	_run(_battle.start())


## The cell was tapped: selects, previews or confirms by what is there
## and what is selected now. Ignored while a playback runs.
func tap_cell(cell: Vector2i) -> void:
	if _mode == Mode.BUSY or _mode == Mode.ENDED or not _map.is_on_map(cell):
		return
	_disarm_retreat()
	_cancel_auto_end()
	var unit := _unit_at(cell)
	match _mode:
		Mode.FORECAST:
			if unit == _pending_target:
				confirm()
				return
		Mode.SKILL_TARGET, Mode.SKILL_PREVIEW:
			if _mode == Mode.SKILL_PREVIEW and cell == _pending_cell:
				confirm()
			elif _battle.get_skill_cells(_selected).has(cell):
				_preview_skill(cell)
			else:
				select_unit(_selected)
			return
	if _is_commandable(_selected) and _mode != Mode.IDLE:
		if unit >= 0 and _battle.get_strike_targets(_selected).has(unit):
			_show_forecast(unit)
			return
		if unit < 0 and _battle.can_move(_selected) and _battle.get_reachable_cells(_selected).has(cell):
			move_to(cell)
			return
	# Anything else: another unit is selected; a tap elsewhere steps back.
	if unit >= 0 and unit != _selected:
		select_unit(unit)
	elif _mode in [Mode.MOVE_PREVIEW, Mode.FORECAST]:
		select_unit(_selected)
	elif unit < 0 and _mode == Mode.IDLE:
		_show_terrain(cell)
	else:
		_go_idle()


## Selects a unit: ours shows where it can go and what it can hit; any
## other shows its card (and an enemy's intent).
func select_unit(unit: int) -> void:
	if _mode == Mode.BUSY or _mode == Mode.ENDED or unit < 0 or not _units[unit]["alive"]:
		return
	_cancel_auto_end()
	_selected = unit
	_pending_cell = NO_CELL
	_pending_target = -1
	_mode = Mode.SELECTED
	_map.set_marks(_selection_marks(unit))
	var state: Dictionary = _units[unit]
	if _is_commandable(unit):
		_set_hint(_selected_hint(unit))
		_panel.show_order_row(state["order"], _text)
	else:
		_panel.hide_order_row()
		if state["role"] == &"leader" and state["side"] != player_side:
			_set_hint("TACTICS_HINT_IDLE")
	_map.reveal(_map.cell_to_local(state["cell"]))
	_update_hold_cells()
	_show_unit_card(unit)
	_panel.set_buttons(_unit_buttons(unit))


## Moves the selected leader to a reachable cell at once (its squad steps
## with it); "Hoàn tác" can take it back while nothing else happened.
func move_to(cell: Vector2i) -> void:
	if not _is_commandable(_selected) or not _battle.can_move(_selected) or not _battle.get_reachable_cells(_selected).has(cell):
		return
	_run(_battle.move_leader(_selected, cell))


## Takes the selected leader's last move back: the battle returns to the
## exact state before it, and the pieces slide home.
func undo() -> void:
	if _mode == Mode.BUSY or _mode == Mode.ENDED or not _can_undo(_selected):
		return
	_cancel_auto_end()
	if not _battle.undo_move(_selected):
		return
	Sound.play(&"card_flip")
	_mode = Mode.BUSY
	_map.set_marks({})
	var tween := create_tween().set_parallel()
	for state: Dictionary in _battle.get_units():
		var piece := _map.get_piece(state["index"])
		if piece != null and state["alive"]:
			tween.tween_property(piece, ^"position", _map.cell_to_local(state["cell"]), UNDO_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.01)
	if is_instant:
		tween.custom_step(1000.0)
	if tween.is_running():
		await tween.finished
	_after_playback()
	_set_hint("TACTICS_HINT_UNDONE")


## Confirms what is previewed: the move, the attack or the skill.
func confirm() -> void:
	match _mode:
		Mode.FORECAST:
			_strike()
		Mode.SKILL_PREVIEW:
			_run(_battle.use_skill(_selected, _pending_cell))


## Back one step: a preview to its leader, a selection to nothing.
func cancel() -> void:
	if _mode in [Mode.MOVE_PREVIEW, Mode.FORECAST, Mode.SKILL_TARGET, Mode.SKILL_PREVIEW]:
		select_unit(_selected)
	elif _mode == Mode.SELECTED:
		_go_idle()


## Presses a panel button by its action, as a tap on it would.
func press_button(action: StringName) -> void:
	_on_action(action)


## One tap on the order row: the squad takes the order at once (the slots
## on the map follow it).
func choose_order(order: StringName) -> void:
	if _mode == Mode.BUSY or _mode == Mode.ENDED or not _is_commandable(_selected):
		return
	_cancel_auto_end()
	if order == _units[_selected]["order"]:
		select_unit(_selected)
		return
	_is_order_change = true
	_run(_battle.set_order(_selected, order))


## The retreat button: the first tap asks, a second within a few seconds
## leaves the battle (with a campaign, through the after-battle summary:
## what happened so far still counts).
func retreat() -> void:
	if _mode == Mode.ENDED:
		return
	if _is_retreat_armed:
		if campaign != null:
			_disarm_retreat()
			_show_summary()
			return
		home_requested.emit()
		return
	_is_retreat_armed = true
	_retreat_arm_count += 1
	_retreat_button.theme_type_variation = &"PrimaryButton"
	_hint_label.text = tr("TACTICS_RETREAT_CONFIRM")
	var arm_count := _retreat_arm_count
	get_tree().create_timer(RETREAT_ARM_SEC).timeout.connect(func() -> void:
		if arm_count == _retreat_arm_count:
			_disarm_retreat())


func is_busy() -> bool:
	return _mode == Mode.BUSY


## True while the phase is about to end by itself.
func is_auto_end_pending() -> bool:
	return _is_auto_end_pending


func get_mode() -> Mode:
	return _mode


func get_selected() -> int:
	return _selected


func get_battle() -> TacticsBattle:
	return _battle


func get_map() -> TacticsMapView:
	return _map


func get_panel() -> TacticsPanel:
	return _panel


func get_playback() -> TacticsPlayback:
	return _playback


func get_close_up() -> TacticsCloseUp:
	return _close_up


func get_result_banner() -> ResultBanner:
	return _result


func get_retreat_button() -> PressButton:
	return _retreat_button


## The after-battle summary once a campaign battle ended, else null.
func get_summary() -> TacticsSummaryView:
	return _summary


## The top bar's hint line as shown now.
func get_hint() -> String:
	return _hint_label.text


## The top bar's round and phase line as shown now.
func get_round_text() -> String:
	return _round_label.text


func _build() -> void:
	var background := ColorRect.new()
	background.color = Palette.BACKDROP
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_map = TacticsMapView.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.offset_top = TOP_BAR_PX
	_map.offset_bottom = -PANEL_PX
	_map.is_instant = is_instant
	_map.cell_tapped.connect(tap_cell)
	_map.cell_held.connect(_on_cell_held)
	_map.hold_released.connect(_on_hold_released)
	_map.hold_cancelled.connect(_on_hold_cancelled)
	add_child(_map)
	_panel = TacticsPanel.new()
	_panel.anchor_top = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = -PANEL_PX
	_panel.action_pressed.connect(_on_action)
	_panel.order_chosen.connect(choose_order)
	add_child(_panel)
	_banner = TacticsBanner.new()
	add_child(_banner)
	# A tap anywhere under the top bar skips the step that plays; the bar
	# stays above it (and above the close-up), so "Rút" works at any time.
	_skip_catcher = Control.new()
	_skip_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_skip_catcher.offset_top = TOP_BAR_PX
	_skip_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_skip_catcher.visible = false
	_skip_catcher.gui_input.connect(_on_skip_input)
	add_child(_skip_catcher)
	_close_up = TacticsCloseUp.new()
	add_child(_close_up)
	_build_top_bar()
	_result = ResultBanner.new()
	_result.button_pressed.connect(home_requested.emit)
	add_child(_result)
	_playback = TacticsPlayback.new()
	_playback.map = _map
	_playback.close_up = _close_up
	_playback.banner = _banner
	_playback.text = _text
	_playback.looks = load(LOOKS_PATH) as TacticsSkillLookSet
	_playback.player_side = player_side
	_playback.is_instant = is_instant
	_playback.phase_shown.connect(_on_phase_shown)
	add_child(_playback)


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.anchor_right = 1.0
	bar.offset_bottom = TOP_BAR_PX
	var box := GameTheme.make_panel(Palette.PANEL, 0, 4)
	box.content_margin_left = 16
	box.content_margin_right = 8
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	bar.add_theme_stylebox_override(&"panel", box)
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	bar.add_child(row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override(&"separation", 0)
	row.add_child(texts)
	_round_label = _bar_label(28, Palette.GOLD)
	texts.add_child(_round_label)
	_hint_label = _bar_label(GameTheme.SMALL_FONT_SIZE, Palette.CREAM)
	texts.add_child(_hint_label)
	_retreat_button = PressButton.new()
	_retreat_button.text = "BUTTON_RETREAT"
	_retreat_button.focus_mode = Control.FOCUS_NONE
	_retreat_button.custom_minimum_size = Vector2(140, 88)
	_retreat_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_retreat_button.add_theme_font_size_override(&"font_size", 26)
	_retreat_button.pressed.connect(func() -> void:
		Sound.play(&"ui_tap")
		retreat())
	row.add_child(_retreat_button)


func _bar_label(font_px: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", font_px)
	label.add_theme_color_override(&"font_color", color)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# Plays a command's events, then brings the map in line with the battle.
func _run(events: Array) -> void:
	if events.is_empty():
		_after_playback()
		return
	_mode = Mode.BUSY
	_skip_catcher.visible = true
	_map.set_marks({})
	_map.hold_cells = []
	_panel.set_buttons([{"action": &"end_turn", "text": "BUTTON_END_TURN", "enabled": false}])
	_playback.reset(_units, _zones)
	await _playback.play(events)
	_skip_catcher.visible = false
	_after_playback()


func _after_playback() -> void:
	_sync()
	if _summary != null:
		return
	if _battle.is_finished():
		_show_end()
		return
	var keep := _selected
	_mode = Mode.IDLE
	# A leader that is done goes back to the phase card, unless its move
	# can still be taken back or its order just changed.
	var was_order := _is_order_change
	_is_order_change = false
	if _is_commandable(keep) and (not _is_done(keep) or _can_undo(keep) or was_order):
		select_unit(keep)
	else:
		_go_idle()
	_update_hold_cells()
	_maybe_auto_end()
	became_idle.emit()


# Every piece, zone and intent as the battle has them now.
func _sync() -> void:
	_units = _battle.get_units()
	_zones = _battle.get_zones()
	for state: Dictionary in _units:
		var piece := _map.get_piece(state["index"])
		if piece == null:
			continue
		var is_alive: bool = state["alive"]
		piece.is_dead = not is_alive
		piece.visible = is_alive
		piece.hp = state["hp"]
		piece.position = _map.cell_to_local(state["cell"])
		piece.set_side(state["side"])
		piece.mark_count = int(_carried_marks.get(state["index"], 0)) + int(state["marks"])
		var is_wavering: bool = is_alive and state["wavering"] != &""
		piece.wavering = (TacticsPieceView.Wavering.GOOD if state["is_wavering_good"] else TacticsPieceView.Wavering.BAD) if is_wavering else TacticsPieceView.Wavering.NONE
		piece.wavering_scale = 1.0
		piece.is_done = state["role"] == &"leader" and state["side"] == player_side and _battle.get_active_side() == player_side and is_alive and _is_done(state["index"])
		if state["role"] == &"leader":
			var charge := _battle.get_skill_charge(state["index"])
			piece.set_charge(charge.get("value", 0), charge.get("threshold", 0))
	_map.set_zones(_zones)
	_intents.clear()
	if _battle.get_active_side() == player_side and not _battle.is_finished():
		for intent: Dictionary in _battle.get_enemy_intents():
			var entry := intent.duplicate()
			entry["from"] = _units[intent["unit"]]["cell"]
			_intents.append(entry)
	_map.set_intents(_intents)
	_show_round(_battle.get_round(), _battle.get_active_side())


func _show_round(round_number: int, side: int) -> void:
	_round_label.text = "%s · %s" % [tr("TACTICS_ROUND_FORMAT") % [round_number, scenario.rules.max_rounds], tr("TACTICS_PHASE_PLAYER") if side == player_side else tr("TACTICS_PHASE_ENEMY")]


# A phase begins inside a playback: the top bar and the panel say whose
# phase it is at once, not only when the playback is over.
func _on_phase_shown(side: int, round_number: int) -> void:
	_show_round(round_number, side)
	if side == player_side:
		_set_hint("TACTICS_HINT_IDLE")
		_show_our_phase_card(round_number)
		_bring_ours_into_view()
		return
	_set_hint("TACTICS_HINT_ENEMY_PHASE")
	var lines: Array[String] = [tr("TACTICS_HINT_ENEMY_PHASE"), "", ""]
	_panel.show_card(tr("TACTICS_PHASE_ENEMY"), TacticsPainter.ENEMY_FILL.lightened(0.35), tr("TACTICS_ROUND_FORMAT") % [round_number, scenario.rules.max_rounds], lines)


# Our phase asks to tap a leader of ours: if the enemy's moves or a drag
# left none on screen, the camera glides back to the first one.
func _bring_ours_into_view() -> void:
	var first := NO_CELL
	for state: Dictionary in _battle.get_units():
		if state["alive"] and state["role"] == &"leader" and state["side"] == player_side:
			if _map.is_in_view(_map.cell_to_local(state["cell"])):
				return
			first = state["cell"] if first == NO_CELL else first
	if first != NO_CELL:
		_map.follow(_map.cell_to_local(first))


func _go_idle() -> void:
	_mode = Mode.IDLE
	_selected = -1
	_pending_cell = NO_CELL
	_pending_target = -1
	_map.set_marks({})
	_panel.hide_order_row()
	var is_all_done := _are_all_done()
	var wavering_hint := _wavering_hint()
	_set_hint(wavering_hint if wavering_hint != "" else "TACTICS_HINT_ALL_DONE" if is_all_done else "TACTICS_HINT_IDLE")
	_show_our_phase_card(_battle.get_round())
	_panel.set_buttons(_end_turn_button(is_all_done))
	_update_hold_cells()


func _show_our_phase_card(round_number: int) -> void:
	var objective := _text.terrain_name(_map.get_terrain_at(scenario.map.objective_cell))
	var lines: Array[String] = [tr("TACTICS_OBJECTIVE_SHORT_FORMAT") % objective, tr(scenario.name_key), "", ""]
	_panel.show_card(tr("TACTICS_PHASE_PLAYER"), Palette.GOLD, tr("TACTICS_ROUND_FORMAT") % [round_number, scenario.rules.max_rounds], lines)


func _end_turn_button(is_primary: bool) -> Array[Dictionary]:
	var buttons: Array[Dictionary] = [{"action": &"end_turn", "text": "BUTTON_END_TURN", "primary": is_primary, "enabled": _battle.get_active_side() == player_side}]
	return buttons


# Blue cells only while the leader may still move; red outlines while it
# may act.
func _selected_hint(unit: int) -> String:
	if _battle.can_move(unit):
		return "TACTICS_HINT_SELECTED"
	if _can_undo(unit):
		return "TACTICS_HINT_MOVED"
	return "TACTICS_HINT_ACT" if not _is_done(unit) else "TACTICS_HINT_DONE"


func _unit_buttons(unit: int) -> Array[Dictionary]:
	if not _is_commandable(unit):
		return _end_turn_button(false)
	var can_act := _battle.can_act(unit)
	var buttons: Array[Dictionary] = [
		{"action": &"skill", "text": "BUTTON_SKILL", "enabled": can_act and not _battle.get_skill_cells(unit).is_empty(), "primary": can_act and bool(_battle.get_skill_charge(unit).get("is_ready", false))},
		{"action": &"wait", "text": "BUTTON_WAIT", "enabled": can_act},
	]
	if _can_undo(unit):
		buttons.append({"action": &"undo", "text": "BUTTON_UNDO"})
	buttons.append({"action": &"end_turn", "text": "BUTTON_END_TURN", "primary": _are_all_done()})
	return buttons


func _on_action(action: StringName) -> void:
	if _mode == Mode.BUSY or _mode == Mode.ENDED:
		return
	_disarm_retreat()
	_cancel_auto_end()
	match action:
		&"end_turn":
			_end_phase()
		&"wait":
			_run(_battle.wait(_selected))
		&"skill":
			_aim_skill()
		&"undo":
			undo()
		&"attack", &"cast":
			confirm()
		&"cancel":
			cancel()


func _on_skip_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		_playback.skip_step()


func _end_phase() -> void:
	_selected = -1
	_panel.hide_order_row()
	_run(_battle.end_phase())


# A finger pressed on one of our leaders: it is selected and its ghosts
# follow the finger until it lifts.
func _on_cell_held(cell: Vector2i) -> void:
	if _mode == Mode.BUSY or _mode == Mode.ENDED:
		return
	if _mode != Mode.MOVE_PREVIEW:
		var unit := _unit_at(cell)
		if not _is_commandable(unit) or not _battle.can_move(unit):
			return
		_disarm_retreat()
		_cancel_auto_end()
		_was_selected_before_drag = unit == _selected and _mode == Mode.SELECTED
		if unit != _selected or _mode != Mode.SELECTED:
			select_unit(unit)
		_mode = Mode.MOVE_PREVIEW
		_drag_cell = cell
		_set_hint("TACTICS_HINT_PREVIEW")
		return
	_drag_cell = cell
	_preview_move(cell)


func _on_hold_released(cell: Vector2i) -> void:
	if _mode != Mode.MOVE_PREVIEW:
		return
	var leader_cell: Vector2i = _units[_selected]["cell"]
	_mode = Mode.SELECTED
	_drag_cell = NO_CELL
	if cell == leader_cell:
		# Pressed and lifted on the leader: a tap on it.
		if _was_selected_before_drag:
			tap_cell(cell)
		else:
			select_unit(_selected)
		return
	if _battle.get_reachable_cells(_selected).has(cell) and _unit_at(cell) < 0:
		move_to(cell)
		return
	select_unit(_selected)


func _on_hold_cancelled() -> void:
	if _mode == Mode.MOVE_PREVIEW:
		_drag_cell = NO_CELL
		select_unit(_selected)


# Only the selected leader, while it can still move, starts a drag: a
# finger that lands on any other piece and slides pans the map, so a pan
# never moves a leader by surprise.
func _update_hold_cells() -> void:
	var cells: Array = []
	if _mode != Mode.BUSY and _mode != Mode.ENDED and _is_commandable(_selected) and _battle.can_move(_selected):
		cells.append(_units[_selected]["cell"])
	_map.hold_cells = cells


# The ghosts of the leader and its squad if it stopped on `cell`.
func _preview_move(cell: Vector2i) -> void:
	var leader: Dictionary = _units[_selected]
	var marks := _selection_marks(_selected)
	if cell != leader["cell"] and _battle.get_reachable_cells(_selected).has(cell) and _unit_at(cell) < 0:
		var ghosts: Array = [{"cell": cell, "from": leader["cell"], "side": player_side, "is_leader": true}]
		for placement: Dictionary in _battle.preview_squad(_selected, cell):
			ghosts.append({"cell": placement["cell"], "from": _units[placement["unit"]]["cell"], "side": player_side, "is_leader": false})
		marks["path"] = _battle.get_path_to(_selected, cell)
		marks["ghosts"] = ghosts
		marks.erase("slots")
	_map.set_marks(marks)


# The marks of a selected unit: where ours can go, what it can strike
# (after a walk too) and its squad's slots; an enemy leader's reach.
func _selection_marks(unit: int) -> Dictionary:
	var state: Dictionary = _units[unit]
	var marks := {"selected": state["cell"]}
	if _is_commandable(unit):
		if _battle.can_move(unit):
			marks["reachable"] = _battle.get_reachable_cells(unit)
		marks["attackable"] = _cells_of(_battle.get_strike_targets(unit))
		marks["slots"] = _battle.get_formation_slots(unit)
	elif state["role"] == &"leader" and state["side"] != player_side:
		marks["threat"] = _battle.get_reachable_cells(unit)
	return marks


# The forecast against `target` from the cell the battle picks (the safest
# one the leader can strike it from), with the walk and the ghosts.
func _show_forecast(target: int) -> void:
	var cell := _battle.get_strike_cell(_selected, target)
	if cell == NO_CELL:
		return
	var forecast := _battle.forecast_move_attack(_selected, cell, target)
	if not forecast.get("is_valid", false) and not forecast.get("target_gone", false):
		return
	_mode = Mode.FORECAST
	_pending_target = target
	_pending_cell = cell
	var attacker: Dictionary = _units[_selected]
	var defender: Dictionary = _units[target]
	var marks := _selection_marks(_selected)
	marks.erase("slots")
	marks["target"] = defender["cell"]
	var walk := 0
	if cell != attacker["cell"]:
		var path: Array = _battle.get_path_to(_selected, cell)
		walk = path.size() - 1
		marks["path"] = path
		var ghosts: Array = [{"cell": cell, "from": attacker["cell"], "side": player_side, "is_leader": true}]
		for placement: Dictionary in forecast.get("squad", []):
			if placement["cell"] != _units[placement["unit"]]["cell"]:
				ghosts.append({"cell": placement["cell"], "from": _units[placement["unit"]]["cell"], "side": player_side, "is_leader": false})
		marks["ghosts"] = ghosts
	_map.set_marks(marks)
	_map.reveal(_map.cell_to_local(defender["cell"]))
	var notes: PackedStringArray = [tr("FORECAST_WALK_FORMAT") % walk if walk > 0 else tr("FORECAST_STAY")]
	if forecast.get("target_gone", false):
		var gone_left: Array[String] = [_text.unit_name(attacker), notes[0], ""]
		var gone_right: Array[String] = [_text.unit_name(defender), tr("FORECAST_DIES"), ""]
		_panel.show_forecast(gone_left, gone_right, tr("FORECAST_TARGET_GONE"))
	else:
		var left: Array[String] = [
			_text.unit_name(attacker),
			tr("FORECAST_HITS_FORMAT") % [forecast["attacker_hits"], forecast["attacker_damage_per_hit"]],
			_hp_line(attacker["hp"], forecast["attacker_hp_after"], forecast["is_attacker_dead"]),
		]
		var right: Array[String] = [
			_text.unit_name(defender),
			tr("FORECAST_HITS_FORMAT") % [forecast["defender_hits"], forecast["defender_damage_per_hit"]] if forecast["can_counter"] else tr("FORECAST_NO_COUNTER"),
			_hp_line(defender["hp"], forecast["defender_hp_after"], forecast["is_defender_dead"]),
		]
		if forecast["is_first_strike"]:
			notes.append(tr("FORECAST_FIRST_STRIKE_FORMAT") % _text.unit_name(defender))
		var sides: PackedStringArray = []
		for pair: Array in [[attacker, forecast["attacker_modifiers"]], [defender, forecast["defender_modifiers"]]]:
			if not (pair[1] as Array).is_empty():
				sides.append(tr("FORECAST_SIDE_FORMAT") % [_text.unit_name(pair[0]), _text.keyword_names(pair[1])])
		notes.append(tr("FORECAST_MODIFIERS_FORMAT") % " · ".join(sides) if not sides.is_empty() else tr("FORECAST_NO_MODIFIERS"))
		_panel.show_forecast(left, right, " · ".join(notes))
	_set_hint("TACTICS_HINT_ATTACK_CONFIRM")
	_panel.set_buttons([
		{"action": &"cancel", "text": "BUTTON_CANCEL"},
		{"action": &"attack", "text": "BUTTON_ATTACK", "primary": true},
		{"action": &"end_turn", "text": "BUTTON_END_TURN"},
	])


# Walks to the forecast's cell (if it is not the leader's own) and
# attacks, played back as one; if the squad fells the target on the way,
# the walk is all.
func _strike() -> void:
	var leader := _selected
	var target := _pending_target
	var events: Array = []
	if _pending_cell != _units[leader]["cell"]:
		events = _battle.move_leader(leader, _pending_cell).duplicate()
		if events.is_empty():
			return
	if not _battle.is_finished() and _battle.get_unit_state(target)["alive"] and _battle.get_attack_targets(leader).has(target):
		events.append_array(_battle.attack(leader, target))
	_run(events)


func _hp_line(hp: int, hp_after: int, is_dead: bool) -> String:
	var line: String = tr("FORECAST_HP_FORMAT") % [hp, hp_after]
	return line + " · " + tr("FORECAST_DIES") if is_dead else line


func _aim_skill() -> void:
	var cells := _battle.get_skill_cells(_selected)
	if cells.is_empty():
		return
	# A skill with one possible cell (cast on the leader itself) goes
	# straight to its preview.
	if cells.size() == 1:
		_preview_skill(cells[0])
		return
	_mode = Mode.SKILL_TARGET
	_pending_cell = NO_CELL
	_map.set_marks({"selected": _units[_selected]["cell"], "skill_cells": cells})
	_set_hint("TACTICS_HINT_SKILL")
	_show_unit_card(_selected)
	_panel.set_buttons([{"action": &"cancel", "text": "BUTTON_CANCEL"}, {"action": &"end_turn", "text": "BUTTON_END_TURN"}])


func _preview_skill(cell: Vector2i) -> void:
	var preview := _battle.preview_skill(_selected, cell)
	if not preview.get("is_valid", false):
		return
	_mode = Mode.SKILL_PREVIEW
	_pending_cell = cell
	var marks := {"selected": _units[_selected]["cell"], "skill_cells": _battle.get_skill_cells(_selected), "area": preview["cells"], "target": cell}
	_map.set_marks(marks)
	var charge := _battle.get_skill_charge(_selected)
	var skill_id: StringName = charge["skill"]
	var lines: Array[String] = []
	for result: Dictionary in preview["results"]:
		if lines.size() < 3:
			var line: String = tr("SKILL_PREVIEW_HIT_FORMAT") % [_text.unit_name(_units[result["unit"]]), result["amount"], result["hp_after"]]
			lines.append(line + " · " + tr("FORECAST_DIES") if result["is_dead"] else line)
	var hit_count := (preview["results"] as Array).size()
	var buffed_count := (preview["buffed"] as Array).size()
	var has_zone := not (preview["zone_cells"] as Array).is_empty()
	# A cast that only leaves a zone says so on its line below.
	var side_note := "" if hit_count == 0 and buffed_count == 0 and has_zone else _text.skill_outcome(true, hit_count, buffed_count, &"")
	var zone := _skill_zone_name(skill_id)
	if has_zone and not zone.is_empty():
		lines.resize(mini(lines.size(), 2))
		lines.append(tr("SKILL_PREVIEW_ZONE_FORMAT") % zone)
	if lines.is_empty():
		lines.append(tr(catalog.get_skill(skill_id).description_key))
	_panel.show_card(_text.skill_name(skill_id), Palette.GOLD, side_note, lines)
	_set_hint("TACTICS_HINT_SKILL_CONFIRM")
	_panel.set_buttons([
		{"action": &"cancel", "text": "BUTTON_CANCEL"},
		{"action": &"cast", "text": "BUTTON_CAST", "primary": true},
		{"action": &"end_turn", "text": "BUTTON_END_TURN"},
	])


func _skill_zone_name(skill_id: StringName) -> String:
	var skill := catalog.get_skill(skill_id)
	if skill == null:
		return ""
	for effect: TacticsSkillEffectData in skill.effects:
		if effect.zone != null:
			return tr(effect.zone.name_key)
	return ""


# A unit's card: hp and marks on the right; for a leader its skill, its
# order (an enemy's declared intent instead), then its passives and
# keywords in words; for a soldier its leader (or what makes it waver),
# its keywords in words and the ground it stands on.
func _show_unit_card(unit: int) -> void:
	var state: Dictionary = _units[unit]
	var lines: Array[String] = []
	var title_color := TacticsPainter.PLAYER_FILL.lightened(0.45) if state["side"] == player_side else TacticsPainter.ENEMY_FILL.lightened(0.35)
	var side_note: String = tr("TACTICS_HP_FORMAT") % [state["hp"], state["max_hp"]]
	var details: Array[String] = []
	if state["role"] == &"leader":
		var charge := _battle.get_skill_charge(unit)
		if charge.get("is_ready", false):
			lines.append("%s · %s" % [_text.skill_name(charge["skill"]), tr("TACTICS_SKILL_READY")])
		else:
			lines.append(tr("TACTICS_SKILL_LINE_FORMAT") % [_text.skill_name(charge["skill"]), _text.charge_name(charge["charge"]), charge["value"], charge["threshold"]])
		var squad_line: String = tr("TACTICS_ORDER_FORMAT") % _text.order_name(state["order"]) + " · " + tr("TACTICS_SQUAD_FORMAT") % [_alive_soldiers(state), state["capacity"]]
		if state["side"] != player_side:
			squad_line = _intent_text(unit) + " · " + tr("TACTICS_SQUAD_FORMAT") % [_alive_soldiers(state), state["capacity"]]
		lines.append(squad_line)
		details.append_array(_text.passive_lines(state["id"]))
	else:
		var leader: int = state["leader"]
		lines.append(tr("TACTICS_SOLDIER_OF_FORMAT") % _text.unit_name(_units[leader]) if leader >= 0 and _units[leader]["alive"] else tr("TACTICS_NO_LEADER"))
		var wavering: StringName = state["wavering"]
		if wavering != &"":
			var incident := catalog.get_incident(wavering)
			lines.append(tr("TACTICS_WAVERING_LINE_FORMAT") % [_text.incident_name(wavering), tr(incident.name_key + "_HINT") if incident != null else ""])
		var marks := int(_carried_marks.get(unit, 0)) + int(state["marks"])
		if marks > 0:
			side_note += " · " + tr("TACTICS_MARKS_FORMAT") % marks
	details.append_array(_text.keyword_lines(state["keywords"]))
	for line: String in details:
		if lines.size() < TacticsPanel.CARD_LINES - 1:
			lines.append(line)
	lines.append(_terrain_line(state["cell"]))
	_panel.show_card(_text.unit_name(state), title_color, side_note, lines)


func _show_terrain(cell: Vector2i) -> void:
	var terrain := _map.get_terrain_at(cell)
	_map.set_marks({"selected": cell})
	var lines: Array[String] = [_text.terrain_effects(terrain), "", "", ""]
	if cell == scenario.map.objective_cell:
		lines[1] = tr("TACTICS_OBJECTIVE_SHORT_FORMAT") % _text.terrain_name(terrain)
	_panel.show_card(_text.terrain_name(terrain), Palette.CREAM, "", lines)


func _terrain_line(cell: Vector2i) -> String:
	var terrain := _map.get_terrain_at(cell)
	return tr("TACTICS_TERRAIN_FORMAT") % ("%s (%s)" % [_text.terrain_name(terrain), _text.terrain_effects(terrain)])


func _intent_text(unit: int) -> String:
	for intent: Dictionary in _intents:
		if intent["unit"] != unit:
			continue
		match intent["action"]:
			&"attack":
				return tr("INTENT_ATTACK_FORMAT") % _text.unit_name(_units[intent["target"]]) if intent["target"] >= 0 else tr("INTENT_WAIT")
			&"skill":
				return tr("INTENT_SKILL_FORMAT") % _text.skill_name(_battle.get_skill_charge(unit)["skill"])
		# A wait after a march shows an arrow on the map; the words agree.
		return tr("INTENT_MARCH") if intent["from"] != intent["to"] else tr("INTENT_WAIT")
	return tr("INTENT_WAIT")


func _alive_soldiers(leader: Dictionary) -> int:
	var count := 0
	for soldier: int in leader["soldiers"]:
		if _units[soldier]["alive"]:
			count += 1
	return count


func _show_end() -> void:
	_mode = Mode.ENDED
	_map.set_marks({})
	_map.set_intents([])
	_panel.set_buttons([])
	var is_win := _battle.get_winner() == player_side
	var key := "TACTICS_END_%s_%s" % [String(_battle.get_end_reason()).to_upper(), "WIN" if is_win else "LOSS"]
	Sound.play(&"win" if is_win else &"lose")
	_disarm_retreat()
	_set_hint(key)
	var lines: Array[String] = [tr(key), tr(scenario.name_key), ""]
	_panel.show_card(tr("RESULT_WIN") if is_win else tr("RESULT_LOSS"), Palette.GOLD if is_win else Palette.VERMILION, tr("TACTICS_ROUND_FORMAT") % [_battle.get_round(), scenario.rules.max_rounds], lines)
	if campaign == null:
		_result.present(is_win, tr(key), [], "BUTTON_HOME")
		return
	_show_summary()


# Writes the battle into the roster and shows what became of everyone.
func _show_summary() -> void:
	if _summary != null:
		return
	_mode = Mode.ENDED
	# Nothing plays on behind the summary.
	_playback.stop()
	_summary = TacticsSummaryView.new()
	_summary.campaign = campaign
	_summary.summary = campaign.finish_battle(_battle, _people())
	_summary.player_side = player_side
	_summary.is_instant = is_instant
	_summary.continue_requested.connect(campaign_continue_requested.emit)
	add_child(_summary)


func _people() -> Array:
	return squad_people if not squad_people.is_empty() else campaign.people


# One of our soldiers wavers in our phase: the hint says what to do, to
# calm a bad incident first; a good one is best left alone. Empty if none.
func _wavering_hint() -> String:
	if _battle.get_active_side() != player_side:
		return ""
	var hint := ""
	for state: Dictionary in _units:
		if state["alive"] and state["side"] == player_side and state["wavering"] != &"":
			if not state["is_wavering_good"]:
				return "TACTICS_HINT_WAVERING"
			hint = "TACTICS_HINT_WAVERING_GOOD"
	return hint


# A leader of ours with nothing left to do: it acted, or it moved and has
# no one to strike and no skill to cast.
func _is_done(unit: int) -> bool:
	if not _battle.can_act(unit):
		return true
	return not _battle.can_move(unit) and _battle.get_attack_targets(unit).is_empty() and _battle.get_skill_cells(unit).is_empty()


func _are_all_done() -> bool:
	if _battle.get_active_side() != player_side or _battle.is_finished():
		return false
	for state: Dictionary in _units:
		if _is_commandable(state["index"]) and not _is_done(state["index"]):
			return false
	return true


# Every leader of ours is done: after a short beat the phase ends, unless
# a tap came in between.
func _maybe_auto_end() -> void:
	if not auto_end or _mode == Mode.ENDED or not _are_all_done():
		return
	_auto_end_ticket += 1
	var ticket := _auto_end_ticket
	_is_auto_end_pending = true
	_set_hint("TACTICS_HINT_AUTO_END")
	Sound.play(&"timer_tick")
	var beat := AUTO_END_UNDO_SEC if _can_undo(_selected) else AUTO_END_SEC
	await get_tree().create_timer(0.05 if is_instant else beat).timeout
	if ticket != _auto_end_ticket or _mode == Mode.BUSY or _mode == Mode.ENDED or not _are_all_done():
		return
	_is_auto_end_pending = false
	_end_phase()


func _cancel_auto_end() -> void:
	_auto_end_ticket += 1
	if _is_auto_end_pending:
		_is_auto_end_pending = false
		_set_hint("TACTICS_HINT_ALL_DONE")


func _can_undo(unit: int) -> bool:
	return unit >= 0 and unit < _units.size() and _battle.can_undo_move(unit)


func _first_leader_cell() -> Vector2i:
	for state: Dictionary in _units:
		if state["alive"] and state["role"] == &"leader" and state["side"] == player_side:
			return state["cell"]
	return Vector2i(_map.map_width / 2, _map.map_height / 2)


func _is_commandable(unit: int) -> bool:
	if unit < 0 or unit >= _units.size():
		return false
	var state: Dictionary = _units[unit]
	return state["alive"] and state["role"] == &"leader" and state["side"] == player_side and _battle.get_active_side() == player_side and not _battle.is_finished()


# The living unit on a cell, a leader before a soldier; -1 if none.
func _unit_at(cell: Vector2i) -> int:
	var found := -1
	for state: Dictionary in _units:
		if state["alive"] and state["cell"] == cell:
			if state["role"] == &"leader":
				return state["index"]
			found = state["index"]
	return found


func _cells_of(units: Array) -> Array:
	var cells: Array = []
	for unit: int in units:
		cells.append(_units[unit]["cell"])
	return cells


# The hint for the current state; the retreat question covers it while
# armed and gives it back after.
func _set_hint(key: String) -> void:
	_hint_key = key
	if not _is_retreat_armed:
		_hint_label.text = tr(key)


func _disarm_retreat() -> void:
	if not _is_retreat_armed:
		return
	_is_retreat_armed = false
	_retreat_button.theme_type_variation = &""
	_hint_label.text = tr(_hint_key)
