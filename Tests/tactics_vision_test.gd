extends SceneTree

# Headless tests for fog of war, weather and times of day
# (Docs/systems/tactics_vision.md): lines of sight blocked by forest and
# hills, hills seeing further, the union of a side's sight, the three fog
# states, forest hiding units from all but neighbours and scouts, an
# attacker showing itself, the ambush stop, undo refused after a reveal,
# cells passed in sight told by the events, forecasts that keep a hidden
# zone of control secret,
# the AI not using what it cannot see, last-seen ghosts, each weather,
# night and lights, read intents, incidents out of the leader's sight,
# a battle without an environment unchanged, and determinism. Side B is
# played by hand unless a check says otherwise. Cells are (col, row).

const Kit := preload("res://Tests/tactics_test_kit.gd")
const MOON_SPEAR: StringName = &"leader.moon_spear"
const THIET_NHA: StringName = &"leader.thiet_nha"
const LIEU_MI: StringName = &"leader.lieu_mi"
const BA_KHAC: StringName = &"leader.ba_khac"
const SPEARMAN: StringName = &"troop.spearman"
const A: int = TacticsBattle.SIDE_A
const B: int = TacticsBattle.SIDE_B
const NEVER_SEEN: int = 0
const SEEN: int = 1
const VISIBLE: int = 2

var _kit := Kit.new()


func _initialize() -> void:
	var ok := _run()
	_kit.free_battles()
	if ok:
		print("Tactics vision test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not _kit.load_catalog():
		return false
	var checks: Array[Callable] = [
		_check_line_of_sight, _check_hill_sees_far, _check_union, _check_fog_states,
		_check_forest_hides, _check_attacker_shows, _check_ambush, _check_undo_after_reveal,
		_check_vision_event, _check_walk_sight_told, _check_forecast_keeps_secret, _check_ai_blind, _check_last_seen, _check_rain, _check_wind,
		_check_fog_weather, _check_burn_in_rain, _check_night_and_lights, _check_daytime_cycle,
		_check_weather_change, _check_intents_at_night, _check_unseen_waver, _check_unseen_calm,
		_check_unseen_odds, _check_no_environment, _check_determinism,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Tactics vision test failed in %s" % check.get_method())
			return false
	return true


# A scenario that carries only an environment, for set_environment().
func _env(fog: bool = true, weather: StringName = &"weather.clear", daytimes: Array[StringName] = [&"daytime.day"]) -> TacticsScenarioData:
	var scenario := TacticsScenarioData.new()
	scenario.id = &"scenario.vision_test"
	scenario.fog_of_war = fog
	scenario.weather = _kit.catalog.get_weather(weather)
	var cycle: Array[TacticsDaytimeData] = []
	for id: StringName in daytimes:
		cycle.append(_kit.catalog.get_daytime(id))
	scenario.daytimes = cycle
	return scenario


func _battle(rows: PackedStringArray, environment: TacticsScenarioData, ai_b: bool = false) -> TacticsBattle:
	var battle := _kit.new_battle(rows, ai_b)
	var ok := battle.set_environment(environment)
	assert(ok, "Tactics vision test: set_environment failed")
	return battle


func _leader(id: StringName, changes: Dictionary = {}) -> TacticsLeaderData:
	return _kit.leader(id, [], changes)


func _rows(changes: Dictionary) -> PackedStringArray:
	var rows := _kit.plain_rows()
	for row: int in changes:
		rows[row] = changes[row]
	return rows


func _fog_at(battle: TacticsBattle, side: int, cell: Vector2i) -> int:
	return battle.get_fog_cells(side)[cell.y * battle.get_map_width() + cell.x]


func _visible(battle: TacticsBattle, cells: Array[Vector2i]) -> Array:
	return cells.map(func(cell: Vector2i) -> bool: return battle.is_cell_visible(A, cell))


# Sight cost: Manhattan distance plus sight_block of the cells between. A
# forest (1) or a hill (2) in the way cuts what a vision of 5 reaches.
func _check_line_of_sight() -> bool:
	var battle := _battle(_rows({5: "..f.........", 8: "h..........."}), _env())
	_kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(0, 5))
	_kit.add(battle, B, _leader(THIET_NHA), Vector2i(11, 0))
	battle.start()
	return Kit.expect("forest and hill block", _visible(battle, [Vector2i(4, 5), Vector2i(5, 5), Vector2i(0, 7), Vector2i(0, 9), Vector2i(3, 3), Vector2i(0, 10)]),
			[true, false, true, false, true, false])


# A leader on a hill sees two cells further.
func _check_hill_sees_far() -> bool:
	var high := _battle(_rows({5: "h..........."}), _env())
	_kit.add(high, A, _leader(MOON_SPEAR), Vector2i(0, 5))
	_kit.add(high, B, _leader(THIET_NHA), Vector2i(11, 11))
	high.start()
	var low := _battle(_kit.plain_rows(), _env())
	_kit.add(low, A, _leader(MOON_SPEAR), Vector2i(0, 5))
	_kit.add(low, B, _leader(THIET_NHA), Vector2i(11, 11))
	low.start()
	return Kit.expect("from the hill", _visible(high, [Vector2i(7, 5), Vector2i(0, 11)]), [true, true]) \
		and Kit.expect("from the plain", _visible(low, [Vector2i(7, 5), Vector2i(0, 11)]), [false, false])


# A side sees what any of its units sees.
func _check_union() -> bool:
	var battle := _battle(_kit.plain_rows(), _env())
	_kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(0, 0))
	_kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(11, 11))
	var enemy := _kit.add(battle, B, _leader(THIET_NHA), Vector2i(6, 6))
	battle.start()
	return Kit.expect("both corners", _visible(battle, [Vector2i(1, 0), Vector2i(10, 11), Vector2i(6, 6)]), [true, true, false]) \
		and Kit.expect("enemy unseen", battle.is_unit_seen(A, enemy), false) \
		and Kit.expect("never seen", _fog_at(battle, A, Vector2i(6, 6)), NEVER_SEEN)


