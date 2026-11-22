extends SceneTree

# Headless tests of the Chiến Dịch world map (Docs/systems/tactics_world.md):
# the world data is valid; a fresh world has the home, two open regions and
# the rest locked; the enemy's declared push follows the roster seed and is
# one of the candidates; a won region is ours and opens its neighbours, a
# push elsewhere hardens its region (up to the cap) or takes back a region
# of ours, which can then be defended; a lost defence gives it up; a
# finished campaign starts the next with more pressure. The roster save
# keeps the world, bonds, items, wounds and hires; a version 1 save loads
# with a fresh world; a broken world is set aside; a save naming unknown
# regions loads without them. A push is heard once (a new one is not; the
# save keeps it). Pressure reaches the hold-the-city waves. Auto resolves
# through the auto battle the same way twice and the same played in slices
# (its fortune of war in bounds), kills no one, wounds the fallen for
# one battle (they sit out the next muster), pays the region's supplies on
# a win only and leaves no marks or bonds. Markets sell at their own
# prices and stock, refuse without supplies, stock, a wounded soldier or a
# region of ours, heal, hire (the hire joins the next muster) and sell
# items, which the next battle uses up. Bonds: the C++ refuses bad bonds,
# gives a leader the bond's attack while its partner is near (source
# "bond" in the forecast), tallies the phases leaders end close together,
# hashes the same on the same seed; the roster turns tallies into points
# (capped per battle) and levels, and a real battle sets them up.

const CATALOG_PATH: String = "res://Data/Tactics/tactics_catalog.tres"
const SAVE_PATH: String = "user://tactics_world_test.json"
const FERRY: StringName = &"region.ferry"
const MISTY: StringName = &"region.misty_woods"
const CITADEL: StringName = &"region.old_citadel"
const HORSE: StringName = &"region.horse_post"
const SIEGE: StringName = &"region.siege_pass"
const HOME: StringName = &"region.home"
const Kit := preload("res://Tests/tactics_test_kit.gd")

var _catalog: TacticsCatalog
var _data: TacticsWorldData
var _battles: Array[TacticsBattle] = []
var _kit := Kit.new()


