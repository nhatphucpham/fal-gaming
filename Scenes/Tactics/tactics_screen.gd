class_name TacticsScreen
extends Control
## The tactics battle screen: a top bar (round, phase, hint, "Rút"), the
## map (zoomed so cells are big, dragged to pan, pinched to zoom), and the
## bottom panel with a card or forecast, the selected leader's row of
## orders and one row of buttons ("Kết lượt" always among them). A tap on
## one of our leaders selects it; a tap on a blue cell moves it at once
## and it stays selected, the blue cells now what its points left reach
## ("Hoàn tác" takes the moves back one by one); a tap on a red-ringed
## enemy shows the forecast from the safest cell that can strike it, and a
## second tap (or "Đánh") walks there and attacks. "Chờ" closes the
## leader's turn. Pressing on the selected leader and dragging shows the
## ghosts under the finger and moves where it lifts. Once every leader of
## ours is closed (it waited, or has nothing left to do), the phase ends
## by itself after a short beat. The screen
## sends commands to its TacticsBattle and plays the events back through
## TacticsPlayback, then brings the map in line with the battle. It holds
## no rules: every list of cells, target, strike cell and forecast comes
## from the battle. With a TacticsCampaign the battle has incidents and
## roster records, and the end shows the after-battle summary. Under fog of
## war the map shows only what our side sees (Docs/systems/tactics_vision.md):
## enemies out of sight are not drawn or offered, those remembered show as
## "?" where last seen, and a chip over the map's top-left shows the weather
## and the time of day (a tap says what they do). Sites and objectives
## (Docs/systems/tactics_sites.md, tactics_objectives.md): a line of the
## top bar names the objective and its progress (a tap on the bar shows
## what to do, the side goals and, escorting, holds or sends the convoy);
## a leader within reach
## of a site gets a button with the site's name that opens its choices; a
## tap on a site cell tells its state; the round before an enemy wave the
## banner warns and the cells it comes in by turn red.
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

## MOVE_PREVIEW: a finger is dragging a leader's ghosts; SITE_CHOICE: the
## panel shows the choices of a site within the selected leader's reach.
enum Mode {IDLE, SELECTED, MOVE_PREVIEW, FORECAST, SKILL_TARGET, SKILL_PREVIEW, BUSY, ENDED, SITE_CHOICE}

const CATALOG_PATH: String = "res://Data/Tactics/tactics_catalog.tres"
const LOOKS_PATH: String = "res://Data/Tactics/Looks/skill_looks.tres"
const TOP_BAR_PX: float = 92.0
const PANEL_PX: float = 430.0
## The panel's corner radius and border, filled behind with the backdrop.
const PANEL_CORNER_PX: float = 26.0
const RETREAT_ARM_SEC: float = 3.0
## The beat between the last leader being done and the phase ending.
const AUTO_END_SEC: float = 1.0
## The beat is longer while the last move can still be taken back.
const AUTO_END_UNDO_SEC: float = 1.8
const UNDO_SEC: float = 0.25
## Room the map's corner chip and "Toàn cảnh" take under the top bar.
const TIP_TOP_CLEAR_PX: float = 96.0
## A tip covering one unit of ours costs as much as covering this many of
## the enemy's.
const TIP_OUR_UNIT_WEIGHT: int = 100
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
var _tips: TacticsTip
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
var _environment_chip: PressButton
var _objective_chip: Button
var _objective_label: Label
## TacticsBattle.get_objective_state() as of the last sync.
var _objective: Dictionary = {}
# Banners that wait for our phase's own banner to go: {title, subtitle,
# is_ours, sound, sec, tip}, shown one after another.
var _warnings: Array[Dictionary] = []
## The site whose choices the panel shows (-1 none), and its choice when
## it asks which recruit.
var _site_shown: int = -1
var _recruit_choice: bool = false
var _weather_icon: TextureRect
var _daytime_icon: TextureRect
## Fog and night were drawn once; later changes blend in.
var _is_fog_shown: bool = false
## Unit index -> marks its roster person carried in.
var _carried_marks: Dictionary = {}
## Bonds whose cord shows now: Vector2i(a, b) -> true.
var _active_bonds: Dictionary = {}


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
	_playback.intent_filter = func(unit: int) -> bool: return _battle.is_intent_known(player_side, unit)
	_map.setup(_battle, _objective_cell())
	_banner.max_rounds = scenario.rules.max_rounds
	_playback.piece_factory = _on_unit_arrived
	_units = _battle.get_units()
	for state: Dictionary in _units:
		_add_piece(state)
	_map.center_on(_start_focus())
	_sync()
	Sound.play_music(&"music_battle")
	_run(_battle.start())


func _add_piece(state: Dictionary) -> TacticsPieceView:
	var piece := TacticsPieceView.new()
	var data := _text.unit_data(state["id"])
	piece.setup(state, TacticsPainter.glyph_for(data.base_class.id if data != null else &"", state["keywords"], state.get("is_noncombatant", false)))
	var person := campaign.get_person(state["record_id"]) if campaign != null else {}
	_carried_marks[state["index"]] = (person["marks"] as Array).size() if not person.is_empty() else 0
	_map.add_piece(piece, state["cell"])
	return piece


# A unit that arrived mid-battle, for the playback: its piece and state.
func _on_unit_arrived(event: Dictionary) -> Dictionary:
	var state := _battle.get_unit_state(event["unit"])
	if _map.get_piece(event["unit"]) == null:
		var piece := _add_piece(state)
		if state["role"] == &"leader":
			var charge := _battle.get_skill_charge(state["index"])
			piece.set_charge(charge.get("value", 0), charge.get("threshold", 0))
	return state


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
		Mode.SITE_CHOICE:
			# Any tap leaves the choices: on a unit it selects it.
			select_unit(unit if unit >= 0 else _selected)
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
	_site_shown = -1
	_recruit_choice = false
	_pending_cell = NO_CELL
	_pending_target = -1
	_mode = Mode.SELECTED
	_map.set_marks(_selection_marks(unit))
	var state: Dictionary = _units[unit]
	if _is_commandable(unit):
		_set_hint(_selected_hint(unit))
		# After "Chờ" the order is shown but can no longer change.
		_panel.show_order_row(state["order"], _text, _battle.can_act(unit))
		_tips.offer(&"select")
	else:
		_panel.hide_order_row()
		if state["role"] == &"leader" and state["side"] != player_side:
			_set_hint("TACTICS_HINT_IDLE")
	_map.reveal(_map.cell_to_local(state["cell"]))
	_update_hold_cells()
	_show_unit_card(unit)
	_panel.set_buttons(_unit_buttons(unit))