# Visible now, seen before (remembered terrain), never seen.
func _check_fog_states() -> bool:
	var battle := _battle(_kit.plain_rows(), _env())
	var spear := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(0, 5))
	_kit.add(battle, B, _leader(THIET_NHA), Vector2i(11, 11))
	battle.start()
	var before := [_fog_at(battle, A, Vector2i(3, 5)), _fog_at(battle, A, Vector2i(11, 0))]
	battle.move_leader(spear, Vector2i(0, 1))
	return Kit.expect("before the move", before, [VISIBLE, NEVER_SEEN]) \
		and Kit.expect("after it", [_fog_at(battle, A, Vector2i(3, 5)), _fog_at(battle, A, Vector2i(0, 0))], [SEEN, VISIBLE])


# A unit in forest shows only to an enemy next to it or to a scout.
func _check_forest_hides() -> bool:
	var rows := _rows({5: "...f........"})
	var battle := _battle(rows, _env())
	var spear := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(1, 5))
	var hidden := _kit.add(battle, B, _leader(THIET_NHA), Vector2i(3, 5))
	battle.start()
	var far := [battle.is_cell_visible(A, Vector2i(3, 5)), battle.is_unit_seen(A, hidden), battle.get_attack_targets(spear).has(hidden)]
	battle.move_leader(spear, Vector2i(2, 5))
	var near := battle.is_unit_seen(A, hidden)
	var scouted := _battle(rows, _env())
	var scout := _kit.add(scouted, A, _leader(LIEU_MI), Vector2i(0, 5))
	var other := _kit.add(scouted, B, _leader(THIET_NHA), Vector2i(3, 5))
	scouted.start()
	return Kit.expect("cell seen, unit hidden and not a target", far, [true, false, false]) \
		and Kit.expect("next to it", near, true) \
		and Kit.expect("scout sees it", [scouted.get_unit_state(scout)["is_scout"], scouted.is_unit_seen(A, other)], [true, true])


# A hidden archer that shoots shows itself for a while.
func _check_attacker_shows() -> bool:
	var battle := _battle(_rows({5: "...f........"}), _env())
	var spear := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(0, 5))
	var archer := _kit.add(battle, B, _leader(LIEU_MI, {"keywords": _kit.keywords([])}), Vector2i(3, 5))
	battle.start()
	var before := battle.is_unit_seen(A, archer)
	battle.wait(spear)
	battle.end_phase()
	battle.attack(archer, spear)
	return Kit.expect("hidden before", before, false) \
		and Kit.expect("seen after shooting", battle.is_unit_seen(A, archer), true)


