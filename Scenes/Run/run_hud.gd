class_name RunHud
extends RefCounted
## Keeps the run screen's numbers and buttons in step with RunState: stage
## and morale in the top bar, units on the board, gold, supply and level
## with their buttons (dimmed when unaffordable), the shop cards and their
## hints. It also turns refused commands into feedback: the lacking chip
## flashes red, the pressed button shakes. Gold still flying as coins is
## held back from the gold chip (hold_gold, release_gold).

var _run: RunState
var _layout: RunLayout
# Gold that has arrived in the run but whose coins have not landed yet.
var _held_gold: int = 0


func _init(run: RunState, layout: RunLayout) -> void:
	_run = run
	_layout = layout
	run.gold_changed.connect(func(_gold: int, _delta: int) -> void:
		_show_gold(true)
		refresh_affordability())
	run.supply_changed.connect(func(supply: int, _delta: int) -> void:
		layout.supply_chip.set_value(supply)
		refresh_affordability())
	run.morale_changed.connect(func(morale: int, _delta: int) -> void: layout.morale_chip.set_value(morale))
	run.level_changed.connect(_on_level_changed)
	run.shop_rolled.connect(func() -> void: show_shop(true))
	run.piece_bought.connect(func(_piece_id: int, slot: int) -> void:
		layout.shop.clear_slot(slot)
		_refresh_pieces())
	run.piece_moved.connect(_refresh_pieces.unbind(1))
	run.piece_sold.connect(_refresh_pieces.unbind(3))
	run.pieces_merged.connect(_refresh_pieces.unbind(2))


## Shows everything as it is now, without counting animations.
func show_all() -> void:
	var stage := _run.get_stage_data()
	_layout.stage_label.text = tr("STAGE_FORMAT") % [_run.stage, _run.rules.stage_count]
	_layout.stage_name_label.text = tr(stage.name_key)
	_layout.morale_chip.set_value(_run.morale, false)
	_show_gold(false)
	_layout.supply_chip.set_value(_run.supply, false)
	_layout.level_chip.set_value(_run.level, false)
	_refresh_pieces()
	show_shop(true)


## Keeps `gold` that just arrived out of the gold chip until
## release_gold(): it counts up when its coins land, never down first.
func hold_gold(gold: int) -> void:
	_held_gold += gold
	_show_gold(true)


## The coins of `gold` held gold landed: the chip counts up to them.
func release_gold(gold: int) -> void:
	_held_gold = maxi(0, _held_gold - gold)
	_show_gold(true)


## Shows the shop offers; `flip` turns the cards over (a reroll).
func show_shop(flip: bool) -> void:
	var units: Array[UnitData] = []
	for unit_id: StringName in _run.get_shop_offers():
		units.append(_run.catalog.get_unit(unit_id) if unit_id != &"" else null)
	_layout.shop.show_offers(units, flip)
	refresh_affordability()


## Dims what cannot be paid and updates the prices and the merge hints.
func refresh_affordability() -> void:
	var refresh_cost := _run.get_refresh_cost()
	_layout.refresh_button.set_cost(refresh_cost, _run.gold >= refresh_cost)
	_layout.supply_button.set_cost(_run.rules.supply_pack_gold, _run.gold >= _run.rules.supply_pack_gold)
	var level_cost := _run.get_level_up_cost()
	_layout.level_button.set_cost(level_cost, level_cost >= 0 and _run.supply >= level_cost)
	var merges: Array[bool] = []
	for unit_id: StringName in _run.get_shop_offers():
		merges.append(unit_id != &"" and _run.would_merge(unit_id))
	_layout.shop.update_hints(_run.gold, merges)


## Feedback for a refused command; `button` (may be null) shakes.
func show_refusal(result: RunState.Result, button: CostButton = null) -> void:
	if button != null:
		button.refuse()
	match result:
		RunState.Result.NOT_ENOUGH_GOLD:
			_layout.gold_chip.flash_lacking()
		RunState.Result.NOT_ENOUGH_SUPPLY:
			_layout.supply_chip.flash_lacking()
		RunState.Result.BOARD_FULL, RunState.Result.LEGEND_LIMIT:
			_layout.capacity_chip.flash_lacking()
		RunState.Result.BENCH_FULL:
			_layout.bench.flash_full()


func _on_level_changed(level: int) -> void:
	_layout.level_chip.set_value(level)
	_layout.level_chip.burst()
	_refresh_pieces()
	_layout.capacity_chip.bounce()


func _show_gold(animate: bool) -> void:
	_layout.gold_chip.set_value(maxi(0, _run.gold - _held_gold), animate)


func _refresh_pieces() -> void:
	_layout.capacity_chip.set_suffix("/%d" % _run.get_capacity())
	_layout.capacity_chip.set_value(_run.get_board_count())
	refresh_affordability()
