extends SceneTree

# Headless test of the muster screen ("Điểm binh") through Main: the
# title's "Chiến Dịch" opens it, it lists our leaders with their squads and
# capacities (from the battle rules), a soldier moves between leaders
# while there is room and is refused when the leader is full, and
# "Xuất quân" opens the tactics screen with the squads as mustered.

const SLIDE_WAIT_SEC: float = 0.5

var _main: Node


func _initialize() -> void:
	RunSettings.path = "user://settings_muster_test.json"
	var ok := await _run()
	if _main != null:
		_main.queue_free()
	await process_frame
	if ok:
		print("Muster test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not ClassDB.class_exists("TacticsBattle"):
		push_error("TacticsBattle is missing: build the GDExtension (scons) before importing")
		return false
	_main = (load("res://Scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await process_frame
	var title := _main.current_screen as TitleScreen
	if title == null:
		push_error("Main should start on the title")
		return false
	title.campaign_requested.emit()
	await create_timer(SLIDE_WAIT_SEC).timeout
	var muster := _main.current_screen as MusterScreen
	if muster == null:
		push_error("Chiến Dịch should open the muster screen")
		return false
	return await _check_muster(muster)


func _check_muster(muster: MusterScreen) -> bool:
	var leaders := muster.scenario.leaders_a
	for slot: int in leaders.size():
		if muster.get_squad(slot).size() != leaders[slot].squad.size():
			push_error("Leader %d should start with its scenario squad" % slot)
			return false
	# Lạc Hồng leads one more than its squad (drilled ranks); the others are full.
	if muster.get_capacity(0) != leaders[0].squad.size() + 1:
		push_error("Lạc Hồng should have room for one more, capacity %d" % muster.get_capacity(0))
		return false
	var moved: TacticsTroopData = muster.get_squad(1)[0]
	muster.select_soldier(1, 0)
	if muster.get_picked() != Vector2i(1, 0):
		push_error("The tapped soldier should be picked")
		return false
	if muster.move_selected_to(2):
		push_error("A full leader should refuse the soldier")
		return false
	if not muster.move_selected_to(0):
		push_error("A leader with room should take the soldier")
		return false
	if muster.get_squad(0).back() != moved or muster.get_squad(1).size() != leaders[1].squad.size() - 1:
		push_error("The soldier should have moved from leader 1 to leader 0")
		return false
	muster.select_soldier(1, 0)
	if muster.move_selected_to(0):
		push_error("Lạc Hồng is full now and should refuse")
		return false
	muster.select_soldier(1, 0)
	if muster.get_picked() != Vector2i(-1, -1):
		push_error("Picking the same soldier again should put it back")
		return false
	muster.start_battle()
	await create_timer(SLIDE_WAIT_SEC).timeout
	var screen := _main.current_screen as TacticsScreen
	if screen == null or screen.get_battle() == null:
		push_error("Xuất quân should open the tactics screen")
		return false
	var states := screen.get_battle().get_units()
	var squad_sizes: Array[int] = []
	for state: Dictionary in states:
		if state["role"] == &"leader" and state["side"] == 0:
			squad_sizes.append((state["soldiers"] as Array).size())
	if squad_sizes != [leaders[0].squad.size() + 1, leaders[1].squad.size() - 1, leaders[2].squad.size()]:
		push_error("The battle should use the mustered squads, got %s" % [squad_sizes])
		return false
	screen.retreat()
	screen.retreat()
	await create_timer(SLIDE_WAIT_SEC).timeout
	if not _main.current_screen is TitleScreen:
		push_error("Retreating twice should go back to the title")
		return false
	return true