# Walking next to a hidden enemy stops the walk on the last free cell
# before it, with an ambushed event; the move cannot be taken back.
func _check_ambush() -> bool:
	var battle := _battle(_rows({5: "....f......."}), _env())
	var spear := _kit.add(battle, A, _leader(MOON_SPEAR, {"keywords": _kit.keywords([])}), Vector2i(2, 5))
	var hidden := _kit.add(battle, B, _leader(THIET_NHA), Vector2i(4, 5))
	battle.start()
	var events := battle.move_leader(spear, Vector2i(5, 5))
	var ambushed := Kit.of_type(events, &"ambushed")
	return Kit.expect("one ambush", ambushed.size(), 1) \
		and Kit.expect("by the hidden enemy", [ambushed[0]["unit"], ambushed[0]["by"]], [spear, hidden]) \
		and Kit.expect("stopped short", Kit.cell_of(battle, spear), Vector2i(3, 5)) \
		and Kit.expect("now seen", battle.is_unit_seen(A, hidden), true) \
		and Kit.expect("no undo", battle.can_undo_move(spear), false)


# A move that shows an enemy cannot be taken back; one that shows none can.
func _check_undo_after_reveal() -> bool:
	var battle := _battle(_kit.plain_rows(), _env())
	var spear := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(0, 5))
	var enemy := _kit.add(battle, B, _leader(THIET_NHA), Vector2i(9, 5))
	battle.start()
	var hidden := battle.is_unit_seen(A, enemy)
	battle.move_leader(spear, Vector2i(4, 5))
	var quiet := _battle(_kit.plain_rows(), _env())
	var walker := _kit.add(quiet, A, _leader(MOON_SPEAR), Vector2i(0, 5))
	_kit.add(quiet, B, _leader(THIET_NHA), Vector2i(11, 11))
	quiet.start()
	quiet.move_leader(walker, Vector2i(1, 5))
	return Kit.expect("revealing move", [hidden, battle.is_unit_seen(A, enemy), battle.can_undo_move(spear)], [false, true, false]) \
		and Kit.expect("quiet move", quiet.can_undo_move(walker), true)


# A side played by hand hears what it newly sees and loses.
func _check_vision_event() -> bool:
	var battle := _battle(_kit.plain_rows(), _env())
	var spear := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(0, 5))
	var enemy := _kit.add(battle, B, _leader(THIET_NHA), Vector2i(9, 5))
	battle.start()
	var events := Kit.of_type(battle.move_leader(spear, Vector2i(4, 5)), &"vision_changed").filter(func(event: Dictionary) -> bool: return event["side"] == A)
	return Kit.expect("one vision change for A", events.size(), 1) \
		and Kit.expect("sees the enemy", events[0]["units"].has(enemy), true) \
		and Kit.expect_true("new cells", events[0]["cells"].has(Vector2i(9, 5))) \
		and Kit.expect_true("lost cells", events[0]["lost_cells"].has(Vector2i(0, 10)))


# A walk remembers what it passed in sight of; the events tell every fog
# cell that changed, so the screen can follow them alone.
func _check_walk_sight_told() -> bool:
	var battle := _battle(_kit.plain_rows(), _env())
	var spear := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(0, 5))
	_kit.add(battle, B, _leader(THIET_NHA), Vector2i(11, 11))
	battle.start()
	var fog := battle.get_fog_cells(A)
	var width := battle.get_map_width()
	var events := battle.move_leader(spear, Vector2i(4, 5))
	for event: Dictionary in Kit.of_type(events, &"vision_changed"):
		if event["side"] != A:
			continue
		for cell: Vector2i in event["cells"]:
			fog[cell.y * width + cell.x] = VISIBLE
		for cell: Vector2i in event["lost_cells"]:
			fog[cell.y * width + cell.x] = SEEN
	# (1, 0) is in sight from (1, 5) only, a cell the walk passed.
	return Kit.expect("passed in sight", _fog_at(battle, A, Vector2i(1, 0)), SEEN) \
		and Kit.expect_true("the events tell the fog", fog == battle.get_fog_cells(A))