func _initialize() -> void:
	TranslationServer.set_locale("vi")
	TacticsRoster.path = SAVE_PATH
	var ok := _run()
	for battle: TacticsBattle in _battles:
		battle.free()
	_kit.free_battles()
	TacticsRoster.delete()
	if ok:
		print("Tactics world test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not ClassDB.class_exists("TacticsBattle"):
		push_error("TacticsBattle is missing: build the GDExtension (scons) before importing")
		return false
	if not _kit.load_catalog():
		return false
	_catalog = load(CATALOG_PATH) as TacticsCatalog
	_data = load(TacticsWorldData.PATH) as TacticsWorldData
	var checks: Array[Callable] = [
		_check_data, _check_fresh_world, _check_threat_seeded, _check_win_opens, _check_harden, _check_take_and_defend,
		_check_new_cycle, _check_save_round_trip, _check_old_save, _check_broken_world, _check_threat_heard, _check_auto_deterministic,
		_check_auto_in_slices, _check_waves_pressed, _check_unknown_regions,
		_check_auto_no_permadeath, _check_auto_rewards, _check_market_prices, _check_market_refusals, _check_market_heal,
		_check_market_hire_joins, _check_items_used, _check_bond_refusals, _check_bond_bonus, _check_bond_tallies,
		_check_bond_levels, _check_campaign_bonds,
	]
	for check: Callable in checks:
		if not check.call():
			push_error("Tactics world test failed in %s" % check.get_method())
			return false
	return true


func _expect(what: String, actual: Variant, expected: Variant) -> bool:
	if actual == expected:
		return true
	push_error("Tactics world test: %s: got %s, expected %s" % [what, actual, expected])
	return false


func _roster(seed_value: int = 11) -> TacticsRoster:
	var roster := TacticsRoster.create(seed_value)
	return roster


func _campaign(roster: TacticsRoster, region_id: StringName, enemy_pct: int = -1, items: Array = []) -> TacticsCampaign:
	var region := roster.world.data.get_region(region_id)
	var pct := enemy_pct if enemy_pct > 0 else roster.world.get_enemy_power_pct(region_id)
	return TacticsCampaign.new(roster, _catalog, region.scenario, {"region": region_id, "enemy_power_pct": pct, "items": items})


func _battle_for(campaign: TacticsCampaign) -> TacticsBattle:
	var battle := TacticsBattle.new()
	_battles.append(battle)
	if not battle.load_scenario_with_squads(campaign.scenario, 0, campaign.squads):
		push_error("Tactics world test: the mustered scenario did not load")
	return battle


func _leaders(battle: TacticsBattle, side: int) -> Array[int]:
	var found: Array[int] = []
	for state: Dictionary in battle.get_units():
		if state["role"] == &"leader" and state["start_side"] == side:
			found.append(int(state["index"]))
	return found


# --- The world ---------------------------------------------------------

func _check_data() -> bool:
	var problems := _data.validate()
	if not problems.is_empty():
		push_error("Tactics world test: %s" % "; ".join(problems))
		return false
	var scenarios := {}
	for region: TacticsRegionData in _data.regions:
		if not region.is_home():
			scenarios[region.scenario.resource_path] = true
	return _expect("regions besides the home", _data.regions.size() - 1, 5) and _expect("one region per battle", scenarios.size(), 5)


func _check_fresh_world() -> bool:
	var world := _roster().world
	var states := {}
	for region: TacticsRegionData in world.data.regions:
		states[region.id] = world.get_state(region.id)
	return _expect("home", states[HOME], TacticsWorld.STATE_HOME) and _expect("ferry", states[FERRY], TacticsWorld.STATE_OPEN) \
			and _expect("misty woods", states[MISTY], TacticsWorld.STATE_OPEN) and _expect("citadel", states[CITADEL], TacticsWorld.STATE_LOCKED) \
			and _expect("horse post", states[HORSE], TacticsWorld.STATE_LOCKED) and _expect("siege pass", states[SIEGE], TacticsWorld.STATE_LOCKED) \
			and _expect("a locked region cannot be fought", world.can_fight(CITADEL), false) and _expect("an open one can", world.can_fight(FERRY), true) \
			and _expect("the home has no fight", world.can_fight(HOME), false) and _expect("not complete", world.is_complete(), false)


func _check_threat_seeded() -> bool:
	var seen := {}
	for seed_value: int in range(1, 40):
		var first := _roster(seed_value).world
		var second := _roster(seed_value).world
		var threat := first.get_threat()
		if threat != second.get_threat() or not first.get_threat_candidates().has(threat):
			push_error("Tactics world test: seed %d threat %s is not stable or not a candidate" % [seed_value, threat])
			return false
		seen[threat] = true
	# Both open regions come up over the seeds: the push is not fixed.
	return _expect("both open regions are pressed on some seed", seen.size(), 2)


func _check_win_opens() -> bool:
	var world := _roster().world
	var change := world.finish_region(FERRY, true)
	return _expect("taken", change["taken"], true) and _expect("ferry ours", world.get_state(FERRY), TacticsWorld.STATE_OURS) \
			and _expect("citadel opens", world.get_state(CITADEL), TacticsWorld.STATE_OPEN) and _expect("horse post opens", world.get_state(HORSE), TacticsWorld.STATE_OPEN) \
			and _expect("siege pass still locked", world.get_state(SIEGE), TacticsWorld.STATE_LOCKED) and _expect("turn", world.turn, 1) \
			and _expect("ferry can be shopped", world.can_shop(FERRY), true) and _expect("next threat named", change["threat"], world.get_threat())


func _check_harden() -> bool:
	var world := _roster().world
	world.threat = MISTY
	var change := world.finish_region(FERRY, false)
	if not (_expect("misty hardened", change["hardened"], MISTY) and _expect("level", world.get_pressure(MISTY), 1) \
			and _expect("enemy power", world.get_enemy_power_pct(MISTY), 100 + _data.pressure_step_pct) and _expect("lost ferry stays open", world.get_state(FERRY), TacticsWorld.STATE_OPEN)):
		return false
	for turn: int in 5:
		world.threat = MISTY
		world.finish_region(FERRY, false)
	if not _expect("pressure capped", world.get_pressure(MISTY), _data.max_pressure):
		return false
	# Winning there clears it.
	world.finish_region(MISTY, true)
	return _expect("won region has no pressure", world.get_pressure(MISTY), 0)


func _check_take_and_defend() -> bool:
	var world := _roster().world
	world.finish_region(FERRY, true)
	world.threat = FERRY
	if not (_expect("a threatened region of ours can be fought", world.can_fight(FERRY), true) and _expect("kind", world.get_threat_kind(), TacticsWorld.THREAT_TAKE)):
		return false
	var change := world.finish_region(MISTY, true)
	if not (_expect("ferry lost", change["lost"], [FERRY]) and _expect("ferry open again", world.get_state(FERRY), TacticsWorld.STATE_OPEN) \
			and _expect("its market closes", world.can_shop(FERRY), false) and _expect("lost region pressed", world.get_pressure(FERRY), 1)):
		return false
	# Defending and losing gives it up too; defending and winning keeps it.
	world.finish_region(FERRY, true)
	world.threat = FERRY
	var lost := world.finish_region(FERRY, false)
	if not _expect("lost defence", lost["lost"], [FERRY]):
		return false
	world.finish_region(FERRY, true)
	world.threat = FERRY
	var kept := world.finish_region(FERRY, true)
	return _expect("kept", kept["lost"], []) and _expect("still ours", world.get_state(FERRY), TacticsWorld.STATE_OURS)


func _check_new_cycle() -> bool:
	var world := _roster().world
	for id: StringName in [FERRY, MISTY, CITADEL, HORSE, SIEGE]:
		world.threat = &""
		world.finish_region(id, true)
	if not (_expect("complete", world.is_complete(), true) and _expect("no threat when all is ours", world.get_threat(), &"")):
		return false
	world.start_new_cycle()
	return _expect("cycle", world.cycle, 1) and _expect("regions back to the enemy", world.cleared, []) \
			and _expect("pressure on every region", world.get_pressure(SIEGE), _data.cycle_pressure) and _expect("a push again", world.get_threat() != &"", true)


# --- The save ----------------------------------------------------------

func _check_save_round_trip() -> bool:
	var roster := _roster(5)
	var person := roster.recruit(&"troop.spearman", &"leader.lac_hong")
	person["rest_until"] = 4
	person["is_hired"] = true
	roster.world.finish_region(FERRY, true)
	roster.world.pressure[MISTY] = 2
	roster.world.note_sold(FERRY, 1)
	roster.bonds.append({"a": &"leader.a", "b": &"leader.b", "points": 6})
	roster.items["item.war_drum"] = 2
	var threat := roster.world.get_threat()
	if not roster.save():
		return false
	var loaded := TacticsRoster.load_roster()
	var again := loaded.get_person(person["id"])
	return _expect("cleared", loaded.world.cleared, [FERRY]) and _expect("pressure", loaded.world.get_pressure(MISTY), 2) and _expect("threat not heard", loaded.world.is_threat_heard, false) \
			and _expect("threat", loaded.world.get_threat(), threat) and _expect("turn", loaded.world.turn, 1) and _expect("sold", loaded.world.get_sold(FERRY, 1), 1) \
			and _expect("bond points", TacticsBonds.find_bond(loaded, &"leader.b", &"leader.a").get("points"), 6) \
			and _expect("items", loaded.get_item_count(&"item.war_drum"), 2) and _expect("rest", again["rest_until"], 4) and _expect("hired", again["is_hired"], true) \
			and _expect("world seed", loaded.world.seed_value, 5)


func _check_old_save() -> bool:
	var roster := _roster(8)
	roster.recruit(&"troop.spearman", &"leader.lac_hong")
	roster.supplies = 3
	var old := roster.to_save_data()
	old["version"] = 1
	for key: String in ["world", "bonds", "items"]:
		old.erase(key)
	for entry: Dictionary in old["people"]:
		entry.erase("rest_until")
		entry.erase("is_hired")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	var loaded := TacticsRoster.load_roster()
	if not (_expect("kept aside", FileAccess.file_exists(SAVE_PATH + TacticsRoster.UNREADABLE_SUFFIX), false) and _expect("people", loaded.people.size(), 1) \
			and _expect("supplies", loaded.supplies, 3) and _expect("fresh world", loaded.world.cleared, []) and _expect("world seed", loaded.world.seed_value, 8) \
			and _expect("no bonds", loaded.bonds, []) and _expect("not resting", loaded.is_resting(loaded.people[0]), false)):
		return false
	# Saved again it is version 2.
	loaded.save()
	return _expect("written as version 2", int(JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))["version"]), TacticsRoster.VERSION)


