extends SceneTree

# Headless tests for the sites on a tactics map (Docs/systems/tactics_sites.md):
# a village heals a hurt squad, gives one of two recruits or is looted
# for supplies at a karma cost, and the enemy burns one; a village still
# standing at the end is good karma; a site is used once (by one leader,
# once a phase) and never undone; a shrine charges a skill, blesses a
# squad or refuses to calm nobody; a camp is captured for supplies (not
# with an enemy next to it) and heals its owner's units nearby; a
# stronghold is captured by a leader standing on it, waits while
# contested, loses the count when left, gives its owner armor and sight
# and brings its reinforcements once; under fog a side knows a site only
# once seen and remembers it as last seen; the leader panel's site
# actions say what may be taken and why not; the same commands give the
# same state hash.

const Kit := preload("res://Tests/tactics_test_kit.gd")
const A: int = TacticsBattle.SIDE_A
const B: int = TacticsBattle.SIDE_B

var _kit := Kit.new()


func _initialize() -> void:
	var ok := _run()
	_kit.free_battles()
	if ok:
		print("Tactics site test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not _kit.load_catalog():
		return false
	var checks: Array[Callable] = [
		_check_village_heal, _check_village_recruit, _check_village_loot, _check_enemy_burns, _check_village_karma_kept,
		_check_once_and_no_undo, _check_shrine, _check_camp, _check_stronghold_capture, _check_contested, _check_capture_lost,
		_check_stronghold_armor_and_sight, _check_reinforcements, _check_fog_memory, _check_site_actions, _check_determinism,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Tactics site test failed in %s" % check.get_method())
			return false
	return true


func _leader(id: StringName = &"leader.lac_hong") -> TacticsLeaderData:
	return _kit.leader(id)


func _soldier(id: StringName = &"troop.spearman") -> TacticsTroopData:
	return _kit.troop(id)


# Our leader at (5, 5) with one spearman, an enemy leader at (5, 11).
func _two_sides(sites: Array, ai_b: bool = false, rules: TacticsRulesData = null) -> TacticsBattle:
	var battle := _kit.new_site_battle(_kit.plain_rows(), sites, ai_b, rules)
	_kit.add(battle, A, _leader(), Vector2i(5, 5), [_soldier()])
	_kit.add(battle, B, _leader(&"leader.ba_khac"), Vector2i(5, 11))
	return battle


func _site_state(battle: TacticsBattle, site: int, side: int = A) -> Dictionary:
	return battle.get_sites(side)[site]


# Ends our phase and the enemy's (played by hand: it only waits).
func _next_round(battle: TacticsBattle) -> Array:
	var events := battle.end_phase().duplicate()
	events.append_array(battle.end_phase())
	return events


func _check_village_heal() -> bool:
	var battle := _kit.new_site_battle(_kit.plain_rows(), [[_kit.site("village"), Vector2i(4, 5), -1]])
	var ours := _kit.add(battle, A, _leader(), Vector2i(5, 5), [_soldier()])
	var enemy := _kit.add(battle, B, _leader(&"leader.ba_khac"), Vector2i(6, 5))
	battle.start()
	battle.end_phase()
	battle.attack(enemy, ours)
	battle.end_phase()
	var hurt := Kit.hp_of(battle, ours)
	var refused := battle.can_use_site(ours, 0, &"heal") == false
	var events := battle.use_site(ours, 0, &"heal")
	var healed := Kit.of_type(events, &"unit_healed")
	return Kit.expect_true("the leader was hurt", hurt < int(battle.get_unit_state(ours)["max_hp"]) and not refused) \
		and Kit.expect("one site_used", Kit.of_type(events, &"site_used").size(), 1) \
		and Kit.expect_true("the leader is healed", not healed.is_empty() and Kit.hp_of(battle, ours) > hurt) \
		and Kit.expect("the village is used", _site_state(battle, 0)["status"], &"used") \
		and Kit.expect("used once", battle.can_use_site(ours, 0, &"recruit", 0), false)


func _check_village_recruit() -> bool:
	var battle := _two_sides([[_kit.site("village"), Vector2i(4, 5), -1]])
	battle.start()
	var leader := 0
	var before: Array = battle.get_unit_state(leader)["soldiers"]
	var events := battle.use_site(leader, 0, &"recruit", 1)
	var arrived := Kit.of_type(events, &"unit_arrived")
	var squad: Array = battle.get_unit_state(leader)["soldiers"]
	var recruit: Dictionary = battle.get_unit_state(arrived[0]["unit"]) if not arrived.is_empty() else {}
	# A full squad takes no recruit.
	var full := _kit.new_site_battle(_kit.plain_rows(), [[_kit.site("village"), Vector2i(4, 5), -1]])
	var crowded := _kit.add(full, A, _leader(&"leader.lieu_mi"), Vector2i(5, 5), [_soldier(), _soldier(), _soldier()])
	_kit.add(full, B, _leader(&"leader.ba_khac"), Vector2i(5, 11))
	full.start()
	return Kit.expect("one arrival", arrived.size(), 1) and Kit.expect("joins the squad", squad.size(), before.size() + 1) \
		and Kit.expect("the second recruit", recruit.get("id"), (_kit.site("village").recruits[1] as TacticsTroopData).id) \
		and Kit.expect("as a recruit", [recruit.get("arrival"), recruit.get("side"), recruit.get("leader")], [&"recruit", A, leader]) \
		and Kit.expect("no recruit for a full squad", full.can_use_site(crowded, 0, &"recruit", 0), false) \
		and Kit.expect("no third option", battle.can_use_site(leader, 0, &"recruit", 2), false)


func _check_village_loot() -> bool:
	var village := _kit.site("village")
	var battle := _two_sides([[village, Vector2i(4, 5), -1]])
	battle.start()
	var events := battle.use_site(0, 0, &"loot")
	var gained := Kit.of_type(events, &"supplies_gained")
	return Kit.expect("supplies", [battle.get_supplies(A), gained.size()], [village.supplies, 1]) \
		and Kit.expect("burned by us", [_site_state(battle, 0)["status"], _site_state(battle, 0)["burned_by"]], [&"burned", A]) \
		and Kit.expect("looting is bait karma", battle.get_karma(A)["bait"], village.karma_looted)


# The enemy AI burns a village it knows is standing; the karma falls on us
# at the burned weight.
func _check_enemy_burns() -> bool:
	var village := _kit.site("village")
	var battle := _kit.new_site_battle(_kit.plain_rows(), [[village, Vector2i(5, 9), -1]], true)
	_kit.add(battle, A, _leader(), Vector2i(1, 1))
	_kit.add(battle, B, _leader(&"leader.ba_khac"), Vector2i(5, 11))
	battle.start()
	var events := battle.end_phase()
	var used := Kit.of_type(events, &"site_used")
	return Kit.expect("the enemy loots", used.map(func(event: Dictionary) -> StringName: return event["choice"]), [&"loot"]) \
		and Kit.expect("burned by them", [_site_state(battle, 0)["status"], _site_state(battle, 0)["burned_by"]], [&"burned", B]) \
		and Kit.expect("their supplies", battle.get_supplies(B), village.supplies) \
		and Kit.expect("our karma", battle.get_karma(A)["bait"], village.karma_burned)


# A village still standing when the battle ends is rescue karma for us.
func _check_village_karma_kept() -> bool:
	var rules := _kit.catalog.rules.duplicate() as TacticsRulesData
	rules.max_rounds = 1
	var village := _kit.site("village")
	var battle := _two_sides([[village, Vector2i(0, 0), -1], [village, Vector2i(11, 0), -1]], false, rules)
	battle.start()
	var events := _next_round(battle)
	return Kit.expect("ended", battle.is_finished(), true) and Kit.expect("rescue per village", battle.get_karma(A)["rescue"], village.karma_kept * 2) \
		and Kit.expect("battle_ended last", events.back()["type"], &"battle_ended")


# One site a phase per leader, a site used is used, and using one ends the
# steps back.
func _check_once_and_no_undo() -> bool:
	var battle := _two_sides([[_kit.site("village"), Vector2i(5, 4), -1], [_kit.site("shrine"), Vector2i(7, 4), -1]])
	battle.start()
	battle.move_leader(0, Vector2i(6, 4))
	var could_undo := battle.can_undo_move(0)
	battle.use_site(0, 0, &"recruit", 0)
	var second := battle.can_use_site(0, 1, &"bless")
	var undo := battle.can_undo_move(0)
	var refused := battle.use_site(0, 0, &"recruit", 1)
	return Kit.expect("undo before", could_undo, true) and Kit.expect("no undo after a site", undo, false) \
		and Kit.expect("one site a phase", second, false) and Kit.expect("a used village refuses", refused, [])


func _check_shrine() -> bool:
	var shrine := _kit.site("shrine")
	var battle := _two_sides([[shrine, Vector2i(4, 5), -1]])
	battle.start()
	var charge_before: int = battle.get_skill_charge(0)["value"]
	var calm := battle.can_use_site(0, 0, &"calm")
	var events := battle.use_site(0, 0, &"charge")
	var charge: Dictionary = battle.get_skill_charge(0)
	var other := _two_sides([[shrine, Vector2i(4, 5), -1]])
	other.start()
	var attack_before: int = other.get_unit_state(1)["attack"]
	other.use_site(0, 0, &"bless")
	return Kit.expect("nobody to calm", calm, false) and Kit.expect("one site_used", Kit.of_type(events, &"site_used").size(), 1) \
		and Kit.expect_true("charged from %d" % charge_before, int(charge["value"]) >= int(charge["threshold"]) and charge["is_ready"]) \
		and Kit.expect("the shrine is spent", _site_state(battle, 0)["status"], &"used") \
		and Kit.expect_true("the blessing lifts the soldier's attack", int(other.get_unit_state(1)["attack"]) > attack_before)


func _check_camp() -> bool:
	var camp := _kit.site("camp")
	var battle := _kit.new_site_battle(_kit.plain_rows(), [[camp, Vector2i(4, 5), B]])
	var ours := _kit.add(battle, A, _leader(), Vector2i(5, 5), [_soldier()])
	var enemy := _kit.add(battle, B, _leader(&"leader.ba_khac"), Vector2i(6, 5))
	battle.start()
	var blocked := battle.can_use_site(ours, 0, &"capture")
	battle.end_phase()
	battle.attack(enemy, ours)
	battle.end_phase()
	battle.move_leader(ours, Vector2i(4, 6))
	var hurt := Kit.hp_of(battle, ours)
	var free := battle.can_use_site(ours, 0, &"capture")
	var events := battle.use_site(ours, 0, &"capture")
	var after_capture := battle.get_supplies(A)
	var rest := battle.end_phase()
	var rested := Kit.of_type(rest, &"unit_healed").filter(func(event: Dictionary) -> bool: return event["unit"] == ours)
	return Kit.expect("not with an enemy next to it", blocked, false) and Kit.expect("free once it left", free, true) \
		and Kit.expect("captured", [_site_state(battle, 0)["owner"], Kit.of_type(events, &"site_changed").size()], [A, 1]) \
		and Kit.expect("camp supplies", after_capture, camp.supplies) \
		and Kit.expect_true("rests at the end of our phase", not rested.is_empty() and Kit.hp_of(battle, ours) > hurt) \
		and Kit.expect("held already", battle.can_use_site(ours, 0, &"capture"), false)


func _check_stronghold_capture() -> bool:
	var keep := _kit.site("keep")
	var battle := _two_sides([[keep, Vector2i(5, 5), -1]])
	battle.start()
	var events := battle.end_phase()
	var progress := Kit.of_type(events, &"capture_progressed")
	var changed := Kit.of_type(events, &"site_changed")
	return Kit.expect("advanced", progress.map(func(event: Dictionary) -> StringName: return event["kind"]), [&"advanced"]) \
		and Kit.expect("captured", changed.map(func(event: Dictionary) -> StringName: return event["kind"]), [&"captured"]) \
		and Kit.expect("owner", _site_state(battle, 0)["owner"], A)


func _check_contested() -> bool:
	var battle := _kit.new_site_battle(_kit.plain_rows(), [[_kit.site("keep"), Vector2i(5, 5), -1]])
	_kit.add(battle, A, _leader(), Vector2i(5, 5))
	_kit.add(battle, B, _leader(&"leader.ba_khac"), Vector2i(5, 6))
	battle.start()
	var events := battle.end_phase()
	var progress := Kit.of_type(events, &"capture_progressed")
	return Kit.expect("contested", progress.map(func(event: Dictionary) -> StringName: return event["kind"]), [&"contested"]) \
		and Kit.expect("not taken", _site_state(battle, 0)["owner"], -1)


func _check_capture_lost() -> bool:
	var tower := _kit.site("watchtower", {"reinforce_round": 0, "reinforce_leader": null})
	var battle := _two_sides([[tower, Vector2i(5, 5), -1]])
	battle.start()
	var first := Kit.of_type(battle.end_phase(), &"capture_progressed")
	battle.end_phase()
	var halfway: int = _site_state(battle, 0)["capture_progress"]
	battle.move_leader(0, Vector2i(5, 3))
	var lost := Kit.of_type(battle.end_phase(), &"capture_progressed")
	return Kit.expect("one of two phases", [first.size(), halfway, tower.capture_phases], [1, 1, 2]) \
		and Kit.expect("left: the count is lost", lost.map(func(event: Dictionary) -> StringName: return event["kind"]), [&"lost"]) \
		and Kit.expect("back to nothing", [_site_state(battle, 0)["capture_progress"], _site_state(battle, 0)["owner"]], [0, -1])


func _check_stronghold_armor_and_sight() -> bool:
	var keep := _kit.site("keep")
	var held := _kit.new_site_battle(_kit.plain_rows(), [[keep, Vector2i(5, 5), A]])
	var on_keep := _kit.add(held, A, _leader(), Vector2i(5, 5))
	_kit.add(held, B, _leader(&"leader.ba_khac"), Vector2i(5, 11))
	var free := _kit.new_site_battle(_kit.plain_rows(), [[keep, Vector2i(5, 5), -1]])
	var plain := _kit.add(free, A, _leader(), Vector2i(5, 5))
	_kit.add(free, B, _leader(&"leader.ba_khac"), Vector2i(5, 11))
	held.start()
	free.start()
	var bonus := int(held.get_unit_state(on_keep)["armor"]) - int(free.get_unit_state(plain)["armor"])
	var sight: int = _site_state(held, 0)["vision_cells"]
	return Kit.expect("the owner's armor", bonus, keep.armor_bonus) and Kit.expect("its sight", sight, keep.vision_cells)


func _check_reinforcements() -> bool:
	var tower := _kit.site("watchtower", {"reinforce_round": 2})
	var battle := _kit.new_site_battle(_kit.plain_rows(), [[tower, Vector2i(2, 2), A]])
	_kit.add(battle, A, _leader(), Vector2i(5, 5))
	_kit.add(battle, B, _leader(&"leader.ba_khac"), Vector2i(5, 11))
	var count := battle.get_unit_count()
	var first := Kit.of_type(battle.start(), &"unit_arrived")
	var arrivals := Kit.of_type(_next_round(battle), &"unit_arrived")
	var arrived := battle.get_units().slice(count)
	var later := Kit.of_type(_next_round(battle) + _next_round(battle), &"unit_arrived")
	var leaders := arrived.filter(func(unit: Dictionary) -> bool: return unit["role"] == &"leader")
	return Kit.expect("none in round 1", first.size(), 0) and Kit.expect("round 2", battle.get_round(), 4) \
		and Kit.expect("the leader and its squad", [leaders.size(), arrived.size(), arrivals.size()], [1, 1 + tower.reinforce_squad.size(), 1 + tower.reinforce_squad.size()]) \
		and Kit.expect("as ours", [leaders[0]["side"], leaders[0]["arrival"], leaders[0]["id"]], [A, &"reinforce", tower.reinforce_leader.id]) \
		and Kit.expect("once", later.size(), 0)


# Under fog a site is known once seen, and stays as last seen.
func _check_fog_memory() -> bool:
	var environment := TacticsScenarioData.new()
	environment.id = &"scenario.site_test"
	environment.fog_of_war = true
	environment.weather = _kit.catalog.get_weather(&"weather.clear")
	var cycle: Array[TacticsDaytimeData] = [_kit.catalog.get_daytime(&"daytime.day")]
	environment.daytimes = cycle
	var village := _kit.site("village")
	var battle := _kit.new_site_battle(_kit.plain_rows(16), [[village, Vector2i(5, 14), -1]])
	battle.set_environment(environment)
	var ours := _kit.add(battle, A, _leader(), Vector2i(5, 1))
	var enemy := _kit.add(battle, B, _leader(&"leader.ba_khac"), Vector2i(5, 13))
	battle.start()
	var unknown: Dictionary = _site_state(battle, 0)
	var theirs: Dictionary = _site_state(battle, 0, B)
	for step: int in 3:
		battle.move_leader(ours, Kit.cell_of(battle, ours) + Vector2i(0, 3))
		battle.end_phase()
		battle.end_phase()
	var seen: Dictionary = _site_state(battle, 0)
	# We walk away; the enemy burns it out of our sight.
	for step: int in 2:
		battle.move_leader(ours, Kit.cell_of(battle, ours) - Vector2i(0, 4))
		battle.end_phase()
		if step == 0:
			battle.end_phase()
	battle.use_site(enemy, 0, &"loot")
	var remembered: Dictionary = _site_state(battle, 0)
	var truth: Dictionary = _site_state(battle, 0, B)
	return Kit.expect("unknown at first", [unknown["is_known"], unknown["status"]], [false, &"ready"]) \
		and Kit.expect("the enemy knows its own", theirs["is_known"], true) \
		and Kit.expect("known once seen", seen["is_known"], true) \
		and Kit.expect("burned for them", truth["status"], &"burned") \
		and Kit.expect("still standing as we last saw it", [remembered["is_known"], remembered["status"], remembered["is_visible"]], [true, &"ready", false])


func _check_site_actions() -> bool:
	var battle := _two_sides([[_kit.site("village"), Vector2i(4, 5), -1], [_kit.site("camp"), Vector2i(10, 10), -1]])
	battle.start()
	var actions := battle.get_site_actions(0)
	var village: Dictionary = actions[0] if not actions.is_empty() else {}
	var choices: Dictionary = {}
	for choice: Dictionary in village.get("choices", []):
		choices[choice["choice"]] = [choice["can"], choice["options"], choice["reason"] != ""]
	return Kit.expect("only the site in reach", actions.size(), 1) \
		and Kit.expect("heal refused (nobody hurt), recruit of two, loot", choices, {&"heal": [false, 1, true], &"recruit": [true, 2, false], &"loot": [true, 1, false]}) \
		and Kit.expect("a soldier has none", battle.get_site_actions(1), [])


func _check_determinism() -> bool:
	var hashes: Array[String] = []
	for run: int in 2:
		var battle := _two_sides([[_kit.site("village"), Vector2i(4, 5), -1], [_kit.site("keep"), Vector2i(7, 5), -1]], true)
		battle.start()
		battle.use_site(0, 0, &"recruit", 1)
		battle.move_leader(0, Vector2i(7, 5))
		_next_round(battle)
		battle.end_phase()
		hashes.append(battle.get_state_hash())
	var other := _two_sides([[_kit.site("village"), Vector2i(4, 5), -1], [_kit.site("keep"), Vector2i(7, 5), -1]], true)
	other.start()
	other.use_site(0, 0, &"recruit", 0)
	other.move_leader(0, Vector2i(7, 5))
	_next_round(other)
	other.end_phase()
	return Kit.expect("same commands, same hash", hashes[0], hashes[1]) and Kit.expect_true("another recruit, another hash", other.get_state_hash() != hashes[0])
