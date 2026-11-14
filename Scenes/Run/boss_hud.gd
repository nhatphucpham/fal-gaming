class_name BossHud
extends RefCounted
## The run screen's boss views: from the reveal stage the top-bar badge
## (it opens the boss card: figure, rule, hint), in the boss battle the
## wide hp bar in the title's place with its Hóa Đá state, and on a win
## over the boss the victory moment (stamp and confetti) before the
## banner. It only shows; the boss's rule lives in the simulation. See
## Docs/systems/boss.md.

const VICTORY_SEC: float = 1.6
const CONFETTI_BURSTS: int = 6

var _run: RunState
var _layout: RunLayout
var _boss: UnitData
var _boss_index: int = -1


func _init(run: RunState, layout: RunLayout) -> void:
	_run = run
	_layout = layout
	var stages := run.catalog.stages
	var boss_stage: StageData = stages[run.rules.boss_stage - 1] if run.rules.boss_stage >= 1 and run.rules.boss_stage <= stages.size() else null
	var slot := boss_stage.get_boss_slot(run.catalog) if boss_stage != null else null
	_boss = run.catalog.get_unit(slot.unit_id) if slot != null else null
	layout.boss_badge.pressed.connect(open_card)


## Preparation: the badge from the reveal stage to the boss stage, pulsing
## on the boss stage; the stage title back in place.
func show_prep() -> void:
	var rules := _run.rules
	_layout.boss_badge.visible = _boss != null and _run.stage >= rules.boss_reveal_stage and _run.stage <= rules.boss_stage
	_layout.boss_badge.set_urgent(_run.is_boss_stage())
	_layout.show_boss_bar(false)
	_boss_index = -1


func open_card() -> void:
	if _boss != null:
		Sound.play(&"ui_tap")
		_layout.boss_card.open(_boss, _run.rules.boss_stage)


## Closes the boss card if it is open (the battle starts under it when
## the timer runs out).
func close_card() -> void:
	_layout.boss_card.close()


## Battle start: finds the boss among the battle's units and shows its bar.
func begin_battle(battle: Battle) -> void:
	close_card()
	_layout.boss_badge.visible = false
	_boss_index = -1
	for state: Dictionary in battle.get_units():
		var unit := _run.catalog.get_unit(state["unit_id"])
		if state["side"] == Battle.SIDE_B and unit != null and unit.is_boss:
			_boss_index = state["index"]
			_layout.boss_bar.present(_layout.tr(unit.name_key))
			_layout.show_boss_bar(true)
			return


func get_boss_index() -> int:
	return _boss_index


func on_tick(battle: Battle) -> void:
	if _boss_index >= 0:
		var state := battle.get_unit_state(_boss_index)
		_layout.boss_bar.show_hp(state["hp"], state["max_hp"])


func on_petrified(index: int, is_petrified: bool) -> void:
	if index == _boss_index:
		_layout.boss_bar.set_petrified(is_petrified)


## Leaving the battle (the banner's "Tiếp tục"): the boss bar gives the
## title its place back, also before the reward cards after a loss.
func end_battle() -> void:
	_layout.show_boss_bar(false)
	_boss_index = -1


## True when the boss fought and fell in `battle`.
func is_boss_defeated(battle: Battle) -> bool:
	return _boss_index >= 0 and not battle.get_unit_state(_boss_index)["alive"]


## The boss fell: "win" sounds, its name is stamped over the board and
## confetti bursts around it. Returns how long to wait before the banner,
## which then plays no sound of its own.
func play_victory() -> float:
	Sound.play(&"win")
	var board_rect := _layout.board.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, Vector2(BoardView.COLS, BoardView.ROWS) * BoardView.CELL_PX)
	var center := board_rect.get_center()
	var stamp := Label.new()
	stamp.theme_type_variation = &"TitleLabel"
	stamp.text = "BOSS_DEFEATED"
	stamp.add_theme_font_size_override(&"font_size", 64)
	stamp.add_theme_color_override(&"font_color", Palette.GOLD)
	stamp.add_theme_constant_override(&"outline_size", 12)
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.size = Vector2(board_rect.size.x, 100)
	stamp.position = center - stamp.size / 2.0 - Vector2(0, 60)
	stamp.pivot_offset = stamp.size / 2.0
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.scale = Vector2(1.8, 1.8)
	stamp.modulate.a = 0.0
	_layout.add_child(stamp)
	var tween := stamp.create_tween()
	tween.tween_property(stamp, ^"modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(stamp, ^"scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(VICTORY_SEC - 0.6)
	tween.tween_property(stamp, ^"modulate:a", 0.0, 0.3)
	tween.tween_callback(stamp.queue_free)
	for burst_index: int in CONFETTI_BURSTS:
		var burst := ConfettiBurst.new()
		burst.position = center + Vector2(randf_range(-0.4, 0.4) * board_rect.size.x, randf_range(-0.3, 0.2) * board_rect.size.y)
		_layout.add_child(burst)
		burst.create_tween().tween_callback(burst.play.bind(1.5)).set_delay(0.15 * burst_index)
	return VICTORY_SEC