func _check_broken_world() -> bool:
	var saved := _roster(3).to_save_data()
	saved["world"] = {"cleared": [1, 2], "pressure": {}, "sold": {}, "threat": "", "turn": 0, "cycle": 0, "has_threat": false}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved))
	file.close()
	var loaded := TacticsRoster.load_roster()
	var kept := FileAccess.file_exists(SAVE_PATH + TacticsRoster.UNREADABLE_SUFFIX)
	TacticsRoster.delete()
	return _expect("a broken world sets the save aside", kept, true) and _expect("and starts empty", loaded.people, [])


# A push is heard once: a new one (a turn, a new campaign) is not heard
# yet; the save keeps it; a save without the field hears it once more.
func _check_threat_heard() -> bool:
	var roster := _roster(12)
	var world := roster.world
	world.get_threat()
	if not _expect("a fresh push is not heard", world.is_threat_heard, false):
		return false
	world.is_threat_heard = true
	roster.save()
	var loaded := TacticsRoster.load_roster()
	if not _expect("heard is saved", loaded.world.is_threat_heard, true):
		return false
	loaded.world.finish_region(FERRY, true)
	if not _expect("a turn declares a new push", loaded.world.is_threat_heard, false):
		return false
	var saved := roster.to_save_data()
	(saved["world"] as Dictionary).erase("threat_heard")
	var old := TacticsWorld.new()
	if not (_expect("reads without it", old.read(saved["world"]), true) and _expect("not heard", old.is_threat_heard, false)):
		return false
	saved["world"]["threat_heard"] = "yes"
	return _expect("a bad value is refused", TacticsWorld.new().read(saved["world"]), false)