## Moves the selected leader to a reachable cell at once (its squad steps
## with it); "Hoàn tác" can take it back while nothing else happened. The
## leader stays selected while it can do more.
func move_to(cell: Vector2i) -> void:
	if not _is_commandable(_selected) or not _battle.can_move(_selected) or not _battle.get_reachable_cells(_selected).has(cell):
		return
	_run(_battle.move_leader(_selected, cell))


## Takes the selected leader's last move back (one step; press again for
## the one before): the battle returns to the exact state before it, and
## the pieces slide home.
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
	if _mode == Mode.SITE_CHOICE:
		select_unit(_selected)
		return
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
	if _mode == Mode.BUSY or _mode == Mode.ENDED or not _is_commandable(_selected) or not _battle.can_act(_selected):
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


## The first-time tips over the map.
func get_tips() -> TacticsTip:
	return _tips


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
	# Behind the panel's rounded corners only (a strip along its top and
	# one along its bottom): the top bar is square and the map draws its
	# own backdrop where the board leaves a gap, so no fill sits under the
	# board or the panel every frame.
	for top: float in [-PANEL_PX, -PANEL_CORNER_PX]:
		var background := ColorRect.new()
		background.color = Palette.BACKDROP
		background.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		background.offset_top = top
		background.offset_bottom = top + PANEL_CORNER_PX
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(background)
	_map = TacticsMapView.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.offset_top = TOP_BAR_PX
	_map.offset_bottom = -PANEL_PX
	_map.is_instant = is_instant
	_map.our_side = player_side
	_map.cell_tapped.connect(tap_cell)
	_map.cell_held.connect(_on_cell_held)
	_map.hold_released.connect(_on_hold_released)
	_map.hold_cancelled.connect(_on_hold_cancelled)
	_map.camera_settled.connect(func() -> void:
		if _tips != null:
			_tips.refresh_place())
	add_child(_map)
	_panel = TacticsPanel.new()
	_panel.anchor_top = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = -PANEL_PX
	_panel.action_pressed.connect(_on_action)
	_panel.order_chosen.connect(choose_order)
	add_child(_panel)
	_tips = TacticsTip.new()
	_tips.bottom_px = PANEL_PX
	# Under the top bar, clear of the map's corner chip and button.
	_tips.top_px = TOP_BAR_PX + TIP_TOP_CLEAR_PX
	_tips.avoid_rects = _tip_avoid_rects
	add_child(_tips)
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
	_playback.phase_banner_ended.connect(_on_phase_banner_ended)
	_playback.environment_changed.connect(_on_environment_changed)
	add_child(_playback)
	_playback.supplies_gained.connect(_on_supplies_gained)
	_build_environment_chip()


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
	# The texts are one flat button: a tap shows the objective.
	_objective_chip = Button.new()
	_objective_chip.name = "ObjectiveChip"
	_objective_chip.flat = true
	_objective_chip.focus_mode = Control.FOCUS_NONE
	_objective_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_objective_chip.custom_minimum_size = Vector2(0, 88)
	_objective_chip.pressed.connect(func() -> void:
		Sound.play(&"ui_tap")
		show_objective())
	row.add_child(_objective_chip)
	var texts := VBoxContainer.new()
	texts.set_anchors_preset(Control.PRESET_FULL_RECT)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override(&"separation", -4)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_chip.add_child(texts)
	_round_label = _bar_label(26, Palette.GOLD)
	texts.add_child(_round_label)
	_objective_label = _bar_label(GameTheme.SMALL_FONT_SIZE, Palette.JADE_LIGHT)
	_objective_label.visible = false
	texts.add_child(_objective_label)
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


# The weather and the time of day over the map's top-left corner (the
# whole-map button holds the top-right), one tap
# target (the top bar keeps its room for the hint); a tap says what both do.
func _build_environment_chip() -> void:
	_environment_chip = PressButton.new()
	_environment_chip.focus_mode = Control.FOCUS_NONE
	_environment_chip.custom_minimum_size = Vector2(132, 88)
	_environment_chip.offset_left = 8
	_environment_chip.offset_right = 8 + _environment_chip.custom_minimum_size.x
	_environment_chip.offset_top = TOP_BAR_PX + 8
	_environment_chip.offset_bottom = TOP_BAR_PX + 8 + _environment_chip.custom_minimum_size.y
	_environment_chip.pressed.connect(func() -> void:
		Sound.play(&"ui_tap")
		show_environment())
	var icons := HBoxContainer.new()
	icons.set_anchors_preset(Control.PRESET_FULL_RECT)
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	icons.add_theme_constant_override(&"separation", 4)
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_environment_chip.add_child(icons)
	_weather_icon = _chip_icon()
	icons.add_child(_weather_icon)
	_daytime_icon = _chip_icon()
	icons.add_child(_daytime_icon)
	# Under the skip catcher and the close-up: it cannot be pressed while a
	# playback runs.
	add_child(_environment_chip)
	move_child(_environment_chip, _map.get_index() + 1)


## The top bar's texts, a button: a tap shows the objective.
func get_objective_chip() -> Button:
	return _objective_chip


## The objective line of the top bar now (its name and progress), for tests.
func get_objective_chip_text() -> String:
	return _objective_label.text


func _objective_kind() -> StringName:
	return _objective.get("kind", &"")


# OBJECTIVE_KIND_TAKE_PASS and the like, from objective_kind.take_pass.
func _kind_key(prefix: String) -> String:
	return prefix + String(_objective_kind()).trim_prefix("objective_kind.").to_upper()


func _update_objective_chip() -> void:
	var kind := _objective_kind()
	_objective_label.visible = kind != &""
	_objective_chip.disabled = kind == &""
	if kind == &"":
		return
	var line := "%s: %s" % [tr(_kind_key("OBJECTIVE_KIND_")), _objective_progress_text()]
	if _objective_label.text != line:
		_objective_label.text = line


