extends SceneTree
## Plays every world region with Auto (TacticsAutoResolve) on rosters of
## many seeds, at each pressure level, and prints the win rate, how many
## of ours end up wounded and the supplies paid, so Auto can be tuned
## against the Thủ công win rates of Tools/tactics_brain_probe.gd (see
## Docs/systems/tactics_world.md, "Balance"). `--veteran=N` gives each
## roster N named soldiers (marks enough to lead, of a good incident, troops
## in the catalog's order) and both items, as a roster some battles in;
## `--rematch` plays each region twice in a row and counts the second
## battle, fought without the soldiers the first one wounded.
## Run: godot --headless --path . --script res://Tools/tactics_world_probe.gd -- --battles=100 [--region=region.ferry] [--veteran=3] [--rematch]

const CATALOG_PATH: String = "res://Data/Tactics/tactics_catalog.tres"
const VETERAN_INCIDENT: StringName = &"incident.stand"


func _initialize() -> void:
	var battles := 100
	var only := &""
	var veterans := 0
	var is_rematch := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--battles="):
			battles = maxi(int(arg.trim_prefix("--battles=")), 1)
		elif arg.begins_with("--region="):
			only = StringName(arg.trim_prefix("--region="))
		elif arg.begins_with("--veteran="):
			veterans = maxi(int(arg.trim_prefix("--veteran=")), 0)
		elif arg == "--rematch":
			is_rematch = true
	var data := load(TacticsWorldData.PATH) as TacticsWorldData
	for problem: String in data.validate():
		push_error(problem)
	var catalog := load(CATALOG_PATH) as TacticsCatalog
	var started := Time.get_ticks_msec()
	print("Tactics world probe: Auto on %d seeds per region and pressure, %d veterans%s" % [battles, veterans, ", the rematch counted" if is_rematch else ""])
	for region: TacticsRegionData in data.regions:
		if region.is_home() or (only != &"" and region.id != only):
			continue
		for level: int in data.max_pressure + 1:
			var wins := 0
			var wounded := 0
			var supplies := 0
			for seed_value: int in range(1, battles + 1):
				var roster := _roster(seed_value, veterans, catalog, data)
				var plan := {"region": region.id, "enemy_power_pct": 100 + data.pressure_step_pct * level, "items": _items(roster, data)}
				var summary := _fight(roster, catalog, region, plan)
				if is_rematch:
					plan["items"] = _items(roster, data)
					summary = _fight(roster, catalog, region, plan)
				wins += 1 if summary["is_won"] else 0
				wounded += (summary["wounded"] as Array).size()
				supplies += int(summary["supplies"])
			print("  %s pressure %d: Auto wins %d / %d (%.0f%%), wounded per battle %.1f, supplies per battle %.2f" % [
				region.id, level, wins, battles, 100.0 * wins / battles, float(wounded) / battles, float(supplies) / battles,
			])
	print("  done in %d ms" % (Time.get_ticks_msec() - started))
	quit()


func _fight(roster: TacticsRoster, catalog: TacticsCatalog, region: TacticsRegionData, plan: Dictionary) -> Dictionary:
	var campaign := TacticsCampaign.new(roster, catalog, region.scenario, plan)
	return campaign.apply_auto(TacticsAutoResolve.resolve(campaign), false)


# A fresh roster, with `veterans` named soldiers and one of each item when
# veterans > 0.
func _roster(seed_value: int, veterans: int, catalog: TacticsCatalog, data: TacticsWorldData) -> TacticsRoster:
	var roster := TacticsRoster.create(seed_value)
	for index: int in veterans:
		var troop: TacticsTroopData = catalog.troops[index % catalog.troops.size()]
		var person := roster.recruit(troop.id, &"")
		for mark: int in catalog.incident_rules.marks_to_name:
			person["marks"].append({"incident": VETERAN_INCIDENT, "leader_id": &"", "terrain": &"", "round": 1, "battle": 0})
		person["is_named"] = true
	if veterans > 0:
		for item: TacticsItemData in data.items:
			roster.items[String(item.id)] = 1
	return roster


func _items(roster: TacticsRoster, data: TacticsWorldData) -> Array:
	var held: Array = []
	for item: TacticsItemData in data.items:
		if roster.get_item_count(item.id) > 0:
			held.append(item)
	return held