# A save naming regions the data does not have, the home as ours or
# pressure past the cap loads with those left out, not set aside.
func _check_unknown_regions() -> bool:
	var saved := _roster(13).to_save_data()
	saved["world"] = {
		"cleared": ["region.gone", String(FERRY), String(FERRY), String(HOME)], "pressure": {"region.gone": 1, String(MISTY): 9}, "sold": {},
		"threat": "region.gone", "turn": 2, "cycle": 0, "has_threat": true,
	}
	var world := TacticsWorld.new()
	world.seed_value = 13
	return _expect("reads", world.read(saved["world"]), true) and _expect("only known regions, once", world.cleared, [FERRY]) \
			and _expect("pressure capped", world.get_pressure(MISTY), _data.max_pressure) and _expect("unknown pressure gone", world.pressure.has(&"region.gone"), false) \
			and _expect("a known push again", world.get_threat_candidates().has(world.get_threat()), true)


# --- Auto --------------------------------------------------------------

func _check_auto_deterministic() -> bool:
	var roster := _roster(21)
	var first := TacticsAutoResolve.resolve(_campaign(roster, FERRY))
	var second := TacticsAutoResolve.resolve(_campaign(_roster(21), FERRY))
	var placed: int = first["counts"][0][1]
	var rolls := {}
	for seed_value: int in range(1, 60):
		var roll := TacticsAutoResolve.fortune_pct(seed_value, _data.auto_fortune_pct)
		if absi(roll) > _data.auto_fortune_pct:
			push_error("Tactics world test: fortune %d is past the limit" % roll)
			return false
		rolls[roll] = true
	return _expect("the fortune of war varies by seed", rolls.size() > 10, true) and _expect("same fortune", first["fortune"], second["fortune"]) \
			and _expect("no fortune at 0", TacticsAutoResolve.fortune_pct(7, 0), 0) and _expect("same hash", first["hash"], second["hash"]) and _expect("same winner", first["winner"], second["winner"]) \
			and _expect("units placed", placed > 0 and placed <= 10, true) and _expect("rows", (first["units"] as Array).size(), placed + int(first["counts"][1][1]))


