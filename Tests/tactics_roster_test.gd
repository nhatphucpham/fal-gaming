extends SceneTree

# Headless tests for the roster (Sổ quân) and the campaign around it: the
# save round trip, written whole or not at all, a wrong version or a broken
# file set aside rather than overwritten; the muster
# fills troop slots with roster soldiers (most marks first) and recruits
# the rest; a report writes marks, deaths, desertions and defections back;
# a soldier is named at three marks with a name and biography that do not
# change after; a named soldier leads a small squad; a traitor with two
# marks comes back as an enemy leader when river_crossing is played again;
# karma carries over at half; a real battle with incidents leaves marks;
# names stay unique; a named leader can die; more named soldiers than
# spawn cells fight in squads; a hundred battles keep the save small.

const CATALOG_PATH: String = "res://Data/Tactics/tactics_catalog.tres"
const SCENARIO_PATH: String = "res://Data/Tactics/Scenarios/river_crossing.tres"
const SAVE_PATH: String = "user://tactics_roster_test.json"
const SPEARMAN: StringName = &"troop.spearman"

var _catalog: TacticsCatalog
var _scenario: TacticsScenarioData
var _battles: Array[TacticsBattle] = []


func _initialize() -> void:
	TranslationServer.set_locale("vi")
	TacticsRoster.path = SAVE_PATH
	var ok := _run()
	for battle: TacticsBattle in _battles:
		battle.free()
	TacticsRoster.delete()
	if ok:
		print("Tactics roster test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	_catalog = load(CATALOG_PATH) as TacticsCatalog
	_scenario = load(SCENARIO_PATH) as TacticsScenarioData
	var checks: Array[Callable] = [
		_check_save_round_trip, _check_bad_saves, _check_muster_fill, _check_report, _check_naming, _check_biography_battles,
		_check_named_leader, _check_traitor_returns, _check_karma_carry, _check_real_battle,
		_check_atomic_save, _check_unreadable_kept, _check_unique_names, _check_named_leader_dies, _check_all_named,
		_check_leader_cap, _check_long_campaign,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Tactics roster test failed in %s" % check.get_method())
			return false
	return true


func _expect(what: String, actual: Variant, expected: Variant) -> bool:
	if actual == expected:
		return true
	push_error("Tactics roster test: %s: got %s, expected %s" % [what, actual, expected])
	return false


func _mark(incident: StringName, terrain: StringName, round_number: int = 2) -> Dictionary:
	return {"incident": incident, "leader_id": &"leader.lieu_mi", "terrain": terrain, "round": round_number, "battle": 1}


func _battle_for(campaign: TacticsCampaign) -> TacticsBattle:
	var battle := TacticsBattle.new()
	_battles.append(battle)
	if not battle.load_scenario_with_squads(campaign.scenario, 0, campaign.squads):
		push_error("Tactics roster test: the mustered scenario did not load")
	return battle


func _check_save_round_trip() -> bool:
	var roster := TacticsRoster.create(99)
	var person := roster.recruit(SPEARMAN, &"leader.lac_hong")
	person["marks"].append(_mark(&"incident.rescue", &"terrain.bridge"))
	roster.karma_bait = 3
	roster.battles = 2
	if not roster.save():
		return false
	var loaded := TacticsRoster.load_roster()
	var again := loaded.get_person(person["id"])
	return _expect("seed", loaded.seed_value, 99) and _expect("battles", loaded.battles, 2) and _expect("karma", loaded.karma_bait, 3) \
		and _expect("next id", loaded.next_id, 2) and _expect("troop", again.get("troop"), SPEARMAN) and _expect("look", again.get("look"), person["look"]) \
		and _expect("mark", again["marks"][0]["incident"], &"incident.rescue") and _expect("mark terrain", again["marks"][0]["terrain"], &"terrain.bridge") \
		and _expect("number", again["number"], 1) and _expect("troop count", loaded.troop_counts.get(String(SPEARMAN)), 1)


func _check_bad_saves() -> bool:
	var data := TacticsRoster.create(5).to_save_data()
	data["version"] = TacticsRoster.VERSION + 1
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	print("Tactics roster test: the next warning (unreadable roster) is expected")
	var newer := TacticsRoster.load_roster()
	file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	var broken := TacticsRoster.load_roster()
	TacticsRoster.delete()
	var missing := TacticsRoster.load_roster()
	return _expect("newer version ignored", newer.people.size(), 0) and _expect("broken ignored", broken.people.size(), 0) \
		and _expect("missing is empty", missing.people.size(), 0) and _expect("fresh seed", missing.seed_value != 0, true)


# A fresh roster recruits every slot; the next muster takes the same people
# back, the marked spearman first; the dead stay out.
func _check_muster_fill() -> bool:
	var roster := TacticsRoster.create(7)
	var first := TacticsCampaign.new(roster, _catalog, _scenario)
	var slots := 0
	for leader: TacticsLeaderData in _scenario.leaders_a:
		slots += leader.squad.size()
	var count := roster.people.size()
	var spearmen: Array = roster.people.filter(func(person: Dictionary) -> bool: return person["troop"] == SPEARMAN)
	var last_spearman: Dictionary = spearmen[-1]
	last_spearman["marks"].append(_mark(&"incident.stand", &"terrain.ford"))
	var dead: Dictionary = roster.people[0]
	dead["status"] = "dead"
	var second := TacticsCampaign.new(roster, _catalog, _scenario)
	var first_spear_slot := -1
	for slot: int in _scenario.leaders_a.size():
		var squad: Array = second.squads[slot]
		for index: int in squad.size():
			if first_spear_slot < 0 and (squad[index] as TacticsTroopData).id == SPEARMAN:
				first_spear_slot = second.people[slot][index]
	var all_ids: Array = []
	for ids: Array in second.people:
		all_ids.append_array(ids)
	return _expect("one person per slot", count, slots) and _expect("squads", first.squads.size(), _scenario.leaders_a.size()) \
		and _expect("one recruit for the dead", roster.people.size(), slots + 1) and _expect("marked first", first_spear_slot, last_spearman["id"]) \
		and _expect("the dead stay out", all_ids.has(dead["id"]), false) and _expect("numbers count up", (spearmen[1] as Dictionary)["number"], 2)


func _report_unit(unit: int, status: StringName, marks: Array = [], side: int = 0, start_side: int = 0) -> Dictionary:
	return {
		"unit": unit, "record_id": -1, "id": SPEARMAN, "role": &"soldier", "start_side": start_side, "side": side, "status": status,
		"has_defected": side != start_side, "leader_id": &"leader.lac_hong", "marks": marks,
	}


func _report(units: Array, karma_a: Dictionary = {}) -> Dictionary:
	var karma := {"bait": 0, "rescue": 0, "carried_bait": 0, "carried_rescue": 0}
	karma.merge(karma_a, true)
	return {"is_finished": true, "winner": 0, "reason": &"objective", "round": 6, "map": &"map.river_crossing", "karma": [karma, karma], "units": units}


func _check_report() -> bool:
	var roster := TacticsRoster.create(3)
	var campaign := TacticsCampaign.new(roster, _catalog, _scenario)
	var ids: Array = campaign.people[0]
	var fled_mark := {"incident": &"incident.flee", "leader_id": &"leader.lac_hong", "terrain": &"terrain.plain", "cell": Vector2i(1, 1), "round": 3}
	var units := [
		_report_unit(1, &"dead"), _report_unit(2, &"fled", [fled_mark]), _report_unit(3, &"alive", [], 1),
		_report_unit(20, &"alive", [], 0, 1),
	]
	units[3]["leader_id"] = &"leader.moon_spear"
	var summary := campaign.apply_report(_report(units), {1: ids[0], 2: ids[1], 3: ids[2]})
	var recruit := roster.people[-1]
	return _expect("dead", roster.get_person(ids[0])["status"], "dead") and _expect("deserted", roster.get_person(ids[1])["status"], "deserted") \
		and _expect("mark kept", roster.get_person(ids[1])["marks"].size(), 1) and _expect("traitor", roster.get_person(ids[2])["status"], "traitor") \
		and _expect("defector joins", recruit["first_leader"], &"leader.moon_spear") and _expect("rows", (summary["rows"] as Array).size(), 4) \
		and _expect("battles", roster.battles, 1)


# Three marks name a spearman number 7 left mostly at the bridge "Bảy Cầu";
# a fourth mark elsewhere changes neither the name nor the biography.
func _check_naming() -> bool:
	var roster := TacticsRoster.create(11)
	for index: int in 7:
		roster.recruit(SPEARMAN, &"leader.lieu_mi")
	var campaign := TacticsCampaign.new(roster, _catalog, _scenario)
	var person: Dictionary = roster.people[6]
	person["marks"].append(_mark(&"incident.rescue", &"terrain.bridge", 2))
	person["marks"].append(_mark(&"incident.stand", &"terrain.ford", 3))
	var new_mark := {"incident": &"incident.surge", "leader_id": &"leader.lieu_mi", "terrain": &"terrain.bridge", "cell": Vector2i(3, 7), "round": 4}
	var summary := campaign.apply_report(_report([_report_unit(5, &"alive", [new_mark])]), {5: person["id"]})
	var name := campaign.bio.person_name(person)
	var lines := campaign.bio.biography(person)
	person["marks"].append(_mark(&"incident.riot", &"terrain.forest", 5))
	print("Tactics roster test: %s — %s" % [name, " ".join(lines)])
	return _expect("named", person["is_named"], true) and _expect("in the summary", summary["named"], [person["id"]]) \
		and _expect("name", name, "Bảy Cầu") and _expect("opening", lines[0], "Binh giáo thứ bảy của toán Liễu Mi.") \
		and _expect("first mark", lines[1], "Vòng 2, ở cầu, lao ra đỡ đòn thay Liễu Mi.") and _expect("closing", lines[-1], "Người trong toán gọi là Bảy Cầu.") \
		and _expect("lines", lines.size(), 5) and _expect("stable name", campaign.bio.person_name(person), name) \
		and _expect("stable biography", campaign.bio.biography(person), lines)


# Marks alike but from two battles (same incident, round, ground and
# leader) read as two different lines that say which battle, and one deed
# recorded twice in one battle is told once: the biography never repeats
# a sentence.
func _check_biography_battles() -> bool:
	var roster := TacticsRoster.create(17)
	var campaign := TacticsCampaign.new(roster, _catalog, _scenario)
	var person := roster.recruit(SPEARMAN, &"leader.lac_hong")
	for battle_number: int in [1, 2, 3]:
		var mark := _mark(&"incident.stand", &"terrain.plain", 2)
		mark["battle"] = battle_number
		person["marks"].append(mark)
	var lines := campaign.bio.biography(person)
	var seen := {}
	for line: String in lines:
		if seen.has(line):
			return _expect("a repeated biography line", line, "")
		seen[line] = true
	var twice := roster.recruit(SPEARMAN, &"leader.lac_hong")
	twice["marks"].append(_mark(&"incident.stand", &"terrain.plain", 2))
	twice["marks"].append(_mark(&"incident.stand", &"terrain.plain", 2))
	twice["marks"].append(_mark(&"incident.surge", &"terrain.plain", 5))
	var twice_lines := campaign.bio.biography(twice)
	return _expect("battle and round", lines[1], "Trận 1, vòng 2, ở đồng bằng, một mình đứng chặn khi toán của Liễu Mi đã lùi.") \
		and _expect("the later battle", lines[3], "Trận 3, vòng 2, ở đồng bằng, một mình đứng chặn khi toán của Liễu Mi đã lùi.") \
		and _expect("one deed recorded twice is told once", twice_lines.size(), 4)


# A named soldier musters as a leader of its own: two places, its troop's
# keywords, the passive of its most common mark, the named skill.
func _check_named_leader() -> bool:
	var roster := TacticsRoster.create(13)
	var person := roster.recruit(SPEARMAN, &"leader.lac_hong")
	for terrain: StringName in [&"terrain.hill", &"terrain.hill", &"terrain.plain"]:
		person["marks"].append(_mark(&"incident.stand", terrain))
	person["is_named"] = true
	var campaign := TacticsCampaign.new(roster, _catalog, _scenario)
	var leader: TacticsLeaderData = campaign.scenario.leaders_a[-1]
	var battle := _battle_for(campaign)
	var state := battle.get_unit_state(battle.get_units().filter(func(unit: Dictionary) -> bool: return unit["id"] == leader.id)[0]["index"])
	var text := TacticsText.new(_catalog)
	campaign.fill_text(text)
	return _expect("a fourth leader", campaign.scenario.leaders_a.size(), _scenario.leaders_a.size() + 1) \
		and _expect("its people", campaign.leader_people[-1], person["id"]) and _expect("capacity", state["capacity"], 2) \
		and _expect("passive", leader.passives[0].id, &"tactics_passive.mark_stand") and _expect("skill", leader.skill.id, &"tactics_skill.named_rally") \
		and _expect("name", text.unit_name(leader.id), "Cả Đồi") and _expect("not a soldier too", campaign.people.any(func(ids: Array) -> bool: return ids.has(person["id"])), false) \
		and _expect("base scenario unchanged", _scenario.leaders_a.size(), 3)


# A spearman goes over to the enemy with two marks; the next river crossing
# has him as a third enemy leader, with a record the report gives back.
func _check_traitor_returns() -> bool:
	var roster := TacticsRoster.create(17)
	var campaign := TacticsCampaign.new(roster, _catalog, _scenario)
	var traitor := roster.get_person(campaign.people[0][0])
	traitor["marks"].append(_mark(&"incident.discontent", &"terrain.river"))
	var betray := {"incident": &"incident.betray", "leader_id": &"leader.lac_hong", "terrain": &"terrain.ford", "cell": Vector2i(8, 7), "round": 4}
	campaign.apply_report(_report([_report_unit(1, &"alive", [betray], 1)]), {1: traitor["id"]})
	var again := TacticsCampaign.new(roster, _catalog, _scenario)
	var enemy: TacticsLeaderData = again.scenario.leaders_b[-1]
	var battle := _battle_for(again)
	if not again.prepare_battle(battle, again.people):
		return false
	battle.start()
	var report := battle.get_battle_report()
	var entry: Dictionary = report["units"].filter(func(unit: Dictionary) -> bool: return unit["id"] == enemy.id)[0]
	return _expect("status", traitor["status"], "traitor") and _expect("third enemy leader", again.scenario.leaders_b.size(), 3) \
		and _expect("named on return", traitor["is_named"], true) and _expect("enemy side", entry["side"], 1) and _expect("record", entry["record_id"], traitor["id"]) \
		and _expect("his squad", enemy.squad.size(), 2) and _expect("his keywords", enemy.keywords, _catalog.get_troop(SPEARMAN).keywords)


func _check_karma_carry() -> bool:
	var roster := TacticsRoster.create(19)
	roster.karma_bait = 4
	var campaign := TacticsCampaign.new(roster, _catalog, _scenario)
	var summary := campaign.apply_report(_report([], {"bait": 6, "rescue": 3, "carried_bait": 4}), {})
	return _expect("bait kept at half", roster.karma_bait, 5) and _expect("rescue kept at half", roster.karma_rescue, 1) \
		and _expect("summary", summary["karma"]["next_bait"], 5)


# Both sides played by the AI over several battle seeds: incidents leave
# marks on roster soldiers, and the roster saves them.
func _check_real_battle() -> bool:
	var roster := TacticsRoster.create(23)
	var marks := 0
	for attempt: int in 12:
		var campaign := TacticsCampaign.new(roster, _catalog, _scenario)
		var battle := _battle_for(campaign)
		battle.set_side_ai(0, true)
		if not campaign.prepare_battle(battle, campaign.people):
			return false
		battle.start()
		var summary := campaign.finish_battle(battle, campaign.people)
		for row: Dictionary in summary["rows"]:
			marks += (row["marks"] as Array).size()
	var loaded := TacticsRoster.load_roster()
	var saved_marks := 0
	for person: Dictionary in loaded.people:
		saved_marks += (person["marks"] as Array).size()
	return _expect("battles", loaded.battles, 12) and _expect("marks were earned", marks > 0, true) and _expect("saved marks", saved_marks, marks)


# A save that cannot be written whole leaves the last good file as it was
# and nothing beside it.
func _check_atomic_save() -> bool:
	var roster := TacticsRoster.create(29)
	roster.battles = 4
	if not roster.save():
		return false
	var is_temp_left := FileAccess.file_exists(SAVE_PATH + TacticsRoster.TEMP_SUFFIX)
	var before := FileAccess.get_file_as_string(SAVE_PATH)
	# A folder where the temporary file goes makes the write fail.
	DirAccess.make_dir_absolute(SAVE_PATH + TacticsRoster.TEMP_SUFFIX)
	roster.battles = 5
	print("Tactics roster test: the next warning (could not write) may be expected")
	var is_saved := roster.save()
	DirAccess.remove_absolute(SAVE_PATH + TacticsRoster.TEMP_SUFFIX)
	return _expect("no temporary file left", is_temp_left, false) and _expect("a failed save says so", is_saved, false) \
		and _expect("the old file untouched", FileAccess.get_file_as_string(SAVE_PATH), before) \
		and _expect("still readable", TacticsRoster.load_roster().battles, 4)


# A roster from a newer build is set aside, and the next save does not
# destroy it.
func _check_unreadable_kept() -> bool:
	var data := TacticsRoster.create(31).to_save_data()
	data["version"] = TacticsRoster.VERSION + 1
	var newer := JSON.stringify(data)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(newer)
	file.close()
	var roster := TacticsRoster.load_roster()
	roster.save()
	var kept := FileAccess.get_file_as_string(SAVE_PATH + TacticsRoster.UNREADABLE_SUFFIX)
	TacticsRoster.delete()
	return _expect("empty roster", roster.people.size(), 0) and _expect("the newer save kept aside", kept, newer) \
		and _expect("delete removes it too", FileAccess.file_exists(SAVE_PATH + TacticsRoster.UNREADABLE_SUFFIX), false)


func _name_by_marks(person: Dictionary, terrain: StringName, battle_number: int) -> void:
	for round_number: int in [2, 3, 4]:
		var mark := _mark(&"incident.stand", terrain, round_number)
		mark["battle"] = battle_number
		person["marks"].append(mark)
	person["is_named"] = true


# Spearman 7, archer 7 and spearman 17, all named at the bridge, one battle
# after another: the first keeps the short name, the archer adds its troop,
# the second spearman its number; the 17th is not called the seventh.
func _check_unique_names() -> bool:
	var roster := TacticsRoster.create(37)
	var spearmen: Array[Dictionary] = []
	for index: int in 17:
		spearmen.append(roster.recruit(SPEARMAN, &"leader.lieu_mi"))
	var archer: Dictionary = {}
	for index: int in 7:
		archer = roster.recruit(&"troop.archer", &"leader.lieu_mi")
	_name_by_marks(spearmen[16], &"terrain.bridge", 3)
	_name_by_marks(archer, &"terrain.bridge", 2)
	_name_by_marks(spearmen[6], &"terrain.bridge", 1)
	var campaign := TacticsCampaign.new(roster, _catalog, _scenario)
	var names := [campaign.bio.person_name(spearmen[6]), campaign.bio.person_name(archer), campaign.bio.person_name(spearmen[16])]
	return _expect("names", names, ["Bảy Cầu", "Bảy Cung Cầu", "Bảy Giáo Cầu số 17"]) \
		and _expect("the 17th", campaign.bio.biography(spearmen[16])[0], "Binh giáo thứ 17 của toán Liễu Mi.")


# A named soldier who falls as a leader is dead in the roster and leads no
# more.
func _check_named_leader_dies() -> bool:
	var roster := TacticsRoster.create(41)
	var person := roster.recruit(SPEARMAN, &"leader.lac_hong")
	_name_by_marks(person, &"terrain.hill", 1)
	var campaign := TacticsCampaign.new(roster, _catalog, _scenario)
	var battle := _battle_for(campaign)
	if not campaign.prepare_battle(battle, campaign.people):
		return false
	var unit: int = battle.get_units().filter(func(state: Dictionary) -> bool: return state["id"] == campaign.runtime_leaders[0].id)[0]["index"]
	var entry := _report_unit(unit, &"dead")
	entry["role"] = &"leader"
	var summary := campaign.apply_report(_report([entry]), {unit: person["id"]})
	var again := TacticsCampaign.new(roster, _catalog, _scenario)
	return _expect("dead", person["status"], "dead") and _expect("in the summary", summary["rows"][0]["after"], "dead") \
		and _expect("leads no more", again.scenario.leaders_a.size(), _scenario.leaders_a.size()) \
		and _expect("not mustered", again.people.any(func(ids: Array) -> bool: return ids.has(person["id"])), false)


# Four named spearmen and two returning traitors on river_crossing (two
# spare spawn cells a side, one for side B): the first two named lead, the
# other two fill spearman slots, one traitor returns, and the battle loads
# with every leader on its own cell.
func _check_all_named() -> bool:
	var roster := TacticsRoster.create(43)
	var named: Array[Dictionary] = []
	for index: int in 4:
		var person := roster.recruit(SPEARMAN, &"leader.lac_hong")
		_name_by_marks(person, &"terrain.plain", 1)
		named.append(person)
	for index: int in 2:
		var traitor := roster.recruit(SPEARMAN, &"leader.lac_hong")
		traitor["status"] = "traitor"
		traitor["marks"].append(_mark(&"incident.discontent", &"terrain.river"))
		traitor["marks"].append(_mark(&"incident.betray", &"terrain.ford"))
	var campaign := TacticsCampaign.new(roster, _catalog, _scenario)
	var battle := _battle_for(campaign)
	if not campaign.prepare_battle(battle, campaign.people):
		return false
	var cells := {}
	var leaders := 0
	for state: Dictionary in battle.get_units():
		if state["role"] == &"leader":
			leaders += 1
			cells[state["cell"]] = true
	var in_squads := named.filter(func(person: Dictionary) -> bool: return campaign.people.any(func(ids: Array) -> bool: return ids.has(person["id"])))
	return _expect("two named lead", campaign.leader_people.slice(_scenario.leaders_a.size()), [named[0]["id"], named[1]["id"]]) \
		and _expect("the others fight in squads", in_squads, [named[2], named[3]]) \
		and _expect("one traitor returns", campaign.scenario.leaders_b.size(), _scenario.leaders_b.size() + 1) \
		and _expect("every leader on the map", leaders, campaign.scenario.leaders_a.size() + campaign.scenario.leaders_b.size()) \
		and _expect("each on its own cell", cells.size(), leaders)


# Rules allowing fewer leaders than the map has spawn cells: the muster
# stays within them and the battle still loads.
func _check_leader_cap() -> bool:
	var scenario := _scenario.duplicate() as TacticsScenarioData
	scenario.rules = _scenario.rules.duplicate() as TacticsRulesData
	scenario.rules.max_leaders_per_side = _scenario.leaders_a.size() + 1
	var roster := TacticsRoster.create(47)
	for index: int in 2:
		_name_by_marks(roster.recruit(SPEARMAN, &"leader.lac_hong"), &"terrain.plain", 1)
	var campaign := TacticsCampaign.new(roster, _catalog, scenario)
	var battle := TacticsBattle.new()
	_battles.append(battle)
	return _expect("within the cap", campaign.scenario.leaders_a.size(), scenario.rules.max_leaders_per_side) \
		and _expect("loads", battle.load_scenario_with_squads(campaign.scenario, 0, campaign.squads), true)


# A hundred battles played by the AI on both sides: the unmarked fallen are
# forgotten past the kept few, so the roster and its file stay small.
func _check_long_campaign() -> bool:
	var roster := TacticsRoster.create(12345)
	var slots := 0
	for leader: TacticsLeaderData in _scenario.leaders_a:
		slots += leader.squad.size()
	for battle_number: int in 100:
		var campaign := TacticsCampaign.new(roster, _catalog, _scenario)
		var battle := TacticsBattle.new()
		if not battle.load_scenario_with_squads(campaign.scenario, 0, campaign.squads):
			battle.free()
			return _expect("battle %d loads" % (battle_number + 1), false, true)
		battle.set_side_ai(0, true)
		battle.set_side_ai(1, true)
		var is_prepared := campaign.prepare_battle(battle, campaign.people)
		battle.start()
		campaign.finish_battle(battle, campaign.people)
		battle.free()
		if not is_prepared:
			return false
		roster = TacticsRoster.load_roster()
	var unmarked_fallen := roster.people.filter(func(person: Dictionary) -> bool: return person["status"] == "dead" and (person["marks"] as Array).is_empty())
	var bytes := FileAccess.get_file_as_bytes(SAVE_PATH).size()
	print("Tactics roster test: after 100 battles %d people, %d bytes" % [roster.people.size(), bytes])
	return _expect("battles", roster.battles, 100) and _expect("unmarked fallen kept", unmarked_fallen.size() <= TacticsRoster.UNMARKED_FALLEN_KEPT + slots, true) \
		and _expect("people bounded", roster.people.size() < 120, true) and _expect("file under 32 KB", bytes < 32768, true)
