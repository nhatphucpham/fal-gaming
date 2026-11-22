extends SceneTree
## Plays every world region with Auto (TacticsAutoResolve) on fresh rosters
## of many seeds, at each pressure level, and prints the win rate, how many
## of ours end up wounded and the supplies paid, so Auto can be tuned
## against the Thủ công win rates of Tools/tactics_brain_probe.gd (see
## Docs/systems/tactics_world.md, "Balance").
## Run: godot --headless --path . --script res://Tools/tactics_world_probe.gd -- --battles=100 [--region=region.ferry]

const CATALOG_PATH: String = "res://Data/Tactics/tactics_catalog.tres"


func _initialize() -> void:
	var battles := 100
	var only := &""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--battles="):
			battles = maxi(int(arg.trim_prefix("--battles=")), 1)
		elif arg.begins_with("--region="):
			only = StringName(arg.trim_prefix("--region="))
	var data := load(TacticsWorldData.PATH) as TacticsWorldData
	for problem: String in data.validate():
		push_error(problem)
	var catalog := load(CATALOG_PATH) as TacticsCatalog
	var started := Time.get_ticks_msec()
	print("Tactics world probe: Auto on %d seeds per region and pressure" % battles)
	for region: TacticsRegionData in data.regions:
		if region.is_home() or (only != &"" and region.id != only):
			continue
		for level: int in data.max_pressure + 1:
			var wins := 0
			var wounded := 0
			var supplies := 0
			for seed_value: int in range(1, battles + 1):
				var roster := TacticsRoster.create(seed_value)
				var plan := {"region": region.id, "enemy_power_pct": 100 + data.pressure_step_pct * level}
				var campaign := TacticsCampaign.new(roster, catalog, region.scenario, plan)
				var summary := campaign.apply_auto(TacticsAutoResolve.resolve(campaign), false)
				wins += 1 if summary["is_won"] else 0
				wounded += (summary["wounded"] as Array).size()
				supplies += int(summary["supplies"])
			print("  %s pressure %d: Auto wins %d / %d (%.0f%%), wounded per battle %.1f, supplies per battle %.2f" % [
				region.id, level, wins, battles, 100.0 * wins / battles, float(wounded) / battles, float(supplies) / battles,
			])
	print("  done in %d ms" % (Time.get_ticks_msec() - started))
	quit()
