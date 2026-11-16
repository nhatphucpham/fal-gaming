extends SceneTree

# Headless tests for the soldiers' judgement (Docs/systems/tactics.md,
# Soldiers): a small scripted map per behaviour (step out and strike, then
# back to formation; ranged in the rear; focus fire for a kill; no strike
# into a deadly counter, except under vanguard; falling back hurt; shielding
# a hurt leader; a free soldier holding outside a wall of enemies), the
# leader's strike cell and move-and-attack forecast, taking a move back,
# and the same hashes for the same commands. Side B is played by hand
# unless a check says otherwise. Cells are (col, row). Last, river
# crossings with every formation order on both sides: no archer or kite
# scout ever steps next to a living enemy (it cannot shoot it there).
# The guard AI (the side defending the objective): outnumbered, it holds
# near its post and lets a stack of leaders be, strikes a leader that comes
# alone, then does what it declared; a guard cell off the map is refused.

const Kit := preload("res://Tests/tactics_test_kit.gd")
const MOON_SPEAR: StringName = &"leader.moon_spear"
const LIEU_MI: StringName = &"leader.lieu_mi"
const THIET_NHA: StringName = &"leader.thiet_nha"
const SPEARMAN: StringName = &"troop.spearman"
const ARCHER: StringName = &"troop.archer"
const SHIELDMAN: StringName = &"troop.shieldman"
const A: int = TacticsBattle.SIDE_A
const B: int = TacticsBattle.SIDE_B
const FAR: Vector2i = Vector2i(11, 0)

var _kit := Kit.new()


func _initialize() -> void:
	var ok := _run()
	_kit.free_battles()
	if ok:
		print("Tactics brain test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not _kit.load_catalog():
		return false
	var checks: Array[Callable] = [
		_check_steps_out_and_returns, _check_leash, _check_ranged_rear, _check_focus_kill, _check_no_deadly_strike,
		_check_vanguard_risks, _check_falls_back, _check_shields_leader, _check_free_wall, _check_strike_cell,
		_check_undo, _check_undo_refused, _check_determinism, _check_ranged_keep_clear,
		_check_guard_holds, _check_guard_strikes_lone, _check_guard_cell_off_map,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Tactics brain test failed in %s" % check.get_method())
			return false
	return true


func _leader(id: StringName, changes: Dictionary = {}) -> TacticsLeaderData:
	var all := {"keywords": _kit.keywords([])}
	all.merge(changes, true)
	return _kit.leader(id, [], all)


func _troops(ids: Array[StringName]) -> Array:
	var squad: Array = []
	for id: StringName in ids:
		squad.append(_kit.troop(id))
	return squad


func _engagements(events: Array) -> Array:
	return Kit.of_type(events, &"engagement_started").map(func(event: Dictionary) -> Array: return [event["unit"], event["target"]])


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# Units not on `side` that could attack `cell` next phase: a reachable cell
# (or their own) with the cell in range.
static func _attackers_of(battle: TacticsBattle, cell: Vector2i, side: int) -> int:
	var count := 0
	for unit: Dictionary in battle.get_units():
		if not unit["alive"] or unit["side"] == side:
			continue
		var cells: Array = battle.get_reachable_cells(unit["index"]).duplicate()
		cells.append(unit["cell"])
		for from: Vector2i in cells:
			var distance := _distance(from, cell)
			if distance >= int(unit["min_range"]) and distance <= int(unit["max_range"]):
				count += 1
				break
	return count


# A weak enemy two cells from the leader: the follow soldier leaves its slot
# to kill it, and the next step brings it back to the slot. The preview of
# the next move matches the real step.
func _check_steps_out_and_returns() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(5, 8), _troops([SPEARMAN]))
	var soldier := leader + 1
	var weak := _kit.add(battle, B, _leader(THIET_NHA, {"hp_pct": 4, "attack_pct": 0}), Vector2i(3, 9))
	_kit.add(battle, B, _leader(THIET_NHA), FAR)
	battle.start()
	battle.set_order(leader, &"order.follow")
	if not Kit.expect("slot", Kit.cell_of(battle, soldier), Vector2i(5, 9)):
		return false
	var events := battle.wait(leader)
	var cell := Kit.cell_of(battle, soldier)
	if not (Kit.expect("struck the weak enemy", _engagements(events), [[soldier, weak]]) and Kit.expect_true("next to it", _distance(cell, Vector2i(3, 9)) == 1) \
			and Kit.expect_true("within the follow leash", _distance(cell, Vector2i(5, 8)) <= _kit.catalog.rules.leash_follow_cells) \
			and Kit.expect("killed it", battle.get_unit_state(weak)["alive"], false)):
		return false
	battle.end_phase()
	battle.end_phase()
	var preview: Array = battle.preview_squad(leader, Vector2i(5, 7))
	battle.move_leader(leader, Vector2i(5, 7))
	return Kit.expect("back to the slot", Kit.cell_of(battle, soldier), Vector2i(5, 8)) \
		and Kit.expect("preview", preview, [{"unit": soldier, "cell": Vector2i(5, 8)}])


# Follow keeps a soldier within two cells of its leader: a weak enemy four
# cells off is left alone; under vanguard (leash 4) the soldier goes for it.
func _check_leash() -> bool:
	var cells: Array = []
	for order: StringName in [&"order.follow", &"order.vanguard"]:
		var battle := _kit.new_battle(_kit.plain_rows())
		var leader := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(5, 8), _troops([SPEARMAN]))
		var weak := _kit.add(battle, B, _leader(THIET_NHA, {"hp_pct": 4, "attack_pct": 0}), Vector2i(2, 9))
		_kit.add(battle, B, _leader(THIET_NHA), FAR)
		battle.start()
		battle.set_order(leader, order)
		var events := battle.wait(leader)
		cells.append([Kit.cell_of(battle, leader + 1), _engagements(events).size(), battle.get_unit_state(weak)["alive"]])
	return Kit.expect("follow stays, vanguard strikes", cells, [[Vector2i(5, 9), 0, true], [Vector2i(3, 9), 1, false]])


