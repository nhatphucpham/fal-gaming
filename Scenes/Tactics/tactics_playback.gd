class_name TacticsPlayback
extends Node
## Plays the events a TacticsBattle command returned on the map, in order,
## with a sound for every change: phase banners, a leader's move with its
## squad stepping along at the same time, soldier fights of a squad
## together (about 0.3 s each, staggered so a squad stays under about
## 1 s), a leader's attack on the map (a lunge or a shot, a flash, the
## numbers, a heavy hit), deaths, charge pips, zones, buffs, passives,
## intents and incidents (a soldier wavering, the incident firing with its
## name over the soldier, calming, fleeing, defecting, a mark earned). The
## close-up opens only for a skill and for a blow that kills a leader. The
## camera follows what plays. Under fog of war it shows only what our side
## sees: an enemy out of sight moves unseen, one that comes into sight fades
## in, one that leaves it fades out and leaves a "?" where it was last seen;
## new cells clear with a soft sound; an ambush bursts over the hidden enemy.
## Weather and time-of-day changes get a banner. Sites and objectives
## (Docs/systems/tactics_sites.md, tactics_objectives.md): a site used, a
## village burned, a capture ring filling, a camp's rest heal, new units
## dropping in (a wave with the enemy's horn, a recruit, reinforcements),
## units leaving by an exit, the convoy halting, the general turning to
## flee (a banner) and supplies gained; what our side does not see of the
## enemy stays hidden. A tap skips the step that
## plays now. It never changes the battle; the screen syncs the map from
## the battle once it is done.
## See Docs/systems/tactics_screen.md.
## [codeblock]
## playback.reset(battle.get_zones())
## await playback.play(battle.end_phase())
## [/codeblock]

signal step_started(type: StringName)
## The last step of a play() is done; the map shows what the events did,
## before the screen syncs it with the battle (tests compare the two here).
signal played()
## A phase_started step began: whose phase, and the round.
signal phase_shown(side: int, round_number: int)
## That phase's banner is gone: the screen's own warnings may show now.
signal phase_banner_ended(side: int, round_number: int)
## The weather or the time of day turned (`kind` is &"weather" or
## &"daytime"); the screen updates its icons and the night.
signal environment_changed(kind: StringName, id: StringName)
## Supplies of our side changed (amount gained, the new total).
signal supplies_gained(amount: int, total: int)

const MOVE_SEC_PER_CELL: float = 0.1
const SQUAD_MOVE_MAX_SEC: float = 0.55
const FIGHT_SEC: float = 0.3
## Soldier fights of one batch start at most this far apart, and all of
## them start within FIGHT_BATCH_SEC.
const FIGHT_STAGGER_SEC: float = 0.14
const FIGHT_BATCH_SEC: float = 0.6
## A leader's attack on the map: lunge, hit, counter.
const LEADER_FIGHT_SEC: float = 0.5
const BANNER_SEC: float = 0.85
const HIT_COLOR := Color("ffd27a")
const COUNTER_COLOR := Color("f3e6c8")
const BURN_COLOR := Color("ff8a3a")
const MARK_COLOR := Color("7fd1b0")
const INCIDENT_SEC: float = 0.8
const WAVER_SEC: float = 0.55
const AMBUSH_SEC: float = 0.75
const FADE_SEC: float = 0.2
## The beat after an enemy comes into sight, so the eye finds it.
const SPOTTED_SEC: float = 0.25
## The fog blends over the walk that changed it, at least this long; alone
## (a death, a unit fleeing) over TacticsMapView.FOG_BLEND_SEC.
const FOG_MIN_BLEND_SEC: float = 0.15
## A unit arriving drops this far onto its cell as it fades in.
const ARRIVE_DROP_PX: float = 40.0
const ARRIVE_SEC: float = 0.35
const HEAL_COLOR := Color("8ff0b0")
## Steps about one unit and nothing else (the unit hit, for damage): for
## an enemy our side does not see they only set its hidden piece, with no
## sound, ring, word or pause to give it away.
const PRIVATE_STEPS: Array[StringName] = [
	&"skill_charge_changed", &"skill_grew", &"buff_applied", &"buff_ended", &"passive_triggered",
	&"order_changed", &"leader_waited", &"soldier_wavered", &"incident_calmed", &"incident_fired",
	&"mark_earned", &"damage_dealt", &"unit_died", &"unit_healed",
]
## The close-up backdrop for the terrain the fight is on.
const BACKDROPS: Dictionary[StringName, StringName] = {
	&"terrain.forest": &"backdrop.mountain", &"terrain.hill": &"backdrop.mountain",
	&"terrain.fort": &"backdrop.camp", &"terrain.village": &"backdrop.camp",
}

var map: TacticsMapView
var close_up: TacticsCloseUp
var banner: TacticsBanner
var text: TacticsText
var looks: TacticsSkillLookSet
## Our side; the other side's phase hides the intents.
var player_side: int = 0
## Multiplies the speed of map steps.
var speed: float = 1.0
## Tests: every step ends at once and close-ups are skipped.
var is_instant: bool = false
var is_playing: bool = false
## How many close-ups were played (or skipped) so far, for tests.
var close_up_count: int = 0
## Whether our side reads an enemy leader's intent (fog of war, night);
## unset reads them all.
var intent_filter: Callable
## Makes the piece of a unit that arrives mid-battle and returns its state
## ({index, side, role, id, ...}); the screen reads it from the battle.
var piece_factory: Callable

var _units: Array[Dictionary] = []
var _zones: Array[Dictionary] = []
var _tween: Tween
var _handlers: Dictionary[StringName, Callable] = {}
var _is_stopped: bool = false


func _init() -> void:
	_handlers = {
		&"phase_started": _play_phase, &"unit_moved": _play_move, &"engagement_started": _play_engagement,
		&"damage_dealt": _play_loose_damage, &"unit_died": _play_death, &"skill_used": _play_skill,
		&"skill_charge_changed": _play_charge, &"skill_grew": _play_growth, &"buff_applied": _play_buffs,
		&"buff_ended": _play_buffs_ended, &"zone_created": _play_zone, &"zone_expired": _play_zone_expired,
		&"passive_triggered": _play_passive, &"order_changed": _play_order, &"leader_waited": _play_wait,
		&"intent_declared": _play_intents, &"soldier_wavered": _play_wavered, &"incident_calmed": _play_calmed,
		&"incident_fired": _play_incident, &"mark_earned": _play_mark, &"unit_fled": _play_fled, &"unit_defected": _play_defected,
		&"vision_changed": _play_vision, &"ambushed": _play_ambush, &"weather_changed": _play_environment, &"daytime_changed": _play_environment,
		&"site_used": _play_site_used, &"site_changed": _play_site_changed, &"capture_progressed": _play_capture,
		&"unit_healed": _play_heals, &"unit_arrived": _play_arrivals, &"unit_escaped": _play_escaped,
		&"convoy_halted": _play_convoy_halted, &"general_fleeing": _play_general_fleeing, &"supplies_gained": _play_supplies,
	}


## Remembers each unit's fixed facts (side, role, id) and the zones before
## the next command.
func reset(units: Array, zones: Array) -> void:
	_units.assign(units)
	_zones.assign(zones)


