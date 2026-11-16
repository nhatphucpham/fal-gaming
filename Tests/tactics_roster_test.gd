extends SceneTree

# Headless tests for the roster (Sổ quân) and the campaign around it: the
# save round trip, a wrong version or a broken file ignored; the muster
# fills troop slots with roster soldiers (most marks first) and recruits
# the rest; a report writes marks, deaths, desertions and defections back;
# a soldier is named at three marks with a name and biography that do not
# change after; a named soldier leads a small squad; a traitor with two
# marks comes back as an enemy leader when river_crossing is played again;
# karma carries over at half; a real battle with incidents leaves marks.

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
# leader) read as two different lines that say which battle: the
# biography never repeats a sentence.
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
	return _expect("battle and round", lines[1], "Trận 1, vòng 2, ở đồng bằng, một mình đứng chặn khi toán của Liễu Mi đã lùi.") \
		and _expect("the later battle", lines[3], "Trận 3, vòng 2, ở đồng bằng, một mình đứng chặn khi toán của Liễu Mi đã lùi.")


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