# Squad order puts the shieldman first and an archer second; slots by role
# put both archers on the rear slots, never ahead of a melee soldier.
func _check_ranged_rear() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR, {"lead_capacity": 4}), Vector2i(5, 10), _troops([SHIELDMAN, ARCHER, SPEARMAN, ARCHER]))
	_kit.add(battle, B, _leader(THIET_NHA), FAR)
	battle.start()
	battle.set_order(leader, &"order.follow")
	var preview: Array = battle.preview_squad(leader, Vector2i(5, 8))
	battle.move_leader(leader, Vector2i(5, 8))
	var actual: Array = []
	var deepest_ranged := -99
	var rearmost_melee := 99
	for soldier: int in battle.get_unit_state(leader)["soldiers"]:
		var cell := Kit.cell_of(battle, soldier)
		actual.append({"unit": soldier, "cell": cell})
		var depth := 8 - cell.y
		if battle.get_unit_state(soldier)["is_ranged"]:
			deepest_ranged = maxi(deepest_ranged, depth)
		else:
			rearmost_melee = mini(rearmost_melee, depth)
	# The shieldman (3 moves) cannot reach its front slot this step, so it
	# may stand level with the archers, never behind them.
	return Kit.expect_true("archers on the rear slots, behind or level with the melee (%d <= %d)" % [deepest_ranged, rearmost_melee], deepest_ranged == -1 and deepest_ranged <= rearmost_melee) \
		and Kit.expect("preview", preview, actual)


# Two held archers can reach an enemy beside their leader (too tough to
# kill) and a weak one that neither kills alone but both together do: they
# both shoot the weak one and it falls (the old rule shot the threat).
func _check_focus_kill() -> bool:
	var probe := _focus_battle(100)
	var per_shot: int = probe[1]
	var full_hp: int = probe[2]
	var hp_pct := int(ceil(150.0 * per_shot / full_hp))
	var parts := _focus_battle(hp_pct)
	var battle: TacticsBattle = parts[0]
	var leader: int = parts[3]
	var weak: int = parts[4]
	var hp: int = battle.get_unit_state(weak)["hp"]
	if not Kit.expect_true("one shot (%d) leaves it, two (%d) kill it (%d hp)" % [per_shot, per_shot * 2, hp], per_shot < hp and per_shot * 2 >= hp):
		return false
	var events := battle.wait(leader)
	return Kit.expect("both shoot the weak one", _engagements(events), [[leader + 1, weak], [leader + 2, weak]]) \
		and Kit.expect("it fell", battle.get_unit_state(weak)["alive"], false)