# The objective's progress in a few words, from what our side knows.
func _objective_progress_text() -> String:
	match _objective_kind():
		&"objective_kind.take_pass", &"objective_kind.hold_city":
			var site := _site_state(int(_objective["site"]))
			if site.is_empty():
				return ""
			if _objective_kind() == &"objective_kind.hold_city":
				if int(site["owner"]) != player_side:
					return tr("OBJECTIVE_PROGRESS_KEEP_LOST")
				return tr("OBJECTIVE_PROGRESS_ROUNDS_FORMAT") % [mini(maxi(_battle.get_round() - 1, 0), int(_objective["rounds"])), _objective["rounds"]]
			if int(site["owner"]) == player_side:
				return tr("OBJECTIVE_PROGRESS_HELD")
			if int(site["capture_side"]) == player_side and int(site["capture_progress"]) > 0:
				return tr("OBJECTIVE_PROGRESS_CAPTURE_FORMAT") % [site["capture_progress"], site["capture_phases"]]
			return tr("OBJECTIVE_PROGRESS_NOT_HELD")
		&"objective_kind.escort":
			if _objective["convoy_holds"]:
				return tr("OBJECTIVE_PROGRESS_HOLDING")
			if _can_steer_convoy(int(_objective["convoy"])) and _convoy_stop_key() != "":
				return tr("OBJECTIVE_PROGRESS_ROAD_STUCK_FORMAT") % _road_left()
			return tr("OBJECTIVE_PROGRESS_ROAD_FORMAT") % _road_left()
		&"objective_kind.break_siege":
			return tr("OBJECTIVE_PROGRESS_ESCAPED_FORMAT") % [_objective["escaped"], _objective["count"]]
		&"objective_kind.slay_general":
			return tr("OBJECTIVE_PROGRESS_FLEEING") if _objective["general_fleeing"] else tr("OBJECTIVE_PROGRESS_HUNT")
	return ""


# Road cells the convoy still has to go.
func _road_left() -> int:
	var convoy: int = _objective.get("convoy", -1)
	var road: Array = _objective.get("road_cells", [])
	if convoy < 0 or convoy >= _units.size():
		return road.size()
	var at := road.find(_units[convoy]["cell"])
	return road.size() - 1 - at if at >= 0 else road.size()


func _site_state(site: int) -> Dictionary:
	for entry: Dictionary in _map.get_sites():
		if entry["site"] == site:
			return entry
	return {}


## What the objective asks, its side goals and (escorting, in our phase)
## the convoy's hold or go, on the panel (the chip's tap).
func show_objective() -> void:
	if _mode == Mode.BUSY or _mode == Mode.ENDED or _objective_kind() == &"":
		return
	_go_idle()
	var lines: Array[String] = [_objective_line(), tr(scenario.name_key)]
	lines.append_array(_goal_lines())
	_panel.show_card(tr("OBJECTIVE_CARD_TITLE") + ": " + tr(_kind_key("OBJECTIVE_KIND_")), Palette.GOLD, _objective_progress_text(), lines)
	var is_escort := _objective_kind() == &"objective_kind.escort"
	_panel.set_buttons(_convoy_buttons() if is_escort and _can_steer_convoy(int(_objective["convoy"])) else _end_turn_button(_are_only_walks_left()))
	_set_hint(_kind_key("OBJECTIVE_KIND_"))


func _is_convoy(unit: int) -> bool:
	return unit >= 0 and unit == int(_objective.get("convoy", -1))


# The cart, alive, in our phase: the player may hold it or let it roll.
func _can_steer_convoy(unit: int) -> bool:
	return _is_convoy(unit) and unit < _units.size() and _units[unit]["alive"] and _battle.get_active_side() == player_side and not _battle.is_finished()


func _convoy_buttons() -> Array[Dictionary]:
	var holds: bool = _objective.get("convoy_holds", false)
	var buttons := _end_turn_button(_are_only_walks_left())
	buttons.push_front({"action": &"convoy_go" if holds else &"convoy_hold", "text": "BUTTON_CONVOY_GO" if holds else "BUTTON_CONVOY_HOLD"})
	return buttons


# Why the cart stands still this phase ("" when it will roll): held, an
# enemy we see on its next road cell, or no free cell ahead.
func _convoy_stop_key() -> String:
	if _objective.get("convoy_holds", false):
		return "TACTICS_CONVOY_HELD"
	if not _battle.get_convoy_path().is_empty():
		return ""
	var road: Array = _objective.get("road_cells", [])
	var at := road.find(_units[int(_objective["convoy"])]["cell"])
	if at >= 0 and at + 1 < road.size():
		var blocker := _unit_at(road[at + 1])
		if blocker >= 0 and _units[blocker]["side"] != player_side:
			return "TACTICS_CONVOY_ENEMY_AHEAD"
	return "TACTICS_CONVOY_BLOCKED"


# The cart's card: how it rolls, the road left, and this phase's walk or
# why it waits.
func _show_convoy_card(unit: int) -> void:
	var state: Dictionary = _units[unit]
	var lines: Array[String] = [tr("TACTICS_CONVOY_RULE_FORMAT") % int(state["move_points"]), tr("TACTICS_CONVOY_ROAD_FORMAT") % _road_left()]
	if _can_steer_convoy(unit):
		var stop := _convoy_stop_key()
		lines.append(tr(stop) if stop != "" else tr("TACTICS_CONVOY_WILL_GO_FORMAT") % (_battle.get_convoy_path().size() - 1))
	lines.append(_terrain_line(state["cell"]))
	_panel.show_card(_text.unit_name(state), TacticsPainter.PLAYER_FILL.lightened(0.45), tr("TACTICS_HP_FORMAT") % [state["hp"], state["max_hp"]], lines)


