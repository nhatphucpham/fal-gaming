class_name TacticsCampaign
extends RefCounted
## One muster and battle of the tactics scenario with the roster (Sổ quân):
## fills every troop slot of our squads with a roster soldier of that troop
## (most marks first, new recruits when none is left), adds our soldiers
## named for their marks as small leaders and the deserters and traitors
## with enough marks as enemy leaders, sets the battle's incidents, karma
## and records, and writes the end-of-battle report back into the roster.
## Rules come from the TacticsIncidentRulesData; the simulation decides
## what happens. See Docs/systems/tactics_roster.md.
## [codeblock]
## var campaign := TacticsCampaign.new(roster, catalog, base_scenario)
## battle.load_scenario_with_squads(campaign.scenario, 0, campaign.squads)
## campaign.prepare_battle(battle, campaign.people)
## var summary := campaign.finish_battle(battle, campaign.people)
## [/codeblock]

const SIDE_A: int = 0
const SIDE_B: int = 1
const NAMED_PREFIX: String = "leader.named_"

var roster: TacticsRoster
var catalog: TacticsCatalog
var rules: TacticsIncidentRulesData
var text: TacticsText
var bio: TacticsBiography
## The scenario as mustered: the base one with the named and returning
## leaders added.
var scenario: TacticsScenarioData
## Per leader of side A: an Array[TacticsTroopData] and the person ids in
## the same order.
var squads: Array = []
var people: Array = []
## Per leader of side A or B: the person id of a leader made from the
## roster, -1 for a scenario leader.
var leader_people: Array[int] = []
var enemy_people: Array[int] = []
## The leaders made from the roster, ours then the enemy's.
var runtime_leaders: Array[TacticsLeaderData] = []

# Unit index -> person id, fixed when the battle is prepared (defections
# change the squads later).
var _unit_to_person: Dictionary = {}


func _init(tactics_roster: TacticsRoster, tactics_catalog: TacticsCatalog, base_scenario: TacticsScenarioData) -> void:
	roster = tactics_roster
	catalog = tactics_catalog
	rules = catalog.incident_rules
	text = TacticsText.new(catalog)
	bio = TacticsBiography.new(text, rules.marks_to_name)
	_build(base_scenario)


## Registers the runtime leaders and the names of roster soldiers on a
## screen's TacticsText.
func fill_text(target: TacticsText) -> void:
	for leader: TacticsLeaderData in runtime_leaders:
		target.register_unit(leader)
	for person: Dictionary in roster.people:
		if person["is_named"]:
			target.person_names[int(person["id"])] = bio.person_name(person)


## The person behind a roster id, or an empty Dictionary.
func get_person(id: int) -> Dictionary:
	return roster.get_person(id)


## The seed this battle's incidents use: the roster's, moved on by the
## battles already fought.
func get_battle_seed() -> int:
	return absi(hash("%d:%d" % [roster.seed_value, roster.battles])) + 1


## Incidents, carried karma and every roster unit's record, on a battle
## loaded with `scenario` and the squads of `squad_people` (the muster may
## have moved soldiers between leaders) that has not started.
func prepare_battle(battle: TacticsBattle, squad_people: Array) -> bool:
	if not battle.set_incident_rules(rules, get_battle_seed()):
		return false
	battle.set_karma(SIDE_A, roster.karma_bait, roster.karma_rescue)
	_unit_to_person.clear()
	for pair: Array in _unit_people(battle, squad_people):
		_unit_to_person[pair[0]] = pair[1]
		var person := roster.get_person(pair[1])
		if person.is_empty():
			continue
		var good := 0
		for mark: Dictionary in person["marks"]:
			var incident := rules.get_incident(mark["incident"])
			good += 1 if incident != null and incident.is_good() else 0
		battle.set_unit_record(pair[0], pair[1], good, (person["marks"] as Array).size() - good)
	return true