# [battle, archer damage per engagement on the weak enemy, its max hp at
# hp_pct 100 or as made, leader, weak].
func _focus_battle(hp_pct: int) -> Array:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR, {"attack_pct": 0}), Vector2i(5, 8), _troops([ARCHER, ARCHER]))
	_kit.add(battle, B, _leader(THIET_NHA), Vector2i(6, 8))
	var weak := _kit.add(battle, B, _leader(THIET_NHA, {"hp_pct": hp_pct}), Vector2i(3, 10))
	battle.start()
	battle.set_order(leader, &"order.hold")
	var forecast := battle.forecast_engagement(leader + 1, weak)
	var per_shot: int = forecast["attacker_damage_per_hit"] * forecast["attacker_hits"]
	return [battle, per_shot, battle.get_unit_state(weak)["max_hp"], leader, weak]


# A held spearman beside an enemy whose counter would kill it does not strike.
func _check_no_deadly_strike() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(5, 8), _troops([SPEARMAN]))
	var brute := _kit.add(battle, B, _leader(THIET_NHA, {"attack_pct": 3000}), Vector2i(5, 10))
	battle.start()
	battle.set_order(leader, &"order.hold")
	var forecast := battle.forecast_engagement(leader + 1, brute)
	if not Kit.expect_true("the counter would kill it", forecast["is_attacker_dead"] and not forecast["is_defender_dead"]):
		return false
	return Kit.expect("no strike", _engagements(battle.wait(leader)), []) and Kit.expect("alive", battle.get_unit_state(leader + 1)["alive"], true)


# Vanguard accepts the trade: the soldier on its slot beside the brute strikes.
func _check_vanguard_risks() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(5, 8), _troops([SPEARMAN]))
	var brute := _kit.add(battle, B, _leader(THIET_NHA, {"attack_pct": 3000}), Vector2i(5, 6))
	_kit.add(battle, B, _leader(THIET_NHA), FAR)
	battle.start()
	battle.set_order(leader, &"order.vanguard")
	return Kit.expect("strikes anyway", _engagements(battle.wait(leader)), [[leader + 1, brute]])


# A spearman worn under 35% next to an enemy falls back, as far from it as
# the follow leash allows, and fewer enemies can reach it there.
func _check_falls_back() -> bool:
	var rules := _kit.catalog.rules.duplicate() as TacticsRulesData
	rules.hits_per_engagement = 1
	var battle := _kit.new_battle(_kit.plain_rows(), false, rules)
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR, {"attack_pct": 0}), Vector2i(5, 8), [_kit.troop(SPEARMAN, {"attack_pct": 0})])
	var soldier := leader + 1
	var enemy := _kit.add(battle, B, _leader(THIET_NHA, {"attack_pct": 15, "hp_pct": 300}), Vector2i(5, 10))
	battle.start()
	battle.set_order(leader, &"order.hold")
	for round_index: int in 30:
		var state := battle.get_unit_state(soldier)
		if int(state["hp"]) * 100 <= int(state["max_hp"]) * rules.retreat_hp_pct:
			break
		battle.end_phase()
		battle.attack(enemy, soldier)
		battle.end_phase()
	var state := battle.get_unit_state(soldier)
	if not Kit.expect_true("hurt and alive (%d / %d)" % [state["hp"], state["max_hp"]], state["alive"] and int(state["hp"]) * 100 <= int(state["max_hp"]) * rules.retreat_hp_pct):
		return false
	var before := Kit.cell_of(battle, soldier)
	var reach_before := _attackers_of(battle, before, A)
	battle.set_order(leader, &"order.follow")
	battle.wait(leader)
	var after := Kit.cell_of(battle, soldier)
	return Kit.expect_true("moved away (%s -> %s)" % [before, after], _distance(after, Vector2i(5, 10)) > _distance(before, Vector2i(5, 10))) \
		and Kit.expect_true("within the leash", _distance(after, Vector2i(5, 8)) <= rules.leash_follow_cells) \
		and Kit.expect_true("no more enemies reach it", _attackers_of(battle, after, A) <= reach_before)


