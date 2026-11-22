class_name TacticsCampaign
extends RefCounted
## One muster and battle of the tactics scenario with the roster (Sổ quân):
## fills every troop slot of our squads with a roster soldier of that troop
## (most marks first, new recruits when none is left), adds our soldiers
## named for their marks as small leaders and the deserters and traitors
## with enough marks as enemy leaders, sets the battle's incidents, karma
## and records, and writes the end-of-battle report back into the roster.
## Rules come from the TacticsIncidentRulesData; the simulation decides
## what happens. A plan from the world map (TacticsWorldScreen) names the
## region, the enemy's pressure there and the items used. See
## Docs/systems/tactics_roster.md and Docs/systems/tactics_world.md.
## [codeblock]
## var campaign := TacticsCampaign.new(roster, catalog, base_scenario, {"region": &"region.ferry"})
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
## Tests and stills: person id -> incident id seeded on that soldier,
## instead of drawing seeds from the battle seed.
var forced_seeds: Dictionary = {}
## The world region this battle is fought in; empty outside the world map.
var region_id: StringName = &""
## Enemy hp and attack in % of the scenario's (the region's pressure).
var enemy_power_pct: int = 100
## Items used on this battle; the roster gives them up when it is fought.
var items_used: Array[TacticsItemData] = []

# Unit index -> person id, fixed when the battle is prepared (defections
# change the squads later).
var _unit_to_person: Dictionary = {}


## `base_scenario` null: no muster, for the roster's names and sheets only.
## `plan` (all optional): region (StringName), enemy_power_pct (int),
## items (Array of TacticsItemData the roster holds).
func _init(tactics_roster: TacticsRoster, tactics_catalog: TacticsCatalog, base_scenario: TacticsScenarioData, plan: Dictionary = {}) -> void:
	region_id = plan.get("region", &"")
	enemy_power_pct = int(plan.get("enemy_power_pct", 100))
	for item: TacticsItemData in plan.get("items", []):
		if tactics_roster.get_item_count(item.id) > items_used.count(item):
			items_used.append(item)
	roster = tactics_roster
	catalog = tactics_catalog
	rules = catalog.incident_rules
	text = TacticsText.new(catalog)
	bio = TacticsBiography.new(text, rules.marks_to_name)
	bio.roster = roster
	# Without a scenario it only names and describes the roster (the world
	# map's Sổ quân, the market): no muster, no recruits.
	if base_scenario != null:
		_build(base_scenario)


## The scenario the roster fights next: the catalog's scenarios in turn,
## one per battle fought, in the catalog's order (the river crossing first,
## and back to it after the last).
static func next_scenario(tactics_roster: TacticsRoster, tactics_catalog: TacticsCatalog) -> TacticsScenarioData:
	if tactics_catalog.scenarios.is_empty():
		return null
	return tactics_catalog.scenarios[tactics_roster.battles % tactics_catalog.scenarios.size()] as TacticsScenarioData


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
		if forced_seeds.has(pair[1]) and not battle.set_incident_seed(pair[0], forced_seeds[pair[1]]):
			return false
	return TacticsBonds.set_up_battle(battle, roster, roster.world.data)


## Writes the battle's report into the roster (marks, deaths, desertions,
## defections, names, recruits, karma and supplies), saves it and returns
## what changed, for the after-battle summary. Works on a battle left early
## too.
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
	# Earlier battles' unmarked fallen go first; this battle's stay for its
	# summary.
	roster.forget_old_fallen()
	var battle_number := roster.battles + 1
	var rows: Array[Dictionary] = []
	var named: Array[int] = []
	for entry: Dictionary in report["units"]:
		var unit: int = entry["unit"]
		var person := roster.get_person(by_unit.get(unit, -1))
		var marks: Array = entry["marks"]
		var is_recruit := false
		if person.is_empty() and entry["start_side"] == SIDE_B and entry["has_defected"] and entry["status"] == &"alive" and entry["role"] == &"soldier":
			person = roster.recruit(entry["id"], entry["leader_id"])
		# A soldier a village gave us joins the roster, face and all, unless
		# it fell.
		if person.is_empty() and entry["start_side"] == SIDE_A and entry.get("arrival", &"") == &"recruit" and entry["status"] != &"dead" and not entry["has_defected"]:
			person = roster.recruit(entry["id"], entry["leader_id"])
			is_recruit = true
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
			"before": before, "after": person["status"], "is_recruit": is_recruit,
		})
	var karma: Dictionary = report["karma"][SIDE_A]
	var next_bait := (int(karma["carried_bait"]) + int(karma["bait"])) * rules.karma_keep_pct / 100
	var next_rescue := (int(karma["carried_rescue"]) + int(karma["rescue"])) * rules.karma_keep_pct / 100
	roster.karma_bait = next_bait
	roster.karma_rescue = next_rescue
	roster.battles = battle_number
	var gained := int(report.get("supplies", 0))
	roster.supplies += gained
	var bond_rows := TacticsBonds.apply_tallies(roster, roster.world.data, report)
	var is_won: bool = report["is_finished"] and int(report["winner"]) == SIDE_A
	return {
		"is_finished": report["is_finished"], "winner": report["winner"], "reason": report["reason"], "round": report["round"],
		"rows": rows, "named": named, "karma": {"bait": karma["bait"], "rescue": karma["rescue"], "next_bait": next_bait, "next_rescue": next_rescue},
		"supplies": gained, "supplies_total": roster.supplies, "goals": _goal_rows(report.get("goals_met", [])),
		"bonds": bond_rows, "world": finish_region(is_won), "mode": &"mode.manual",
	}