# A zone of control the side cannot see does not show in a strike's
# forecast: the forecast is the walk as planned; the walk itself stops.
func _check_forecast_keeps_secret() -> bool:
	var battle := _battle(_rows({4: ".....f......"}), _env())
	var spear := _kit.add(battle, A, _leader(MOON_SPEAR, {"keywords": _kit.keywords([])}), Vector2i(2, 5))
	var target := _kit.add(battle, B, _leader(THIET_NHA), Vector2i(7, 5))
	var hidden := _kit.add(battle, B, _leader(LIEU_MI, {"keywords": _kit.keywords([])}), Vector2i(5, 4))
	battle.start()
	if not Kit.expect("the guard is hidden", battle.is_unit_seen(A, hidden), false):
		return false
	var cell := Vector2i(6, 5)
	var forecast := battle.forecast_move_attack(spear, cell, target)
	var events := battle.move_leader(spear, cell)
	return Kit.expect("forecast as planned", forecast.get("is_valid", false), true) \
		and Kit.expect("the walk is ambushed", Kit.of_type(events, &"ambushed").size(), 1) \
		and Kit.expect_true("short of the cell", Kit.cell_of(battle, spear) != cell)


# The AI does not plan around a unit it cannot see: with fog off it goes
# for the leader hidden in forest, with fog on it does not know it is there.
func _check_ai_blind() -> bool:
	var targets: Array = []
	for fog: bool in [false, true]:
		var battle := _battle(_rows({5: ".....f......"}), _env(fog), true)
		var hidden := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(5, 5))
		var guard := _kit.add(battle, B, _leader(THIET_NHA), Vector2i(5, 2))
		battle.start()
		var intents := battle.get_enemy_intents().filter(func(intent: Dictionary) -> bool: return intent["unit"] == guard)
		targets.append(hidden if intents.is_empty() else intents[0]["target"])
		targets.append(hidden)
	return Kit.expect("fog off: goes for it", targets[0], targets[1]) \
		and Kit.expect_true("fog on: does not", targets[2] != targets[3])


# An enemy that drops out of sight is remembered where it was seen; the
# memory goes once that cell is seen again without it.
func _check_last_seen() -> bool:
	var battle := _battle(_kit.plain_rows(), _env())
	var spear := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(0, 5))
	var enemy := _kit.add(battle, B, _leader(THIET_NHA), Vector2i(5, 5))
	battle.start()
	battle.move_leader(spear, Vector2i(0, 1))
	var ghosts := battle.get_last_seen(A)
	battle.wait(spear)
	battle.end_phase()
	battle.move_leader(enemy, Vector2i(9, 5))
	battle.wait(enemy)
	var kept := battle.get_last_seen(A)
	battle.end_phase()
	battle.move_leader(spear, Vector2i(1, 4))
	return Kit.expect("remembered", ghosts, [{"unit": enemy, "cell": Vector2i(5, 5)}]) \
		and Kit.expect("kept while unseen", kept, ghosts) \
		and Kit.expect("forgotten when seen empty", battle.get_last_seen(A), [])


# Rain: ranged reach -1 and fords cost one more to cross.
func _check_rain() -> bool:
	var reach: Array = []
	var crossing: Array = []
	for weather: StringName in [&"weather.clear", &"weather.rain"]:
		var battle := _battle(_rows({7: "dddddddddddd"}), _env(false, weather))
		var archer := _kit.add(battle, A, _leader(LIEU_MI, {"keywords": _kit.keywords([]), "max_range_cells": 3}), Vector2i(2, 8))
		var spear := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(5, 8))
		var target := _kit.add(battle, B, _leader(THIET_NHA), Vector2i(2, 11))
		battle.start()
		reach.append(battle.get_attack_targets(archer).has(target))
		crossing.append(battle.get_reachable_cells(spear).has(Vector2i(5, 6)))
	return Kit.expect("range 3 in clear, not in rain", reach, [true, false]) \
		and Kit.expect("ford crossing in clear, not in rain", crossing, [true, false])


# Wind from the west: shots east reach one further, shots west one less.
func _check_wind() -> bool:
	var result: Array = []
	for weather: StringName in [&"weather.clear", &"weather.wind"]:
		var battle := _battle(_kit.plain_rows(), _env(false, weather))
		var archer := _kit.add(battle, A, _leader(LIEU_MI, {"keywords": _kit.keywords([]), "max_range_cells": 3}), Vector2i(5, 5))
		var east := _kit.add(battle, B, _leader(THIET_NHA), Vector2i(9, 5))
		var west := _kit.add(battle, B, _leader(THIET_NHA), Vector2i(2, 5))
		battle.start()
		var targets := battle.get_attack_targets(archer)
		result.append([targets.has(east), targets.has(west)])
	return Kit.expect("east and west", result, [[false, true], [true, false]])