# The objective in one short line.
func _objective_line() -> String:
	var site_name := ""
	var site := int(_objective.get("site", -1))
	if site >= 0:
		var data := catalog.get_site(_site_state(site).get("id", &""))
		site_name = tr(data.name_key) if data != null else ""
	match _objective_kind():
		&"objective_kind.take_pass":
			return tr("OBJECTIVE_SHORT_TAKE_PASS_FORMAT") % site_name
		&"objective_kind.hold_city":
			return tr("OBJECTIVE_SHORT_HOLD_CITY_FORMAT") % [site_name, _objective["rounds"]]
		&"objective_kind.escort":
			return tr("OBJECTIVE_SHORT_ESCORT")
		&"objective_kind.break_siege":
			return tr("OBJECTIVE_SHORT_BREAK_SIEGE_FORMAT") % [_objective["count"], _required_leader_name()]
		&"objective_kind.slay_general":
			var general: int = _objective["general"]
			return tr("OBJECTIVE_SHORT_SLAY_GENERAL_FORMAT") % (_text.unit_name(_units[general]) if general >= 0 else "")
		&"objective_kind.cell":
			return tr("TACTICS_OBJECTIVE_SHORT_FORMAT") % _text.terrain_name(_map.get_terrain_at(_objective_cell()))
	return ""


# The leader that must break out (by scenario order among our leaders).
func _required_leader_name() -> String:
	var order := 0
	for state: Dictionary in _units:
		if state["role"] == &"leader" and state["start_side"] == player_side and state.get("arrival", &"") == &"":
			if order == int(_objective.get("required_leader", -1)):
				return _text.unit_name(state)
			order += 1
	return ""


# One line per side goal: what it asks, its reward, met or not.
func _goal_lines() -> Array[String]:
	var lines: Array[String] = []
	for goal: Dictionary in _objective.get("goals", []):
		var what := _goal_name(goal)
		lines.append(tr("OBJECTIVE_GOAL_MET_FORMAT") % what if goal["is_met"] else tr("OBJECTIVE_GOAL_LINE_FORMAT") % [what, goal["supplies"]])
	return lines


func _goal_name(goal: Dictionary) -> String:
	if goal["kind"] == &"goal.by_round":
		return tr("GOAL_BY_ROUND_FORMAT") % goal["value"]
	return tr("GOAL_" + String(goal["kind"]).trim_prefix("goal.").to_upper())


# Supplies rise at the top of the map, under the objective line.
func _on_supplies_gained(amount: int, _total: int) -> void:
	var at := _map.view_to_board(Vector2(_map.size.x / 2.0, 60.0))
	_map.float_text(at, tr("TACTICS_FLOAT_SUPPLIES_FORMAT") % amount, Palette.GOLD, 26)


# Enemy wave entries to mark: waves still to come this round or the next.
func _upcoming_entries() -> Array:
	var cells: Array = []
	var round_number := _battle.get_round()
	var waves: Array = _objective.get("waves", [])
	for index: int in range(int(_objective.get("waves_sent", 0)), waves.size()):
		var wave: Dictionary = waves[index]
		if int(wave["round"]) <= round_number + 1:
			cells.append_array(wave["entry_cells"])
	return cells


# The round before an enemy wave comes, a banner and the horn say so.
func _warn_wave(round_number: int) -> void:
	var waves: Array = _objective.get("waves", [])
	for index: int in range(int(_objective.get("waves_sent", 0)), waves.size()):
		var wave: Dictionary = waves[index]
		if int(wave["round"]) != round_number + 1:
			continue
		_warnings.append({"title": tr("TACTICS_BANNER_WAVE_SOON"), "subtitle": tr("TACTICS_BANNER_WAVE_SOON_FORMAT") % [wave["leaders"], tr(_direction_key(wave["entry_cells"]))],
			"is_ours": false, "sound": &"war_horn", "sec": TacticsPlayback.BANNER_SEC * 1.8, "tip": &"wave"})
		return


func _on_phase_banner_ended(side: int, _round_number: int) -> void:
	if side == player_side:
		_show_next_warning()


# The next queued warning on the banner (under the phase's own banner it
# would be hidden at once), then the one after it.
func _show_next_warning() -> void:
	if _warnings.is_empty() or _battle.is_finished():
		_warnings.clear()
		return
	var warning: Dictionary = _warnings.pop_front()
	Sound.play(warning["sound"])
	_banner.present(warning["title"], warning["subtitle"], warning["is_ours"])
	if warning["tip"] != &"":
		_tips.offer(warning["tip"])
	get_tree().create_timer(0.01 if is_instant else float(warning["sec"])).timeout.connect(_on_warning_shown)


func _on_warning_shown() -> void:
	_banner.dismiss()
	_show_next_warning()


# Which edge the cells sit on: north, south, east or west.
func _direction_key(cells: Array) -> String:
	var cell: Vector2i = cells[0] if not cells.is_empty() else Vector2i.ZERO
	if cell.y == 0:
		return "DIR_NORTH"
	if cell.y == _map.map_height - 1:
		return "DIR_SOUTH"
	return "DIR_WEST" if cell.x < _map.map_width / 2 else "DIR_EAST"


# Sites as our side knows them, the objective's marks and the chip.
func _sync_objective() -> void:
	_objective = _battle.get_objective_state()
	_map.set_sites(_battle.get_sites(player_side))
	var marks := {}
	match _objective_kind():
		&"objective_kind.break_siege":
			marks["exits"] = _objective["exit_cells"]
		&"objective_kind.slay_general":
			marks["enemy_exits"] = _objective["exit_cells"]
		&"objective_kind.escort":
			marks["road"] = _objective["road_cells"]
			if _battle.get_active_side() == player_side and not _battle.is_finished():
				marks["convoy_path"] = _battle.get_convoy_path()
	var entries := _upcoming_entries()
	if not entries.is_empty() and not _battle.is_finished():
		marks["entries"] = entries
	_map.set_objective_marks(marks)
	_update_objective_chip()


func _chip_icon() -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


## The weather and the time of day in words on the panel (the chip's tap).
func show_environment() -> void:
	if _mode == Mode.BUSY or _mode == Mode.ENDED:
		return
	_go_idle()
	var round_number := _battle.get_round()
	var weather := _battle.get_weather_id(round_number)
	var daytime := _battle.get_daytime_id(round_number)
	var lines: Array[String] = [
		_environment_line(&"weather", weather),
		_environment_line(&"daytime", daytime),
	]
	var change := _battle.get_weather_change_round()
	if change > round_number:
		lines.append(tr("TACTICS_WEATHER_LATER_FORMAT") % [change, _text.environment_name(&"weather", _battle.get_weather_id(change))])
	if _battle.has_fog_of_war():
		lines.append(tr("TACTICS_FOG_LINE"))
	_panel.show_card(tr("TACTICS_ENVIRONMENT_TITLE"), Palette.CREAM, "", lines)
	_set_hint(_text.environment_description(&"weather", weather))