# Played a slice at a time (as the world screen does) Auto ends exactly as
# resolve() does, and shows who stands as it goes.
func _check_auto_in_slices() -> bool:
	var whole := TacticsAutoResolve.resolve(_campaign(_roster(23), MISTY))
	var auto := TacticsAutoResolve.new()
	auto.start(_campaign(_roster(23), MISTY))
	var placed := auto.get_placed_counts()
	if not (_expect("all stand at first", auto.get_alive_counts(), placed) and _expect("no result yet", auto.get_result(), {})):
		return false
	var slices := 0
	var fewer := false
	while not auto.advance(TacticsAutoResolve.TICKS_PER_CHUNK):
		slices += 1
		var alive := auto.get_alive_counts()
		fewer = fewer or alive[0] < placed[0] or alive[1] < placed[1]
	var sliced := auto.get_result()
	return _expect("many slices", slices > 5, true) and _expect("units fall as it goes", fewer, true) and _expect("same hash", sliced["hash"], whole["hash"]) \
			and _expect("same ticks", sliced["ticks"], whole["ticks"]) and _expect("same counts", sliced["counts"], whole["counts"]) \
			and _expect("same fortune", auto.get_fortune(), whole["fortune"]) and _expect("finished", auto.advance(1), true)


# Pressure reaches the waves that come later (hold the city) too, on copies.
func _check_waves_pressed() -> bool:
	var base := load("res://Data/Tactics/Scenarios/city_defense.tres") as TacticsScenarioData
	var campaign := TacticsCampaign.new(_roster(), _catalog, base, {"region": CITADEL, "enemy_power_pct": 130})
	var wave_leader: TacticsLeaderData = campaign.scenario.objective.waves[0].leaders[0]
	var base_leader: TacticsLeaderData = base.objective.waves[0].leaders[0]
	return _expect("wave leader hp", wave_leader.hp_pct, base_leader.hp_pct * 130 / 100) and _expect("wave leader attack", wave_leader.attack_pct, base_leader.attack_pct * 130 / 100) \
			and _expect("wave squad hp", wave_leader.squad[0].hp_pct, base_leader.squad[0].hp_pct * 130 / 100) \
			and _expect("the data untouched", (base.objective.waves[0].leaders[0] as TacticsLeaderData).hp_pct, base_leader.hp_pct) \
			and _expect("same rounds", campaign.scenario.objective.waves[0].round, base.objective.waves[0].round)


func _check_auto_no_permadeath() -> bool:
	var roster := _roster(31)
	# A strong enemy: many of ours fall.
	var campaign := _campaign(roster, MISTY, 260)
	var result := TacticsAutoResolve.resolve(campaign)
	var summary := campaign.apply_auto(result, false)
	var wounded: Array = summary["wounded"]
	if not _expect("lost", summary["is_won"], false) or not _expect("someone was wounded", wounded.is_empty(), false):
		return false
	for person: Dictionary in roster.people:
		if person["status"] != "active" or not (person["marks"] as Array).is_empty():
			push_error("Tactics world test: Auto left %s %s with marks %s" % [person["id"], person["status"], person["marks"]])
			return false
	for id: int in wounded:
		if not _expect("rest", roster.get_person(id)["rest_until"], roster.battles + _data.wound_rest_battles):
			return false
	# The next muster leaves the wounded out; the one after has them back.
	var next := _campaign(roster, FERRY)
	for squad: Array in next.people:
		for id: int in squad:
			if wounded.has(id):
				push_error("Tactics world test: wounded %d was mustered" % id)
				return false
	next.apply_auto(TacticsAutoResolve.resolve(next), false)
	var back := 0
	for id: int in wounded:
		back += 0 if roster.is_resting(roster.get_person(id)) else 1
	return _expect("the wounded are back after one battle", back, wounded.size()) and _expect("no bonds from Auto", roster.bonds, [])


