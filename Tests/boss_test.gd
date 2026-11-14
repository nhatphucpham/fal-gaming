extends SceneTree

# Headless tests of the boss Cự Nham and its rule Hóa Đá: the passive fires
# exactly on the third player skill inside a 60-tick sliding window (a
# reference model of the window is compared with the battle; casts while it
# is already stone do not count), the boss is
# immune and idle while petrified, the battle stays deterministic, and the
# boss data holds (stage 12 has 7 units and one boss, the shop never offers
# it, a save never holds it, the view draws it 1.6x).

const Kit := preload("res://Tests/skill_test_kit.gd")
const BOSS: StringName = &"unit.boss_cu_nham"
const HOA_DA: StringName = &"passive.hoa_da"

var _kit := Kit.new()


func _initialize() -> void:
	var ok := _run()
	_kit.free_battles()
	if ok:
		print("Boss test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not ClassDB.class_exists("Battle"):
		push_error("Battle is missing: build the GDExtension (scons) before importing")
		return false
	if not _kit.load_catalog():
		return false
	var checks: Array[Callable] = [
		_check_window_burst, _check_window_slow, _check_petrified, _check_determinism,
		_check_stage_12, _check_shop_and_save, _check_view_scale,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Boss test failed in %s" % check.get_method())
			return false
	return true


# Four quick casters against the boss: every Hóa Đá lands on the tick of a
# player cast, exactly where the sliding-window model fires, and at least
# once.
func _check_window_burst() -> bool:
	var battle := _boss_battle(_kit.quick_rules(), [Kit.MAGE, Kit.ARCHER, &"unit.ice_mage", &"unit.wolf_archer"])
	var outcome := _compare_with_model(battle)
	if outcome.is_empty():
		return false
	if outcome["fired"] == 0:
		push_error("Quick casters should turn the boss to stone at least once")
		return false
	return true


# One caster with normal Khí: its casts are far apart, three never fit in
# the window, and the boss never turns to stone though it sees 3+ casts.
func _check_window_slow() -> bool:
	var battle := _boss_battle(_kit.catalog.battle_rules, [Kit.ARCHER, Kit.SHIELD, Kit.SHIELD])
	var outcome := _compare_with_model(battle)
	if outcome.is_empty():
		return false
	if outcome["casts"] < 3 or outcome["fired"] != 0:
		push_error("Spaced casts should not petrify: %d casts, %d fired" % [outcome["casts"], outcome["fired"]])
		return false
	return true


# From status_applied to status_ended of status.petrified the boss takes no
# damage (every hit is an immune 0), keeps its hp and does nothing.
func _check_petrified() -> bool:
	var battle := _boss_battle(_kit.quick_rules(), [Kit.MAGE, Kit.ARCHER, &"unit.ice_mage", &"unit.wolf_archer"])
	var boss := _boss_index(battle)
	var events := _kit.run_until(battle, func(event: Dictionary) -> bool:
		return event["type"] == &"status_applied" and event["unit"] == boss and event["status"] == &"status.petrified")
	if events.is_empty() or events.back()["type"] != &"status_applied":
		push_error("The boss was never petrified")
		return false
	var hp: int = battle.get_unit_state(boss)["hp"]
	var immune_hits := 0
	var ended := false
	while not battle.is_finished() and not ended:
		for event: Dictionary in battle.step():
			if event["type"] == &"status_ended" and event["unit"] == boss and event["status"] == &"status.petrified":
				ended = true
				break
			if event["type"] == &"damage_dealt" and event["target"] == boss:
				if event["amount"] != 0 or not event["is_immune"]:
					push_error("A petrified boss took %d damage" % event["amount"])
					return false
				immune_hits += 1
			if event.get("unit", -1) == boss and [&"unit_attacked", &"unit_moved", &"skill_cast_started"].has(event["type"]):
				push_error("A petrified boss acted: %s" % event["type"])
				return false
		if battle.get_unit_state(boss)["hp"] != hp and not ended:
			push_error("The boss's hp changed while petrified")
			return false
	if not ended or immune_hits == 0:
		push_error("Expected immune hits and the end of Hóa Đá (%d hits)" % immune_hits)
		return false
	return true


# The same boss battle twice ends with the same state hash and tick.
func _check_determinism() -> bool:
	var results: Array[String] = []
	for run: int in 2:
		var battle := _boss_battle(_kit.quick_rules(), [Kit.MAGE, Kit.ARCHER, &"unit.ice_mage", Kit.SWORD])
		battle.run_to_end(Kit.MAX_TICKS)
		results.append("%s@%d" % [battle.get_state_hash(), battle.get_tick()])
	if results[0] != results[1]:
		push_error("The boss battle is not deterministic: %s" % [results])
		return false
	return true


# Stage 12: 7 units, exactly one boss (Cự Nham, boss flag, Hóa Đá); a
# stage 12 without its boss is refused.
func _check_stage_12() -> bool:
	var catalog := _kit.catalog
	var stage: StageData = catalog.stages[catalog.run_rules.boss_stage - 1]
	var boss := catalog.get_unit(BOSS)
	if stage.slots.size() != 7 or stage.get_boss_slot(catalog) == null or stage.get_boss_slot(catalog).unit_id != BOSS:
		push_error("Stage 12 should have 7 units with Cự Nham")
		return false
	if boss == null or not boss.is_boss or boss.passive_override == null or boss.passive_override.id != HOA_DA:
		push_error("Cự Nham needs the boss flag and Hóa Đá")
		return false
	if stage.validate(catalog, 7, 0).is_empty() or not stage.validate(catalog, 7, 1).is_empty():
		push_error("Stage validation should count the boss")
		return false
	var other: StageData = catalog.stages[0]
	if other.get_boss_slot(catalog) != null:
		push_error("Only stage 12 has a boss")
		return false
	return true


# The shop never offers the boss; a save with a boss piece is refused.
func _check_shop_and_save() -> bool:
	var catalog := _kit.catalog
	for seed_value: int in 200:
		var run := RunState.new(catalog, seed_value)
		run.start()
		if run.get_shop_offers().has(BOSS):
			push_error("The shop offered the boss")
			return false
	var start := RunState.new(catalog, 3)
	start.start()
	var data := start.to_save_data()
	data["pieces"] = [{"id": 1, "unit_id": String(BOSS), "star": 1, "bench": 0, "col": 0, "rank": 0, "has_fought": false}]
	data["next_piece_id"] = 2
	if RunState.new(catalog, 0).load_save_data(data):
		push_error("A save holding the boss should not load")
		return false
	return true


# The boss's view draws the figure 1.6x a normal unit's.
func _check_view_scale() -> bool:
	var normal := UnitView.new()
	normal.setup(_kit.catalog.get_unit(Kit.SHIELD), Battle.SIDE_B, 1)
	var boss := UnitView.new()
	boss.setup(_kit.catalog.get_unit(BOSS), Battle.SIDE_B, 1)
	root.add_child(normal)
	root.add_child(boss)
	normal._process(0.0)
	boss._process(0.0)
	var ratio: float = boss.get_child(0).scale.y / normal.get_child(0).scale.y
	normal.free()
	boss.free()
	if absf(ratio - UnitView.BOSS_SCALE) > 0.1:
		push_error("The boss should be drawn %.1fx, got %.2f" % [UnitView.BOSS_SCALE, ratio])
		return false
	return true


# The boss at its stage-12 cell with two guards, against `casters` on rank 1.
func _boss_battle(rules: BattleRulesData, casters: Array) -> Battle:
	var battle := _kit.new_battle(rules)
	battle.set_synergy(_kit.catalog.get_synergy())
	_kit.add(battle, Battle.SIDE_B, BOSS, 4, 2)
	_kit.add(battle, Battle.SIDE_B, &"unit.iron_guard", 3, 1)
	_kit.add(battle, Battle.SIDE_B, &"unit.wolf_shield", 5, 1)
	for index: int in casters.size():
		_kit.add(battle, Battle.SIDE_A, casters[index], 2 + index, 1)
	return battle


func _boss_index(battle: Battle) -> int:
	for state: Dictionary in battle.get_units():
		if state["unit_id"] == BOSS:
			return state["index"]
	return -1


# Runs `battle` to its end while the boss lives, feeding each player cast
# (skill_resolved, not an after-skill) to a sliding-window model of Hóa Đá;
# the model must fire on exactly the ticks the boss's passive fires.
# {"casts", "fired"}, or {} after an error.
func _compare_with_model(battle: Battle) -> Dictionary:
	var rules := _kit.catalog.get_passive(HOA_DA)
	var boss := _boss_index(battle)
	var window: Array[int] = []
	var model_ticks: Array[int] = []
	var actual_ticks: Array[int] = []
	var casts := 0
	var is_stone := false
	battle.start()
	while not battle.is_finished() and battle.get_tick() < Kit.MAX_TICKS and battle.get_unit_state(boss)["alive"]:
		for event: Dictionary in battle.step():
			var tick: int = event["tick"]
			if event.get("status", &"") == &"status.petrified" and event["unit"] == boss:
				is_stone = event["type"] == &"status_applied"
			# Casts while the boss is stone do not count.
			if event["type"] == &"skill_resolved" and not event["is_after_skill"] and not is_stone and battle.get_unit_state(event["unit"])["side"] == Battle.SIDE_A:
				casts += 1
				window = window.filter(func(hit: int) -> bool: return tick - hit < rules.window_ticks)
				window.append(tick)
				if window.size() >= rules.every_nth:
					model_ticks.append(tick)
					window.clear()
			elif event["type"] == &"passive_triggered" and event["unit"] == boss and event["passive"] == HOA_DA:
				actual_ticks.append(tick)
	if model_ticks != actual_ticks:
		push_error("Hóa Đá fired on ticks %s, the window model on %s" % [actual_ticks, model_ticks])
		return {}
	return {"casts": casts, "fired": actual_ticks.size()}