# Fog: vision -2 for everyone.
func _check_fog_weather() -> bool:
	var battle := _battle(_kit.plain_rows(), _env(true, &"weather.fog"))
	_kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(0, 5))
	_kit.add(battle, B, _leader(THIET_NHA), Vector2i(11, 11))
	battle.start()
	# A leader sees 5 cells; fog takes its vision_delta off (the data's).
	var sight: int = 5 + _kit.catalog.get_weather(&"weather.fog").vision_delta
	return Kit.expect_true("fog shortens sight", sight < 5) \
		and Kit.expect("sight %d" % sight, _visible(battle, [Vector2i(sight, 5), Vector2i(sight + 1, 5)]), [true, false])


# Rain halves what a fire zone burns.
func _check_burn_in_rain() -> bool:
	var hp: Array = []
	for weather: StringName in [&"weather.clear", &"weather.rain"]:
		var skill := _kit.catalog.get_leader(BA_KHAC).skill.duplicate() as TacticsSkillData
		skill.charge = &"charge.turns"
		skill.charge_threshold = 1
		var battle := _battle(_kit.plain_rows(), _env(false, weather))
		var caster := _kit.add(battle, A, _leader(BA_KHAC, {"skill": skill}), Vector2i(5, 9))
		var target := _kit.add(battle, B, _leader(THIET_NHA, {"hp_pct": 400}), Vector2i(5, 5))
		battle.start()
		battle.end_phase()
		battle.end_phase()
		battle.use_skill(caster, Vector2i(5, 5))
		var after_cast := Kit.hp_of(battle, target)
		battle.end_phase()
		battle.end_phase()
		battle.end_phase()
		hp.append(after_cast - Kit.hp_of(battle, target))
	return Kit.expect_true("fire burned in clear: %s" % [hp], hp[0] > 0) \
		and Kit.expect("half in rain", hp[1], hp[0] * 50 / 100)


# Night: vision shorter by the night's vision_delta, but lit cells (around
# villages and leaders) are seen as far as by day.
func _check_night_and_lights() -> bool:
	var night: Array[StringName] = [&"daytime.night"]
	var battle := _battle(_rows({5: "....v......."}), _env(true, &"weather.clear", night))
	_kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(0, 5))
	var lit_leader := _kit.add(battle, B, _leader(THIET_NHA), Vector2i(0, 9))
	battle.start()
	var lit := battle.get_lit_cells()
	var sight: int = 5 + _kit.catalog.get_daytime(&"daytime.night").vision_delta
	return Kit.expect_true("night shortens sight below the village", sight < 4) \
		and Kit.expect("night sight %d off the light" % sight, _visible(battle, [Vector2i(0, 5 - sight), Vector2i(0, 4 - sight)]), [true, false]) \
		and Kit.expect("lit village seen", _visible(battle, [Vector2i(3, 5), Vector2i(4, 5), Vector2i(7, 5)]), [true, true, false]) \
		and Kit.expect("village and leader lights", [lit[5 * 12 + 6], lit[9 * 12 + 0], lit[0]], [1, 1, 0]) \
		and Kit.expect("enemy leader seen by its own torch", battle.is_unit_seen(A, lit_leader), true)


# The time of day steps every daytime_step_rounds rounds from the start
# index and is announced when it changes.
func _check_daytime_cycle() -> bool:
	var cycle: Array[StringName] = [&"daytime.day", &"daytime.night"]
	var environment := _env(true, &"weather.clear", cycle)
	environment.daytime_step_rounds = 2
	var battle := _battle(_kit.plain_rows(), environment)
	_kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(0, 5))
	_kit.add(battle, B, _leader(THIET_NHA), Vector2i(11, 11))
	battle.start()
	var ids := [1, 2, 3, 4, 5].map(func(round_number: int) -> StringName: return battle.get_daytime_id(round_number))
	var changed: Array = []
	for phase: int in 4:
		changed.append_array(Kit.of_type(battle.end_phase(), &"daytime_changed"))
	environment.daytime_start_index = 1
	var night_first := _battle(_kit.plain_rows(), environment)
	return Kit.expect("cycle", ids, [&"daytime.day", &"daytime.day", &"daytime.night", &"daytime.night", &"daytime.day"]) \
		and Kit.expect("announced once by round 3", changed.map(func(event: Dictionary) -> Array: return [event["now"], event["before"]]), [[&"daytime.night", &"daytime.day"]]) \
		and Kit.expect("start index", night_first.get_daytime_id(1), &"daytime.night")