func _check_auto_rewards() -> bool:
	var roster := _roster(41)
	var campaign := _campaign(roster, FERRY, 30)
	var won := campaign.apply_auto(TacticsAutoResolve.resolve(campaign), false)
	if not (_expect("a weak enemy loses", won["is_won"], true) and _expect("pay", won["supplies"], _data.get_region(FERRY).auto_supplies) \
			and _expect("region taken", roster.world.get_state(FERRY), TacticsWorld.STATE_OURS) and _expect("battles", roster.battles, 1)):
		return false
	var lost_campaign := _campaign(roster, MISTY, 300)
	var lost := lost_campaign.apply_auto(TacticsAutoResolve.resolve(lost_campaign), false)
	# Auto pays less than the side goals of a Thủ công win would.
	var goals := 0
	for goal: TacticsGoalData in _data.get_region(FERRY).scenario.objective.goals:
		goals += goal.supplies
	return _expect("no pay on a loss", lost["supplies"], 0) and _expect("misty not taken", roster.world.get_state(MISTY), TacticsWorld.STATE_OPEN) \
			and _expect("Auto pays less than the side goals", _data.get_region(FERRY).auto_supplies < goals, true)


# --- Markets -----------------------------------------------------------

func _check_market_prices() -> bool:
	var ferry := _data.get_region(FERRY)
	var citadel := _data.get_region(CITADEL)
	var heal_prices: Array[int] = []
	for region: TacticsRegionData in [ferry, citadel]:
		for offer: TacticsOfferData in region.offers:
			if offer.kind == &"offer.heal":
				heal_prices.append(offer.price)
	return _expect("different stock", ferry.offers.size() != citadel.offers.size(), true) and _expect("healing costs differ", heal_prices[0] != heal_prices[1], true)


func _check_market_refusals() -> bool:
	var roster := _roster(51)
	var region := _data.get_region(FERRY)
	var market := TacticsMarket.new(roster, region)
	if not _expect("closed before it is ours", market.refusal(0, -1), TacticsMarket.REASON_CLOSED):
		return false
	roster.world.finish_region(FERRY, true)
	if not _expect("no supplies", market.buy(0)["reason"], TacticsMarket.REASON_SUPPLIES):
		return false
	roster.supplies = 20
	var stock := region.offers[0].stock
	for index: int in stock:
		if not market.buy(0)["ok"]:
			push_error("Tactics world test: buy %d of the ferry's first offer was refused" % index)
			return false
	if not (_expect("sold out", market.buy(0)["reason"], TacticsMarket.REASON_SOLD_OUT) and _expect("spent", roster.supplies, 20 - stock * region.offers[0].price)):
		return false
	var heal := _offer_index(region, &"offer.heal")
	if not _expect("nobody to heal", market.buy(heal)["reason"], TacticsMarket.REASON_NO_WOUNDED):
		return false
	# A new turn restocks.
	roster.world.finish_region(MISTY, false)
	return _expect("restocked", market.refusal(0, -1), &"")


func _check_market_heal() -> bool:
	var roster := _roster(61)
	roster.world.finish_region(FERRY, true)
	roster.supplies = 10
	var person := roster.recruit(&"troop.spearman", &"leader.lac_hong")
	person["rest_until"] = roster.battles + 1
	var market := TacticsMarket.new(roster, _data.get_region(FERRY))
	var result := market.buy(_offer_index(market.region, &"offer.heal"), int(person["id"]))
	return _expect("healed", result["ok"], true) and _expect("patient", result["person"], person["id"]) and _expect("not resting", roster.is_resting(person), false)


func _check_market_hire_joins() -> bool:
	var roster := _roster(71)
	roster.world.finish_region(FERRY, true)
	roster.supplies = 10
	var market := TacticsMarket.new(roster, _data.get_region(FERRY))
	var result := market.buy(0)
	if not (_expect("hired", result["ok"], true) and _expect("is_hired", roster.get_person(result["person"])["is_hired"], true)):
		return false
	var campaign := _campaign(roster, CITADEL)
	for squad: Array in campaign.people:
		if squad.has(result["person"]):
			return true
	push_error("Tactics world test: the hired soldier %d was not in the next muster %s" % [result["person"], campaign.people])
	return false


