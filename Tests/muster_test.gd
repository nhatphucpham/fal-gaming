extends SceneTree

# Headless test of the muster screen ("Điểm binh") through Main: the
# title's "Chiến Dịch" opens the world map, whose first region's
# "Thủ công" opens it; it lists our leaders with their squads and
# capacities (from the battle rules), a soldier moves between leaders
# while there is room and is refused when the leader is full, and
# "Xuất quân" opens the tactics screen with the squads as mustered;
# retreating writes the battle into the roster and shows the summary,
# whose "Tiếp tục" goes back to the world map, where the region opens
# the muster again; "Về" goes back to the map, then the title. With
# touch, taps on a soldier chip and a leader card move a soldier, and a
# drag that starts on a card or a chip scrolls the page instead. At the
# 720x1280 layout no text on the muster, roster, character sheet or
# summary is cut or under the game's small font size. Every scenario's
# muster tells its objective in full (no format left unfilled), its side
# goals and sites, and the supplies in store; hiring the reserve soldier
# spends them and puts a new roster person in the first squad with room,
# and is refused without supplies or room. Each scenario's summary shows
# its side goals and the supplies.

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
	var muster := await _muster_from_world(&"region.ferry")
	if muster == null:
		push_error("Chiến Dịch should open the world map, and Bến Đò's Thủ công the muster screen")
		return false
	if not await _check_muster(muster):
		return false
	# Main's screens would sit above the muster screen made below.
	_main.queue_free()
	_main = null
	await process_frame
	return await _check_touch() and await _check_text_fits() and await _check_scenarios()


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
	var again := await _muster_from_world(&"region.ferry")
	if again == null:
		push_error("The summary's Tiếp tục should open the world map, and the region the muster again")
		return false
	again.back_requested.emit()
	await create_timer(SLIDE_WAIT_SEC).timeout
	var world := _main.current_screen as TacticsWorldScreen
	if world == null:
		push_error("The muster's Về should go back to the world map")
		return false
	world.back_requested.emit()
	await create_timer(SLIDE_WAIT_SEC).timeout
	if not _main.current_screen is TitleScreen:
		push_error("The world map's Về should go back to the title")
		return false
	return true


# From the world map Main shows now: the region's card, its Thủ công
# pressed, and the muster that opens (null when any step is missing).
func _muster_from_world(region_id: StringName) -> MusterScreen:
	var world := _main.current_screen as TacticsWorldScreen
	if world == null:
		return null
	var card := world.open_region(region_id)
	if card == null:
		return null
	await process_frame
	var manual := card.find_child("ManualButton", true, false) as BaseButton
	if manual == null:
		return null
	manual.pressed.emit()
	await create_timer(SLIDE_WAIT_SEC).timeout
	return _main.current_screen as MusterScreen


# A roster with marks, a named soldier and a returning traitor, on every
# campaign screen at the 720x1280 layout: no one-line text is cut, none is
# under GameTheme.SMALL_FONT_SIZE, every button is at least 88 px tall.
func _check_text_fits() -> bool:
	Input.emulate_touch_from_mouse = false
	var catalog := load("res://Data/Tactics/tactics_catalog.tres") as TacticsCatalog
	var scenario := load("res://Data/Tactics/Scenarios/river_crossing.tres") as TacticsScenarioData
	var roster := TacticsRoster.create(424242)
	TacticsCampaign.new(roster, catalog, scenario)
	var mark := func(incident: StringName, terrain: StringName, battle: int) -> Dictionary:
		return {"incident": incident, "leader_id": &"leader.lieu_mi", "terrain": terrain, "round": 12, "battle": battle}
	for index: int in 3:
		roster.people[6]["marks"].append(mark.call(&"incident.stand", &"terrain.village", index + 1))
	roster.people[6]["is_named"] = true
	roster.people[2]["marks"].append(mark.call(&"incident.betray", &"terrain.ford", 1))
	roster.people[2]["marks"].append(mark.call(&"incident.discontent", &"terrain.forest", 2))
	roster.people[2]["status"] = "traitor"
	roster.battles = 3
	for count: int in 12:
		roster.recruit(&"troop.kite_scout", &"leader.lieu_mi")
	var campaign := TacticsCampaign.new(roster, catalog, scenario)
	var muster := MusterScreen.new()
	muster.campaign = campaign
	muster.size = Vector2(720, 1280)
	root.add_child(muster)
	await process_frame
	if not await _texts_fit(muster, "muster"):
		return false
	var view := muster.open_roster()
	await create_timer(SLIDE_WAIT_SEC).timeout
	if not await _texts_fit(view, "roster"):
		return false
	for person: Dictionary in [roster.people[6], roster.people[2], roster.people[0]]:
		view.show_sheet(person["id"])
		await create_timer(SLIDE_WAIT_SEC).timeout
		if not await _texts_fit(view, "sheet %d" % person["id"]):
			return false
	muster.queue_free()
	var screen := TacticsScreen.new()
	screen.scenario = campaign.scenario
	screen.squads = campaign.squads
	screen.campaign = campaign
	screen.is_instant = true
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	await process_frame
	screen.retreat()
	screen.retreat()
	await create_timer(SLIDE_WAIT_SEC).timeout
	var ok := await _texts_fit(screen.get_summary(), "summary")
	screen.queue_free()
	await process_frame
	TacticsRoster.delete()
	return ok