## Plays `events` in order; returns when the last step is done.
func play(events: Array) -> void:
	is_playing = true
	_is_stopped = false
	var index := 0
	while index < events.size() and not _is_stopped:
		var event: Dictionary = events[index]
		var handler: Callable = _handlers.get(event["type"], Callable())
		if _is_hidden_step(event):
			_apply_quietly(event)
			index += 1
		elif handler.is_valid():
			step_started.emit(event["type"])
			index = await handler.call(events, index)
		else:
			index += 1
	is_playing = false
	played.emit()


## Ends the playback now: the step that plays ends at once and no other
## starts (the battle is left for the summary). play() returns as usual.
func stop() -> void:
	if not is_playing:
		return
	_is_stopped = true
	skip_step()


## A tap during playback: the step that plays now ends at once.
func skip_step() -> void:
	if close_up.is_playing:
		close_up.skip()
	if _tween != null and _tween.is_valid():
		_tween.custom_step(1000.0)


func _new_step() -> Tween:
	_tween = create_tween()
	_tween.set_speed_scale(speed)
	return _tween


# Waits for the step's tween (at once in instant mode or after a skip).
func _finish(tween: Tween) -> void:
	if is_instant and tween.is_valid():
		tween.custom_step(1000.0)
	if tween.is_valid() and tween.is_running():
		await tween.finished


func _piece(unit: int) -> TacticsPieceView:
	return map.get_piece(unit)


func _is_leader(unit: int) -> bool:
	return _units[unit]["role"] == &"leader"


func _above(unit: int) -> Vector2:
	var piece := _piece(unit)
	return piece.position + Vector2(0, -24) if piece != null else Vector2.ZERO