# The weather turns once, at weather_change_round, and says so.
func _check_weather_change() -> bool:
	var environment := _env(true, &"weather.fog")
	environment.weather_change_round = 3
	environment.weather_after = _kit.catalog.get_weather(&"weather.rain")
	var battle := _battle(_kit.plain_rows(), environment)
	_kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(0, 5))
	_kit.add(battle, B, _leader(THIET_NHA), Vector2i(11, 11))
	battle.start()
	var changed: Array = []
	for phase: int in 4:
		changed.append_array(Kit.of_type(battle.end_phase(), &"weather_changed"))
	return Kit.expect("rounds", [battle.get_weather_id(2), battle.get_weather_id(3), battle.get_weather_change_round()], [&"weather.fog", &"weather.rain", 3]) \
		and Kit.expect("announced", changed.map(func(event: Dictionary) -> StringName: return event["now"]), [&"weather.rain"])


# At night an enemy intent is read only within intent_read_cells (3), or a
# scout's reach (4); by day whenever the enemy is seen.
func _check_intents_at_night() -> bool:
	var known: Array = []
	for setup: Array in [[MOON_SPEAR, 5, &"daytime.night"], [MOON_SPEAR, 3, &"daytime.night"], [LIEU_MI, 4, &"daytime.night"], [MOON_SPEAR, 5, &"daytime.day"]]:
		var daytimes: Array[StringName] = [setup[2]]
		var battle := _battle(_kit.plain_rows(), _env(true, &"weather.clear", daytimes), true)
		_kit.add(battle, A, _leader(setup[0]), Vector2i(5, 1 + setup[1]))
		var guard := _kit.add(battle, B, _leader(THIET_NHA), Vector2i(5, 1))
		battle.start()
		known.append(battle.get_enemy_intents().any(func(intent: Dictionary) -> bool: return intent["unit"] == guard))
	return Kit.expect("far, near, scout, day", known, [false, true, true, true])


# Incident rules where a soldier out of sight always wavers to flee.
func _sure_flee_rules() -> TacticsIncidentRulesData:
	var rules := _kit.catalog.incident_rules.duplicate() as TacticsIncidentRulesData
	var incidents: Array[TacticsIncidentData] = []
	for incident: TacticsIncidentData in rules.incidents:
		var copy := incident.duplicate() as TacticsIncidentData
		if copy.id == &"incident.flee":
			copy.unseen_waver_pct = 100
		incidents.append(copy)
	rules.incidents = incidents
	return rules


# A leader with one spearman holding its ground at (2, 3); the leader
# walks off out of sight. Returns [battle, leader, soldier].
func _straggler(environment: TacticsScenarioData, rules: TacticsIncidentRulesData, seed_value: int, vision: int = 1) -> Array:
	var battle := _battle(_kit.plain_rows(), environment)
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR, {"vision_cells": vision}), Vector2i(2, 2), [_kit.troop(SPEARMAN)])
	_kit.add(battle, B, _leader(THIET_NHA), Vector2i(11, 11))
	var soldier: int = battle.get_unit_state(leader)["soldiers"][0]
	battle.set_incident_rules(rules, seed_value)
	battle.set_incident_seed(soldier, &"incident.flee")
	battle.start()
	battle.set_order(leader, &"order.hold")
	battle.move_leader(leader, Vector2i(6, 2))
	battle.wait(leader)
	battle.end_phase()
	return [battle, leader, soldier]


func _wavers(battle: TacticsBattle) -> Array:
	return Kit.of_type(battle.end_phase(), &"soldier_wavered")


# Out of its leader's sight the soldier wavers though no enemy is near; it
# still is at the end of the phase, so it flees.
func _check_unseen_waver() -> bool:
	var night: Array[StringName] = [&"daytime.night"]
	var parts := _straggler(_env(true, &"weather.clear", night), _sure_flee_rules(), 1)
	var battle: TacticsBattle = parts[0]
	var soldier: int = parts[2]
	var out_of_sight: bool = battle.get_unit_state(soldier)["is_out_of_leader_sight"]
	var wavered := _wavers(battle)
	var fired := Kit.of_type(battle.end_phase(), &"incident_fired")
	return Kit.expect("out of sight", out_of_sight, true) \
		and Kit.expect("wavers", wavered.map(func(event: Dictionary) -> int: return event["unit"]), [soldier]) \
		and Kit.expect("flees", fired.map(func(event: Dictionary) -> StringName: return event["incident"]), [&"incident.flee"])