func _environment_line(kind: StringName, id: StringName) -> String:
	return _text.environment_description(kind, id) if id != &"" else ""


func get_environment_chip() -> PressButton:
	return _environment_chip


func _on_environment_changed(_kind: StringName, _id: StringName) -> void:
	_show_environment_icons()
	var daytime := _text.environment_data(&"daytime", _battle.get_daytime_id(_battle.get_round())) as TacticsDaytimeData
	_map.update_night(_battle.get_lit_cells(), daytime.darkness_pct / 100.0 if daytime != null else 0.0, not is_instant)


func _show_environment_icons() -> void:
	var round_number := maxi(_battle.get_round(), 1)
	var weather := _text.environment_data(&"weather", _battle.get_weather_id(round_number)) as TacticsWeatherData
	var daytime := _text.environment_data(&"daytime", _battle.get_daytime_id(round_number)) as TacticsDaytimeData
	_weather_icon.texture = weather.icon if weather != null else null
	_daytime_icon.texture = daytime.icon if daytime != null else null
	_weather_icon.visible = weather != null
	_daytime_icon.visible = daytime != null
	_environment_chip.visible = weather != null or daytime != null


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
	# A leader that is closed goes back to the phase card, unless its move
	# can still be taken back or its order just changed.
	var was_order := _is_order_change
	_is_order_change = false
	if _is_commandable(keep) and (not _is_done(keep) or _can_undo(keep) or was_order):
		select_unit(keep)
	elif _can_steer_convoy(keep):
		select_unit(keep)
	else:
		_go_idle()
	_update_hold_cells()
	_offer_tips(keep, was_order)
	_tips.refresh_place()
	_maybe_auto_end()
	became_idle.emit()


# Every piece, zone and intent as the battle has them now.
func _sync() -> void:
	_units = _battle.get_units()
	_zones = _battle.get_zones()
	for state: Dictionary in _units:
		var piece := _map.get_piece(state["index"])
		if piece == null:
			piece = _add_piece(state)
		var is_alive: bool = state["alive"]
		piece.is_dead = not is_alive
		piece.visible = is_alive and _is_seen(state["index"])
		piece.modulate.a = 1.0
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
	_sync_vision()
	_sync_objective()
	_intents.clear()
	if _battle.get_active_side() == player_side and not _battle.is_finished():
		for intent: Dictionary in _battle.get_enemy_intents():
			var entry := intent.duplicate()
			entry["from"] = _units[intent["unit"]]["cell"]
			_intents.append(entry)
	_map.set_intents(_intents)
	_sync_bonds()
	_show_round(_battle.get_round(), _battle.get_active_side())


# The gold cord between bonded leaders of ours standing close (the bonus
# is on); a cord that appears floats its bonus with a sound.
func _sync_bonds() -> void:
	var links: Array = []
	for bond: Dictionary in _battle.get_bonds():
		if not bond["is_active"] or _units[bond["a"]]["side"] != player_side:
			continue
		var link := {"from": _units[bond["a"]]["cell"], "to": _units[bond["b"]]["cell"], "level": bond["level"]}
		links.append(link)
		var key := Vector2i(bond["a"], bond["b"])
		if not _active_bonds.has(key):
			var middle := (_map.cell_to_local(link["from"]) + _map.cell_to_local(link["to"])) / 2.0
			_map.float_text(middle, tr("BOND_FLOAT_FORMAT") % bond["attack_pct"], Palette.GOLD, 24)
			Sound.play(&"formation_on")
	_active_bonds.clear()
	for bond: Dictionary in _battle.get_bonds():
		if bond["is_active"]:
			_active_bonds[Vector2i(bond["a"], bond["b"])] = true
	_map.set_bond_links(links)


# Fog, night, lights, remembered enemies and the edge marks of our
# wavering soldiers, as the battle has them now.
func _sync_vision() -> void:
	var daytime := _text.environment_data(&"daytime", _battle.get_daytime_id(maxi(_battle.get_round(), 1))) as TacticsDaytimeData
	var darkness := daytime.darkness_pct / 100.0 if daytime != null else 0.0
	var fog := _battle.get_fog_cells(player_side) if _battle.has_fog_of_war() else PackedByteArray()
	_map.set_fog(fog, _battle.get_lit_cells() if darkness > 0.0 else PackedByteArray(), darkness, _is_fog_shown and not is_instant)
	_is_fog_shown = true
	var ghosts: Array = []
	for ghost: Dictionary in _battle.get_last_seen(player_side):
		ghosts.append({"unit": ghost["unit"], "cell": ghost["cell"], "is_leader": _units[ghost["unit"]]["role"] == &"leader"})
	_map.set_last_seen(ghosts)
	var wavering: Array = []
	for state: Dictionary in _units:
		if state["alive"] and state["side"] == player_side and state["wavering"] != &"" and not state["is_wavering_good"]:
			wavering.append(state["cell"])
	_map.set_edge_marks(wavering)
	_show_environment_icons()


# Our side sees the unit now (always its own).
func _is_seen(unit: int) -> bool:
	return _units[unit]["side"] == player_side or _battle.is_unit_seen(player_side, unit)


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
		_warn_weather(round_number)
		_objective = _battle.get_objective_state()
		_warn_wave(round_number)
		if _battle.has_fog_of_war():
			_tips.offer(&"fog")
		_offer_objective_tips()
		return
	_set_hint("TACTICS_HINT_ENEMY_PHASE")
	var lines: Array[String] = [tr("TACTICS_HINT_ENEMY_PHASE"), "", ""]
	_panel.show_card(tr("TACTICS_PHASE_ENEMY"), TacticsPainter.ENEMY_FILL.lightened(0.35), tr("TACTICS_ROUND_FORMAT") % [round_number, scenario.rules.max_rounds], lines)