func _play_phase(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	var is_ours: bool = event["side"] == player_side
	if not is_ours:
		map.set_intents([])
	for piece: TacticsPieceView in map.get_pieces():
		piece.is_done = false
	Sound.play(&"battle_drum")
	phase_shown.emit(int(event["side"]), int(event["round"]))
	var tween := _new_step()
	banner.present(tr("TACTICS_PHASE_PLAYER") if is_ours else tr("TACTICS_PHASE_ENEMY"), tr("TACTICS_ROUND_FORMAT") % [event["round"], banner.max_rounds], is_ours)
	tween.tween_interval(BANNER_SEC)
	tween.tween_callback(banner.dismiss)
	await _finish(tween)
	banner.dismiss()
	phase_banner_ended.emit(int(event["side"]), int(event["round"]))
	return index + 1


func _play_move(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	if event["kind"] == &"squad":
		return await _play_squad_moves(events, index)
	var piece := _piece(event["unit"])
	if piece != null and _is_unseen_move(event, piece):
		piece.position = map.cell_to_local(event["to"])
		return index + 1
	var tween := _new_step()
	var path: Array = event["path"]
	var walk_sec := maxf(MOVE_SEC_PER_CELL * (path.size() - 1), 0.05)
	map.follow(map.cell_to_local(event["to"]))
	_fade_with_sight(tween, piece, event, maxf(walk_sec, FADE_SEC))
	if event["kind"] == &"pull":
		Sound.play(&"block")
		tween.tween_property(piece, ^"position", map.cell_to_local(event["to"]), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await _finish(tween)
		return index + 1
	Sound.play(&"charge")
	tween.set_parallel()
	for step: int in range(1, path.size()):
		tween.tween_property(piece, ^"position", map.cell_to_local(path[step]), MOVE_SEC_PER_CELL).set_delay(MOVE_SEC_PER_CELL * (step - 1))
	tween.tween_interval(walk_sec)
	# What the walk shows clears while it walks, and the squad steps right
	# after its leader, one step behind: one span of frames, not three.
	var end := index + 1
	var visions: Array[int] = []
	if _is_leader(event["unit"]):
		var charges: Array[int] = []
		while end < events.size() and events[end]["type"] in [&"skill_charge_changed", &"vision_changed"]:
			(charges if events[end]["type"] == &"skill_charge_changed" else visions).append(end)
			end += 1
		for at: int in charges:
			_play_charge(events, at)
		if end < events.size() and events[end]["type"] == &"unit_moved" and events[end]["kind"] == &"squad":
			var squad_sec: Array[float] = [0.0]
			end = _add_squad_moves(tween, events, end, MOVE_SEC_PER_CELL, visions, squad_sec)
			walk_sec = maxf(walk_sec, squad_sec[0])
			Sound.play(&"card_flip")
	_blend_sight(events, visions, walk_sec)
	await _finish(tween)
	return await _show_sight(events, visions, end)


# Consecutive squad steps move together, each soldier along its own path;
# what they show clears as they walk.
func _play_squad_moves(events: Array, index: int) -> int:
	var visions: Array[int] = []
	var squad_sec: Array[float] = [0.0]
	var end := index
	var is_any_shown := false
	while end < events.size() and (events[end]["type"] == &"vision_changed" or (events[end]["type"] == &"unit_moved" and events[end]["kind"] == &"squad")):
		if events[end]["type"] == &"unit_moved":
			var piece := _piece(events[end]["unit"])
			is_any_shown = is_any_shown or (piece != null and not _is_unseen_move(events[end], piece))
		end += 1
	if not is_any_shown:
		end = _add_squad_moves(null, events, index, 0.0, visions, squad_sec)
		_blend_sight(events, visions, TacticsMapView.FOG_BLEND_SEC)
		return await _show_sight(events, visions, end)
	var tween := _new_step()
	tween.set_parallel()
	end = _add_squad_moves(tween, events, index, 0.0, visions, squad_sec)
	Sound.play(&"card_flip")
	_blend_sight(events, visions, squad_sec[0])
	await _finish(tween)
	return await _show_sight(events, visions, end)


# Adds the run of squad steps from `index` to a parallel tween, starting
# after `delay`; returns the index after the run. Sight changes between
# the steps are skipped and listed in `visions`; `seconds[0]` is set to
# how long the run takes.
func _add_squad_moves(tween: Tween, events: Array, index: int, delay: float, visions: Array[int], seconds: Array[float]) -> int:
	var end := index
	var longest := 1
	var steps: Array[int] = []
	while end < events.size():
		var type: StringName = events[end]["type"]
		if type == &"vision_changed":
			visions.append(end)
		elif type == &"unit_moved" and events[end]["kind"] == &"squad":
			steps.append(end)
			longest = maxi(longest, (events[end]["path"] as Array).size() - 1)
		else:
			break
		end += 1
	var per_cell := minf(MOVE_SEC_PER_CELL * 0.9, SQUAD_MOVE_MAX_SEC / longest)
	for step_index: int in steps:
		var event: Dictionary = events[step_index]
		var piece := _piece(event["unit"])
		if piece == null:
			continue
		# A soldier our side does not see moves unseen.
		if tween == null or _is_unseen_move(event, piece):
			piece.position = map.cell_to_local(event["to"])
			continue
		_fade_with_sight(tween, piece, event, delay + per_cell * maxf((event["path"] as Array).size() - 1, 1))
		var path: Array = event["path"]
		for step: int in range(1, path.size()):
			tween.tween_property(piece, ^"position", map.cell_to_local(path[step]), per_cell).set_delay(delay + per_cell * (step - 1))
	seconds[0] = delay + per_cell * longest
	if tween != null:
		tween.tween_interval(seconds[0])
	return end


# The span of one engagement: from engagement_started to its
# engagement_ended (or to battle_ended); returns the index after it.
func _span_end(events: Array, index: int, end_type: StringName) -> int:
	var started_id: int = events[index]["id"]
	var end := index + 1
	while end < events.size():
		var event: Dictionary = events[end]
		if event["type"] == &"battle_ended":
			return end
		if event["type"] == end_type and (event["cause"] == started_id or end_type == &"skill_resolved"):
			return end + 1
		end += 1
	return end


func _play_engagement(events: Array, index: int) -> int:
	var started: Dictionary = events[index]
	var span_end := _span_end(events, index, &"engagement_ended")
	if _is_leader(started["unit"]):
		await _play_leader_engagement(events, index, span_end)
		return span_end
	# Soldier fights that follow each other are played as one batch.
	var spans: Array[Vector2i] = [Vector2i(index, span_end)]
	while spans[-1].y < events.size() and events[spans[-1].y]["type"] == &"engagement_started" and not _is_leader(events[spans[-1].y]["unit"]):
		var next := spans[-1].y
		spans.append(Vector2i(next, _span_end(events, next, &"engagement_ended")))
	await _play_soldier_fights(events, spans)
	return spans[-1].y


func _play_soldier_fights(events: Array, spans: Array[Vector2i]) -> void:
	var first := _piece(events[spans[0].x]["target"])
	if first != null:
		map.follow(first.position)
	var tween := _new_step()
	tween.set_parallel()
	var stagger := minf(FIGHT_STAGGER_SEC, FIGHT_BATCH_SEC / maxf(spans.size() - 1, 1))
	for order: int in spans.size():
		_add_fight(tween, events, spans[order], order * stagger)
	tween.chain().tween_interval(0.02)
	await _finish(tween)
	for span: Vector2i in spans:
		await _apply_span(events, span.x + 1, span.y, false)


# One soldier fight on the map: the attacker lunges (or shoots), the
# target flashes with the total it took, then the counter, then deaths.
func _add_fight(tween: Tween, events: Array, span: Vector2i, delay: float, is_leader_fight: bool = false) -> void:
	var started: Dictionary = events[span.x]
	var attacker := _piece(started["unit"])
	var defender := _piece(started["target"])
	if attacker == null or defender == null:
		return
	var dealt := 0
	var taken := 0
	var hp_after := {}
	for at: int in range(span.x, span.y):
		var event: Dictionary = events[at]
		if event["type"] != &"damage_dealt":
			continue
		hp_after[event["target"]] = event["hp_after"]
		if event["source"] == started["unit"]:
			dealt += int(event["amount"])
		else:
			taken += int(event["amount"])
	var home := attacker.position
	# A leader lunges further and hits harder, with its counter later.
	var reach := 0.45 if is_leader_fight else 0.3
	var beat := 1.6 if is_leader_fight else 1.0
	var toward: Vector2 = home + (defender.position - home) * reach
	var is_ranged: bool = started["kind"] == &"ranged"
	var blow: StringName = &"hit_heavy" if is_leader_fight else &"hit_light"
	tween.tween_callback(Sound.play.bind(&"arrow" if is_ranged else blow)).set_delay(delay)
	if not is_ranged:
		tween.tween_property(attacker, ^"position", toward, 0.1 * beat).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(delay)
		tween.tween_property(attacker, ^"position", home, 0.12 * beat).set_delay(delay + 0.1 * beat)
	else:
		tween.tween_callback(_shoot.bind(attacker.position, defender.position)).set_delay(delay)
	tween.tween_callback(_hit.bind(started["target"], dealt, int(hp_after.get(started["target"], defender.hp)), HIT_COLOR)).set_delay(delay + 0.12 * beat)
	if is_leader_fight and is_ranged:
		tween.tween_callback(Sound.play.bind(blow)).set_delay(delay + 0.12 * beat)
	if taken > 0:
		tween.tween_callback(Sound.play.bind(&"block")).set_delay(delay + 0.22 * beat)
		tween.tween_callback(_hit.bind(started["unit"], taken, int(hp_after.get(started["unit"], attacker.hp)), COUNTER_COLOR)).set_delay(delay + 0.22 * beat)
	tween.tween_interval(delay + (LEADER_FIGHT_SEC if is_leader_fight else FIGHT_SEC))


func _shoot(from: Vector2, to: Vector2) -> void:
	var shot := _Shot.new()
	shot.position = from
	map.get_fx_layer().add_child(shot)
	var tween := shot.create_tween()
	tween.tween_property(shot, ^"position", to, 0.12)
	tween.tween_callback(shot.queue_free)


func _hit(unit: int, amount: int, hp_after: int, color: Color) -> void:
	var piece := _piece(unit)
	if piece == null:
		return
	piece.hp = hp_after
	piece.flash = 1.0
	var tween := piece.create_tween()
	tween.tween_property(piece, ^"flash", 0.0, 0.2)
	if amount > 0 and piece.visible:
		_float_at(unit, _above(unit), "-%d" % amount, color, 26 if _is_leader(unit) else 22)


# Applies what a span left behind once its fight was shown: hp, deaths,
# charge pips and the short steps of anything else in it.
func _apply_span(events: Array, from: int, to: int, sets_hp: bool) -> void:
	var died := false
	var index := from
	while index < to:
		var event: Dictionary = events[index]
		match event["type"]:
			&"damage_dealt":
				if sets_hp and _piece(event["target"]) != null:
					_piece(event["target"]).hp = event["hp_after"]
				index += 1
			&"unit_died":
				_fall(event["unit"])
				died = true
				index += 1
			&"engagement_ended", &"skill_resolved", &"skill_used":
				index += 1
			_:
				var handler: Callable = _handlers.get(event["type"], Callable())
				if _is_hidden_step(event):
					_apply_quietly(event)
					index += 1
				else:
					index = await handler.call(events, index) if handler.is_valid() else index + 1
	if died:
		Sound.play(&"death")
		var tween := _new_step()
		tween.tween_interval(0.3)
		await _finish(tween)


func _fall(unit: int) -> void:
	var piece := _piece(unit)
	if piece == null or piece.is_dead:
		return
	piece.is_dead = true
	piece.hp = 0
	_forget(unit)
	var tween := piece.create_tween()
	tween.tween_property(piece, ^"scale", Vector2(1.25, 0.4), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(piece, ^"modulate:a", 0.0, 0.25)
	tween.tween_callback(piece.hide)
	if is_instant:
		tween.custom_step(1000.0)


# A leader's attack plays on the map; only a blow that kills a leader
# opens the close-up.
func _play_leader_engagement(events: Array, index: int, span_end: int) -> void:
	var started: Dictionary = events[index]
	var hits: Array = []
	var kills_leader := false
	for at: int in range(index, span_end):
		if events[at]["type"] == &"damage_dealt":
			hits.append(events[at])
		elif events[at]["type"] == &"unit_died" and _is_leader(events[at]["unit"]):
			kills_leader = true
	var target_piece := _piece(started["target"])
	if target_piece != null:
		map.follow(target_piece.position)
	if not kills_leader:
		var tween := _new_step()
		tween.set_parallel()
		_add_fight(tween, events, Vector2i(index, span_end), 0.0, true)
		await _finish(tween)
		await _apply_span(events, index + 1, span_end, true)
		return
	var attacker := _actor(started["unit"])
	var defender := _actor(started["target"])
	close_up_count += 1
	if not is_instant:
		await close_up.play_engagement(attacker, defender, hits, started["is_first_strike"], _backdrop_at(started["target"]))
	for hit: Dictionary in hits:
		_hit(hit["target"], 0, hit["hp_after"], HIT_COLOR)
	var dealt: int = hits.filter(func(hit: Dictionary) -> bool: return hit["source"] == started["unit"]).reduce(func(sum: int, hit: Dictionary) -> int: return sum + int(hit["amount"]), 0)
	var taken: int = hits.filter(func(hit: Dictionary) -> bool: return hit["source"] != started["unit"]).reduce(func(sum: int, hit: Dictionary) -> int: return sum + int(hit["amount"]), 0)
	if dealt > 0:
		_float_at(started["target"], _above(started["target"]), "-%d" % dealt, HIT_COLOR, 26)
	if taken > 0:
		_float_at(started["unit"], _above(started["unit"]), "-%d" % taken, COUNTER_COLOR, 26)
	await _apply_span(events, index + 1, span_end, true)


# What the close-up needs to stand a unit up: its figure, name, side and
# the hp the map shows now.
func _actor(unit: int) -> Dictionary:
	var info: Dictionary = _units[unit]
	var piece := _piece(unit)
	return {
		"unit": unit, "data": text.base_unit(info["id"]), "name": text.unit_name(info), "side": info["side"],
		"hp": piece.hp if piece != null else info["hp"], "max_hp": info["max_hp"], "is_ranged": info["is_ranged"],
	}


func _backdrop_at(unit: int) -> StringName:
	var piece := _piece(unit)
	var terrain := map.get_terrain_at(map.local_to_cell(piece.position)) if piece != null else &""
	return BACKDROPS.get(terrain, &"backdrop.road")


func _play_skill(events: Array, index: int) -> int:
	var used: Dictionary = events[index]
	var span_end := _span_end(events, index, &"skill_resolved")
	var results := {}
	var buffed: Array[int] = []
	var mark_text := ""
	var zone_id: StringName = &""
	for at: int in range(index, span_end):
		var event: Dictionary = events[at]
		if event["type"] == &"damage_dealt" and event["source_id"] == used["skill"]:
			var entry: Dictionary = results.get(event["target"], {"amount": 0, "hp_after": 0})
			entry["amount"] = int(entry["amount"]) + int(event["amount"])
			entry["hp_after"] = event["hp_after"]
			results[event["target"]] = entry
		elif event["type"] == &"buff_applied":
			buffed.append(event["unit"])
			mark_text = tr("TACTICS_FLOAT_ATTACK_FORMAT") % event["amount"]
		elif event["type"] == &"zone_created":
			zone_id = event["zone"]
	var shown: Array = []
	for unit: int in (results.keys() if not results.is_empty() else buffed):
		if shown.size() < 3:
			shown.append(_actor(unit))
	var is_ours := int(_units[used["unit"]]["side"]) == player_side
	var subtitle := text.skill_outcome(is_ours, results.size(), buffed.size(), zone_id)
	close_up_count += 1
	var caster := _actor(used["unit"])
	if not is_instant:
		await close_up.play_skill(looks.get_look(used["skill"]), caster, shown, results, mark_text, "%s · %s" % [caster["name"], text.skill_name(used["skill"])], subtitle, _backdrop_at(used["unit"]))
	for unit: int in results:
		_hit(unit, int(results[unit]["amount"]), int(results[unit]["hp_after"]), HIT_COLOR)
	await _apply_span(events, index + 1, span_end, true)
	return span_end


func _play_loose_damage(events: Array, index: int) -> int:
	var tween := _new_step()
	var end := index
	while end < events.size() and events[end]["type"] == &"damage_dealt":
		var event: Dictionary = events[end]
		var is_burn: bool = String(event["source_id"]).begins_with("zone.")
		_hit(event["target"], int(event["amount"]), int(event["hp_after"]), BURN_COLOR if is_burn else HIT_COLOR)
		end += 1
	Sound.play(&"hit_light")
	tween.tween_interval(0.35)
	await _finish(tween)
	return end


func _play_death(events: Array, index: int) -> int:
	_fall(events[index]["unit"])
	Sound.play(&"death")
	var tween := _new_step()
	tween.tween_interval(0.3)
	await _finish(tween)
	return index + 1


# Charge pips fill without a pause; a sound when a pip fills, a word when
# the skill is ready.
func _play_charge(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	var piece := _piece(event["unit"])
	if piece == null:
		return index + 1
	var pips := TacticsPainter.MAX_PIPS
	var before := floori(float(piece.charge_value) / maxf(event["threshold"], 1) * mini(event["threshold"], pips))
	var after := floori(float(event["value"]) / maxf(event["threshold"], 1) * mini(event["threshold"], pips))
	piece.set_charge(event["value"], event["threshold"])
	if event["value"] >= event["threshold"] and int(event["value"]) > 0:
		Sound.play(&"level_up")
		_float_at(event["unit"], _above(event["unit"]), tr("TACTICS_SKILL_READY"), Palette.GOLD, 22)
	elif after != before:
		Sound.play(&"coin" if after > before else &"formation_break")
	return index + 1


func _play_growth(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	Sound.play(&"level_up")
	_float_at(event["unit"], _above(event["unit"]), tr("TACTICS_FLOAT_SKILL_GREW_FORMAT") % event["area_bonus"], Palette.GOLD, 22)
	return await _pause(index, 0.35)


func _play_buffs(events: Array, index: int) -> int:
	var end := index
	while end < events.size() and events[end]["type"] == &"buff_applied":
		var is_armor: bool = events[end].get("stat", &"") == &"stat.armor"
		var format := "TACTICS_FLOAT_ARMOR_FORMAT" if is_armor else "TACTICS_FLOAT_ATTACK_FORMAT"
		_float_at(events[end]["unit"], _above(events[end]["unit"]), tr(format) % events[end]["amount"], MARK_COLOR, 20)
		end += 1
	Sound.play(&"level_up")
	await _pause(index, 0.4)
	return end


func _play_buffs_ended(events: Array, index: int) -> int:
	var end := index
	while end < events.size() and events[end]["type"] == &"buff_ended":
		_float_at(events[end]["unit"], _above(events[end]["unit"]), tr("TACTICS_FLOAT_BUFF_ENDED"), Palette.TEXT_DIM, 18)
		end += 1
	Sound.play(&"formation_break")
	await _pause(index, 0.35)
	return end


func _play_zone(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	_zones.append({"zone": event["zone"], "cells": event["cells"], "source": event["unit"]})
	map.set_zones(_zones)
	var cells: Array = event["cells"]
	if not cells.is_empty():
		var center: Vector2i = cells[cells.size() / 2]
		var rounds: int = int(event["end_round"]) - int(event["round"])
		map.float_text(map.cell_to_local(center), tr("TACTICS_FLOAT_ZONE_FORMAT") % [text.zone_name(event["zone"]), maxi(rounds, 1)], Palette.CREAM, 20)
	Sound.play(&"spell")
	return await _pause(index, 0.35)


func _play_zone_expired(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	for at: int in _zones.size():
		var zone: Dictionary = _zones[at]
		if zone["zone"] == event["zone"] and zone["source"] == event["unit"] and Array(zone["cells"]) == Array(event["cells"]):
			_zones.remove_at(at)
			break
	map.set_zones(_zones)
	var cells: Array = event["cells"]
	if not cells.is_empty():
		map.float_text(map.cell_to_local(cells[cells.size() / 2]), tr("TACTICS_FLOAT_ZONE_ENDED_FORMAT") % text.zone_name(event["zone"]), Palette.TEXT_DIM, 18)
	Sound.play(&"formation_break")
	return await _pause(index, 0.3)


func _play_passive(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	Sound.play(&"merge")
	_float_at(event["unit"], _above(event["unit"]) + Vector2(0, -16), text.passive_name(event["passive"]), Palette.GOLD, 20)
	return await _pause(index, 0.35)


func _play_order(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	Sound.play(&"formation_on")
	_float_at(event["unit"], _above(event["unit"]), tr("TACTICS_FLOAT_ORDER_FORMAT") % text.order_name(event["order"]), Palette.CREAM, 20)
	return await _pause(index, 0.3)


func _play_wait(events: Array, index: int) -> int:
	Sound.play(&"timer_tick")
	_float_at(events[index]["unit"], _above(events[index]["unit"]), tr("TACTICS_FLOAT_WAIT"), Palette.TEXT_DIM, 20)
	return await _pause(index, 0.25)


func _play_intents(events: Array, index: int) -> int:
	var intents: Array = []
	var end := index
	while end < events.size() and events[end]["type"] == &"intent_declared":
		var event: Dictionary = events[end]
		var piece := _piece(event["unit"])
		var from: Vector2i = map.local_to_cell(piece.position) if piece != null else event["to"]
		end += 1
		if intent_filter.is_valid() and not intent_filter.call(int(event["unit"])):
			continue
		intents.append({"unit": event["unit"], "from": from, "to": event["to"], "action": event["action"], "target": event["target"], "target_cell": event["target_cell"]})
	map.set_intents(intents)
	Sound.play(&"text_blip")
	await _pause(index, 0.3)
	return end


# Soldiers that start to waver in this phase: the mark pops over each.
func _play_wavered(events: Array, index: int) -> int:
	var end := index
	var tween := _new_step()
	tween.set_parallel()
	while end < events.size() and events[end]["type"] == &"soldier_wavered":
		var event: Dictionary = events[end]
		var piece := _piece(event["unit"])
		if piece != null:
			var is_good: bool = event["is_good"]
			piece.wavering = TacticsPieceView.Wavering.GOOD if is_good else TacticsPieceView.Wavering.BAD
			piece.wavering_scale = 0.0
			tween.tween_property(piece, ^"wavering_scale", 1.4, 0.18).set_delay(0.08 * (end - index))
			tween.chain().tween_property(piece, ^"wavering_scale", 1.0, 0.12)
			tween.set_parallel()
			var line: String = tr("TACTICS_FLOAT_WAVERING_FORMAT") % text.incident_name(event["incident"])
			_float_at(event["unit"], _above(event["unit"]) + Vector2(0, -14 - 22 * ((end - index) % 2)), line, Palette.GOLD if is_good else Palette.VERMILION.lightened(0.25), 20, 30.0, 1.3)
		end += 1
	tween.chain().tween_interval(WAVER_SEC)
	Sound.play(&"timer_tick")
	await _finish(tween)
	return end


func _play_calmed(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	var piece := _piece(event["unit"])
	var tween := _new_step()
	if piece != null:
		tween.tween_property(piece, ^"wavering_scale", 0.0, 0.2)
		tween.tween_callback(func() -> void: piece.wavering = TacticsPieceView.Wavering.NONE)
	var key := "TACTICS_FLOAT_CALMED_LEADER" if event["reason"] == &"leader" else "TACTICS_FLOAT_CALMED"
	_float_at(event["unit"], _above(event["unit"]), tr(key), Palette.CREAM, 20)
	Sound.play(&"formation_on")
	tween.tween_interval(0.3)
	await _finish(tween)
	return index + 1


# The incident's name bursts over the soldier with a ring; its effects
# (dash, buffs, shoves, flight, defection) follow as their own steps.
func _play_incident(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	var piece := _piece(event["unit"])
	var is_good: bool = event["is_good"]
	var color := Palette.GOLD if is_good else Palette.VERMILION
	var tween := _new_step()
	if piece != null:
		piece.wavering = TacticsPieceView.Wavering.NONE
		var ring := _Ring.new()
		ring.color = color
		ring.position = piece.position + piece.get_token_center()
		map.get_fx_layer().add_child(ring)
		var grow := ring.create_tween()
		grow.tween_property(ring, ^"radius", 46.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		grow.parallel().tween_property(ring, ^"modulate:a", 0.0, 0.45)
		grow.tween_callback(ring.queue_free)
		if is_instant:
			grow.custom_step(1000.0)
		piece.flash = 1.0
		tween.tween_property(piece, ^"flash", 0.0, 0.3)
	_float_at(event["unit"], _above(event["unit"]) + Vector2(0, -20), text.incident_name(event["incident"]), color, 30, 44.0, 1.4)
	Sound.play(&"epiphany" if is_good else &"formation_break")
	tween.tween_interval(INCIDENT_SEC)
	await _finish(tween)
	return index + 1


# A mark (Dấu): a gold diamond rises from the soldier and its count grows.
func _play_mark(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	var piece := _piece(event["unit"])
	if piece != null:
		piece.mark_count += 1
		var medal := _Medal.new()
		medal.position = piece.position + Vector2(0, -30)
		map.get_fx_layer().add_child(medal)
		var rise := medal.create_tween()
		rise.tween_property(medal, ^"position:y", medal.position.y - 30.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		rise.parallel().tween_property(medal, ^"modulate:a", 0.0, 0.6).set_delay(0.3)
		rise.tween_callback(medal.queue_free)
		if is_instant:
			rise.custom_step(1000.0)
	_float_at(event["unit"], _above(event["unit"]) + Vector2(0, 8), tr("TACTICS_FLOAT_MARK_FORMAT") % text.incident_name(event["incident"]), Palette.GOLD, 18)
	Sound.play(&"coin")
	return await _pause(index, 0.45)


# The soldier runs to the map's edge and is gone.
func _play_fled(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	var piece := _piece(event["unit"])
	var tween := _new_step()
	_float_at(event["unit"], _above(event["unit"]), tr("TACTICS_FLOAT_FLED"), Palette.VERMILION.lightened(0.25), 22)
	if piece == null or piece.visible:
		Sound.play(&"charge")
	_forget(event["unit"])
	if piece != null:
		piece.is_dead = true
		tween.tween_property(piece, ^"position", map.cell_to_local(event["to"]), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(piece, ^"modulate:a", 0.0, 0.2)
		tween.tween_callback(piece.hide)
	await _finish(tween)
	return index + 1


# The soldier turns: it squashes flat, comes back in the other side's
# colours, and the map's side for it changes.
func _play_defected(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	var unit: int = event["unit"]
	var piece := _piece(unit)
	var new_side: int = event["side"]
	_units[unit]["side"] = new_side
	var is_to_us := new_side == player_side
	var tween := _new_step()
	# An enemy we did not see joins us: it comes into sight as it turns.
	if piece != null and is_to_us and not piece.visible:
		piece.modulate.a = 0.0
		piece.visible = true
		tween.parallel().tween_property(piece, ^"modulate:a", 1.0, FADE_SEC)
	if piece != null:
		tween.tween_property(piece, ^"scale", Vector2(0.15, 1.1), 0.18)
		tween.tween_callback(piece.set_side.bind(new_side))
		tween.tween_property(piece, ^"scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_float_at(unit, _above(unit) + Vector2(0, -12), tr("TACTICS_FLOAT_JOINED_US" if is_to_us else "TACTICS_FLOAT_DEFECTED"), Palette.JADE_LIGHT if is_to_us else Palette.VERMILION.lightened(0.25), 24)
	Sound.play(&"formation_on" if is_to_us else &"petrify")
	tween.tween_interval(0.35)
	await _finish(tween)
	return index + 1


# A step that would show only an enemy our side does not see.
func _is_hidden_step(event: Dictionary) -> bool:
	if not PRIVATE_STEPS.has(event["type"]):
		return false
	var unit: int = event["target"] if event["type"] == &"damage_dealt" else event["unit"]
	var piece := _piece(unit)
	return piece != null and not piece.visible and int(_units[unit]["side"]) != player_side


# What a hidden step leaves on the hidden piece, shown once it is seen.
func _apply_quietly(event: Dictionary) -> void:
	var unit: int = event["target"] if event["type"] == &"damage_dealt" else event["unit"]
	var piece := _piece(unit)
	match event["type"]:
		&"skill_charge_changed":
			piece.set_charge(event["value"], event["threshold"])
		&"soldier_wavered":
			piece.wavering = TacticsPieceView.Wavering.GOOD if event["is_good"] else TacticsPieceView.Wavering.BAD
			piece.wavering_scale = 1.0
		&"incident_calmed", &"incident_fired":
			piece.wavering = TacticsPieceView.Wavering.NONE
		&"mark_earned":
			piece.mark_count += 1
		&"damage_dealt":
			piece.hp = event["hp_after"]
		&"unit_died":
			piece.is_dead = true
			piece.hp = 0
			_forget(unit)
		&"unit_healed":
			piece.hp = event["hp_after"]


# Text rising over a unit, unless our side does not see it.
func _float_at(unit: int, at: Vector2, line: String, color: Color, font_px: int = 26, rise_px: float = 36.0, seconds: float = 0.9) -> void:
	var piece := _piece(unit)
	if piece == null or piece.visible:
		map.float_text(at, line, color, font_px, rise_px, seconds)


# A move of the other side that our side sees neither where it set off nor
# where it stopped.
func _is_unseen_move(event: Dictionary, piece: TacticsPieceView) -> bool:
	return int(_units[event["unit"]]["side"]) != player_side and not piece.visible and not event.get("seen_to", true)


# An enemy coming into sight fades in as it sets off; one leaving it fades
# out at the end of its walk, remembered where it was last seen.
func _fade_with_sight(tween: Tween, piece: TacticsPieceView, event: Dictionary, end_sec: float) -> void:
	if piece == null or int(_units[event["unit"]]["side"]) == player_side:
		return
	var is_shown: bool = event.get("seen_to", true)
	if not piece.visible and is_shown:
		piece.modulate.a = 0.0
		piece.visible = true
		tween.parallel().tween_property(piece, ^"modulate:a", 1.0, FADE_SEC)
	elif piece.visible and not is_shown:
		tween.parallel().tween_property(piece, ^"modulate:a", 0.0, FADE_SEC).set_delay(maxf(end_sec - FADE_SEC, 0.0))


# What our side sees changed: cells clear (or dim) with a short blend and
# a soft sound, enemies come into sight or leave it ("?" where last seen).
func _play_vision(events: Array, index: int) -> int:
	var visions: Array[int] = [index]
	_blend_sight(events, visions, TacticsMapView.FOG_BLEND_SEC)
	return await _show_sight(events, visions, index + 1)


# Starts one blend of the fog to what the listed sight changes of our side
# show, over `seconds` (the walk that caused them), with the soft sound.
func _blend_sight(events: Array, visions: Array[int], seconds: float) -> void:
	var states := map.get_fog().duplicate()
	if states.is_empty():
		return
	var is_any_new := false
	for at: int in visions:
		var event: Dictionary = events[at]
		if int(event["side"]) != player_side:
			continue
		for cell: Vector2i in event["cells"]:
			states[cell.y * map.map_width + cell.x] = 2
		for cell: Vector2i in event["lost_cells"]:
			states[cell.y * map.map_width + cell.x] = 1
		is_any_new = is_any_new or not (event["cells"] as Array).is_empty()
	map.update_fog_states(states, not is_instant, maxf(seconds, FOG_MIN_BLEND_SEC))
	if is_any_new:
		Sound.play(&"fog_reveal")


# After the listed sight changes: enemies that came into sight show (the
# camera finds the first one), those that left it go, and the "?" marks
# follow; returns `end` once a spotted enemy had its beat.
func _show_sight(events: Array, visions: Array[int], end: int) -> int:
	var states := map.get_fog()
	if states.is_empty():
		return end
	var ghosts: Array = map.get_last_seen().duplicate(true)
	var spotted: Array = []
	for at: int in visions:
		var event: Dictionary = events[at]
		if int(event["side"]) != player_side:
			continue
		for unit: int in event["units"]:
			var piece := _piece(unit)
			if piece != null and not piece.is_dead:
				spotted.append(unit)
				piece.visible = true
				if piece.modulate.a < 1.0:
					piece.create_tween().tween_property(piece, ^"modulate:a", 1.0, FADE_SEC)
		var lost: Array = event["lost_units"]
		for lost_index: int in lost.size():
			var unit: int = lost[lost_index]
			# Remembered where the battle says now (nowhere for one that
			# fell, fled or whose cell was seen empty).
			ghosts = ghosts.filter(func(ghost: Dictionary) -> bool: return ghost["unit"] != unit)
			var cell: Vector2i = event["lost_at"][lost_index]
			if cell.x >= 0:
				ghosts.append({"unit": unit, "cell": cell, "is_leader": _is_leader(unit)})
			spotted.erase(unit)
			var piece := _piece(unit)
			if piece == null or piece.is_dead:
				continue
			piece.visible = false
			piece.modulate.a = 1.0
	# A ghost goes when its enemy is seen again, or its cell is seen empty.
	ghosts = ghosts.filter(func(ghost: Dictionary) -> bool:
		var piece := _piece(ghost["unit"])
		var is_seen := piece != null and piece.visible
		return not is_seen and states[(ghost["cell"] as Vector2i).y * map.map_width + (ghost["cell"] as Vector2i).x] != 2)
	map.set_last_seen(ghosts)
	if spotted.is_empty():
		return end
	map.follow(_piece(spotted[0]).position)
	var tween := _new_step()
	tween.tween_interval(SPOTTED_SEC)
	await _finish(tween)
	return end


# A walk stopped by an enemy hidden in the way: the ambusher bursts into
# sight with a ring and the word, and the walker shakes.
func _play_ambush(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	var ambusher := _piece(event["by"])
	var walker := _piece(event["unit"])
	var tween := _new_step()
	if ambusher != null:
		ambusher.visible = true
		ambusher.modulate.a = 1.0
		map.follow(ambusher.position)
		var ring := _Ring.new()
		ring.color = Palette.VERMILION
		ring.position = ambusher.position + ambusher.get_token_center()
		map.get_fx_layer().add_child(ring)
		var grow := ring.create_tween()
		grow.tween_property(ring, ^"radius", 54.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		grow.parallel().tween_property(ring, ^"modulate:a", 0.0, 0.4)
		grow.tween_callback(ring.queue_free)
		if is_instant:
			grow.custom_step(1000.0)
		ambusher.flash = 1.0
		tween.tween_property(ambusher, ^"flash", 0.0, 0.3)
		_float_at(event["by"], _above(event["by"]) + Vector2(0, -18), tr("TACTICS_FLOAT_AMBUSH"), Palette.VERMILION.lightened(0.3), 30, 44.0, 1.3)
	if walker != null:
		var home := walker.position
		for shake: int in 4:
			tween.tween_property(walker, ^"position", home + Vector2(5.0 if shake % 2 == 0 else -5.0, 0.0), 0.05)
		tween.tween_property(walker, ^"position", home, 0.05)
	Sound.play(&"ambush")
	tween.tween_interval(AMBUSH_SEC)
	await _finish(tween)
	return index + 1


# The weather or the time of day turned: a banner with its name.
func _play_environment(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	var kind: StringName = &"weather" if event["type"] == &"weather_changed" else &"daytime"
	environment_changed.emit(kind, event["now"])
	Sound.play(&"weather_turn")
	var tween := _new_step()
	banner.present(text.environment_name(kind, event["now"]), text.environment_description(kind, event["now"]), true)
	tween.tween_interval(BANNER_SEC)
	tween.tween_callback(banner.dismiss)
	await _finish(tween)
	banner.dismiss()
	return index + 1


# --- Sites and objectives ---------------------------------------------

# Our side sees the cell (bit of seen_mask), or the site was ours to use.
func _sees_site_event(event: Dictionary) -> bool:
	return int(event.get("side", -1)) == player_side or (int(event.get("seen_mask", 0)) >> player_side) & 1 == 1


# The map's site entry updated from an event (what our side now knows).
func _update_site(site: int, changes: Dictionary) -> void:
	var sites: Array = map.get_sites().duplicate(true)
	for entry: Dictionary in sites:
		if entry["site"] == site:
			entry.merge(changes, true)
			entry["is_known"] = true
	map.set_sites(sites)


func _play_site_used(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	if not _sees_site_event(event):
		return index + 1
	var cell: Vector2i = event["cell"]
	map.follow(map.cell_to_local(cell))
	var tween := _new_step()
	var at := map.cell_to_local(cell) + Vector2(0, -30)
	map.float_text(at, tr("SITE_CHOICE_" + String(event["choice"]).to_upper()), Palette.GOLD, 26)
	Sound.play(&"site_fire" if event["choice"] == &"loot" else &"site_heal")
	var ring := _Ring.new()
	ring.color = Palette.GOLD
	ring.position = map.cell_to_local(cell)
	map.get_fx_layer().add_child(ring)
	tween.tween_property(ring, ^"radius", TacticsMapView.CELL_PX * 0.7, 0.4).from(8.0)
	tween.parallel().tween_property(ring, ^"modulate:a", 0.0, 0.4)
	tween.tween_callback(ring.queue_free)
	await _finish(tween)
	return index + 1


func _play_site_changed(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	if not _sees_site_event(event):
		return index + 1
	_update_site(event["site"], {"status": event["status"], "owner": event["owner"], "capture_progress": 0})
	var kind: StringName = event["kind"]
	if kind == &"used":
		return index + 1
	var cell: Vector2i = event["cell"]
	var line := tr("TACTICS_FLOAT_BURNED") if kind == &"looted" else tr("TACTICS_FLOAT_CAPTURED")
	var is_ours: bool = event["owner"] == player_side
	map.float_text(map.cell_to_local(cell) + Vector2(0, -10), line, Palette.JADE_LIGHT if is_ours and kind != &"looted" else Palette.VERMILION.lightened(0.25), 26)
	Sound.play(&"site_fire" if kind == &"looted" else &"capture")
	return await _pause(index, 0.45)


func _play_capture(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	if not _sees_site_event(event):
		return index + 1
	var progress: int = event["progress"] if event["kind"] == &"advanced" else (0 if event["kind"] == &"lost" else -1)
	if progress >= 0:
		_update_site(event["site"], {"capture_progress": progress, "capture_side": event["side"]})
	var cell: Vector2i = event["cell"]
	var line := tr("TACTICS_FLOAT_CAPTURE_FORMAT") % [event["progress"], event["phases"]]
	if event["kind"] == &"contested":
		line = tr("TACTICS_FLOAT_CONTESTED")
	elif event["kind"] == &"lost":
		line = tr("TACTICS_FLOAT_CAPTURE_LOST")
	map.follow(map.cell_to_local(cell))
	map.float_text(map.cell_to_local(cell) + Vector2(0, -36), line, TacticsPainter.side_color(event["side"]).lightened(0.4), 24)
	Sound.play(&"battle_drum" if event["kind"] == &"advanced" else &"block")
	return await _pause(index, 0.4)


# Heals in a row rise together (a squad at a village, a camp's rest).
func _play_heals(events: Array, index: int) -> int:
	var end := index
	var any_shown := false
	while end < events.size() and events[end]["type"] == &"unit_healed":
		var event: Dictionary = events[end]
		var piece := _piece(event["unit"])
		if piece != null:
			piece.hp = event["hp_after"]
			if piece.visible:
				any_shown = true
				_float_at(event["unit"], _above(event["unit"]), tr("TACTICS_FLOAT_HEAL_FORMAT") % event["amount"], HEAL_COLOR, 24)
		end += 1
	if not any_shown:
		return end
	Sound.play(&"site_heal")
	var tween := _new_step()
	tween.tween_interval(0.35)
	await _finish(tween)
	return end


# New units in a row drop in together: a wave, a recruit, reinforcements,
# the convoy. An enemy our side does not see arrives hidden.
func _play_arrivals(events: Array, index: int) -> int:
	var end := index
	var tween := _new_step()
	tween.set_parallel()
	var shown: Array[Dictionary] = []
	while end < events.size() and events[end]["type"] == &"unit_arrived":
		var event: Dictionary = events[end]
		end += 1
		var piece := _arrive(event)
		if piece == null:
			continue
		var is_seen: bool = int(event["side"]) == player_side or event["seen_to"]
		piece.visible = is_seen
		if not is_seen:
			continue
		shown.append(event)
		var cell_at := map.cell_to_local(event["cell"])
		piece.position = cell_at + Vector2(0, -ARRIVE_DROP_PX)
		piece.modulate.a = 0.0
		tween.tween_property(piece, ^"position", cell_at, ARRIVE_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(piece, ^"modulate:a", 1.0, FADE_SEC)
	if shown.is_empty():
		tween.kill()
		return end
	var first: Dictionary = shown[0]
	map.follow(map.cell_to_local(first["cell"]))
	var kind: StringName = first["kind"]
	var is_ours: bool = int(first["side"]) == player_side
	if kind == &"wave":
		Sound.play(&"war_horn")
		banner.present(tr("TACTICS_BANNER_WAVE"), "", false)
		tween.chain().tween_interval(BANNER_SEC)
		tween.chain().tween_callback(banner.dismiss)
	elif kind == &"reinforce":
		Sound.play(&"formation_on" if is_ours else &"war_horn")
		banner.present(tr("TACTICS_BANNER_REINFORCE"), "", is_ours)
		tween.chain().tween_interval(BANNER_SEC)
		tween.chain().tween_callback(banner.dismiss)
	else:
		Sound.play(&"cart" if kind == &"convoy" else &"merge")
	if kind == &"recruit":
		_float_at(first["unit"], map.cell_to_local(first["cell"]) + Vector2(0, -40), tr("TACTICS_FLOAT_RECRUIT"), Palette.JADE_LIGHT, 24)
	await _finish(tween)
	banner.dismiss()
	return end


# The piece of an arriving unit, made by the screen; our _units grows to it.
func _arrive(event: Dictionary) -> TacticsPieceView:
	var unit: int = event["unit"]
	var piece := _piece(unit)
	if piece == null and piece_factory.is_valid():
		var state: Dictionary = piece_factory.call(event)
		while _units.size() <= unit:
			_units.append({})
		_units[unit] = state
		piece = _piece(unit)
	elif unit < _units.size() and not _units[unit].is_empty():
		_units[unit]["side"] = event["side"]
	if piece != null:
		piece.is_dead = false
		piece.position = map.cell_to_local(event["cell"])
	return piece


# A unit leaves by an exit (a leader breaking out with its squad, the
# convoy at the road's end, the fleeing general): it slides off and fades.
func _play_escaped(events: Array, index: int) -> int:
	var end := index
	var tween := _new_step()
	tween.set_parallel()
	var first_shown: Dictionary = {}
	while end < events.size() and events[end]["type"] == &"unit_escaped":
		var event: Dictionary = events[end]
		end += 1
		var unit: int = event["unit"]
		var piece := _piece(unit)
		_forget(unit)
		if piece == null:
			continue
		piece.is_dead = true
		var is_seen: bool = int(event["side"]) == player_side or event["seen_from"] or piece.visible
		if not is_seen:
			piece.hide()
			continue
		if first_shown.is_empty():
			first_shown = event
		var out := map.cell_to_local(event["cell"]) + _outward_of(event["cell"]) * TacticsMapView.CELL_PX
		tween.tween_property(piece, ^"position", out, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(piece, ^"modulate:a", 0.0, 0.45)
	if first_shown.is_empty():
		tween.kill()
		return end
	var kind: StringName = first_shown["kind"]
	var line := tr("TACTICS_FLOAT_ESCAPED")
	if kind == &"convoy":
		line = tr("TACTICS_FLOAT_CONVOY_OUT")
	elif kind == &"general":
		line = tr("TACTICS_FLOAT_GENERAL_OUT")
	map.follow(map.cell_to_local(first_shown["cell"]))
	map.float_text(map.cell_to_local(first_shown["cell"]) + Vector2(0, -30), line, Palette.GOLD, 26)
	Sound.play(&"cart" if kind == &"convoy" else &"charge")
	tween.chain().tween_callback(func() -> void:
		for at: int in range(index, end):
			var gone := _piece(events[at]["unit"])
			if gone != null:
				gone.hide())
	await _finish(tween)
	return end


# The way off the map from an edge cell.
func _outward_of(cell: Vector2i) -> Vector2:
	if cell.y == 0:
		return Vector2.UP
	if cell.y == map.map_height - 1:
		return Vector2.DOWN
	return Vector2.LEFT if cell.x == 0 else Vector2.RIGHT


func _play_convoy_halted(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	var keys := {&"hold": "TACTICS_FLOAT_CONVOY_HOLD", &"go": "TACTICS_FLOAT_CONVOY_GO", &"holding": "TACTICS_FLOAT_CONVOY_HOLD",
		&"enemy": "TACTICS_FLOAT_CONVOY_ENEMY", &"blocked": "TACTICS_FLOAT_CONVOY_BLOCKED"}
	var is_trouble: bool = event["kind"] == &"enemy" or event["kind"] == &"blocked"
	_float_at(event["unit"], _above(event["unit"]), tr(keys.get(event["kind"], "TACTICS_FLOAT_CONVOY_HOLD")), Palette.VERMILION.lightened(0.25) if is_trouble else Palette.CREAM, 24)
	Sound.play(&"block" if is_trouble else &"cart")
	return await _pause(index, 0.35)


# The general's nerve breaks: a banner, and his piece shakes if seen.
func _play_general_fleeing(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	var piece := _piece(event["unit"])
	Sound.play(&"war_horn")
	var tween := _new_step()
	banner.present(tr("TACTICS_BANNER_GENERAL_FLEEING"), tr("TACTICS_BANNER_GENERAL_FLEEING_DETAIL"), int(_units[event["unit"]]["side"]) != player_side)
	if piece != null and piece.visible:
		map.follow(piece.position)
		var home := piece.position
		for step: int in 3:
			tween.tween_property(piece, ^"position", home + Vector2(6, 0), 0.05)
			tween.tween_property(piece, ^"position", home - Vector2(6, 0), 0.05)
		tween.tween_property(piece, ^"position", home, 0.05)
	tween.tween_interval(BANNER_SEC)
	tween.tween_callback(banner.dismiss)
	await _finish(tween)
	banner.dismiss()
	return index + 1


func _play_supplies(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	if int(event["side"]) != player_side:
		return index + 1
	supplies_gained.emit(int(event["amount"]), int(event["total"]))
	Sound.play(&"coin")
	return await _pause(index, 0.2)


# A unit that is gone (dead, fled) is not remembered.
func _forget(unit: int) -> void:
	var ghosts := map.get_last_seen().filter(func(ghost: Dictionary) -> bool: return ghost["unit"] != unit)
	if ghosts.size() != map.get_last_seen().size():
		map.set_last_seen(ghosts)


func _pause(index: int, seconds: float) -> int:
	var tween := _new_step()
	tween.tween_interval(seconds)
	await _finish(tween)
	return index + 1


## The ring an incident bursts with.
class _Ring extends Node2D:
	var color := Palette.GOLD
	var radius: float = 12.0:
		set(value):
			radius = value
			queue_redraw()

	func _draw() -> void:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Palette.INK, 6.0, true)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, color, 3.5, true)


## The gold diamond a mark rises as.
class _Medal extends Node2D:
	func _draw() -> void:
		var points := PackedVector2Array([Vector2(0, -9), Vector2(7, 0), Vector2(0, 9), Vector2(-7, 0)])
		draw_colored_polygon(points, Palette.GOLD)
		points.append(points[0])
		draw_polyline(points, Palette.INK, 2.0)


## A small dot flying from shooter to target.
class _Shot extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2(0, -6), 4.0, Palette.INK)
		draw_circle(Vector2(0, -6), 2.5, Palette.CREAM)