## An Auto battle's result (TacticsAutoResolve.resolve()) written into the
## roster, then saved: no one dies; each roster person of ours who fell is
## wounded and sits out the next `wound_rest_battles` battles; a win pays
## the region's `auto_supplies` (no side goals, no marks, no bonds).
## Returns {mode, is_won, wounded (person ids), rows, counts, fortune,
## supplies, supplies_total, world}.
func apply_auto(result: Dictionary, is_saved: bool = true) -> Dictionary:
	var data := roster.world.data
	roster.battles += 1
	var wounded: Array[int] = []
	for row: Dictionary in result["units"]:
		var person := roster.get_person(int(row["person"]))
		if row["side"] != SIDE_A or row["alive"] or person.is_empty():
			continue
		person["rest_until"] = roster.battles + data.wound_rest_battles
		wounded.append(int(person["id"]))
	var region := data.get_region(region_id)
	var gained: int = region.auto_supplies if result["is_won"] and region != null else 0
	roster.supplies += gained
	var summary := {
		"mode": &"mode.auto", "is_won": result["is_won"], "wounded": wounded, "rows": result["units"], "counts": result["counts"], "fortune": result.get("fortune", 0),
		"supplies": gained, "supplies_total": roster.supplies, "world": finish_region(result["is_won"]),
	}
	if is_saved:
		roster.save()
	return summary


## The battle's end for the world map: the items are used up and, with a
## region, the world turn moves on (TacticsWorld.finish_region()). Empty
## Dictionary outside the world map.
func finish_region(is_won: bool) -> Dictionary:
	for item: TacticsItemData in items_used:
		roster.items[String(item.id)] = maxi(roster.get_item_count(item.id) - 1, 0)
		if roster.get_item_count(item.id) == 0:
			roster.items.erase(String(item.id))
	if region_id == &"":
		return {}
	return roster.world.finish_region(region_id, is_won)