func _check_items_used() -> bool:
	var roster := _roster(81)
	roster.world.finish_region(FERRY, true)
	roster.world.finish_region(CITADEL, true)
	roster.supplies = 10
	var citadel := _data.get_region(CITADEL)
	var market := TacticsMarket.new(roster, citadel)
	if not _expect("drum bought", market.buy(_offer_index(citadel, &"offer.item"))["ok"], true):
		return false
	var drum := _data.get_item(&"item.war_drum")
	var plain := _campaign(roster, HORSE)
	var boosted := _campaign(roster, HORSE, -1, [drum])
	var plain_attack: int = plain.scenario.leaders_a[0].attack_pct
	var boosted_attack: int = boosted.scenario.leaders_a[0].attack_pct
	if not _expect("drum adds its percent", boosted_attack, plain_attack + plain_attack * drum.amount / 100):
		return false
	boosted.finish_region(true)
	return _expect("used up", roster.get_item_count(&"item.war_drum"), 0) and _expect("removed from store", roster.items.has("item.war_drum"), false)


func _offer_index(region: TacticsRegionData, kind: StringName) -> int:
	for index: int in region.offers.size():
		if region.offers[index].kind == kind:
			return index
	return -1


# --- Bonds -------------------------------------------------------------

func _check_bond_refusals() -> bool:
	var campaign := _campaign(_roster(91), FERRY)
	var battle := _battle_for(campaign)
	var ours := _leaders(battle, 0)
	var theirs := _leaders(battle, 1)
	var soldier := -1
	for state: Dictionary in battle.get_units():
		if state["role"] == &"soldier":
			soldier = int(state["index"])
			break
	var rules := _data.get_bond_rules()
	var bad: Array = [
		[{"a": ours[0], "b": soldier, "level": 1}], [{"a": ours[0], "b": theirs[0], "level": 1}], [{"a": ours[0], "b": ours[0], "level": 1}],
		[{"a": ours[0], "b": ours[1], "level": 0}], [{"a": ours[0], "b": ours[1], "level": 9}],
	]
	for bonds: Array in bad:
		if battle.set_bonds(bonds, rules):
			push_error("Tactics world test: set_bonds accepted %s" % [bonds])
			return false
	if battle.set_bonds([], {"radius_cells": 99}):
		push_error("Tactics world test: set_bonds accepted a radius of 99")
		return false
	battle.start()
	return _expect("no bonds after the start", battle.set_bonds([{"a": ours[0], "b": ours[1], "level": 1}], rules), false)


func _check_bond_bonus() -> bool:
	# Two of ours side by side next to an enemy; a third of ours far off.
	var battles: Array[TacticsBattle] = []
	var ours: Array[int] = []
	var enemy := -1
	for is_bonded: bool in [false, true]:
		var battle := _kit.new_battle(_kit.plain_rows())
		ours = [
			_kit.add(battle, 0, _kit.leader(&"leader.lac_hong"), Vector2i(5, 6)), _kit.add(battle, 0, _kit.leader(&"leader.lieu_mi"), Vector2i(6, 6)),
			_kit.add(battle, 0, _kit.leader(&"leader.lac_hong"), Vector2i(0, 11)),
		]
		enemy = _kit.add(battle, 1, _kit.leader(&"leader.thiet_nha"), Vector2i(5, 5))
		if is_bonded and not battle.set_bonds([{"a": ours[0], "b": ours[1], "level": 2}, {"a": ours[0], "b": ours[2], "level": 1}], {"radius_cells": 2, "attack_pct_per_level": 10, "max_level": 3}):
			return false
		battle.start()
		battles.append(battle)
	var plain := battles[0]
	var bonded := battles[1]
	var bonds := bonded.get_bonds()
	if not (_expect("two bonds", bonds.size(), 2) and _expect("near: active", bonds[0]["is_active"], true) and _expect("far: not", bonds[1]["is_active"], false) \
			and _expect("pct", bonds[0]["attack_pct"], 20)):
		return false
	var before := int(plain.get_unit_state(ours[0])["attack"])
	var after := int(bonded.get_unit_state(ours[0])["attack"])
	if not (_expect("bond raises attack", after > before, true) and _expect("only the near bond counts", after, before * 120 / 100) \
			and _expect("the far one gets nothing", bonded.get_unit_state(ours[2])["attack"], plain.get_unit_state(ours[2])["attack"])):
		return false
	var forecast := bonded.forecast_engagement(ours[0], enemy)
	var plain_forecast := plain.forecast_engagement(ours[0], enemy)
	return _expect("bond in the forecast", (forecast["attacker_modifiers"] as Array).has(&"bond"), true) \
			and _expect("not without it", (plain_forecast["attacker_modifiers"] as Array).has(&"bond"), false) \
			and _expect("more damage", int(forecast["attacker_damage_per_hit"]) > int(plain_forecast["attacker_damage_per_hit"]), true) \
			and _expect("hashes differ with a bond", bonded.get_state_hash() != plain.get_state_hash(), true)