func _check_scenarios() -> bool:
	var catalog := load("res://Data/Tactics/tactics_catalog.tres") as TacticsCatalog
	for scenario: TacticsScenarioData in catalog.scenarios:
		var where := String(scenario.id)
		var roster := TacticsRoster.create(777)
		var campaign := TacticsCampaign.new(roster, catalog, scenario)
		roster.supplies = scenario.reserve_cost + 1
		var muster := MusterScreen.new()
		muster.campaign = campaign
		muster.size = Vector2(720, 1280)
		root.add_child(muster)
		await process_frame
		var line := muster.objective_text()
		if line == "" or line.contains("%s") or line.contains("%d"):
			push_error("%s: the objective reads \"%s\"" % [where, line])
			return false
		var panel := muster.find_child("ObjectivePanel", true, false) as Control
		var panel_text := _all_text(panel)
		if scenario.objective != null and not scenario.objective.goals.is_empty() and not panel_text.contains(tr("MUSTER_GOALS_FORMAT").get_slice("%", 0)):
			push_error("%s: the muster does not list the side goals" % where)
			return false
		if not panel_text.contains(tr("MUSTER_SUPPLIES_FORMAT") % roster.supplies):
			push_error("%s: the muster does not show the supplies (%s)" % [where, panel_text])
			return false
		if not await _texts_fit(muster, "muster " + where):
			return false
		var sizes: Array[int] = []
		for slot: int in scenario.leaders_a.size():
			sizes.append(muster.get_squad(slot).size())
		var people_before := roster.people.size()
		var has_room := false
		for slot: int in sizes.size():
			has_room = has_room or sizes[slot] < muster.get_capacity(slot)
		var hired := muster.hire_reserve()
		if hired != has_room:
			push_error("%s: hiring with room %s gave %s" % [where, has_room, hired])
			return false
		if hired:
			if roster.supplies != 1 or roster.people.size() != people_before + 1:
				push_error("%s: a hire should cost %d and add a person (supplies %d, people %d)" % [where, scenario.reserve_cost, roster.supplies, roster.people.size()])
				return false
			var grown := -1
			for slot: int in sizes.size():
				if muster.get_squad(slot).size() == sizes[slot] + 1:
					grown = slot
					break
			if grown < 0 or muster.get_squad(grown).back() != scenario.reserve_troop or int(muster.get_people()[grown].back()) != int(roster.people.back()["id"]):
				push_error("%s: the hired soldier should join a squad with room" % where)
				return false
			if muster.hire_reserve() or roster.supplies != 1:
				push_error("%s: a hire without supplies should be refused" % where)
				return false
		muster.queue_free()
		var screen := TacticsScreen.new()
		screen.scenario = campaign.scenario
		screen.squads = campaign.squads
		screen.campaign = campaign
		screen.is_instant = true
		screen.size = Vector2(720, 1280)
		root.add_child(screen)
		await process_frame
		screen.retreat()
		screen.retreat()
		await create_timer(SLIDE_WAIT_SEC).timeout
		var summary := screen.get_summary()
		var goals := summary.find_child("GoalsPanel", true, false) as Control
		if goals == null or not _all_text(goals).contains(tr("SUMMARY_SUPPLIES_FORMAT").get_slice("%", 0)):
			push_error("%s: the summary should show the supplies" % where)
			return false
		if scenario.objective != null and not scenario.objective.goals.is_empty() and not _all_text(goals).contains(tr("SUMMARY_GOALS")):
			push_error("%s: the summary should list the side goals" % where)
			return false
		if not await _texts_fit(summary, "summary " + where):
			return false
		screen.queue_free()
		await process_frame
	TacticsRoster.delete()
	return true


func _all_text(control: Control) -> String:
	var texts: PackedStringArray = []
	for node: Node in control.find_children("*", "", true, false):
		if node is Label or node is Button:
			texts.append(tr(node.text))
	return "\n".join(texts)


func _texts_fit(screen: Control, where: String) -> bool:
	await process_frame
	for node: Node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree():
			continue
		var label := control as Label
		if label != null and label.text != "":
			var font_px := label.get_theme_font_size(&"font_size")
			if font_px < GameTheme.SMALL_FONT_SIZE:
				push_error("%s: \"%s\" is %d px, under %d" % [where, label.text, font_px, GameTheme.SMALL_FONT_SIZE])
				return false
			var font := label.get_theme_font(&"font")
			if label.autowrap_mode == TextServer.AUTOWRAP_OFF and font.get_string_size(tr(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x > label.size.x + 0.5:
				push_error("%s: \"%s\" is cut (%.0f px wide label)" % [where, tr(label.text), label.size.x])
				return false
		var button := control as Button
		if button != null and button.size.y < 88.0:
			push_error("%s: the button \"%s\" is %.0f px tall, under 88" % [where, tr(button.text), button.size.y])
			return false
		# A chip's caption ("Giáo") sits under the face, not over it.
		if control.has_method(&"get_shape") and control.get(&"caption") != "":
			var shape: Dictionary = control.call(&"get_shape")
			var face_bottom: float = shape["center"].y + shape["radius"]
			if face_bottom > shape["top"] + 0.5 or shape["center"].y - shape["radius"] < -0.5:
				push_error("%s: the face of \"%s\" (%.0f..%.0f px) runs into its caption (from %.0f px) or off its chip" % [where, control.get(&"caption"), shape["center"].y - shape["radius"], face_bottom, shape["top"]])
				return false
	return true
