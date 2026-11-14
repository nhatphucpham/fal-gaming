class_name RunScreen
extends Control
## One run on screen: the preparation (shop, bench, board, timer), the
## battle on the same board, the result banner and the reward choice, stage
## after stage, until the run is won or lost. RunState holds every rule;
## this screen sends it commands, plays the battle with BattlePlayback and
## saves after each reward. Main sets [member run], [member sim_clock] and
## [member prep_seconds] before adding it. See Docs/systems/run.md.

## The run was won or lost; Main shows the end screen.
signal run_finished(run: RunState)

const SPEEDS: Array[int] = [1, 2, 4]
const ENEMY_DIM: float = 0.18
const STATUS_EVERY_TICKS: int = 2

var run: RunState
var sim_clock: SimClock
## Preparation seconds; 0 means no limit.
var prep_seconds: int = RunSettings.DEFAULT_PREP_SECONDS
## Whether the screen writes the save (tests turn it off).
var is_saving: bool = true
var layout: RunLayout
var controller: PrepController
var playback: BattlePlayback
var timer: PrepTimer
var reward_screen: RewardScreen
## The last stage's result as the banner showed it, for tests.
var last_battle_won: bool = false

var _catalog: Catalog
var _battle: Battle
var _hud: RunHud
var _pieces: PieceViews
var _enemy_lineup := Lineup.new(10)
var _enemy_views: LineupViews
var _speed_index: int = 0
var _deltas: Array = []
var _is_battling: bool = false


func _ready() -> void:
	theme = GameTheme.create()
	_catalog = run.catalog
	layout = RunLayout.new()
	add_child(layout)
	_battle = BattleFactory.create(_catalog)
	add_child(_battle)
	playback = BattlePlayback.new()
	add_child(playback)
	timer = PrepTimer.new()
	add_child(timer)
	reward_screen = RewardScreen.new()
	layout.add_child(reward_screen)
	layout.bench.setup(run.rules.bench_slots, RunLayout.BOARD_SCALE)
	layout.shop.setup(run.rules.shop_slots)
	_enemy_views = LineupViews.new(_enemy_lineup, Battle.SIDE_B, layout.board, _catalog)
	_pieces = PieceViews.new(run, layout.board, layout.bench, layout.shop, layout.piece_overlay, layout.gold_chip.get_icon_center)
	controller = PrepController.new()
	add_child(controller)
	controller.setup(run, layout.board, layout.bench, layout.shop, layout.sell_zone, layout.ghost, _pieces, _enemy_views, _enemy_lineup)
	_hud = RunHud.new(run, layout)
	_connect_signals()
	_update_speed_label()
	_enter_prep()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and run != null:
		_disconnect_run()


## "Ra trận", or the timer ran out: starts the battle with the board as it
## is (a held piece goes back first). False outside the preparation.
func start_battle() -> bool:
	if run.phase != RunState.Phase.PREP or _is_battling:
		return false
	controller.is_enabled = false
	timer.stop()
	if run.get_board_count() == 0:
		run.begin_battle()
		_finish_battle(false, _enemy_lineup.size(), &"")
		return true
	var views := _build_battle()
	run.begin_battle()
	_is_battling = true
	_pieces.set_hp_bars_shown(true)
	_enemy_views.set_hp_bars_shown(true)
	_enemy_views.set_dim(0.0)
	layout.board.set_top_half_dim(0.0)
	layout.show_battle_layout()
	_on_tick_advanced(0)
	playback.begin(_battle, layout.board, views, sim_clock)
	return true


## The banner's "Tiếp tục": on to the reward, or to the end of the run.
func continue_after_battle() -> void:
	if run.phase == RunState.Phase.BATTLE or run.phase == RunState.Phase.PREP:
		return
	layout.banner.dismiss()
	playback.abort()
	_clear_fx()
	if run.phase == RunState.Phase.REWARD:
		reward_screen.present(run.get_reward_options(), run.rules)
		return
	if is_saving:
		RunSave.delete()
	run_finished.emit(run)


func cycle_speed() -> void:
	_speed_index = (_speed_index + 1) % SPEEDS.size()
	playback.speed = SPEEDS[_speed_index]
	_update_speed_label()


## The three economy buttons; tests call them like the buttons do.
func press_refresh() -> void:
	_press(run.refresh_shop(), layout.refresh_button)


func press_buy_supply() -> void:
	_press(run.buy_supply(), layout.supply_button)


func press_level_up() -> void:
	_press(run.level_up(), layout.level_button)