# The leader is worn under half by an archer three cells north: the
# shieldman (not the archer) steps onto the cell between them.
func _check_shields_leader() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR, {"attack_pct": 0}), Vector2i(5, 8), _troops([ARCHER, SHIELDMAN]))
	var shooter := _kit.add(battle, B, _leader(LIEU_MI, {"attack_pct": 60}), Vector2i(5, 5))
	battle.start()
	battle.set_order(leader, &"order.hold")
	for round_index: int in 30:
		var state := battle.get_unit_state(leader)
		if int(state["hp"]) * 100 <= int(state["max_hp"]) * _kit.catalog.rules.shield_leader_hp_pct:
			break
		battle.end_phase()
		battle.attack(shooter, leader)
		battle.end_phase()
	var state := battle.get_unit_state(leader)
	if not Kit.expect_true("leader worn (%d / %d)" % [state["hp"], state["max_hp"]], state["alive"] and int(state["hp"]) * 100 <= int(state["max_hp"]) * _kit.catalog.rules.shield_leader_hp_pct):
		return false
	battle.set_order(leader, &"order.follow")
	battle.wait(leader)
	return Kit.expect("shieldman between", Kit.cell_of(battle, leader + 2), Vector2i(5, 7)) \
		and Kit.expect_true("archer elsewhere", Kit.cell_of(battle, leader + 1) != Vector2i(5, 7))


# A free spearman with no fight it can win (three leaders whose counter
# kills it) closes in but stops where fewer than two of them can reach it.
func _check_free_wall() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(1, 11), _troops([SPEARMAN]))
	var soldier := leader + 1
	for col: int in [5, 6, 7]:
		_kit.add(battle, B, _leader(THIET_NHA, {"attack_pct": 3000, "move_points": 2}), Vector2i(col, 3))
	battle.start()
	battle.set_order(leader, &"order.free")
	var before := Kit.cell_of(battle, soldier)
	battle.wait(leader)
	var after := Kit.cell_of(battle, soldier)
	return Kit.expect_true("closed in (%s -> %s)" % [before, after], _distance(after, Vector2i(6, 3)) < _distance(before, Vector2i(6, 3))) \
		and Kit.expect_true("outside the wall (%d can reach %s)" % [_attackers_of(battle, after, A), after], _attackers_of(battle, after, A) < _kit.catalog.rules.free_threat_limit)


# The leader's strike cell is reachable and in range; the forecast after the
# move matches the real move then attack, soldiers' strikes included.
func _check_strike_cell() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(5, 9), _troops([SPEARMAN, ARCHER]))
	var enemy := _kit.add(battle, B, _leader(THIET_NHA, {"hp_pct": 300}), Vector2i(5, 5))
	battle.start()
	if not Kit.expect_true("a strike target", battle.get_strike_targets(leader).has(enemy)):
		return false
	var cell := battle.get_strike_cell(leader, enemy)
	var reach := battle.get_unit_state(leader)
	var distance := _distance(cell, Vector2i(5, 5))
	if not (Kit.expect_true("reachable", battle.get_reachable_cells(leader).has(cell)) \
			and Kit.expect_true("in range", distance >= int(reach["min_range"]) and distance <= int(reach["max_range"]))):
		return false
	var hash_before := battle.get_state_hash()
	var forecast := battle.forecast_move_attack(leader, cell, enemy)
	if not (Kit.expect("forecast changes nothing", battle.get_state_hash(), hash_before) and Kit.expect("valid", forecast["is_valid"], true)):
		return false
	battle.move_leader(leader, cell)
	var squad: Array = []
	for soldier: int in battle.get_unit_state(leader)["soldiers"]:
		squad.append({"unit": soldier, "cell": Kit.cell_of(battle, soldier)})
	battle.attack(leader, enemy)
	return Kit.expect("squad cells", forecast["squad"], squad) \
		and Kit.expect("hp after", [Kit.hp_of(battle, leader), Kit.hp_of(battle, enemy)], [forecast["attacker_hp_after"], forecast["defender_hp_after"]])