## The scenario's side goals: [{kind, value, supplies, is_met}].
func _goal_rows(met: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var objective := scenario.objective
	if objective == null:
		return rows
	for index: int in objective.goals.size():
		var goal: TacticsGoalData = objective.goals[index]
		rows.append({"kind": goal.kind, "value": goal.value, "supplies": goal.supplies, "is_met": met.has(index)})
	return rows


## Whether the muster can buy one more reserve soldier now: the scenario
## names one and the roster has the supplies.
func can_hire_reserve() -> bool:
	return scenario.reserve_troop != null and roster.supplies >= scenario.reserve_cost


## Buys the scenario's reserve soldier for `leader_id`: a new roster person
## (face and all); returns its id, or -1 without enough supplies.
func hire_reserve(leader_id: StringName) -> int:
	if not can_hire_reserve():
		return -1
	roster.supplies -= scenario.reserve_cost
	return int(roster.recruit(scenario.reserve_troop.id, leader_id)["id"])


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


# Fills the slots, adds the named and returning leaders and the hired
# soldiers, then the items and the enemy's pressure.
func _build(base: TacticsScenarioData) -> void:
	scenario = base.duplicate() as TacticsScenarioData
	var leaders_a: Array[TacticsLeaderData] = []
	leaders_a.assign(base.leaders_a)
	var leaders_b: Array[TacticsLeaderData] = []
	leaders_b.assign(base.leaders_b)
	var taken := {}
	# Named soldiers lead while spare spawn cells last (lowest ids first);
	# the others fight in a squad of their troop rather than sit out.
	var leading: Array[Dictionary] = []
	for person: Dictionary in roster.get_named():
		if leading.size() < _room(scenario.map.spawn_cells_a.size(), leaders_a.size()):
			leading.append(person)
			taken[person["id"]] = true
	for slot: int in base.leaders_a.size():
		var leader: TacticsLeaderData = base.leaders_a[slot]
		var squad: Array[TacticsTroopData] = []
		var ids: Array[int] = []
		# The scenario's supplied soldiers, else the leader's own squad.
		for troop: TacticsTroopData in base.get_squad(SIDE_A, slot):
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
	for person: Dictionary in leading:
		var leader := make_leader(person)
		leaders_a.append(leader)
		runtime_leaders.append(leader)
		var empty_squad: Array[TacticsTroopData] = []
		var empty_ids: Array[int] = []
		squads.append(empty_squad)
		people.append(empty_ids)
		leader_people.append(int(person["id"]))
	var room_b := _room(scenario.map.spawn_cells_b.size(), leaders_b.size())
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
	scenario.leaders_a = _boosted(leaders_a)
	scenario.leaders_b = _pressed(leaders_b)
	_press_waves()
	_add_hired(taken)
	for leader: TacticsLeaderData in runtime_leaders:
		text.register_unit(leader)
		bio.leader_names[leader.id] = leader.name_key


# Our leaders with the used items' percents added (copies; the scenario's
# own leaders are shared resources).
func _boosted(leaders: Array[TacticsLeaderData]) -> Array[TacticsLeaderData]:
	if items_used.is_empty():
		return leaders
	var boosted: Array[TacticsLeaderData] = []
	for leader: TacticsLeaderData in leaders:
		var copy := leader.duplicate() as TacticsLeaderData
		for item: TacticsItemData in items_used:
			if item.stat == &"stat.hp_pct":
				copy.hp_pct += copy.hp_pct * item.amount / 100
			else:
				copy.attack_pct += copy.attack_pct * item.amount / 100
		boosted.append(copy)
	return boosted


# The enemy's leaders and soldiers at enemy_power_pct of their hp and
# attack (copies).
func _pressed(leaders: Array[TacticsLeaderData]) -> Array[TacticsLeaderData]:
	if enemy_power_pct == 100:
		return leaders
	var pressed: Array[TacticsLeaderData] = []
	for leader: TacticsLeaderData in leaders:
		var copy := _scaled(leader, enemy_power_pct) as TacticsLeaderData
		var squad: Array[TacticsTroopData] = []
		for troop: TacticsTroopData in leader.squad:
			squad.append(_scaled(troop, enemy_power_pct) as TacticsTroopData)
		copy.squad = squad
		pressed.append(copy)
	return pressed


# The objective's waves (hold the city) come at the same pressure as the
# enemy on the map: copies of the objective and its waves.
func _press_waves() -> void:
	if enemy_power_pct == 100 or scenario.objective == null or scenario.objective.waves.is_empty():
		return
	var objective := scenario.objective.duplicate() as TacticsObjectiveData
	var waves: Array[TacticsWaveData] = []
	for wave: TacticsWaveData in objective.waves:
		var copy := wave.duplicate() as TacticsWaveData
		copy.leaders = _pressed(wave.leaders)
		waves.append(copy)
	objective.waves = waves
	scenario.objective = objective


static func _scaled(unit: TacticsUnitData, pct: int) -> TacticsUnitData:
	var copy := unit.duplicate() as TacticsUnitData
	copy.hp_pct = unit.hp_pct * pct / 100
	copy.attack_pct = unit.attack_pct * pct / 100
	return copy


# Soldiers bought at a market join our leaders with room (in order), the
# lowest ids first; capacities come from the rules in C++.
func _add_hired(taken: Dictionary) -> void:
	var hired := roster.get_hired(taken)
	if hired.is_empty():
		return
	var capacities := get_capacities()
	for person: Dictionary in hired:
		for slot: int in squads.size():
			if slot < capacities.size() and (squads[slot] as Array).size() < capacities[slot]:
				squads[slot].append(catalog.get_troop(person["troop"]))
				people[slot].append(int(person["id"]))
				taken[person["id"]] = true
				break


## How many hired soldiers the muster of `base` can place: the room our
## leaders' squads have past the soldiers the scenario gives them, and the
## squads of the named soldiers who would lead. Reads the roster, changes
## nothing.
static func hire_room(tactics_roster: TacticsRoster, tactics_catalog: TacticsCatalog, base: TacticsScenarioData) -> int:
	var room := 0
	var scratch := TacticsBattle.new()
	if scratch.load_scenario(base):
		var slot := 0
		for state: Dictionary in scratch.get_units():
			if state["role"] == &"leader" and state["side"] == SIDE_A:
				room += maxi(int(state["capacity"]) - base.get_squad(SIDE_A, slot).size(), 0)
				slot += 1
	scratch.free()
	var spare_leaders := mini(base.map.spawn_cells_a.size(), base.rules.max_leaders_per_side) - base.leaders_a.size()
	return room + mini(tactics_roster.get_named().size(), maxi(spare_leaders, 0)) * tactics_catalog.incident_rules.named_lead_capacity


## The squad capacity of each of our leaders in the mustered scenario.
func get_capacities() -> Array[int]:
	var capacities: Array[int] = []
	var scratch := TacticsBattle.new()
	if scratch.load_scenario(scenario):
		for state: Dictionary in scratch.get_units():
			if state["role"] == &"leader" and state["side"] == SIDE_A:
				capacities.append(int(state["capacity"]))
	scratch.free()
	return capacities


# Leaders a side can still add: a spawn cell each, within the rules' cap.
func _room(spawn_cells: int, leaders: int) -> int:
	return mini(spawn_cells, scenario.rules.max_leaders_per_side) - leaders


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
