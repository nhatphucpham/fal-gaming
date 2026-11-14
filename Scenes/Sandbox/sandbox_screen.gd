class_name SandboxScreen
extends Control
## The sandbox: the player places up to 8 units from a roster of every unit,
## sees the enemy line-up on the top half, presses "Ra trận" and watches the
## battle. It owns the two Lineups, builds the Battle from them and switches
## between the setup and battle layouts. See Docs/systems/board.md.
## Main sets [member sim_clock] before the first battle.

const CATALOG_PATH: String = "res://Data/catalog.tres"
const SANDBOX_PATH: String = "res://Data/Sandbox/sandbox.tres"
const MAX_UNITS: int = 8
const SPEEDS: Array[int] = [1, 2, 4]
const ENEMY_DIM: float = 0.18
const SLIDE_PX: float = 320.0
## How often the side health bars are refreshed during a battle.
const STATUS_EVERY_TICKS: int = 2

## "Về": the player wants the title screen.
signal back_requested()

enum Phase { SETUP, BATTLE, RESULT }

## Drives battle ticks; set by Main.
var sim_clock: SimClock
var phase: Phase = Phase.SETUP
var player_lineup := Lineup.new(MAX_UNITS)
var enemy_lineup := Lineup.new(MAX_UNITS)
## The last battle's result, -1 before any battle: the winning side.
var last_winner: int = -1
var last_reason: StringName = &""

var _catalog: Catalog
var _sandbox: SandboxData
var _battle: Battle
var _player_views: LineupViews
var _enemy_views: LineupViews
var _preset_index: int = 0
var _speed_index: int = 0
var _phase_tween: Tween
var _count_shake_tween: Tween
var _count_pop_tween: Tween
# Where the count label rests between shakes (its container's position).
var _count_rest_x: float = 0.0

@onready var board: BoardView = %BoardView
@onready var setup_controller: SetupController = %SetupController
@onready var playback: BattlePlayback = %BattlePlayback
@onready var _roster: RosterStrip = %Roster
@onready var _setup_panel: Control = %SetupPanel
@onready var _title_box: Control = %TitleBox
@onready var _timer_label: Label = %TimerLabel
@onready var _enemy_label: Label = %EnemyLabel
@onready var _count_label: Label = %CountLabel
@onready var _speed_button: PressButton = %SpeedButton
@onready var _fight_button: PressButton = %FightButton
@onready var _info_panel: UnitInfoPanel = %InfoPanel
@onready var _banner: ResultBanner = %ResultBanner
@onready var _battle_status: BattleStatus = %BattleStatus


func _ready() -> void:
	theme = GameTheme.create()
	_catalog = load(CATALOG_PATH) as Catalog
	_sandbox = load(SANDBOX_PATH) as SandboxData
	var problems := _catalog.validate()
	problems.append_array(_sandbox.validate(_catalog))
	for problem: String in problems:
		push_error(problem)
	_battle = BattleFactory.create(_catalog)
	add_child(_battle)
	_add_back_button()
	_player_views = LineupViews.new(player_lineup, Battle.SIDE_A, board, _catalog)
	_enemy_views = LineupViews.new(enemy_lineup, Battle.SIDE_B, board, _catalog)
	setup_controller.setup(board, _roster, %Ghost, _catalog, _player_views, player_lineup, _enemy_views, enemy_lineup)
	setup_controller.info_requested.connect(_show_info)
	setup_controller.action_refused.connect(_on_action_refused)
	board.cell_long_pressed.connect(_on_battle_long_press)
	_roster.set_units(_roster_units())
	player_lineup.entry_added.connect(_update_count.unbind(1))
	player_lineup.entry_removed.connect(_update_count.unbind(2))
	player_lineup.cleared.connect(_update_count)
	%NextEnemyButton.pressed.connect(next_enemy)
	%ClearButton.pressed.connect(clear_board)
	_fight_button.pressed.connect(start_battle)
	_speed_button.pressed.connect(cycle_speed)
	_banner.button_pressed.connect(return_to_setup)
	playback.tick_advanced.connect(_on_tick_advanced)
	playback.battle_finished.connect(_on_battle_finished)
	_timer_label.modulate.a = 0.0
	_load_enemy_preset()
	board.set_top_half_dim(1.0)
	_update_count()
	_update_speed_label()