const BA_KHAC: StringName = &"leader.ba_khac"
const LAC_HONG: StringName = &"leader.lac_hong"
const GUARD_POST: Vector2i = Vector2i(5, 2)
const OBJECTIVE: Vector2i = Vector2i(5, 0)


# Side B guards the objective (side A's) from GUARD_POST, played by the AI;
# side A has a leader on each of `our_cells`. Returns [battle, guard].
func _guard_battle(our_cells: Array[Vector2i]) -> Array:
	var battle := TacticsBattle.new()
	_kit._battles.append(battle)
	battle.set_side_ai(B, true)
	var map := _kit.make_map(_kit.plain_rows(12), OBJECTIVE)
	map.objective_side = A
	map.guard_cells = [GUARD_POST]
	if not battle.setup(_kit.catalog.rules, map):
		return []
	var ids: Array[StringName] = [LAC_HONG, MOON_SPEAR, LIEU_MI]
	for index: int in our_cells.size():
		_kit.add(battle, A, _leader(ids[index % ids.size()]), our_cells[index])
	var guard := _kit.add(battle, B, _leader(BA_KHAC), Vector2i(5, 4))
	return [battle, guard]


# The intent of `guard` declared at the start of our phase.
func _intent_of(battle: TacticsBattle, guard: int) -> Dictionary:
	for intent: Dictionary in battle.get_enemy_intents():
		if intent["unit"] == guard:
			return intent
	return {}


# After our phase, the guard stands where it said and did what it said.
func _keeps_intent(battle: TacticsBattle, guard: int, intent: Dictionary) -> bool:
	var events := battle.end_phase()
	var attacked := Kit.of_type(events, &"engagement_started").filter(func(event: Dictionary) -> bool: return event["unit"] == guard)
	return Kit.expect("guard ends where it declared", Kit.cell_of(battle, guard), intent["to"]) and \
			Kit.expect("guard attacks as it declared", attacked.size() > 0, intent["action"] == &"attack")


# A stack of three leaders a walk away: the guard holds within one cell of
# its post and declares a wait, though it could reach one of them.
func _check_guard_holds() -> bool:
	var setup := _guard_battle([Vector2i(4, 8), Vector2i(5, 8), Vector2i(6, 8)])
	if setup.is_empty():
		return Kit.expect_true("guard map loads", false)
	var battle: TacticsBattle = setup[0]
	var guard: int = setup[1]
	battle.start()
	var intent := _intent_of(battle, guard)
	var to: Vector2i = intent.get("to", Vector2i(-1, -1))
	if not Kit.expect("guard waits", intent.get("action"), &"wait") or \
			not Kit.expect_true("guard holds by its post (%s)" % to, absi(to.x - GUARD_POST.x) + absi(to.y - GUARD_POST.y) <= _kit.catalog.rules.ai_hold_radius_cells):
		return false
	return _keeps_intent(battle, guard, intent)


# One leader alone within reach, the others far: the guard goes for it.
func _check_guard_strikes_lone() -> bool:
	var setup := _guard_battle([Vector2i(5, 8), Vector2i(0, 11), Vector2i(11, 11)])
	var battle: TacticsBattle = setup[0]
	var guard: int = setup[1]
	battle.start()
	var intent := _intent_of(battle, guard)
	if not Kit.expect("guard strikes the lone leader", [intent.get("action"), intent.get("target")], [&"attack", 0]):
		return false
	return _keeps_intent(battle, guard, intent)


func _check_guard_cell_off_map() -> bool:
	var battle := TacticsBattle.new()
	_kit._battles.append(battle)
	var map := _kit.make_map(_kit.plain_rows(12), OBJECTIVE)
	map.guard_cells = [Vector2i(40, 2)]
	Engine.print_error_messages = false
	var ok := battle.setup(_kit.catalog.rules, map)
	Engine.print_error_messages = true
	return Kit.expect("a guard cell off the map is refused", ok, false)