# Coming back into sight calms it; nothing else does.
func _check_unseen_calm() -> bool:
	var night: Array[StringName] = [&"daytime.night"]
	var parts := _straggler(_env(true, &"weather.clear", night), _sure_flee_rules(), 1)
	var battle: TacticsBattle = parts[0]
	var leader: int = parts[1]
	var soldier: int = parts[2]
	_wavers(battle)
	var soldier_cell := Kit.cell_of(battle, soldier)
	var beside := Vector2i(-1, -1)
	for cell: Vector2i in battle.get_reachable_cells(leader):
		if (cell - soldier_cell).length_squared() == 1:
			beside = cell
	battle.move_leader(leader, beside)
	var calmed := Kit.of_type(battle.end_phase(), &"incident_calmed")
	return Kit.expect_true("a cell beside it", beside != Vector2i(-1, -1)) \
		and Kit.expect("calmed by its leader", calmed.map(func(event: Dictionary) -> Array: return [event["unit"], event["reason"]]), [[soldier, &"leader"]])


# The data odds (20 %) rise at night (+10) and in fog (+10); with fog of
# war off nobody wavers this way.
func _check_unseen_odds() -> bool:
	var counts: Array = []
	var cases: Array = [[false, &"weather.clear", &"daytime.day"], [true, &"weather.clear", &"daytime.day"], [true, &"weather.clear", &"daytime.night"], [true, &"weather.fog", &"daytime.night"]]
	for setup: Array in cases:
		var count := 0
		for seed_value: int in range(1, 121):
			var daytimes: Array[StringName] = [setup[2]]
			var battle: TacticsBattle = _straggler(_env(setup[0], setup[1], daytimes), _kit.catalog.incident_rules, seed_value)[0]
			count += _wavers(battle).size()
		counts.append(count)
	return Kit.expect("no fog: none", counts[0], 0) \
		and Kit.expect_true("day < night < night in fog: %s" % [counts], counts[1] > 0 and counts[1] < counts[2] and counts[2] < counts[3])


# Without an environment every cell and unit is visible and nothing is
# remembered.
func _check_no_environment() -> bool:
	var battle := _kit.new_battle(_rows({5: ".....f......"}))
	_kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(0, 0))
	var far := _kit.add(battle, B, _leader(THIET_NHA), Vector2i(5, 5))
	battle.start()
	var all_visible := Array(battle.get_fog_cells(A)).all(func(state: int) -> bool: return state == VISIBLE)
	return Kit.expect("all visible", [all_visible, battle.has_fog_of_war(), battle.is_unit_seen(A, far), battle.get_last_seen(A)], [true, false, true, []])


func _play_scenario(scenario: TacticsScenarioData) -> Array:
	var battle := TacticsBattle.new()
	_kit._battles.append(battle)
	battle.set_side_ai(A, true)
	battle.set_side_ai(B, true)
	battle.load_scenario(scenario)
	battle.set_incident_rules(_kit.catalog.incident_rules, 7)
	var events := battle.start()
	return [battle.get_state_hash(), events.size(), battle.is_finished()]


# The same battle under fog, night and a turning weather plays the same.
func _check_determinism() -> bool:
	var scenario := _kit.catalog.get_scenario(&"scenario.river_crossing").duplicate() as TacticsScenarioData
	scenario.fog_of_war = true
	scenario.weather = _kit.catalog.get_weather(&"weather.fog")
	scenario.weather_change_round = 4
	scenario.weather_after = _kit.catalog.get_weather(&"weather.rain")
	var cycle: Array[TacticsDaytimeData] = [_kit.catalog.get_daytime(&"daytime.night"), _kit.catalog.get_daytime(&"daytime.dusk")]
	scenario.daytimes = cycle
	var first := _play_scenario(scenario)
	var second := _play_scenario(scenario)
	return Kit.expect("finished", first[2], true) and Kit.expect("same hash and events", second, first)
