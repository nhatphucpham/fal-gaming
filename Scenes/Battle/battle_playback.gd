class_name BattlePlayback
extends Node
## Drives a started Battle and turns its events into animations on a
## BoardView. Ticking: every frame it feeds `delta * speed` to a SimClock
## whose own _process is switched off, and steps the battle once per
## `ticked`, so the clock's catch-up cap (5 ticks per frame) applies. Views
## change only through the events step() returns. See
## Docs/systems/battle_playback.md for the event-to-animation table.
## [codeblock]
## playback.begin(battle, board, views_by_index, sim_clock)
## playback.battle_finished.connect(_on_battle_finished)
## [/codeblock]

## A tick was stepped; `tick` is the battle tick after it.
signal tick_advanced(tick: int)
## The battle ended and its closing animation (winners cheering) is done.
signal battle_finished(winner: int, reason: StringName)

const MELEE_IMPACT_SEC: float = 0.08
const PROJECTILE_PX_PER_SEC: float = 900.0
const MIN_FLIGHT_SEC: float = 0.12
const MAX_FLIGHT_SEC: float = 0.35
const END_PAUSE_SEC: float = 0.6
const CHEER_SEC: float = 0.7
const MAGIC_COLOR := Color("ff9b4a")

## Multiplies both the tick rate and every animation: 1, 2 or 4.
var speed: float = 1.0:
	set(value):
		speed = value
		for view: UnitView in _views.values():
			if is_instance_valid(view):
				view.playback_speed = value

var _battle: Battle
var _board: BoardView
var _clock: SimClock
var _views: Dictionary[int, UnitView] = {}
var _max_hp: Dictionary[int, int] = {}
# Seconds of battle time from an event until its visible impact, by event id,
# so damage and deaths land when the arrow or bolt arrives.
var _impact_delay_sec: Dictionary[int, float] = {}
var _handlers: Dictionary[StringName, Callable] = {}
var _hp_order := ImpactOrder.new()
var _is_running: bool = false
# Bumped by abort(); delayed animations from an older generation are dropped.
var _generation: int = 0


func _ready() -> void:
	_handlers = {
		&"unit_moved": _on_unit_moved,
		&"unit_attacked": _on_unit_attacked,
		&"damage_dealt": _on_damage_dealt,
		&"unit_died": _on_unit_died,
		&"battle_ended": _on_battle_ended,
	}


## Starts playing `battle` (already started) on `board`. `views` maps each
## battle unit index to its UnitView; `clock` is reset and driven by hand.
func begin(battle: Battle, board: BoardView, views: Dictionary[int, UnitView], clock: SimClock) -> void:
	_battle = battle
	_board = board
	_clock = clock
	_views = views
	_impact_delay_sec.clear()
	_max_hp.clear()
	_hp_order.clear()
	for index: int in views:
		_max_hp[index] = maxi(1, battle.get_unit_state(index)["max_hp"])
	speed = speed
	clock.set_process(false)
	clock.reset()
	if not clock.ticked.is_connected(_on_ticked):
		clock.ticked.connect(_on_ticked)
	_is_running = true


## Stops playing; pending animations finish on their own.
func stop() -> void:
	_is_running = false
	if _clock != null and _clock.ticked.is_connected(_on_ticked):
		_clock.ticked.disconnect(_on_ticked)


## Stops playing and cancels every delayed animation, for leaving the battle
## before its animations are done.
func abort() -> void:
	stop()
	_generation += 1
	# The views belong to the screen and are freed after this; forget them.
	_views = {}
	_max_hp.clear()
	_impact_delay_sec.clear()


## How many unit views this playback still refers to (0 after abort()).
func get_view_count() -> int:
	return _views.size()


func is_running() -> bool:
	return _is_running


## Advances by `delta_sec` of real time, scaled by speed. Called every frame;
## tests call it directly.
func advance(delta_sec: float) -> void:
	if _is_running:
		_clock.advance(delta_sec * speed)


func _process(delta: float) -> void:
	advance(delta)


func _on_ticked(_tick: int) -> void:
	if _battle == null or _battle.is_finished():
		return
	for event: Dictionary in _battle.step():
		var handler: Callable = _handlers.get(event["type"], Callable())
		if handler.is_valid():
			handler.call(event)
	tick_advanced.emit(_battle.get_tick())


func _on_unit_moved(event: Dictionary) -> void:
	var view := _view(event["unit"])
	if view == null:
		return
	var target := _board.cell_to_local(Vector2i(event["to_col"], event["to_row"]))
	var seconds := float(event["duration_ticks"]) / _clock.ticks_per_second
	var kind: StringName = event["kind"]
	_after(_delay_of(event["cause"]), func() -> void:
		view.glide_to(target, seconds, kind)
		if kind == &"charge":
			_trail_dust(view.position, target, seconds)
		elif kind == &"knockback":
			_spawn(BattleFx.dust(view.position + UnitView.FEET)))