# A plain move is taken back to the exact state hash, cells and charge.
func _check_undo() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _kit.leader(&"leader.lac_hong"), Vector2i(5, 9), _troops([SPEARMAN, ARCHER]))
	_kit.add(battle, B, _leader(THIET_NHA), FAR)
	battle.start()
	var hash_before := battle.get_state_hash()
	var cells_before := battle.get_units().map(func(unit: Dictionary) -> Vector2i: return unit["cell"])
	if not Kit.expect("nothing to undo yet", battle.can_undo_move(leader), false):
		return false
	battle.move_leader(leader, Vector2i(5, 6))
	if not Kit.expect("undo offered", battle.can_undo_move(leader), true):
		return false
	var undone := battle.undo_move(leader)
	return Kit.expect("undone", undone, true) and Kit.expect("same hash", battle.get_state_hash(), hash_before) \
		and Kit.expect("same cells", battle.get_units().map(func(unit: Dictionary) -> Vector2i: return unit["cell"]), cells_before) \
		and Kit.expect("can move again", battle.can_move(leader), true) and Kit.expect("once only", battle.can_undo_move(leader), false)


# A move whose squad strikes, or an attack after a move, cannot be taken back.
func _check_undo_refused() -> bool:
	var battle := _kit.new_battle(_kit.plain_rows())
	var leader := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(5, 9), _troops([SPEARMAN]))
	_kit.add(battle, B, _leader(THIET_NHA, {"hp_pct": 4, "attack_pct": 0}), Vector2i(3, 7))
	var other := _kit.add(battle, A, _leader(MOON_SPEAR), Vector2i(9, 9), [])
	var target := _kit.add(battle, B, _leader(THIET_NHA, {"attack_pct": 0}), Vector2i(9, 6))
	battle.start()
	var events := battle.move_leader(leader, Vector2i(4, 8))
	if not (Kit.expect_true("the squad struck", not _engagements(events).is_empty()) and Kit.expect("no undo", battle.can_undo_move(leader), false)):
		return false
	battle.move_leader(other, Vector2i(9, 7))
	if not Kit.expect("undo after a plain move", battle.can_undo_move(other), true):
		return false
	battle.attack(other, target)
	Engine.print_error_messages = false
	var undone := battle.undo_move(other)
	Engine.print_error_messages = true
	return Kit.expect("no undo after the attack", [battle.can_undo_move(other), undone], [false, false])


# Two battles with the brains at work and the same commands give the same
# hashes after every command.
func _check_determinism() -> bool:
	var hashes: Array = []
	for run: int in 2:
		var battle := _kit.new_battle(_kit.plain_rows(), true)
		var ours := _kit.add(battle, A, _kit.leader(MOON_SPEAR), Vector2i(4, 10), _troops([SPEARMAN, ARCHER, SHIELDMAN]))
		_kit.add(battle, A, _kit.leader(&"leader.lac_hong"), Vector2i(7, 10), _troops([ARCHER, SPEARMAN]))
		_kit.add(battle, B, _kit.leader(THIET_NHA), Vector2i(5, 2))
		_kit.add(battle, B, _kit.leader(LIEU_MI), Vector2i(8, 1))
		battle.start()
		battle.set_order(ours, &"order.vanguard")
		var trail: Array = []
		for round_index: int in 8:
			if battle.is_finished():
				break
			for unit: Dictionary in battle.get_units():
				if unit["role"] == &"leader" and unit["side"] == A and battle.can_move(unit["index"]):
					var reachable: Array = battle.get_reachable_cells(unit["index"])
					if not reachable.is_empty():
						battle.move_leader(unit["index"], reachable[reachable.size() / 2])
					trail.append(battle.get_state_hash())
			if not battle.is_finished():
				battle.end_phase()
				trail.append(battle.get_state_hash())
		hashes.append(trail)
	return Kit.expect("same hashes", hashes[0], hashes[1])


