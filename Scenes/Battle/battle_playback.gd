class_name BattlePlayback
extends Node
## Drives a started Battle and turns its events into animations on a
## BoardView. Ticking: every frame it feeds `delta * speed` to a SimClock
## whose own _process is switched off, and steps the battle once per
## `ticked`, so the clock's catch-up cap (5 ticks per frame) applies. Views
## change only through the events step() returns; skill events go to a
## SkillPlayback and synergy procs to a SynergyPlayback. See Docs/systems/battle_playback.md for the
## event-to-animation table.
## [codeblock]
## playback.begin(battle, board, views_by_index, sim_clock, catalog)
## playback.battle_finished.connect(_on_battle_finished)
## [/codeblock]

## A tick was stepped; `tick` is the battle tick after it.
signal tick_advanced(tick: int)
## The battle ended and its closing animation (winners cheering) is done.
signal battle_finished(winner: int, reason: StringName)
## A member's death broke a formation; the screen shatters its outline.
## `cells` are the instance's members' global cells (two instances of one
## formation are told apart by them).
signal formation_broken(side: int, formation_id: StringName, cells: Array)
## A unit turned to stone (Hóa Đá) or came back from it.
signal unit_petrified(index: int, is_petrified: bool)

const MELEE_IMPACT_SEC: float = 0.08
const PROJECTILE_PX_PER_SEC: float = 900.0
const MIN_FLIGHT_SEC: float = 0.12
const MAX_FLIGHT_SEC: float = 0.35
const END_PAUSE_SEC: float = 0.6
const CHEER_SEC: float = 0.7
const MAGIC_COLOR := Color("ff9b4a")
## A hit at least this big sounds heavy.
const HEAVY_HIT: int = 120

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
var _skills := SkillPlayback.new(self)
var _synergies := SynergyPlayback.new(self)
var _catalog: Catalog
var _is_running: bool = false
# Bumped by abort(); delayed animations from an older generation are dropped.
var _generation: int = 0


func _ready() -> void:
	_handlers = {
		&"unit_moved": _on_unit_moved,
		&"unit_attacked": _on_unit_attacked,
		&"charge_ended": _on_charge_ended,
		&"damage_dealt": _on_damage_dealt,
		&"unit_died": _on_unit_died,
		&"battle_ended": _on_battle_ended,
	}
	_handlers.merge(_skills.get_handlers())
	_handlers.merge(_synergies.get_handlers())


## Starts playing `battle` (already started) on `board`. `views` maps each
## battle unit index to its UnitView; `clock` is reset and driven by hand.
## `catalog` names the skills in their popups; without it none show.
func begin(battle: Battle, board: BoardView, views: Dictionary[int, UnitView], clock: SimClock, catalog: Catalog = null) -> void:
	_battle = battle
	_board = board
	_clock = clock
	_views = views
	_impact_delay_sec.clear()
	_max_hp.clear()
	_hp_order.clear()
	_skills.begin(catalog)
	_catalog = catalog
	for index: int in views:
		var state := battle.get_unit_state(index)
		_max_hp[index] = maxi(1, state["max_hp"])
		views[index].set_qi(state["qi"], state["qi_max"])
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


## The view of battle unit `index`, or null.
func get_view(index: int) -> UnitView:
	return _views.get(index, null)


## Adds `fx` to the board's effect layer and plays it at the battle speed.
func spawn_fx(fx: BattleFx) -> void:
	_board.get_fx_layer().add_child(fx)
	fx.play(speed)


## Runs `action` after `seconds` of battle time, scaled by the current speed;
## dropped if the battle is aborted first.
func run_after(seconds: float, action: Callable) -> void:
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


## Seconds of battle time from event `event_id` until it shows (an arrow's
## flight), so an effect it causes lands with it.
func get_impact_delay(event_id: int) -> float:
	return _delay_of(event_id)


## A formation's name over `view` (a volley); nothing without a catalog.
func show_source_name(view: UnitView, source_id: StringName, color: Color) -> void:
	var formation := _catalog.get_formation(source_id) if _catalog != null else null
	if formation != null:
		spawn_fx(SkillFx.name_popup(view.position + Vector2(0, -62), view.tr(formation.name_key), color))


## Board-local centre of `cell`.
func cell_center(cell: Vector2i) -> Vector2:
	return _board.cell_to_local(cell)


func get_ticks_per_second() -> float:
	return _clock.ticks_per_second


## The layers a screen shake moves: pieces and effects, not the board.
func get_shake_layers() -> Array[Node2D]:
	return [_board.get_piece_layer(), _board.get_fx_layer()]


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
	var view := get_view(event["unit"])
	if view == null:
		return
	var target := _board.cell_to_local(Vector2i(event["to_col"], event["to_row"]))
	var seconds := float(event["duration_ticks"]) / _clock.ticks_per_second
	var kind: StringName = event["kind"]
	run_after(_delay_of(event["cause"]), func() -> void:
		view.glide_to(target, seconds, kind)
		if kind == &"charge":
			_trail_dust(view.position, target, seconds)
			Sound.play(&"charge")
		elif kind == &"knockback":
			spawn_fx(BattleFx.dust(view.position + UnitView.FEET)))