func _on_unit_attacked(event: Dictionary) -> void:
	var attacker := _view(event["unit"])
	if attacker == null:
		return
	var target := _board.cell_to_local(Vector2i(event["to_col"], event["to_row"]))
	var direction := target - attacker.position
	match event["kind"]:
		&"ranged":
			var flight := _flight_sec(attacker.position, target)
			attacker.recoil(direction)
			_spawn(BattleFx.arrow(attacker.position + Vector2(0, -22), target + Vector2(0, -14), flight))
			_impact_delay_sec[event["id"]] = flight
		&"magic":
			var flight := _flight_sec(attacker.position, target)
			attacker.recoil(direction)
			_spawn(BattleFx.bolt(attacker.position + Vector2(0, -30), target + Vector2(0, -14), flight, MAGIC_COLOR))
			_impact_delay_sec[event["id"]] = flight
			_after(flight, _flash_row3.bind(Vector2i(event["to_col"], event["to_row"])))
		_:
			attacker.lunge(direction)
			_after(MELEE_IMPACT_SEC * 0.5, func() -> void: _spawn(BattleFx.slash(target, direction)))
			_impact_delay_sec[event["id"]] = MELEE_IMPACT_SEC


func _on_damage_dealt(event: Dictionary) -> void:
	var target_index: int = event["target"]
	var view := _view(target_index)
	if view == null:
		return
	var delay := _delay_of(event["cause"])
	_impact_delay_sec[event["id"]] = delay
	var ratio: float = float(event["hp_after"]) / _max_hp.get(target_index, 1)
	var amount: int = event["amount"]
	var is_counter: bool = event["is_counter"]
	var blocker := _view(event["blocked_by"])
	var event_id: int = event["id"]
	_after(delay, func() -> void:
		# A late arrow must not flash a unit that is already falling.
		if view.is_dead:
			return
		view.hit_flash()
		if _hp_order.accept(target_index, event_id):
			view.set_hp_ratio(ratio)
		_spawn(BattleFx.number(view.position + Vector2(randf_range(-18.0, 18.0), randf_range(-40.0, -26.0)), amount, is_counter))
		if blocker != null:
			_spawn(BattleFx.shield_flash(blocker.position + Vector2(0, -14), blocker.side == 0)))


func _on_unit_died(event: Dictionary) -> void:
	var view := _view(event["unit"])
	if view != null:
		_after(_delay_of(event["cause"]) + 0.05, view.die)


func _on_battle_ended(event: Dictionary) -> void:
	var winner: int = event["winner"]
	var reason: StringName = event["reason"]
	stop()
	_after(END_PAUSE_SEC, func() -> void:
		for view: UnitView in _views.values():
			if view.side == winner and not view.is_dead:
				view.cheer())
	_after(END_PAUSE_SEC + CHEER_SEC, func() -> void: battle_finished.emit(winner, reason))


func _flash_row3(center: Vector2i) -> void:
	for offset: int in [-1, 0, 1]:
		var cell := center + Vector2i(offset, 0)
		if BoardView.is_on_board(cell):
			_spawn(BattleFx.cell_flash(_board.cell_to_local(cell), MAGIC_COLOR))


func _trail_dust(from: Vector2, to: Vector2, seconds: float) -> void:
	for step: int in 3:
		var share := step / 3.0
		_after(seconds * share, func() -> void: _spawn(BattleFx.dust(from.lerp(to, share) + UnitView.FEET)))


func _flight_sec(from: Vector2, to: Vector2) -> float:
	return clampf(from.distance_to(to) / PROJECTILE_PX_PER_SEC, MIN_FLIGHT_SEC, MAX_FLIGHT_SEC)


func _delay_of(event_id: int) -> float:
	return _impact_delay_sec.get(event_id, 0.0)


func _view(index: int) -> UnitView:
	return _views.get(index, null)


func _spawn(fx: BattleFx) -> void:
	_board.get_fx_layer().add_child(fx)
	fx.play(speed)


# Runs `action` after `seconds` of battle time, scaled by the current speed.
func _after(seconds: float, action: Callable) -> void:
	if seconds <= 0.0:
		action.call()
		return
	var generation := _generation
	var tween := create_tween()
	tween.set_speed_scale(speed)
	tween.tween_interval(seconds)
	tween.tween_callback(func() -> void:
		if generation == _generation:
			action.call())
