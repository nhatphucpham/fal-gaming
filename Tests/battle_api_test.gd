extends SceneTree

# Headless tests for the Battle node's API: signals and event ids, read-only
# events, commands refused during signals, a handler that frees the node, and
# rejected input. Rejections print errors on purpose; the test announces how
# many to expect. Rules of the battle itself are in battle_test.gd.

const CATALOG_PATH: String = "res://Data/catalog.tres"
const MAX_TICKS: int = 5000
const SHIELD: StringName = &"unit.shield_guard"
const SWORD: StringName = &"unit.blade_wanderer"
const ARCHER: StringName = &"unit.archer"
const HUGE: int = 1 << 40

var _catalog: Catalog
var _battles: Array[Battle] = []


func _initialize() -> void:
	var ok := _run()
	for battle: Battle in _battles:
		if is_instance_valid(battle):
			battle.free()
	if ok:
		print("Battle API test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	_catalog = load(CATALOG_PATH) as Catalog
	if _catalog == null or not ClassDB.class_exists("Battle"):
		push_error("Battle API test needs the GDExtension and %s" % CATALOG_PATH)
		return false
	var checks: Array[Callable] = [
		_check_signals, _check_read_only_events, _check_freed_in_handler,
		_check_refused_commands, _check_rejected_input,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Battle API test failed in %s" % check.get_method())
			return false
	return true


func _check_signals() -> bool:
	# step() returns the same events the signal emits; ids count up from 1.
	var battle := _new_battle()
	_add(battle, Battle.SIDE_A, SWORD, 4, 1)
	_add(battle, Battle.SIDE_B, ARCHER, 4, 4)
	var emitted: Array[Dictionary] = []
	var endings: Array = []
	battle.event_emitted.connect(func(event: Dictionary) -> void: emitted.append(event))
	battle.battle_ended.connect(func(winner: int, reason: StringName) -> void: endings.append([winner, reason]))
	var returned := _run_events(battle)
	if emitted != returned or returned.is_empty() or returned[0]["type"] != &"battle_started":
		push_error("Signals and step() results differ: %d vs %d events" % [emitted.size(), returned.size()])
		return false
	for index: int in returned.size():
		if returned[index]["id"] != index + 1:
			push_error("Event ids are not consecutive at %s" % returned[index])
			return false
	if endings != [[battle.get_winner(), returned.back()["reason"]]] or not battle.step().is_empty():
		push_error("battle_ended signal or post-end step() is wrong: %s" % [endings])
		return false
	return true


func _check_read_only_events() -> bool:
	var battle := _new_battle()
	_add(battle, Battle.SIDE_A, SWORD, 4, 1)
	_add(battle, Battle.SIDE_B, SWORD, 4, 1)
	var seen_read_only: Array[bool] = []
	battle.event_emitted.connect(func(event: Dictionary) -> void: seen_read_only.append(event.is_read_only()))
	battle.start()
	var events := battle.step()
	if events.is_empty() or not events.is_read_only() or not events[0].is_read_only() or seen_read_only != [true]:
		push_error("Events are not read-only: %s %s" % [events, seen_read_only])
		return false
	return true


func _check_freed_in_handler() -> bool:
	# The handler frees the battle's parent, and so the battle, mid-step.
	# Godot itself warns about freeing an object during its own signal.
	print("Battle API test: the next error (freed while emitting) is expected")
	var parent := Node.new()
	var battle := _new_battle()
	parent.add_child(battle)
	_add(battle, Battle.SIDE_A, SWORD, 4, 1)
	_add(battle, Battle.SIDE_B, SWORD, 4, 1)
	var calls: Array[int] = []
	battle.event_emitted.connect(func(_event: Dictionary) -> void:
		calls.append(1)
		if is_instance_valid(parent):
			parent.free())
	var hash := battle.run_to_end(MAX_TICKS)
	if is_instance_valid(battle) or hash != "" or calls.size() != 1:
		push_error("Freeing the battle in a handler was not handled: hash '%s', %d calls" % [hash, calls.size()])
		return false
	return true


func _check_refused_commands() -> bool:
	print("Battle API test: the next 2 errors are expected")
	# A class in use cannot be replaced: units keep what they copied from it.
	var battle := _new_battle()
	_add(battle, Battle.SIDE_A, SHIELD, 4, 1)
	_add(battle, Battle.SIDE_B, SWORD, 4, 1)
	var changed := _catalog.get_class_data(&"class.shield").duplicate() as ClassData
	changed.opening = &""
	if battle.register_class(changed):
		push_error("register_class replaced a class that a unit uses")
		return false
	# A handler that calls step() is refused and the tick does not move.
	var nested: Array = []
	battle.event_emitted.connect(func(_event: Dictionary) -> void:
		if nested.is_empty():
			nested.append([battle.step(), battle.get_tick()]))
	battle.start()
	var events := battle.step()
	if nested.size() != 1 or not nested[0][0].is_empty() or nested[0][1] != 1 or battle.get_tick() != 1 or events.is_empty():
		push_error("Re-entrant step() was not refused: %s" % [nested])
		return false
	return battle.run_to_end(MAX_TICKS) != "" and battle.is_finished()


func _check_rejected_input() -> bool:
	print("Battle API test: the next 8 errors are expected")
	var rules := _catalog.battle_rules.duplicate() as BattleRulesData
	rules.move_ticks_per_cell = HUGE
	var refused := Battle.new()
	_battles.append(refused)
	refused.set_rules(rules)
	if refused.get_rules() != null:
		push_error("set_rules accepted move_ticks_per_cell %d" % HUGE)
		return false
	var battle := _new_battle()
	var bad_kind := _catalog.get_class_data(&"class.sword").duplicate() as ClassData
	bad_kind.id = &"class.test_bad_kind"
	bad_kind.damage_kind = 7 as ClassData.DamageKind
	if battle.register_class(bad_kind):
		push_error("register_class accepted damage_kind 7")
		return false
	var sword := _catalog.get_unit(SWORD)
	if battle.add_unit(2, sword, 1, 4, 1) != -1 or battle.add_unit(Battle.SIDE_A, sword, HUGE + 1, 4, 1) != -1 or battle.add_unit(Battle.SIDE_A, sword, 1, HUGE + 4, 1) != -1:
		push_error("add_unit accepted a bad side, star or column")
		return false
	if not battle.get_unit_state(HUGE).is_empty():
		push_error("get_unit_state accepted index %d" % HUGE)
		return false
	if Battle.local_to_global(Battle.SIDE_A, 8, 1) != Vector2i(-1, -1) or Battle.global_to_local(3, 0, 0) != Vector2i(-1, -1):
		push_error("Coordinate helpers accepted a bad cell or side")
		return false
	return battle.get_unit_count() == 0


func _new_battle() -> Battle:
	var battle := Battle.new()
	_battles.append(battle)
	battle.set_rules(_catalog.battle_rules)
	for class_data: ClassData in _catalog.classes:
		battle.register_class(class_data)
	return battle


func _add(battle: Battle, side: int, unit_id: StringName, col: int, rank: int) -> int:
	var index := battle.add_unit(side, _catalog.get_unit(unit_id), 1, col, rank)
	assert(index >= 0, "Battle API test: could not add %s at col %d rank %d" % [unit_id, col, rank])
	return index


# Starts the battle and returns every event until it ends.
func _run_events(battle: Battle) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	battle.start()
	while not battle.is_finished() and battle.get_tick() < MAX_TICKS:
		for event: Dictionary in battle.step():
			events.append(event)
	return events