# The round before the weather turns, a banner says so.
func _warn_weather(round_number: int) -> void:
	var change := _battle.get_weather_change_round()
	if change <= 0 or round_number != change - 1:
		return
	_warnings.append({"title": tr("TACTICS_WEATHER_SOON_FORMAT") % _text.environment_name(&"weather", _battle.get_weather_id(change)),
		"subtitle": _text.environment_description(&"weather", _battle.get_weather_id(change)), "is_ours": true, "sound": &"weather_turn", "sec": TacticsPlayback.BANNER_SEC * 1.6, "tip": &""})


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
	_site_shown = -1
	_recruit_choice = false
	_pending_cell = NO_CELL
	_pending_target = -1
	_map.set_marks({})
	_panel.hide_order_row()
	var is_all_done := _are_all_done()
	var is_only_walks := _are_only_walks_left()
	var wavering_hint := _wavering_hint()
	var hint := "TACTICS_HINT_ALL_DONE" if is_all_done else "TACTICS_HINT_ONLY_WALKS" if is_only_walks else "TACTICS_HINT_IDLE"
	_set_hint(wavering_hint if wavering_hint != "" else hint)
	_show_our_phase_card(_battle.get_round())
	_panel.set_buttons(_end_turn_button(is_only_walks))
	_update_hold_cells()


# The cell the objective points at: the stronghold or the general's post;
# a plain objective cell only for the side that must take it.
func _objective_cell() -> Vector2i:
	var state := _battle.get_objective_state()
	if state.get("kind", &"") == &"objective_kind.cell" and int(state.get("side", -1)) != player_side:
		return NO_CELL
	return state.get("cell", NO_CELL)


func _show_our_phase_card(round_number: int) -> void:
	if _objective.is_empty():
		_objective = _battle.get_objective_state()
	var lines: Array[String] = [_objective_line(), tr(scenario.name_key), "", ""]
	_panel.show_card(tr("TACTICS_PHASE_PLAYER"), Palette.GOLD, tr("TACTICS_ROUND_FORMAT") % [round_number, scenario.rules.max_rounds], lines)


func _end_turn_button(is_primary: bool) -> Array[Dictionary]:
	var buttons: Array[Dictionary] = [{"action": &"end_turn", "text": "BUTTON_END_TURN", "primary": is_primary, "enabled": _battle.get_active_side() == player_side}]
	return buttons


# Blue cells only while the leader's points reach a cell; red outlines
# while it may still attack.
# Once it struck, the red rings are gone: the hint says what is left.
func _selected_hint(unit: int) -> String:
	var state: Dictionary = _units[unit]
	if _battle.can_move(unit):
		if not _battle.get_strike_targets(unit).is_empty():
			return "TACTICS_HINT_MOVE_ON" if state["has_moved"] else "TACTICS_HINT_SELECTED"
		return "TACTICS_HINT_MOVE_ON_STRUCK" if state["has_attacked"] else "TACTICS_HINT_WALK_ONLY"
	if _can_undo(unit):
		return "TACTICS_HINT_MOVED" if not _battle.get_strike_targets(unit).is_empty() else "TACTICS_HINT_MOVED_NO_TARGET"
	if _is_done(unit):
		return "TACTICS_HINT_DONE"
	return "TACTICS_HINT_ACT" if not _battle.get_strike_targets(unit).is_empty() else "TACTICS_HINT_SKILL_LEFT"


func _unit_buttons(unit: int) -> Array[Dictionary]:
	if _can_steer_convoy(unit):
		return _convoy_buttons()
	if not _is_commandable(unit):
		return _end_turn_button(false)
	var can_act := _battle.can_act(unit)
	var buttons: Array[Dictionary] = [
		{"action": &"skill", "text": "BUTTON_SKILL", "enabled": can_act and not _battle.get_skill_cells(unit).is_empty(), "primary": can_act and bool(_battle.get_skill_charge(unit).get("is_ready", false))},
	]
	var site := _site_action(unit)
	if not site.is_empty():
		var data := catalog.get_site(site["site_id"])
		buttons.append({"action": &"site", "text": data.name_key if data != null else "SITE_VILLAGE", "enabled": _site_can(site)})
	buttons.append({"action": &"wait", "text": "BUTTON_WAIT", "enabled": can_act})
	if _can_undo(unit):
		buttons.append({"action": &"undo", "text": "BUTTON_UNDO"})
	# Four buttons fit a row: with a site and an undo, "Kết lượt" waits for
	# the phase card.
	if buttons.size() < 4:
		buttons.append({"action": &"end_turn", "text": "BUTTON_END_TURN", "primary": _are_only_walks_left()})
	return buttons


# The site within the leader's reach it can use now, else the first one in
# reach; empty when none is.
func _site_action(unit: int) -> Dictionary:
	var actions := _battle.get_site_actions(unit)
	for entry: Dictionary in actions:
		if _site_can(entry):
			return entry
	return actions[0] if not actions.is_empty() else {}


func _site_can(entry: Dictionary) -> bool:
	for choice: Dictionary in entry["choices"]:
		if choice["can"]:
			return true
	return false


# The site's choices on the panel: one line and one button each, the
# reason on the line when it cannot be taken now.
func _show_site_choices() -> void:
	var entry := _site_action(_selected)
	if entry.is_empty():
		return
	_site_shown = entry["site"]
	_recruit_choice = false
	var data := catalog.get_site(entry["site_id"])
	var lines: Array[String] = []
	var buttons: Array[Dictionary] = []
	for choice: Dictionary in entry["choices"]:
		var id: StringName = choice["choice"]
		lines.append(_site_choice_line(data, id) if choice["can"] else "%s: %s" % [tr("SITE_CHOICE_" + String(id).to_upper()), tr(_site_refusal(id))])
		buttons.append({"action": StringName("site_" + String(id)), "text": "SITE_CHOICE_" + String(id).to_upper(), "enabled": choice["can"]})
	lines.append(tr("SITE_LINE_NO_UNDO"))
	buttons.append({"action": &"cancel", "text": "BUTTON_CANCEL"})
	_mode = Mode.SITE_CHOICE
	_panel.hide_order_row()
	_panel.show_card(tr(data.name_key), Palette.GOLD, "", lines)
	_panel.set_buttons(buttons)
	_set_hint(tr("TACTICS_HINT_SITE_FORMAT") % tr(data.name_key))