## Writes the battle's report into the roster (marks, deaths, desertions,
## defections, names, recruits and karma), saves it and returns what
## changed, for the after-battle summary. Works on a battle left early too.
func finish_battle(battle: TacticsBattle, squad_people: Array, is_saved: bool = true) -> Dictionary:
	if _unit_to_person.is_empty():
		for pair: Array in _unit_people(battle, squad_people):
			_unit_to_person[pair[0]] = pair[1]
	var summary := apply_report(battle.get_battle_report(), _unit_to_person)
	if is_saved:
		roster.save()
	return summary


## finish_battle() without the battle: a get_battle_report() Dictionary and
## unit index -> person id; changes the roster, does not save it.
func apply_report(report: Dictionary, by_unit: Dictionary) -> Dictionary:
	var battle_number := roster.battles + 1
	var rows: Array[Dictionary] = []
	var named: Array[int] = []
	for entry: Dictionary in report["units"]:
		var unit: int = entry["unit"]
		var person := roster.get_person(by_unit.get(unit, -1))
		var marks: Array = entry["marks"]
		if person.is_empty() and entry["start_side"] == SIDE_B and entry["has_defected"] and entry["status"] == &"alive" and entry["role"] == &"soldier":
			person = roster.recruit(entry["id"], entry["leader_id"])
		if person.is_empty():
			continue
		for mark: Dictionary in marks:
			person["marks"].append({
				"incident": mark["incident"], "leader_id": mark["leader_id"], "terrain": mark["terrain"],
				"round": int(mark["round"]), "battle": battle_number,
			})
		var before: String = person["status"]
		person["status"] = _status_after(entry, before)
		var is_named_now: bool = person["status"] == "active" and not person["is_named"] and (person["marks"] as Array).size() >= rules.marks_to_name
		if is_named_now:
			person["is_named"] = true
			named.append(int(person["id"]))
		rows.append({
			"id": person["id"], "unit": unit, "status": entry["status"], "has_defected": entry["has_defected"], "start_side": entry["start_side"],
			"role": entry["role"], "marks": marks.map(func(mark: Dictionary) -> StringName: return mark["incident"]), "is_named_now": is_named_now,
			"before": before, "after": person["status"],
		})
	var karma: Dictionary = report["karma"][SIDE_A]
	var next_bait := (int(karma["carried_bait"]) + int(karma["bait"])) * rules.karma_keep_pct / 100
	var next_rescue := (int(karma["carried_rescue"]) + int(karma["rescue"])) * rules.karma_keep_pct / 100
	roster.karma_bait = next_bait
	roster.karma_rescue = next_rescue
	roster.battles = battle_number
	return {
		"is_finished": report["is_finished"], "winner": report["winner"], "reason": report["reason"], "round": report["round"],
		"rows": rows, "named": named, "karma": {"bait": karma["bait"], "rescue": karma["rescue"], "next_bait": next_bait, "next_rescue": next_rescue},
	}


## A roster person as a leader: its troop's figure, keywords and ranges,
## the passive of the incident most of its marks name, the named skill.
func make_leader(person: Dictionary) -> TacticsLeaderData:
	var troop := catalog.get_troop(person["troop"])
	var leader := TacticsLeaderData.new()
	leader.id = StringName(NAMED_PREFIX + str(person["id"]))
	leader.name_key = bio.person_name(person)
	leader.base_unit = troop.base_unit
	leader.base_class = troop.base_class
	leader.hp_pct = rules.named_hp_pct
	leader.attack_pct = troop.attack_pct * rules.named_attack_pct / 100
	leader.min_range_cells = troop.min_range_cells
	leader.max_range_cells = troop.max_range_cells
	leader.move_points = troop.move_points
	leader.keywords = troop.keywords
	leader.lead_capacity = rules.named_lead_capacity
	var passives: Array[TacticsPassiveData] = []
	var incident := rules.get_incident(TacticsRoster.main_incident(person))
	if incident != null and incident.mark_passive != null:
		passives.append(incident.mark_passive)
	leader.passives = passives
	leader.skill = rules.named_skill
	return leader


