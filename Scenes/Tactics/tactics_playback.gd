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
## camera follows what plays. A tap skips the step that plays now. It
## never changes the battle; the screen syncs the map from the battle once
## it is done.
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
		if handler.is_valid():
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
	return index + 1


func _play_move(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	if event["kind"] == &"squad":
		return await _play_squad_moves(events, index)
	var piece := _piece(event["unit"])
	var tween := _new_step()
	var path: Array = event["path"]
	map.follow(map.cell_to_local(event["to"]))
	if event["kind"] == &"pull":
		Sound.play(&"block")
		tween.tween_property(piece, ^"position", map.cell_to_local(event["to"]), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await _finish(tween)
		return index + 1
	Sound.play(&"charge")
	tween.set_parallel()
	for step: int in range(1, path.size()):
		tween.tween_property(piece, ^"position", map.cell_to_local(path[step]), MOVE_SEC_PER_CELL).set_delay(MOVE_SEC_PER_CELL * (step - 1))
	tween.tween_interval(maxf(MOVE_SEC_PER_CELL * (path.size() - 1), 0.05))
	# The squad steps right after its leader: it sets off one step behind.
	var end := index + 1
	if _is_leader(event["unit"]):
		var squad_end := end
		while squad_end < events.size() and events[squad_end]["type"] == &"skill_charge_changed":
			squad_end += 1
		if squad_end < events.size() and events[squad_end]["type"] == &"unit_moved" and events[squad_end]["kind"] == &"squad":
			for at: int in range(end, squad_end):
				_play_charge(events, at)
			end = _add_squad_moves(tween, events, squad_end, MOVE_SEC_PER_CELL)
			Sound.play(&"card_flip")
	await _finish(tween)
	return end


# Consecutive squad steps move together, each soldier along its own path.
func _play_squad_moves(events: Array, index: int) -> int:
	var tween := _new_step()
	tween.set_parallel()
	var end := _add_squad_moves(tween, events, index, 0.0)
	Sound.play(&"card_flip")
	await _finish(tween)
	return end


# Adds the run of squad steps from `index` to a parallel tween, starting
# after `delay`; returns the index after the run.
func _add_squad_moves(tween: Tween, events: Array, index: int, delay: float) -> int:
	var end := index
	var longest := 1
	while end < events.size() and events[end]["type"] == &"unit_moved" and events[end]["kind"] == &"squad":
		longest = maxi(longest, (events[end]["path"] as Array).size() - 1)
		end += 1
	var per_cell := minf(MOVE_SEC_PER_CELL * 0.9, SQUAD_MOVE_MAX_SEC / longest)
	for step_index: int in range(index, end):
		var event: Dictionary = events[step_index]
		var piece := _piece(event["unit"])
		if piece == null:
			continue
		var path: Array = event["path"]
		for step: int in range(1, path.size()):
			tween.tween_property(piece, ^"position", map.cell_to_local(path[step]), per_cell).set_delay(delay + per_cell * (step - 1))
	tween.tween_interval(delay + per_cell * longest)
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
	if amount > 0:
		map.float_text(_above(unit), "-%d" % amount, color, 26 if _is_leader(unit) else 22)


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
		map.float_text(_above(started["target"]), "-%d" % dealt, HIT_COLOR, 26)
	if taken > 0:
		map.float_text(_above(started["unit"]), "-%d" % taken, COUNTER_COLOR, 26)
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
		map.float_text(_above(event["unit"]), tr("TACTICS_SKILL_READY"), Palette.GOLD, 22)
	elif after != before:
		Sound.play(&"coin" if after > before else &"formation_break")
	return index + 1


func _play_growth(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	Sound.play(&"level_up")
	map.float_text(_above(event["unit"]), tr("TACTICS_FLOAT_SKILL_GREW_FORMAT") % event["area_bonus"], Palette.GOLD, 22)
	return await _pause(index, 0.35)


func _play_buffs(events: Array, index: int) -> int:
	var end := index
	while end < events.size() and events[end]["type"] == &"buff_applied":
		var is_armor: bool = events[end].get("stat", &"") == &"stat.armor"
		var format := "TACTICS_FLOAT_ARMOR_FORMAT" if is_armor else "TACTICS_FLOAT_ATTACK_FORMAT"
		map.float_text(_above(events[end]["unit"]), tr(format) % events[end]["amount"], MARK_COLOR, 20)
		end += 1
	Sound.play(&"level_up")
	await _pause(index, 0.4)
	return end


func _play_buffs_ended(events: Array, index: int) -> int:
	var end := index
	while end < events.size() and events[end]["type"] == &"buff_ended":
		map.float_text(_above(events[end]["unit"]), tr("TACTICS_FLOAT_BUFF_ENDED"), Palette.TEXT_DIM, 18)
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
	map.float_text(_above(event["unit"]) + Vector2(0, -16), text.passive_name(event["passive"]), Palette.GOLD, 20)
	return await _pause(index, 0.35)


func _play_order(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	Sound.play(&"formation_on")
	map.float_text(_above(event["unit"]), tr("TACTICS_FLOAT_ORDER_FORMAT") % text.order_name(event["order"]), Palette.CREAM, 20)
	return await _pause(index, 0.3)


func _play_wait(events: Array, index: int) -> int:
	Sound.play(&"timer_tick")
	map.float_text(_above(events[index]["unit"]), tr("TACTICS_FLOAT_WAIT"), Palette.TEXT_DIM, 20)
	return await _pause(index, 0.25)


func _play_intents(events: Array, index: int) -> int:
	var intents: Array = []
	var end := index
	while end < events.size() and events[end]["type"] == &"intent_declared":
		var event: Dictionary = events[end]
		var piece := _piece(event["unit"])
		var from: Vector2i = map.local_to_cell(piece.position) if piece != null else event["to"]
		intents.append({"unit": event["unit"], "from": from, "to": event["to"], "action": event["action"], "target": event["target"], "target_cell": event["target_cell"]})
		end += 1
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
			map.float_text(_above(event["unit"]) + Vector2(0, -14 - 22 * ((end - index) % 2)), line, Palette.GOLD if is_good else Palette.VERMILION.lightened(0.25), 20, 30.0, 1.3)
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
	map.float_text(_above(event["unit"]), tr(key), Palette.CREAM, 20)
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
	map.float_text(_above(event["unit"]) + Vector2(0, -20), text.incident_name(event["incident"]), color, 30, 44.0, 1.4)
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
	map.float_text(_above(event["unit"]) + Vector2(0, 8), tr("TACTICS_FLOAT_MARK_FORMAT") % text.incident_name(event["incident"]), Palette.GOLD, 18)
	Sound.play(&"coin")
	return await _pause(index, 0.45)


# The soldier runs to the map's edge and is gone.
func _play_fled(events: Array, index: int) -> int:
	var event: Dictionary = events[index]
	var piece := _piece(event["unit"])
	var tween := _new_step()
	map.float_text(_above(event["unit"]), tr("TACTICS_FLOAT_FLED"), Palette.VERMILION.lightened(0.25), 22)
	Sound.play(&"charge")
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
	if piece != null:
		tween.tween_property(piece, ^"scale", Vector2(0.15, 1.1), 0.18)
		tween.tween_callback(piece.set_side.bind(new_side))
		tween.tween_property(piece, ^"scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	map.float_text(_above(unit) + Vector2(0, -12), tr("TACTICS_FLOAT_JOINED_US" if is_to_us else "TACTICS_FLOAT_DEFECTED"), Palette.JADE_LIGHT if is_to_us else Palette.VERMILION.lightened(0.25), 24)
	Sound.play(&"formation_on" if is_to_us else &"petrify")
	tween.tween_interval(0.35)
	await _finish(tween)
	return index + 1


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
