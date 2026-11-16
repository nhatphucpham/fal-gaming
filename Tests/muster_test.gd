extends SceneTree

# Headless test of the muster screen ("Điểm binh") through Main: the
# title's "Chiến Dịch" opens it, it lists our leaders with their squads and
# capacities (from the battle rules), a soldier moves between leaders
# while there is room and is refused when the leader is full, and
# "Xuất quân" opens the tactics screen with the squads as mustered;
# retreating writes the battle into the roster and shows the summary,
# whose "Tiếp tục" opens the muster again. With
# touch, taps on a soldier chip and a leader card move a soldier, and a
# drag that starts on a card or a chip scrolls the page instead.

const SLIDE_WAIT_SEC: float = 0.5

var _main: Node


func _initialize() -> void:
	RunSettings.path = "user://settings_muster_test.json"
	TacticsRoster.path = "user://tactics_roster_muster_test.json"
	TacticsRoster.delete()
	var ok := await _run()
	if _main != null:
		_main.queue_free()
	await process_frame
	TacticsRoster.delete()
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
	if not await _check_muster(muster):
		return false
	# Main's screens would sit above the muster screen made below.
	_main.queue_free()
	_main = null
	await process_frame
	return await _check_touch()


# A muster screen of its own at the 720x1280 layout, driven by pushed taps
# and drags with touch emulated (as on a phone).
func _check_touch() -> bool:
	Input.emulate_touch_from_mouse = true
	var muster := MusterScreen.new()
	muster.scenario = load("res://Data/Tactics/Scenarios/river_crossing.tres") as TacticsScenarioData
	muster.size = Vector2(720, 1280)
	root.add_child(muster)
	await process_frame
	await process_frame
	var scroll := muster.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
	if _card(muster, 0) == null or _card(muster, 1) == null:
		push_error("The muster screen should name its leader cards LeaderCard<slot>")
		return false
	if scroll.get_v_scroll_bar().max_value <= scroll.get_v_scroll_bar().page:
		push_error("The muster page should be taller than the 720x1280 screen for this check")
		return false
	await _drag(_card(muster, 1), Vector2(0, -300))
	var from_card := scroll.scroll_vertical
	scroll.scroll_vertical = 0
	await process_frame
	await _drag(_chip(muster, 1, 0), Vector2(0, -300))
	var from_chip := scroll.scroll_vertical
	if from_card <= 0 or from_chip <= 0 or muster.get_picked() != Vector2i(-1, -1):
		push_error("A drag on a leader card (%d px) or a chip (%d px) should scroll and pick nothing" % [from_card, from_chip])
		return false
	scroll.scroll_vertical = 0
	await process_frame
	_tap(_chip(muster, 1, 0))
	await process_frame
	if muster.get_picked() != Vector2i(1, 0):
		push_error("A tap on a soldier chip should pick it")
		return false
	await _drag(_card(muster, 0), Vector2(0, -300))
	if muster.get_squad(0).size() != muster.scenario.leaders_a[0].squad.size():
		push_error("A drag that ends on a leader card must not move the soldier")
		return false
	scroll.scroll_vertical = 0
	await process_frame
	_tap(_card(muster, 0), Vector2(0.5, 0.1))
	await process_frame
	var moved := muster.get_squad(0).size() == muster.scenario.leaders_a[0].squad.size() + 1
	muster.queue_free()
	Input.emulate_touch_from_mouse = false
	if not moved:
		push_error("A tap on a leader card with room should take the picked soldier")
	return moved


func _card(muster: MusterScreen, slot: int) -> Control:
	return muster.find_child("LeaderCard%d" % slot, true, false) as Control


func _chip(muster: MusterScreen, slot: int, soldier: int) -> Control:
	return _card(muster, slot).find_children("*", "PressButton", true, false)[soldier]


# A tap at a point of the control given as fractions of its size.
func _tap(control: Control, where: Vector2 = Vector2(0.5, 0.5)) -> void:
	var at := root.get_final_transform() * (control.get_global_rect().position + control.size * where)
	for is_pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = is_pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)


# Presses near the control's top, slides by `by` (layout pixels) and lets go.
func _drag(control: Control, by: Vector2) -> void:
	var to_screen := root.get_final_transform()
	var start := to_screen * (control.get_global_rect().position + Vector2(control.size.x * 0.5, 20))
	var step := to_screen.basis_xform(by) / 10.0
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	press.global_position = start
	Input.parse_input_event(press)
	await process_frame
	for index: int in 10:
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.position = start + step * (index + 1)
		motion.global_position = motion.position
		motion.relative = step
		Input.parse_input_event(motion)
		await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = start + step * 10
	release.global_position = release.position
	Input.parse_input_event(release)
	for frame: int in 5:
		await process_frame


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
	var summary := screen.get_summary()
	if summary == null:
		push_error("Retreating twice should show the after-battle summary")
		return false
	if TacticsRoster.load_roster().battles != 1:
		push_error("The retreat should be written into the roster")
		return false
	summary.continue_requested.emit()
	await create_timer(SLIDE_WAIT_SEC).timeout
	var again := _main.current_screen as MusterScreen
	if again == null:
		push_error("The summary's Tiếp tục should open the muster again")
		return false
	again.back_requested.emit()
	await create_timer(SLIDE_WAIT_SEC).timeout
	if not _main.current_screen is TitleScreen:
		push_error("Về should go back to the title")
		return false
	return true