# Fills the slots, adds the named and returning leaders.
func _build(base: TacticsScenarioData) -> void:
	scenario = base.duplicate() as TacticsScenarioData
	var leaders_a: Array[TacticsLeaderData] = []
	leaders_a.assign(base.leaders_a)
	var leaders_b: Array[TacticsLeaderData] = []
	leaders_b.assign(base.leaders_b)
	var taken := {}
	for leader: TacticsLeaderData in base.leaders_a:
		var squad: Array[TacticsTroopData] = []
		var ids: Array[int] = []
		for troop: TacticsTroopData in leader.squad:
			var found := roster.find_soldiers(troop.id, taken)
			var person: Dictionary = found[0] if not found.is_empty() else roster.recruit(troop.id, leader.id)
			taken[person["id"]] = true
			squad.append(troop)
			ids.append(int(person["id"]))
		squads.append(squad)
		people.append(ids)
		leader_people.append(-1)
	for leader: TacticsLeaderData in base.leaders_b:
		enemy_people.append(-1)
	var room_a := scenario.map.spawn_cells_a.size() - leaders_a.size()
	for person: Dictionary in roster.get_named():
		if room_a <= 0:
			break
		room_a -= 1
		var leader := make_leader(person)
		leaders_a.append(leader)
		runtime_leaders.append(leader)
		var empty_squad: Array[TacticsTroopData] = []
		var empty_ids: Array[int] = []
		squads.append(empty_squad)
		people.append(empty_ids)
		leader_people.append(int(person["id"]))
	var room_b := scenario.map.spawn_cells_b.size() - leaders_b.size()
	for person: Dictionary in roster.get_returning(rules.traitor_marks_to_return):
		if room_b <= 0:
			break
		room_b -= 1
		person["is_named"] = true
		var leader := make_leader(person)
		var squad: Array[TacticsTroopData] = []
		for slot: int in rules.named_lead_capacity:
			squad.append(catalog.get_troop(person["troop"]))
		leader.squad = squad
		leaders_b.append(leader)
		runtime_leaders.append(leader)
		enemy_people.append(int(person["id"]))
	scenario.leaders_a = leaders_a
	scenario.leaders_b = leaders_b
	for leader: TacticsLeaderData in runtime_leaders:
		text.register_unit(leader)
		bio.leader_names[leader.id] = leader.name_key


# [unit index, person id] for every roster unit of a loaded battle: our
# soldiers by squad order, our named leaders, the returning enemy leaders.
func _unit_people(battle: TacticsBattle, squad_people: Array) -> Array:
	var pairs: Array = []
	var slots := [0, 0]
	for state: Dictionary in battle.get_units():
		if state["role"] != &"leader" or state["start_side"] < 0:
			continue
		var side: int = state["start_side"]
		var slot: int = slots[side]
		slots[side] += 1
		var leader_ids: Array[int] = leader_people if side == SIDE_A else enemy_people
		if slot < leader_ids.size() and leader_ids[slot] >= 0:
			pairs.append([state["index"], leader_ids[slot]])
		if side != SIDE_A or slot >= squad_people.size():
			continue
		var ids: Array = squad_people[slot]
		var soldiers: Array = state["soldiers"]
		for index: int in mini(ids.size(), soldiers.size()):
			pairs.append([soldiers[index], ids[index]])
	return pairs


# active / dead / deserted / traitor after the battle, from the report.
static func _status_after(entry: Dictionary, before: String) -> String:
	if entry["status"] == &"dead":
		return "dead"
	var is_ours: bool = entry["start_side"] == SIDE_A
	if entry["status"] == &"fled":
		return "deserted" if is_ours else before
	if entry["has_defected"]:
		return "traitor" if is_ours else "active"
	return before