## Shows the next enemy preset with a quick cross-fade.
func next_enemy() -> void:
	if phase != Phase.SETUP:
		return
	_preset_index = (_preset_index + 1) % _sandbox.enemy_presets.size()
	_enemy_views.fade_out_all()
	_load_enemy_preset()


## Removes every player unit from the board.
func clear_board() -> void:
	if phase != Phase.SETUP:
		return
	setup_controller.deselect()
	player_lineup.clear()


## Builds the battle from both line-ups and starts playing it. False when
## the player has no units or a battle is already on.
func start_battle() -> bool:
	if phase != Phase.SETUP or player_lineup.size() == 0 or sim_clock == null:
		_on_action_refused()
		return false
	_battle.clear()
	var views: Dictionary[int, UnitView] = {}
	for pair: Array in [[player_lineup, _player_views], [enemy_lineup, _enemy_views]]:
		var lineup: Lineup = pair[0]
		var lineup_views: LineupViews = pair[1]
		for entry_id: int in lineup.get_entry_ids():
			var slot := lineup.get_slot(entry_id)
			var index := _battle.add_unit(lineup_views.side, _catalog.get_unit(slot.unit_id), slot.star, slot.local_col, slot.local_rank)
			if index >= 0:
				views[index] = lineup_views.get_view(entry_id)
	_battle.start()
	setup_controller.is_enabled = false
	phase = Phase.BATTLE
	_enemy_views.set_dim(0.0)
	board.set_top_half_dim(0.0)
	_on_tick_advanced(0)
	_slide_setup_out()
	playback.begin(_battle, board, views, sim_clock)
	return true


## "Xếp lại": back to setup with the player's line-up as it was.
func return_to_setup() -> void:
	if phase == Phase.SETUP:
		return
	playback.abort()
	_banner.dismiss()
	_info_panel.close()
	phase = Phase.SETUP
	_player_views.rebuild()
	_enemy_views.rebuild()
	_enemy_views.set_dim(ENEMY_DIM)
	board.set_top_half_dim(1.0)
	_clear_fx()
	_slide_setup_in()
	setup_controller.is_enabled = true


## Cycles the battle speed x1, x2, x4.
func cycle_speed() -> void:
	_speed_index = (_speed_index + 1) % SPEEDS.size()
	playback.speed = SPEEDS[_speed_index]
	_update_speed_label()


func _roster_units() -> Array[UnitData]:
	var indexed: Array[Array] = []
	for index: int in _catalog.units.size():
		indexed.append([_catalog.units[index].cost, index])
	indexed.sort()
	var units: Array[UnitData] = []
	for pair: Array in indexed:
		units.append(_catalog.units[pair[1]])
	return units


func _load_enemy_preset() -> void:
	var preset := _sandbox.enemy_presets[_preset_index]
	enemy_lineup.load_slots(preset.slots)
	_enemy_views.set_dim(ENEMY_DIM)
	_enemy_label.text = tr("ENEMY_LABEL") % tr(preset.name_key)


func _update_count() -> void:
	_count_label.text = tr("COUNT_FORMAT") % [player_lineup.size(), player_lineup.max_size]
	_fight_button.disabled = player_lineup.size() == 0
	_pop_count()


func _update_speed_label() -> void:
	_speed_button.text = tr("SPEED_FORMAT") % SPEEDS[_speed_index]


func _on_action_refused() -> void:
	# One shake at a time, always around the same rest position, so repeated
	# refusals cannot walk the label sideways.
	if _count_shake_tween != null and _count_shake_tween.is_running():
		_count_shake_tween.kill()
	else:
		_count_rest_x = _count_label.position.x
	_count_label.position.x = _count_rest_x
	_count_shake_tween = _count_label.create_tween()
	_count_label.add_theme_color_override(&"font_color", Palette.VERMILION)
	for offset_x: float in [-6.0, 5.0, -3.0, 0.0]:
		_count_shake_tween.tween_property(_count_label, ^"position:x", _count_rest_x + offset_x, 0.04)
	_count_shake_tween.tween_callback(_count_label.remove_theme_color_override.bind(&"font_color"))


