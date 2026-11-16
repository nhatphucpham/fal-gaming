extends SceneTree

func _initialize() -> void:
	var scenario := load("res://Data/Tactics/Scenarios/night_raid.tres") as TacticsScenarioData
	var catalog := load("res://Data/Tactics/tactics_catalog.tres") as TacticsCatalog
	var battle := TacticsBattle.new()
	root.add_child(battle)
	battle.load_scenario(scenario)
	battle.start()
	var leader := -1
	for state: Dictionary in battle.get_units():
		if state["side"] == 0 and state["role"] == &"leader":
			leader = state["index"]
			break
	var cells := battle.get_reachable_cells(leader)
	var best: Vector2i = cells[0]
	for c: Vector2i in cells:
		if c.y < best.y:
			best = c
	var events := battle.move_leader(leader, best)
	for e: Dictionary in events:
		print(e["type"], " ", e.get("unit", ""), " ", e.get("kind", ""), " cells=", (e.get("cells", []) as Array).size())
	quit(0)