func _site_choice_line(data: TacticsSiteData, choice: StringName) -> String:
	match choice:
		&"heal":
			return tr("SITE_LINE_HEAL_FORMAT") % data.heal_pct
		&"recruit":
			var names: Array[String] = []
			for troop: TacticsTroopData in data.recruits:
				names.append(tr(troop.name_key))
			while names.size() < 2:
				names.append(names[0] if not names.is_empty() else "")
			return tr("SITE_LINE_RECRUIT_FORMAT") % [names[0], names[1]]
		&"loot":
			return tr("SITE_LINE_LOOT_FORMAT") % data.supplies
		&"charge":
			return tr("SITE_LINE_CHARGE")
		&"calm":
			return tr("SITE_LINE_CALM_FORMAT") % data.calm_radius_cells
		&"bless":
			return tr("SITE_LINE_BLESS_FORMAT") % data.bless_amount
		&"capture":
			return tr("SITE_LINE_CAPTURE_FORMAT") % data.supplies
	return ""


# Why a choice cannot be taken now, in the player's words.
func _site_refusal(choice: StringName) -> String:
	if not _battle.can_act(_selected):
		return "SITE_NO_ACT"
	match choice:
		&"heal":
			return "SITE_NO_HURT"
		&"recruit":
			return "SITE_NO_ROOM"
		&"charge":
			return "SITE_NO_CHARGE"
		&"calm":
			return "SITE_NO_WAVERING"
		&"capture":
			return "SITE_NO_CAMP"
	return "SITE_NO_ACT"


# A site choice pressed: a village's recruit asks which soldier first.
func _choose_site(choice: StringName) -> void:
	if _mode != Mode.SITE_CHOICE or _site_shown < 0 or not _is_commandable(_selected):
		return
	var site := _site_shown
	if choice == &"recruit" and not _recruit_choice:
		var data := catalog.get_site(_battle.get_sites(player_side)[site]["id"])
		if data != null and data.recruits.size() > 1:
			_recruit_choice = true
			var buttons: Array[Dictionary] = []
			var lines: Array[String] = []
			for option: int in data.recruits.size():
				var troop: TacticsTroopData = data.recruits[option]
				buttons.append({"action": StringName("recruit_%d" % option), "text": troop.name_key, "enabled": _battle.can_use_site(_selected, site, &"recruit", option)})
				lines.append(tr("SITE_RECRUIT_LINE_FORMAT") % [tr(troop.name_key), troop.min_range_cells, troop.max_range_cells, troop.move_points])
			buttons.append({"action": &"cancel", "text": "BUTTON_CANCEL"})
			_panel.show_card(tr("SITE_RECRUIT_TITLE"), Palette.GOLD, "", lines)
			_panel.set_buttons(buttons)
			_set_hint("TACTICS_HINT_RECRUIT")
			return
	_use_site(choice, 0)


## The site whose choices the panel shows now, -1 if none (for tests).
func get_shown_site() -> int:
	return _site_shown if _mode == Mode.SITE_CHOICE else -1


func _use_site(choice: StringName, option: int) -> void:
	var site := _site_shown
	_site_shown = -1
	_recruit_choice = false
	if not _battle.can_use_site(_selected, site, choice, option):
		Sound.play(&"block")
		select_unit(_selected)
		return
	_run(_battle.use_site(_selected, site, choice, option))


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
		&"site":
			_show_site_choices()
		&"convoy_hold", &"convoy_go":
			_run(_battle.set_convoy_hold(action == &"convoy_hold"))
		_:
			if String(action).begins_with("recruit_"):
				if _mode == Mode.SITE_CHOICE:
					_use_site(&"recruit", int(String(action).trim_prefix("recruit_")))
			elif String(action).begins_with("site_"):
				_choose_site(StringName(String(action).trim_prefix("site_")))


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
# attacks, played back as one; the walk spends the leader's points, and
# if the target is gone after it (nothing on the way should fell it), the
# walk is all.
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
	if _is_convoy(unit):
		_show_convoy_card(unit)
		return
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
		# Our leader in our phase: what it can still do comes before its
		# passives (they show again in the enemy phase).
		if _is_commandable(unit):
			lines.append(_turn_line(state))
		lines.append(squad_line)
		details.append_array(_text.passive_lines(state["id"]))
	else:
		var leader: int = state["leader"]
		lines.append(tr("TACTICS_SOLDIER_OF_FORMAT") % _text.unit_name(_units[leader]) if leader >= 0 and _units[leader]["alive"] else tr("TACTICS_NO_LEADER"))
		var is_ours: bool = state["side"] == player_side
		if is_ours and state.get("is_out_of_leader_sight", false):
			lines.append(tr("TACTICS_OUT_OF_SIGHT"))
		var wavering: StringName = state["wavering"]
		if wavering != &"":
			# Wavering only out of its leader's sight: that is the reason and
			# the cure, not its incident's own situation.
			var incident := catalog.get_incident(wavering)
			var why := tr(incident.name_key + "_HINT") if incident != null else ""
			if state.get("is_wavering_unseen", false):
				why = tr("TACTICS_WAVERING_UNSEEN_HINT")
			lines.append(tr("TACTICS_WAVERING_LINE_FORMAT") % [_text.incident_name(wavering), why])
		var marks := int(_carried_marks.get(unit, 0)) + int(state["marks"])
		if marks > 0:
			side_note += " · " + tr("TACTICS_MARKS_FORMAT") % marks
	details.append_array(_text.keyword_lines(state["keywords"]))
	for line: String in details:
		if lines.size() < TacticsPanel.CARD_LINES - 1:
			lines.append(line)
	lines.append(_terrain_line(state["cell"]))
	_panel.show_card(_text.unit_name(state), title_color, side_note, lines)


# Move points left and whether the attack is spent, or that it waited.
func _turn_line(state: Dictionary) -> String:
	if state["has_waited"]:
		return tr("TACTICS_TURN_WAITED")
	var attack := tr("TACTICS_TURN_ATTACK_USED") if state["has_attacked"] else tr("TACTICS_TURN_ATTACK_READY")
	return tr("TACTICS_TURN_FORMAT") % [state["move_points_left"], state["move_points"], attack]


func _show_terrain(cell: Vector2i) -> void:
	var terrain := _map.get_terrain_at(cell)
	_map.set_marks({"selected": cell})
	for site: Dictionary in _map.get_sites():
		if site["cell"] == cell and site["is_known"]:
			_show_site(site, terrain)
			return
	var lines: Array[String] = [_text.terrain_effects(terrain), "", "", ""]
	if cell == _objective_cell():
		lines[1] = _objective_line()
	_panel.show_card(_text.terrain_name(terrain), Palette.CREAM, "", lines)