func _check_bond_tallies() -> bool:
	var hashes: Array = []
	var tallies: Array = []
	for attempt: int in 2:
		var campaign := _campaign(_roster(93), FERRY)
		var battle := _battle_for(campaign)
		battle.set_side_ai(0, true)
		if not campaign.prepare_battle(battle, campaign.people):
			return false
		battle.start()
		hashes.append(battle.get_state_hash())
		tallies = battle.get_battle_report().get("bond_tallies", [])
	var leaders := _leaders(_battles.back(), 0)
	var ours := leaders.size()
	var our_pairs := 0
	var phases := 0
	for tally: Dictionary in tallies:
		if leaders.has(int(tally["a"])) and leaders.has(int(tally["b"])):
			our_pairs += 1
			phases += int(tally["phases"])
	return _expect("same seed, same hash", hashes[0], hashes[1]) and _expect("one tally per pair of our leaders", our_pairs, ours * (ours - 1) / 2) \
			and _expect("leaders ended phases close", phases > 0, true)


func _check_bond_levels() -> bool:
	if not (_expect("level 0", TacticsBonds.level_of(2, _data), 0) and _expect("level 1", TacticsBonds.level_of(3, _data), 1) \
			and _expect("level 3", TacticsBonds.level_of(40, _data), 3)):
		return false
	var roster := _roster(94)
	var report := {
		"units": [
			{"unit": 0, "role": &"leader", "start_side": 0, "id": &"leader.b"}, {"unit": 1, "role": &"leader", "start_side": 0, "id": &"leader.a"},
			{"unit": 2, "role": &"leader", "start_side": 1, "id": &"leader.enemy"},
		],
		"bond_tallies": [{"a": 0, "b": 1, "phases": 9}, {"a": 0, "b": 2, "phases": 9}],
	}
	var rows := TacticsBonds.apply_tallies(roster, _data, report)
	if not (_expect("one row (ours only)", rows.size(), 1) and _expect("capped", rows[0]["gained"], _data.bond_points_per_battle) \
			and _expect("pair order", [rows[0]["a"], rows[0]["b"]], [&"leader.a", &"leader.b"]) and _expect("level up", rows[0]["level"], 1)):
		return false
	TacticsBonds.apply_tallies(roster, _data, report)
	TacticsBonds.apply_tallies(roster, _data, report)
	var found := TacticsBonds.bonds_of(roster, _data, &"leader.a")
	return _expect("points", TacticsBonds.find_bond(roster, &"leader.a", &"leader.b")["points"], 3 * _data.bond_points_per_battle) \
			and _expect("bonds_of", found, [{"partner": &"leader.b", "level": 2}])


func _check_campaign_bonds() -> bool:
	var roster := _roster(95)
	var campaign := _campaign(roster, FERRY)
	var battle := _battle_for(campaign)
	var leaders := campaign.scenario.leaders_a
	roster.bonds.append({"a": leaders[0].id, "b": leaders[1].id, "points": 7})
	if String(leaders[1].id) < String(leaders[0].id):
		roster.bonds[0] = {"a": leaders[1].id, "b": leaders[0].id, "points": 7}
	battle.set_side_ai(0, true)
	if not campaign.prepare_battle(battle, campaign.people):
		return false
	var bonds := battle.get_bonds()
	if not (_expect("the roster's bond is set", bonds.size(), 1) and _expect("its level", bonds[0]["level"], 2)):
		return false
	battle.start()
	var summary := campaign.finish_battle(battle, campaign.people, false)
	return _expect("summary rows for bonds", summary.has("bonds"), true) and _expect("world change", summary["world"]["region"], FERRY) \
			and _expect("mode", summary["mode"], &"mode.manual")