# The river crossing, side A marching on the nearest enemy leader and
# striking when it can, side B the AI, both under each formation order
# (and the AI's own): a ranged soldier that stood clear of the enemy never
# ends its step next to a living enemy.
func _check_ranged_keep_clear() -> bool:
	var scenario := load("res://Data/Tactics/Scenarios/river_crossing.tres") as TacticsScenarioData
	var troops: Array = _kit.catalog.troops
	for order: StringName in [&"order.follow", &"order.vanguard", &"order.flank"]:
		for seed_value: int in range(1, 6):
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var battle := TacticsBattle.new()
			battle.set_side_ai(B, true)
			var squads: Array = []
			for leader: TacticsLeaderData in scenario.leaders_a:
				var squad: Array[TacticsTroopData] = []
				for slot: int in leader.lead_capacity:
					squad.append(troops[rng.randi_range(0, troops.size() - 1)])
				squads.append(squad)
			if not battle.load_scenario_with_squads(scenario, A, squads):
				battle.free()
				return Kit.expect_true("the river crossing loads", false)
			battle.start()
			for unit: Dictionary in battle.get_units():
				if unit["role"] == &"leader" and unit["side"] == A:
					battle.set_order(unit["index"], order)
			for command: int in 200:
				if battle.is_finished():
					break
				var before := battle.get_units()
				var leader := _next_leader(battle)
				if leader >= 0:
					_march_and_strike(battle, leader)
				else:
					battle.end_phase()
				var where := "%s seed %d round %d" % [order, seed_value, battle.get_round()]
				if not _ranged_kept_clear(before, battle.get_units(), where):
					battle.free()
					return false
			battle.free()
	return true


func _next_leader(battle: TacticsBattle) -> int:
	for unit: Dictionary in battle.get_units():
		if unit["role"] == &"leader" and unit["side"] == A and battle.can_act(unit["index"]):
			return unit["index"]
	return -1


func _march_and_strike(battle: TacticsBattle, leader: int) -> void:
	var targets := battle.get_strike_targets(leader)
	if not targets.is_empty():
		var cell := battle.get_strike_cell(leader, targets[0])
		if cell != Kit.cell_of(battle, leader):
			battle.move_leader(leader, cell)
		if not battle.is_finished() and battle.get_attack_targets(leader).has(targets[0]):
			battle.attack(leader, targets[0])
			return
	else:
		var here := Kit.cell_of(battle, leader)
		var goal := here
		for unit: Dictionary in battle.get_units():
			if unit["alive"] and unit["side"] == B and unit["role"] == &"leader" and (goal == here or _distance(unit["cell"], here) < _distance(goal, here)):
				goal = unit["cell"]
		var best := here
		for cell: Vector2i in battle.get_reachable_cells(leader):
			if _distance(cell, goal) < _distance(best, goal):
				best = cell
		if best != here:
			battle.move_leader(leader, best)
	if not battle.is_finished() and battle.can_act(leader):
		battle.wait(leader)


# An enemy stands next to `unit` (one that `before` puts on the same cell
# when given: an enemy pushed there afterwards is not the soldier's doing).
static func _next_to_enemy(units: Array, unit: Dictionary, before: Array = []) -> bool:
	for other: Dictionary in units:
		var has_stayed: bool = before.is_empty() or before[other["index"]]["cell"] == other["cell"]
		if other["alive"] and other["side"] != unit["side"] and _distance(other["cell"], unit["cell"]) == 1 and has_stayed:
			return true
	return false


static func _ranged_kept_clear(before: Array, after: Array, where: String) -> bool:
	for unit: Dictionary in after:
		var was: Dictionary = before[unit["index"]]
		if unit["role"] != &"soldier" or not unit["alive"] or not (unit["is_ranged"] or int(unit["max_range"]) > 1) or unit["cell"] == was["cell"]:
			continue
		if was["side"] == unit["side"] and not _next_to_enemy(before, was) and _next_to_enemy(after, unit, before):
			return Kit.expect_true("%s: ranged soldier %d stepped next to an enemy (%s -> %s, hp %d/%d, leader %s, holds %s, free %s)" % [where, unit["index"], was["cell"], unit["cell"], unit["hp"], unit["max_hp"], after[unit["leader"]]["cell"] if unit["leader"] >= 0 else "-", unit["holds_ground"], unit["acts_free"]], false)
	return true
