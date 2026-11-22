extends SceneTree

# Headless tests of the world map's screens (Docs/systems/tactics_world.md):
# Auto plays in its result view a slice a frame (more than one frame, each
# within the frame budget, bars live) and ends with the same result as
# TacticsAutoResolve.resolve() on the same roster, applied and saved once;
# the war horn sounds once per declared push (not when the map opens again,
# again after a turn, and a save keeps that it was heard); the market lists
# healing as one row with the next patient's face, whose Mua heals the
# wounded soldier with the most marks; the map's page is hidden under a
# full-screen overlay and back after it; the Auto result and the market
# draw nothing while idle.

const SAVE_PATH: String = "user://tactics_world_screen_test.json"
const FERRY: StringName = &"region.ferry"
const SETTLE_SEC: float = 1.2
const Kit := preload("res://Tests/tactics_test_kit.gd")

var _kit := Kit.new()


func _initialize() -> void:
	TranslationServer.set_locale("vi")
	TacticsRoster.path = SAVE_PATH
	var ok := ClassDB.class_exists("TacticsBattle") and _kit.load_catalog()
	if not ok:
		push_error("TacticsBattle is missing: build the GDExtension (scons) before importing")
	var checks: Array[Callable] = [_check_auto_in_slices, _check_horn_once, _check_market_heal_row]
	for check: Callable in checks:
		if not ok:
			break
		TacticsRoster.delete()
		if not await check.call():
			push_error("Tactics world screen test failed in %s" % check.get_method())
			ok = false
	_kit.free_battles()
	TacticsRoster.delete()
	if ok:
		print("Tactics world screen test passed")
	quit(0 if ok else 1)


func _expect(what: String, actual: Variant, expected: Variant) -> bool:
	if actual == expected:
		return true
	push_error("Tactics world screen test: %s: got %s, expected %s" % [what, actual, expected])
	return false


func _screen(roster: TacticsRoster) -> TacticsWorldScreen:
	var screen := TacticsWorldScreen.new()
	screen.roster = roster
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	return screen


# Frames over `seconds` that changed what would be drawn (see
# Tests/idle_frames_test.gd).
func _changed_frames(seconds: float) -> int:
	var changed := 0
	var end_msec := Time.get_ticks_msec() + roundi(seconds * 1000.0)
	RenderingServer.force_draw(false)
	while Time.get_ticks_msec() < end_msec:
		await process_frame
		if RenderingServer.has_changed():
			changed += 1
			RenderingServer.force_draw(false)
	return changed


func _check_auto_in_slices() -> bool:
	# What resolve() gives on the same roster, for comparison.
	var twin := TacticsRoster.create(5)
	var twin_region := twin.world.data.get_region(FERRY)
	var catalog := load("res://Data/Tactics/tactics_catalog.tres") as TacticsCatalog
	var expected := TacticsAutoResolve.resolve(TacticsCampaign.new(twin, catalog, twin_region.scenario, {"region": FERRY, "enemy_power_pct": 100}))
	var roster := TacticsRoster.create(5)
	var screen := _screen(roster)
	await process_frame
	var view := screen.resolve_auto(FERRY)
	var ok := _expect("Auto opens its view", view != null, true) and _expect("fighting at first", view.is_fighting(), true) \
			and _expect("nothing applied yet", roster.battles, 0) and _expect("no second Auto meanwhile", screen.resolve_auto(FERRY), null)
	var frames := 0
	var bar_moved := false
	while ok and view.is_fighting() and frames < 2000:
		await process_frame
		frames += 1
		var bar := view.find_child("ForcesPanel", true, false).get_child(0).get_child(2) as Control
		bar_moved = bar_moved or float(bar.get("value")) < 1.0
	if not ok:
		return false
	var summary := view.summary
	ok = _expect("several frames", frames > 3, true) and _expect("the bars move during the fight", bar_moved, true) \
			and _expect("same winner as resolve()", summary["is_won"], expected["is_won"]) and _expect("one battle", roster.battles, 1) \
			and _expect("same units standing", summary["counts"], expected["counts"]) and _expect("saved", FileAccess.file_exists(SAVE_PATH), true)
	var saved := TacticsRoster.load_roster()
	ok = ok and _expect("the save has the battle", saved.battles, 1) and _expect("the save has the turn", saved.world.turn, 1)
	await create_timer(SETTLE_SEC).timeout
	ok = ok and _expect("the map's page hidden under the result", screen.get_map().is_visible_in_tree(), false)
	ok = ok and _expect("an idle Auto result draws nothing", await _changed_frames(1.0), 0)
	view.continue_requested.emit()
	await process_frame
	ok = ok and _expect("the map back after it", screen.get_map().is_visible_in_tree(), true) and _expect("not applied twice", roster.battles, 1)
	screen.queue_free()
	await process_frame
	return ok


func _check_horn_once() -> bool:
	var roster := TacticsRoster.create(7)
	var screen := _screen(roster)
	var ok := _expect("the push was heard on opening", roster.world.is_threat_heard, true) and _expect("not twice", screen.announce_threat(), false)
	screen.queue_free()
	await process_frame
	# Opened again (the save of the first opening): no horn.
	var again := TacticsRoster.load_roster()
	ok = ok and _expect("heard kept in the save", again.world.is_threat_heard, true)
	screen = _screen(again)
	ok = ok and _expect("no horn on reopening", screen.announce_threat(), false)
	# A turn declares the next push: the horn sounds once for it.
	again.world.finish_region(FERRY, true)
	ok = ok and _expect("a new push is not heard yet", again.world.is_threat_heard, false) and _expect("its horn", screen.announce_threat(), true) \
			and _expect("once", screen.announce_threat(), false)
	screen.queue_free()
	await process_frame
	return ok


func _check_market_heal_row() -> bool:
	var roster := TacticsRoster.create(9)
	roster.supplies = 20
	roster.world.finish_region(FERRY, true)
	# Three wounded; the one with marks is treated first.
	var wounded: Array[Dictionary] = []
	for index: int in 3:
		var person := roster.recruit(&"troop.spearman", &"")
		person["rest_until"] = roster.battles + 1
		wounded.append(person)
	wounded[1]["marks"].append({"incident": &"incident.stand", "leader_id": &"", "terrain": &"", "round": 1, "battle": 0})
	var screen := _screen(roster)
	var market := screen.open_market(FERRY)
	await process_frame
	var heal := -1
	for index: int in market._market.region.offers.size():
		if market._market.region.offers[index].kind == &"offer.heal":
			heal = index
	var buttons := market.find_children("Buy*", "", true, false)
	var ok := _expect("one Mua per offer", buttons.size(), market._market.region.offers.size()) \
			and _expect("one patient row", market.find_children("Patient", "", true, false).size(), 1) \
			and _expect("the most marked is next", market._market.get_next_patient()["id"], wounded[1]["id"])
	ok = ok and _expect("Mua heals", market.buy(heal), true) and _expect("the marked one is healed", roster.is_resting(wounded[1]), false) \
			and _expect("the others still rest", roster.is_resting(wounded[0]) and roster.is_resting(wounded[2]), true)
	await create_timer(SETTLE_SEC).timeout
	ok = ok and _expect("an idle market draws nothing", await _changed_frames(1.0), 0)
	market.close()
	await process_frame
	ok = ok and _expect("the map back after the market", screen.get_map().is_visible_in_tree(), true)
	screen.queue_free()
	await process_frame
	return ok