func _on_tick_advanced(tick: int) -> void:
	var rules := _catalog.battle_rules
	var seconds_left := ceili(float(rules.time_limit_ticks - tick) / rules.ticks_per_second)
	_timer_label.text = tr("TIMER_FORMAT") % maxi(0, seconds_left)
	if tick % STATUS_EVERY_TICKS == 0 or _battle.is_finished():
		_battle_status.show_battle(_battle)


# A small "Về" button before the title, back to the title screen.
func _add_back_button() -> void:
	var back := PressButton.new()
	back.text = "BUTTON_BACK"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(108, 88)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: back_requested.emit())
	var row := _title_box.get_parent().get_parent()
	row.add_child(back)
	row.move_child(back, 0)


func _on_battle_finished(winner: int, reason: StringName) -> void:
	last_winner = winner
	last_reason = reason
	phase = Phase.RESULT
	var reason_text := tr("RESULT_TIME_LIMIT") if reason == &"time_limit" else ""
	_banner.present(winner == Battle.SIDE_A, reason_text)


func _show_info(unit: UnitData, star: int) -> void:
	if unit != null:
		_info_panel.open(unit, UnitStats.derive(_catalog, unit, star), star)


# During a battle the line-ups no longer say who stands where; ask the battle.
func _on_battle_long_press(cell: Vector2i) -> void:
	if phase == Phase.SETUP:
		return
	for state: Dictionary in _battle.get_units():
		if state["alive"] and state["col"] == cell.x and state["row"] == cell.y:
			_info_panel.open(_catalog.get_unit(state["unit_id"]), UnitStats.from_state(_catalog, state), state["star"])
			return


func _slide_setup_out() -> void:
	_restart_phase_tween()
	_phase_tween.tween_property(_setup_panel, ^"position:y", SLIDE_PX, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_phase_tween.parallel().tween_property(_setup_panel, ^"modulate:a", 0.0, 0.25)
	_phase_tween.parallel().tween_property(_title_box, ^"modulate:a", 0.0, 0.15)
	_phase_tween.parallel().tween_property(_timer_label, ^"modulate:a", 1.0, 0.2).set_delay(0.1)
	_phase_tween.parallel().tween_property(_count_label, ^"modulate:a", 0.0, 0.15)
	_phase_tween.parallel().tween_property(_battle_status, ^"position:y", 0.0, 0.3).set_delay(0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_phase_tween.parallel().tween_property(_battle_status, ^"modulate:a", 1.0, 0.2).set_delay(0.15)


func _slide_setup_in() -> void:
	_restart_phase_tween()
	_phase_tween.tween_property(_setup_panel, ^"position:y", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_phase_tween.parallel().tween_property(_setup_panel, ^"modulate:a", 1.0, 0.2)
	_phase_tween.parallel().tween_property(_timer_label, ^"modulate:a", 0.0, 0.15)
	_phase_tween.parallel().tween_property(_title_box, ^"modulate:a", 1.0, 0.2).set_delay(0.1)
	_phase_tween.parallel().tween_property(_count_label, ^"modulate:a", 1.0, 0.2)
	_phase_tween.parallel().tween_property(_battle_status, ^"position:y", SLIDE_PX, 0.25).set_ease(Tween.EASE_IN)
	_phase_tween.parallel().tween_property(_battle_status, ^"modulate:a", 0.0, 0.2)


func _restart_phase_tween() -> void:
	if _phase_tween != null:
		_phase_tween.kill()
	_phase_tween = create_tween()


func _clear_fx() -> void:
	for fx: Node in board.get_fx_layer().get_children():
		fx.queue_free()


func _pop_count() -> void:
	if _count_pop_tween != null:
		_count_pop_tween.kill()
	_count_label.pivot_offset = _count_label.size / 2.0
	_count_label.scale = Vector2(1.25, 1.25)
	_count_pop_tween = _count_label.create_tween()
	_count_pop_tween.tween_property(_count_label, ^"scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