# A charge that hit kicks up dust where rider and target meet (the hit
# itself sounds through damage_dealt). A charge that hit nothing shows none.
func _on_charge_ended(event: Dictionary) -> void:
	var rider := get_view(event["unit"])
	var target := get_view(event["hit"]) if event["hit"] >= 0 else null
	if rider == null or target == null:
		return
	var meet := rider.position.lerp(target.position, 0.6) + UnitView.FEET
	run_after(MELEE_IMPACT_SEC, func() -> void:
		spawn_fx(BattleFx.dust(meet))
		spawn_fx(BattleFx.dust(meet + Vector2(-14, 4)))
		spawn_fx(BattleFx.dust(meet + Vector2(14, 4))))


func _on_unit_attacked(event: Dictionary) -> void:
	var attacker := get_view(event["unit"])
	if attacker == null:
		return
	var target := _board.cell_to_local(Vector2i(event["to_col"], event["to_row"]))
	var direction := target - attacker.position
	match event["kind"]:
		&"ranged":
			var flight := _flight_sec(attacker.position, target)
			attacker.recoil(direction)
			spawn_fx(BattleFx.arrow(attacker.position + Vector2(0, -22), target + Vector2(0, -14), flight))
			Sound.play(&"arrow")
			_impact_delay_sec[event["id"]] = flight
		&"magic":
			var flight := _flight_sec(attacker.position, target)
			attacker.recoil(direction)
			spawn_fx(BattleFx.bolt(attacker.position + Vector2(0, -30), target + Vector2(0, -14), flight, MAGIC_COLOR))
			_impact_delay_sec[event["id"]] = flight
			run_after(flight, _flash_row3.bind(Vector2i(event["to_col"], event["to_row"])))
		_:
			attacker.lunge(direction)
			run_after(MELEE_IMPACT_SEC * 0.5, func() -> void: spawn_fx(BattleFx.slash(target, direction)))
			_impact_delay_sec[event["id"]] = MELEE_IMPACT_SEC


func _on_damage_dealt(event: Dictionary) -> void:
	var target_index: int = event["target"]
	var view := get_view(target_index)
	if view == null:
		return
	var delay := _delay_of(event["cause"])
	if event["skill"] != &"":
		delay = _skills.damage_delay(event, delay)
	_impact_delay_sec[event["id"]] = delay
	var ratio: float = float(event["hp_after"]) / _max_hp.get(target_index, 1)
	var amount: int = event["amount"]
	var is_counter: bool = event["is_counter"]
	var is_crit: bool = event["is_crit"]
	var blocker := get_view(event["blocked_by"])
	var event_id: int = event["id"]
	# A hit a synergy blocked shows its "Chặn" instead of a 0; a hit on
	# stone (Hóa Đá) shows nothing and only clinks.
	var is_immune: bool = event.get("is_immune", false)
	var shows_number: bool = not event.get("is_blocked_by_modifier", false) and not is_immune
	var sound: StringName = &"block" if is_immune or blocker != null else (&"hit_heavy" if is_crit or amount >= HEAVY_HIT else &"hit_light")
	run_after(delay, func() -> void:
		# A late arrow must not flash a unit that is already falling.
		if view.is_dead:
			return
		Sound.play(sound)
		if is_immune:
			return
		view.hit_flash()
		if _hp_order.accept(target_index, event_id):
			view.set_hp_ratio(ratio)
		if shows_number:
			spawn_fx(BattleFx.number(view.position + Vector2(randf_range(-18.0, 18.0), randf_range(-40.0, -26.0)), amount, is_counter, is_crit))
		if blocker != null:
			spawn_fx(BattleFx.shield_flash(blocker.position + Vector2(0, -14), blocker.side == 0)))


func _on_unit_died(event: Dictionary) -> void:
	var view := get_view(event["unit"])
	if view == null:
		return
	# A boss cracks and crumbles instead of falling over.
	var ending := view.crumble if view.unit != null and view.unit.is_boss else view.die
	run_after(_delay_of(event["cause"]) + 0.05, func() -> void:
		Sound.play(&"death")
		ending.call())


func _on_battle_ended(event: Dictionary) -> void:
	var winner: int = event["winner"]
	var reason: StringName = event["reason"]
	stop()
	run_after(END_PAUSE_SEC, func() -> void:
		for view: UnitView in _views.values():
			if view.side == winner and not view.is_dead:
				view.cheer())
	run_after(END_PAUSE_SEC + CHEER_SEC, func() -> void: battle_finished.emit(winner, reason))


func _flash_row3(center: Vector2i) -> void:
	for offset: int in [-1, 0, 1]:
		var cell := center + Vector2i(offset, 0)
		if BoardView.is_on_board(cell):
			spawn_fx(BattleFx.cell_flash(_board.cell_to_local(cell), MAGIC_COLOR))


func _trail_dust(from: Vector2, to: Vector2, seconds: float) -> void:
	for step: int in 3:
		var share := step / 3.0
		run_after(seconds * share, func() -> void: spawn_fx(BattleFx.dust(from.lerp(to, share) + UnitView.FEET)))


func _flight_sec(from: Vector2, to: Vector2) -> float:
	return clampf(from.distance_to(to) / PROJECTILE_PX_PER_SEC, MIN_FLIGHT_SEC, MAX_FLIGHT_SEC)


func _delay_of(event_id: int) -> float:
	return _impact_delay_sec.get(event_id, 0.0)