func _connect_signals() -> void:
	layout.fight_button.pressed.connect(start_battle)
	layout.speed_button.pressed.connect(cycle_speed)
	layout.refresh_button.pressed.connect(press_refresh)
	layout.supply_button.pressed.connect(press_buy_supply)
	layout.level_button.pressed.connect(press_level_up)
	layout.banner.button_pressed.connect(continue_after_battle)
	layout.board.cell_long_pressed.connect(_on_battle_long_press)
	reward_screen.reward_chosen.connect(_on_reward_chosen)
	controller.action_refused.connect(func(result: RunState.Result) -> void: _hud.show_refusal(result))
	controller.info_requested.connect(_show_info)
	timer.seconds_changed.connect(func(seconds: int) -> void: layout.timer_badge.show_seconds(seconds, prep_seconds))
	timer.expired.connect(start_battle)
	playback.tick_advanced.connect(_on_tick_advanced)
	playback.battle_finished.connect(func(winner: int, reason: StringName) -> void:
		_finish_battle(winner == Battle.SIDE_A, BattleFactory.count_alive(_battle, Battle.SIDE_B), reason))
	run.battle_resolved.connect(_on_battle_resolved)


func _enter_prep() -> void:
	_is_battling = false
	_enemy_views.fade_out_all()
	_enemy_views.set_hp_bars_shown(false)
	_enemy_lineup.load_slots(run.get_stage_data().slots)
	_enemy_views.set_dim(ENEMY_DIM)
	layout.board.set_top_half_dim(1.0)
	_pieces.rebuild()
	_hud.show_all()
	layout.timer_badge.visible = prep_seconds > 0
	timer.start(prep_seconds)
	layout.show_prep_layout()
	controller.is_enabled = true


# Side A from the board pieces, side B from the stage; views by unit index.
func _build_battle() -> Dictionary[int, UnitView]:
	_battle.clear()
	var views: Dictionary[int, UnitView] = {}
	for piece: RunPiece in run.get_board_pieces():
		var index := _battle.add_unit(Battle.SIDE_A, _catalog.get_unit(piece.unit_id), piece.star, piece.cell.x, piece.cell.y)
		if index >= 0:
			views[index] = _pieces.get_view(piece.id)
	for entry_id: int in _enemy_lineup.get_entry_ids():
		var slot := _enemy_lineup.get_slot(entry_id)
		var index := _battle.add_unit(Battle.SIDE_B, _catalog.get_unit(slot.unit_id), slot.star, slot.local_col, slot.local_rank)
		if index >= 0:
			views[index] = _enemy_views.get_view(entry_id)
	_battle.start()
	return views


func _finish_battle(is_win: bool, enemies_alive: int, reason: StringName) -> void:
	last_battle_won = is_win
	_deltas.clear()
	run.finish_battle(is_win, enemies_alive)
	var reason_text := tr("RESULT_TIME_LIMIT") if reason == &"time_limit" else ""
	if reason == &"" and not is_win:
		reason_text = tr("RESULT_EMPTY_BOARD")
	layout.banner.present(is_win, reason_text, _deltas, "BUTTON_CONTINUE")


func _on_battle_resolved(_is_win: bool, gold_delta: int, supply_delta: int, morale_delta: int) -> void:
	for pair: Array in [[&"coin", gold_delta], [&"supply", supply_delta], [&"morale", morale_delta]]:
		if pair[1] != 0:
			_deltas.append(pair)


func _on_reward_chosen(reward: RunState.Reward) -> void:
	if run.choose_reward(reward) != RunState.Result.OK:
		return
	if is_saving:
		RunSave.save(run)
	_enter_prep()


func _on_tick_advanced(tick: int) -> void:
	var rules := _catalog.battle_rules
	var seconds_left := ceili(float(rules.time_limit_ticks - tick) / rules.ticks_per_second)
	layout.timer_badge.visible = true
	layout.timer_badge.show_seconds(seconds_left, rules.time_limit_ticks / rules.ticks_per_second, false)
	if tick % STATUS_EVERY_TICKS == 0 or _battle.is_finished():
		layout.battle_status.show_battle(_battle)


func _press(result: RunState.Result, button: CostButton) -> void:
	if result != RunState.Result.OK:
		_hud.show_refusal(result, button)


func _show_info(unit: UnitData, star: int) -> void:
	if unit != null:
		layout.info_panel.open(unit, UnitStats.derive(_catalog, unit, star), star)


# During a battle the pieces no longer say who stands where; ask the battle.
func _on_battle_long_press(cell: Vector2i) -> void:
	if not _is_battling:
		return
	for state: Dictionary in _battle.get_units():
		if state["alive"] and state["col"] == cell.x and state["row"] == cell.y:
			layout.info_panel.open(_catalog.get_unit(state["unit_id"]), UnitStats.from_state(_catalog, state), state["star"])
			return


func _update_speed_label() -> void:
	layout.speed_button.text = tr("SPEED_FORMAT") % SPEEDS[_speed_index]


# RunHud and PieceViews are RefCounted; their handlers on the run's signals
# keep them alive and they keep the run, so the cycle is cut here.
func _disconnect_run() -> void:
	for info: Dictionary in run.get_signal_list():
		for connection: Dictionary in run.get_signal_connection_list(info["name"]):
			run.disconnect(info["name"], connection["callable"])


func _clear_fx() -> void:
	for fx: Node in layout.board.get_fx_layer().get_children():
		fx.queue_free()