# A known site's card: what it does, who holds it, its capture.
func _show_site(site: Dictionary, terrain: StringName) -> void:
	var data := catalog.get_site(site["id"])
	if data == null:
		return
	var owner: int = site["owner"]
	var side_note := tr("SITE_OWNER_OURS") if owner == player_side else (tr("SITE_OWNER_NONE") if owner < 0 else tr("SITE_OWNER_ENEMY"))
	if site["status"] == &"burned":
		side_note = tr("SITE_STATUS_BURNED")
	elif site["status"] == &"used":
		side_note = tr("SITE_STATUS_USED")
	var lines: Array[String] = [tr(data.description_key)]
	if int(site["capture_phases"]) > 0:
		if int(site["capture_progress"]) > 0:
			var who := tr("SITE_SIDE_OURS") if int(site["capture_side"]) == player_side else tr("SITE_SIDE_ENEMY")
			lines.append(tr("SITE_CAPTURE_FORMAT") % [who, site["capture_progress"], site["capture_phases"]])
		else:
			lines.append(tr("SITE_LINE_HOLD_FORMAT") % site["capture_phases"])
	if site["cell"] == _objective_cell():
		lines.append(_objective_line())
	lines.append(_text.terrain_effects(terrain))
	_panel.show_card(tr(data.name_key), Palette.GOLD, side_note, lines)


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
			&"site":
				return tr("INTENT_SITE")
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
				return "TACTICS_HINT_WAVERING_UNSEEN" if _is_beyond_calm(state) else "TACTICS_HINT_WAVERING"
			hint = "TACTICS_HINT_WAVERING_GOOD"
	return hint


# A bad wavering soldier its leader cannot calm until it sees it: it
# wavers out of sight, or is out of its leader's sight now.
func _is_beyond_calm(state: Dictionary) -> bool:
	return state.get("is_wavering_unseen", false) or state.get("is_out_of_leader_sight", false)


# The units on the map as shown now (screen rects, one cell each): a tip
# never sits over ours if it can help it, and keeps off the enemy's too.
func _tip_avoid_rects() -> Array:
	var items: Array = []
	var view := Rect2(_map.position, _map.size)
	var cell := Vector2.ONE * _map.get_cell_px()
	for piece: TacticsPieceView in _map.get_pieces():
		if not piece.visible:
			continue
		var rect := Rect2(_map.position + _map.board_to_view(piece.position) - cell / 2.0, cell)
		if view.intersects(rect):
			items.append({"rect": rect.intersection(view), "weight": TIP_OUR_UNIT_WEIGHT if piece.side == player_side else 1})
	return items


# First-time tips after our command played: the first move that can be
# taken back (moving on until "Chờ"), the first time such moves spent the
# last point (undo step by step), the first order change, the first
# soldier that wavers badly.
func _offer_tips(unit: int, was_order: bool) -> void:
	if _is_commandable(unit) and not _site_action(unit).is_empty():
		_tips.offer(&"site")
	for site: Dictionary in _map.get_sites():
		if int(site.get("capture_progress", 0)) > 0:
			_tips.offer(&"capture")
	if _can_undo(unit):
		_tips.offer(&"move")
		if not _battle.can_move(unit):
			_tips.offer(&"undo")
	if was_order:
		_tips.offer(&"order")
	var wavering_hint := _wavering_hint()
	if wavering_hint == "TACTICS_HINT_WAVERING":
		_tips.offer(&"waver")
	elif wavering_hint == "TACTICS_HINT_WAVERING_UNSEEN":
		_tips.offer(&"waver_unseen")


# The objective's own tips, the first time each kind shows.
func _offer_objective_tips() -> void:
	if _objective_kind() == &"":
		return
	_tips.offer(&"objective")
	match _objective_kind():
		&"objective_kind.escort":
			_tips.offer(&"convoy")
		&"objective_kind.break_siege":
			_tips.offer(&"exit")


# A leader of ours whose turn is closed: it waited, or it has no point to
# reach a cell, no strike and no skill left (TacticsBattle.is_closed).
func _is_done(unit: int) -> bool:
	return _battle.is_closed(unit)


func _are_all_done() -> bool:
	if _battle.get_active_side() != player_side or _battle.is_finished():
		return false
	for state: Dictionary in _units:
		if _is_commandable(state["index"]) and not _is_done(state["index"]):
			return false
	return true


# Every leader of ours is done, or acted this phase and has no strike and
# no skill left: only walks remain, so "Kết lượt" is the button to press
# (one tap, not a Chờ per leader). A leader that has not acted yet keeps
# it plain, so a phase with no enemy in reach does not invite skipping it.
# The phase still ends by itself only when all are done.
func _are_only_walks_left() -> bool:
	if _battle.get_active_side() != player_side or _battle.is_finished():
		return false
	for state: Dictionary in _units:
		var unit: int = state["index"]
		if not _is_commandable(unit) or _is_done(unit):
			continue
		var has_acted: bool = state["has_moved"] or state["has_attacked"] or state["has_cast"]
		if not has_acted or not (_battle.get_strike_targets(unit).is_empty() and _battle.get_skill_cells(unit).is_empty()):
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


# Where the map opens: the middle of our leaders, across on a line between
# columns, so the view (a whole number of columns wide) cuts no column of
# tokens in half at its edges.
func _start_focus() -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for state: Dictionary in _units:
		if state["alive"] and state["role"] == &"leader" and state["side"] == player_side:
			sum += Vector2(state["cell"]) + Vector2(0.5, 0.5)
			count += 1
	if count == 0:
		return _map.get_board_size() / 2.0
	var middle := sum / count
	return Vector2(floorf(middle.x), middle.y) * TacticsMapView.CELL_PX


func _is_commandable(unit: int) -> bool:
	if unit < 0 or unit >= _units.size():
		return false
	var state: Dictionary = _units[unit]
	return state["alive"] and state["role"] == &"leader" and state["side"] == player_side and _battle.get_active_side() == player_side and not _battle.is_finished()


# The living unit on a cell, a leader before a soldier; -1 if none.
func _unit_at(cell: Vector2i) -> int:
	var found := -1
	for state: Dictionary in _units:
		if state["alive"] and state["cell"] == cell and _is_seen(state["index"]):
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
