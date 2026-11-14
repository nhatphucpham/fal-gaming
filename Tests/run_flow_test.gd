extends SceneTree

# Headless test of one stage through the real screens: Main starts a run,
# the units are bought and placed with the same taps the gestures call,
# the battle plays to its end at full speed, the banner's "Tiếp tục" opens
# the reward cards; the game is then "closed" and continued, which lands on
# the same cards, and a held press on one begins stage 2's preparation. A
# lost run deletes its save at the result banner, and an unusable save is
# deleted when "Chơi tiếp" fails. Saved runs then cover the interludes: a
# pending Kỳ Ngộ plays before the reward cards and leads on to stage 3's
# preparation; the story scene plays once before stage 12 (saved only at
# its end) and not again after a stage-12 loss, whose boss bar and boss
# card are put away; a win over the boss shows its victory moment before
# the banner. It writes the run save like the game does, but to
# TEST_SAVE_PATH (never the player's save), and deletes it.

const SEED: int = 4242
const TEST_SAVE_PATH: String = "user://run_save_test.json"
const MAX_FRAMES: int = 3000
const STEP_SEC: float = 0.25
const SLIDE_WAIT_SEC: float = 0.5
## A run past stage 10 has met all five road encounters.
const FIVE_ENCOUNTERS: Array[String] = ["encounter.merchants", "encounter.wager", "encounter.deserters", "encounter.villagers", "encounter.stranger"]

var _main: Node
var _screen: RunScreen


func _initialize() -> void:
	RunSave.path = TEST_SAVE_PATH
	RunSettings.path = "user://settings_run_flow_test.json"
	var had_player_save := RunSave.has_save(RunSave.PATH)
	var ok := await _run()
	if _main != null:
		_main.queue_free()
	RunSave.delete()
	await process_frame
	if RunSave.has_save(RunSave.PATH) != had_player_save:
		push_error("The test must not create or delete the player's save")
		ok = false
	if ok:
		print("Run flow test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not ClassDB.class_exists("Battle"):
		push_error("Battle is missing: build the GDExtension (scons) before importing")
		return false
	_main = (load("res://Scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await process_frame
	_screen = _main.start_new_run(SEED)
	await create_timer(SLIDE_WAIT_SEC).timeout
	if not RunSave.has_save():
		push_error("A new run should be saved at once")
		return false
	var checks: Array[Callable] = [
		_check_place, _check_bench_gap_drag, _check_sell_zone_release, _check_battle, _check_reward,
		_check_reward_after_reload, _check_second_fight_press, _check_prep_saves, _check_sell_zone_hold_and_slide,
		_check_loss_deletes_save, _check_bad_save_cleared, _check_epiphany_flow, _check_encounter_resume, _check_story_and_boss_loss,
		_check_boss_win,
	]
	for check: Callable in checks:
		if not await check.call():
			push_error("Run flow test failed in %s" % check.get_method())
			return false
	return true


# Buys every affordable offer onto one row of the player's half (global rows
# 0-3 are side A), up to capacity.
func _check_place() -> bool:
	var run := _screen.run
	var column := 0
	for slot: int in run.rules.shop_slots:
		if run.get_board_count() >= run.get_capacity():
			break
		var unit_id := run.get_shop_offers()[slot]
		if unit_id == &"" or _main._catalog.get_unit(unit_id).cost > run.gold:
			continue
		_screen.controller.tap_shop_card(slot)
		_screen.controller.tap_cell(Vector2i(column, 1))
		column += 1
	await process_frame
	if run.get_board_count() == 0 or run.get_board_count() != column:
		push_error("Expected %d placed pieces, found %d" % [column, run.get_board_count()])
		return false
	return true


func _check_battle() -> bool:
	var run := _screen.run
	for press: int in 2:
		_screen.cycle_speed()
	if not _screen.start_battle() or run.phase != RunState.Phase.BATTLE:
		push_error("The battle did not start")
		return false
	# Preparation input is ignored while the battle plays.
	var count := run.get_board_count()
	_screen.controller.tap_shop_card(0)
	_screen.controller.tap_shop_card(0)
	if run.get_board_count() != count or _screen.start_battle():
		push_error("Preparation input was accepted during the battle")
		return false
	var frames := 0
	while run.phase == RunState.Phase.BATTLE and frames < MAX_FRAMES:
		_screen.playback.advance(STEP_SEC)
		await process_frame
		frames += 1
	if run.phase != RunState.Phase.REWARD:
		push_error("Expected the reward phase after stage 1, got %s after %d frames" % [RunState.Phase.keys()[run.phase], frames])
		return false
	print("Stage 1 ended: %s, gold %d, morale %d" % ["won" if _screen.last_battle_won else "lost", run.gold, run.morale])
	return true


# The banner's "Tiếp tục" opens the cards; the save already holds the
# reward choice (written when the battle ended).
func _check_reward() -> bool:
	var run := _screen.run
	_screen.continue_after_battle()
	await process_frame
	# A Kỳ Ngộ that fired plays its cutscene first; take its first card.
	if not await _pass_cutscene():
		return false
	if not _screen.reward_screen.visible or run.get_reward_options().is_empty():
		push_error("The reward cards did not open")
		return false
	var saved := RunSave.load_run(_main._catalog)
	if saved == null or saved.phase != RunState.Phase.REWARD or saved.morale != run.morale or saved.get_reward_options() != run.get_reward_options():
		push_error("The save should hold the reward choice at morale %d" % run.morale)
		return false
	return true


# Skips a playing cutscene's lines, takes its first choice and waits until
# the ink has wiped it away. True when none was playing.
func _pass_cutscene() -> bool:
	var cutscene := _screen.interludes.cutscene
	if cutscene == null:
		return true
	await create_timer(1.0).timeout
	cutscene.skip()
	await process_frame
	if cutscene.is_choosing() and not cutscene.choose(0):
		push_error("The Kỳ Ngộ card could not be chosen")
		return false
	await create_timer(1.5).timeout
	if _screen.interludes.is_playing() or _screen.run.epiphanies.has_pending():
		push_error("The Kỳ Ngộ cutscene did not end with a choice")
		return false
	return true


# "Closing" the game at the reward and choosing "Chơi tiếp" lands on the same
# cards at the same morale, not on stage 1 again. A cancelled release on a
# card does nothing; a press held 0.5 s chooses it.
func _check_reward_after_reload() -> bool:
	var before := _screen.run
	_screen = _main.continue_run()
	if _screen == null:
		push_error("Continuing the saved run failed")
		return false
	await create_timer(SLIDE_WAIT_SEC).timeout
	var run := _screen.run
	if run.phase != RunState.Phase.REWARD or run.stage != 1 or run.morale != before.morale or _screen.controller.is_enabled:
		push_error("Continuing should land on stage 1's reward choice at morale %d" % before.morale)
		return false
	if not _screen.reward_screen.visible or run.get_reward_options() != before.get_reward_options():
		push_error("The reloaded run should show the same reward cards")
		return false
	var cards := _screen.reward_screen.find_children("*", "RewardCard", true, false)
	var center := (cards[0] as Control).get_global_rect().get_center()
	_push_mouse(center, true)
	_push_mouse(center, false, true)
	# Longer than the card's choose animation, so a wrong choice would land.
	await create_timer(0.9).timeout
	if run.phase != RunState.Phase.REWARD:
		push_error("A cancelled release on a reward card chose it")
		return false
	_push_mouse(center, true)
	await create_timer(0.5).timeout
	_push_mouse(center, false)
	await create_timer(1.0).timeout
	if run.phase != RunState.Phase.PREP or run.stage != 2 or not _screen.controller.is_enabled:
		push_error("A 0.5 s press on a card should begin stage 2, got stage %d in %s" % [run.stage, RunState.Phase.keys()[run.phase]])
		return false
	var saved := RunSave.load_run(_main._catalog)
	if saved == null or saved.stage != 2 or saved.phase != RunState.Phase.PREP:
		push_error("The save should hold stage 2's preparation after the reward")
		return false
	return true


# A refresh is saved at once, so reloading cannot roll it back.
func _check_prep_saves() -> bool:
	var run := _screen.run
	_screen.press_refresh()
	var saved := RunSave.load_run(_main._catalog)
	if saved == null or saved.get_shop_offers() != run.get_shop_offers() or saved.gold != run.gold:
		push_error("A refresh should be saved at once")
		return false
	return true


# The sell zone sells on a press held past the long-press time and on a
# finger that slides within the zone before lifting.
func _check_sell_zone_hold_and_slide() -> bool:
	var run := _screen.run
	var zone := _screen.layout.sell_zone
	while run.get_pieces().size() < 2 and run.gold >= 1:
		_screen.controller.tap_shop_card(0)
		_screen.controller.tap_shop_card(0)
	if run.get_pieces().size() < 2:
		push_error("Need two pieces to sell")
		return false
	for slide: Vector2 in [Vector2.ZERO, Vector2(30, 0)]:
		var count := run.get_pieces().size()
		var piece: RunPiece = run.get_pieces()[0]
		if piece.is_on_bench():
			_screen.controller.tap_bench_slot(piece.bench_slot)
		else:
			_screen.controller.tap_cell(Battle.local_to_global(Battle.SIDE_A, piece.cell.x, piece.cell.y))
		await process_frame
		var inside := zone.get_global_rect().get_center()
		_push_mouse(inside, true)
		if slide == Vector2.ZERO:
			await create_timer(0.5).timeout
		_push_motion(inside + slide)
		_push_mouse(inside + slide, false)
		await process_frame
		if run.get_pieces().size() != count - 1:
			push_error("A release on the sell zone should sell (held %s, slid %s)" % [slide == Vector2.ZERO, slide])
			return false
	return true


# A drag that starts between two bench slots must pick nothing up, not a
# board piece (board pieces have no bench slot). Real events, so the
# gesture and the bench bar are tested too.
func _check_bench_gap_drag() -> bool:
	var bench := _screen.layout.bench
	var rect := bench.get_global_rect()
	var gap := Vector2(-1.0, rect.get_center().y)
	for x: int in range(int(rect.position.x) + 1, int(rect.end.x)):
		if bench.slot_at_global(Vector2(x, gap.y)) == BenchBar.NO_SLOT and bench.slot_at_global(Vector2(x - 20, gap.y)) != BenchBar.NO_SLOT:
			gap.x = x + 2
			break
	if gap.x < 0.0 or _screen.run.get_board_count() == 0:
		push_error("No bench gap found, or nothing on the board")
		return false
	var count := _screen.run.get_pieces().size()
	_push_mouse(gap, true)
	_push_motion(gap + Vector2(0, -60))
	await process_frame
	var picked := _screen.controller.is_dragging() or _screen.layout.sell_zone.is_shown()
	_push_mouse(_screen.layout.sell_zone.get_global_rect().get_center(), false)
	await process_frame
	if picked or _screen.run.get_pieces().size() != count:
		push_error("A drag from a bench gap picked up a piece (dragging %s, pieces %d -> %d)" % [picked, count, _screen.run.get_pieces().size()])
		return false
	return true


# The sell zone sells on a tap that ends on it, not on a cancelled touch
# release or a release after the finger slid off.
func _check_sell_zone_release() -> bool:
	var run := _screen.run
	var zone := _screen.layout.sell_zone
	var count := run.get_pieces().size()
	_screen.controller.tap_cell(Vector2i(0, 1))
	var inside := zone.get_global_rect().get_center()
	if not zone.is_shown():
		push_error("Selecting a board piece should show the sell zone")
		return false
	_push_mouse(inside, true)
	_push_mouse(inside, false, true)
	_push_mouse(inside, true)
	_push_motion(inside + Vector2(0, -zone.size.y))
	_push_mouse(inside + Vector2(0, -zone.size.y), false)
	await process_frame
	if run.get_pieces().size() != count:
		push_error("A cancelled or slid-off release on the sell zone sold a piece")
		return false
	_push_mouse(inside, true)
	_push_mouse(inside, false)
	await process_frame
	if run.get_pieces().size() != count - 1:
		push_error("A tap on the sell zone should sell the selected piece")
		return false
	return true


# A run that ends deletes its save at the banner, before "Tiếp tục".
func _check_loss_deletes_save() -> bool:
	var run := RunState.new(_main._catalog, 0)
	var data := _screen.run.to_save_data()
	data.merge({"morale": 1, "pieces": [], "next_piece_id": 1}, true)
	if not run.load_save_data(data) or not RunSave.save(run):
		push_error("Could not set up a run at 1 morale")
		return false
	_screen = _main._open_run(run)
	await create_timer(SLIDE_WAIT_SEC).timeout
	# An empty board loses at once.
	_screen.start_battle()
	if run.phase != RunState.Phase.LOST or RunSave.has_save():
		push_error("A lost run must delete its save at once (phase %s, saved %s)" % [RunState.Phase.keys()[run.phase], RunSave.has_save()])
		return false
	_screen.continue_after_battle()
	return true


# A save that cannot be used: "Chơi tiếp" warns once, deletes it and shows
# the title again without "Chơi tiếp".
func _check_bad_save_cleared() -> bool:
	var file := FileAccess.open(RunSave.path, FileAccess.WRITE)
	file.store_string("{\"version\": 1}")
	file.close()
	print("Run flow test: the next warning (an old save) is expected")
	if _main.continue_run() != null or RunSave.has_save():
		push_error("An unusable save should be deleted when continuing fails")
		return false
	var title := _main.current_screen as TitleScreen
	if title == null or title.has_save:
		push_error("The title should offer no \"Chơi tiếp\" after a failed load")
		return false
	return true


func _push_mouse(at: Vector2, is_pressed: bool, is_canceled: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = is_pressed
	event.canceled = is_canceled
	event.position = at
	event.global_position = at
	root.push_input(event, true)


# A finger on the screen, sent through Input like a phone's touch (mouse
# emulation from touch is on, as on the phone). `at` is in the game's
# coordinates; Input takes window pixels.
func _push_touch(at: Vector2, is_pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = is_pressed
	event.position = root.get_screen_transform() * at
	Input.parse_input_event(event)


func _push_motion(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


# Back in a preparation after a battle, the slid-away battle panel must not
# sit over the fight button (it once swallowed "Ra trận" from stage 2 on).
func _check_second_fight_press() -> bool:
	await create_timer(1.0).timeout
	var layout := _screen.layout
	if layout.battle_status.is_visible_in_tree():
		push_error("The battle panel should be hidden in the preparation")
		return false
	var center := layout.fight_button.get_global_rect().get_center()
	_push_mouse(center, true)
	await process_frame
	var hovered := root.gui_get_hovered_control()
	_push_mouse(center, false, true)
	if hovered != layout.fight_button:
		push_error("A press on the fight button reached %s" % hovered)
		return false
	return true


# A saved run in stage 2's reward with a pending sword Kỳ Ngộ: its cutscene
# plays before the cards; the card taken is in the save at once (before the
# closing wipe); the reward cards follow, and a reward reaches stage 3's
# preparation with "Ra trận" on top.
func _check_epiphany_flow() -> bool:
	var run := _saved_run({"phase": "reward", "stage": 2, "stages_cleared": 1, "rewards": ["reward.rest", "reward.hunt"]}, {
		"pending_family": "milestone.class_sword", "last_stage": 2,
		"pending_options": ["epiphany.sword_lower_2", "epiphany.sword_swift_edge"],
	})
	if run == null:
		return false
	_screen = _main._open_run(run)
	await create_timer(SLIDE_WAIT_SEC).timeout
	var cutscene := _screen.interludes.cutscene
	if cutscene == null or _screen.reward_screen.visible:
		push_error("A pending Kỳ Ngộ should play its cutscene before the reward cards")
		return false
	await _skip_when_typing(cutscene)
	if not cutscene.choose(0):
		push_error("The Kỳ Ngộ cards should be up after skipping")
		return false
	var saved := RunSave.load_run(_main._catalog)
	if run.epiphanies.has_pending() or saved == null or saved.epiphanies.has_pending() or saved.epiphanies.get_chosen_ids() != [&"epiphany.sword_lower_2"]:
		push_error("The Kỳ Ngộ card should be taken and saved the moment it is chosen")
		return false
	if _screen.reward_screen.visible:
		push_error("The reward cards should wait for the closing wipe")
		return false
	await create_timer(1.5).timeout
	if _screen.interludes.is_playing() or not _screen.reward_screen.visible:
		push_error("The reward cards should follow the Kỳ Ngộ cutscene")
		return false
	await _hold_reward_card(0)
	# Stage 2 is a road stage: the encounter cutscene comes before stage 3.
	saved = RunSave.load_run(_main._catalog)
	var road := _screen.interludes.cutscene
	if run.phase != RunState.Phase.ENCOUNTER or road == null or saved == null or saved.phase != RunState.Phase.ENCOUNTER:
		push_error("A reward at stage 2 should open a saved road encounter, got %s" % RunState.Phase.keys()[run.phase])
		return false
	await _skip_when_typing(road)
	await process_frame
	if not await _touch_encounter_card(run, road):
		return false
	await create_timer(1.5).timeout
	if run.phase != RunState.Phase.PREP or run.stage != 3 or not _screen.controller.is_enabled or _screen.interludes.is_playing():
		push_error("The road encounter should begin stage 3, got stage %d in %s" % [run.stage, RunState.Phase.keys()[run.phase]])
		return false
	return await _check_second_fight_press()


# Touches (a real screen touch through Input) the first card the run can
# pay for; the choice lands in the run at once.
func _touch_encounter_card(run: RunState, cutscene: CutsceneScreen) -> bool:
	var cards := cutscene.find_children("*", "CutsceneChoiceCard", true, false)
	var pending := run.encounters.get_pending()
	if not cutscene.is_choosing() or pending == null or cards.size() != pending.options.size():
		push_error("The road encounter should show one card per option")
		return false
	for index: int in cards.size():
		var card := cards[index] as CutsceneChoiceCard
		if card.is_disabled() != (run.get_encounter_refusal(index) != RunState.Result.OK):
			push_error("Encounter card %d disabled should match whether the run can pay" % index)
			return false
		if card.is_disabled():
			continue
		var center := card.get_global_rect().get_center()
		_push_touch(center, true)
		await create_timer(0.2).timeout
		_push_touch(center, false)
		await create_timer(0.3).timeout
		if run.phase == RunState.Phase.ENCOUNTER:
			push_error("A touch on encounter card %d did not choose it" % index)
			return false
		return true
	push_error("Every road encounter should offer one card the run can pay")
	return false


# A run closed at a road encounter (here: no gold, so the deserters' paid
# card is out) resumes on the same encounter. Touching the greyed card
# shakes it and changes nothing; the other card goes on to stage 3.
func _check_encounter_resume() -> bool:
	var run := _saved_run({"phase": "encounter", "stage": 2, "stages_cleared": 2, "gold": 0, "rewards": [],
		"encounter": {"drawn": ["encounter.deserters"], "pending": "encounter.deserters", "bet_gold": 0}}, {})
	if run == null:
		return false
	_screen = _main.continue_run()
	if _screen == null:
		push_error("Continuing a run saved at a road encounter failed")
		return false
	await create_timer(SLIDE_WAIT_SEC).timeout
	run = _screen.run
	var cutscene := _screen.interludes.cutscene
	if run.phase != RunState.Phase.ENCOUNTER or cutscene == null or run.encounters.get_pending().id != &"encounter.deserters":
		push_error("Continuing should replay the same road encounter")
		return false
	await _skip_when_typing(cutscene)
	await process_frame
	var cards := cutscene.find_children("*", "CutsceneChoiceCard", true, false)
	if cards.size() != 2 or not (cards[0] as CutsceneChoiceCard).is_disabled() or (cards[1] as CutsceneChoiceCard).is_disabled():
		push_error("With no gold the deserters' paid card should be greyed out and the other open")
		return false
	var refused: Array[int] = []
	cutscene.choice_refused.connect(func(choice: int) -> void: refused.append(choice))
	var center := (cards[0] as Control).get_global_rect().get_center()
	_push_touch(center, true)
	await create_timer(0.2).timeout
	_push_touch(center, false)
	await create_timer(0.5).timeout
	if refused != [0] or run.phase != RunState.Phase.ENCOUNTER or run.gold != 0:
		push_error("A touch on the greyed card should be refused and change nothing (refused %s)" % [refused])
		return false
	if not await _touch_encounter_card(run, cutscene):
		return false
	await create_timer(1.5).timeout
	if run.phase != RunState.Phase.PREP or run.stage != 3 or run.gold < 3:
		push_error("The deserters' free card should pay 3 gold and begin stage 3")
		return false
	return await _check_second_fight_press()


# Stage 11 won: the reward leads to the story scene, and the save keeps the
# reward choice until the story ends (closing the app during it plays it
# again). In stage 12 the boss card closes when the battle starts; after a
# loss the boss bar is gone at the reward cards, the battle speed no longer
# pitches sounds, and the next reward goes straight to stage 12 again.
func _check_story_and_boss_loss() -> bool:
	var run := _saved_run({"phase": "reward", "stage": 11, "stages_cleared": 11, "rewards": ["reward.rest", "reward.hunt", "reward.black_market"],
		"encounter": {"drawn": FIVE_ENCOUNTERS, "pending": "", "bet_gold": 0}}, {})
	if run == null:
		return false
	_screen = _main._open_run(run)
	await create_timer(SLIDE_WAIT_SEC).timeout
	await _hold_reward_card(0)
	var story := _screen.interludes.cutscene
	var saved := RunSave.load_run(_main._catalog)
	if story == null or run.stage != 12 or saved == null or saved.stage != 11 or saved.phase != RunState.Phase.REWARD:
		push_error("The story scene should play before stage 12 with stage 11's reward still saved")
		return false
	await _skip_when_typing(story)
	await create_timer(1.2).timeout
	saved = RunSave.load_run(_main._catalog)
	if _screen.interludes.is_playing() or not _screen.controller.is_enabled or saved == null or saved.stage != 12 or saved.phase != RunState.Phase.PREP:
		push_error("After the story, stage 12's preparation should be shown and saved")
		return false
	var layout := _screen.layout
	_screen.boss_hud.open_card()
	if not layout.boss_card.visible:
		push_error("The boss badge should open the boss card")
		return false
	if not _screen.start_battle() or layout.boss_card.visible or not layout.boss_bar.visible:
		push_error("The battle should close the boss card and show the boss bar")
		return false
	_screen.cycle_speed()
	var frames := 0
	while run.phase == RunState.Phase.BATTLE and frames < MAX_FRAMES:
		_screen.playback.advance(STEP_SEC)
		await process_frame
		frames += 1
	if run.phase != RunState.Phase.REWARD or _screen.last_battle_won:
		push_error("One sword against the boss should lose into the reward, got %s" % RunState.Phase.keys()[run.phase])
		return false
	if AudioService.instance != null and AudioService.instance.battle_speed != 1:
		push_error("The battle speed should stop pitching sounds when the battle ends")
		return false
	_screen.continue_after_battle()
	await process_frame
	if not await _pass_cutscene():
		return false
	if layout.boss_bar.visible or not _screen.reward_screen.visible:
		push_error("After a boss loss the reward cards should show without the boss bar")
		return false
	await _hold_reward_card(0)
	if _screen.interludes.is_playing() or run.phase != RunState.Phase.PREP or run.stage != 12:
		push_error("A stage 12 loss should go back to stage 12 without the story")
		return false
	return true


# A strong stage-12 board beats the boss: the victory stamp comes first,
# the banner only after BossHud.VICTORY_SEC.
func _check_boss_win() -> bool:
	var units := [
		["unit.wolf_king_shield", 3, 3, 1], ["unit.ba_khac", 2, 4, 1], ["unit.heavy_rider", 3, 5, 1], ["unit.thiet_nha", 2, 2, 1],
		["unit.moon_spear", 3, 3, 2], ["unit.moon_spear", 3, 5, 2], ["unit.thunder_mage", 3, 3, 3], ["unit.thunder_mage", 3, 5, 3],
	]
	var pieces := []
	for index: int in units.size():
		var unit: Array = units[index]
		pieces.append({"id": index + 1, "unit_id": unit[0], "star": unit[1], "bench": -1, "col": unit[2], "rank": unit[3], "has_fought": true})
	var run := _saved_run({"stage": 12, "stages_cleared": 11, "level": 9, "pieces": pieces, "next_piece_id": units.size() + 1,
		"encounter": {"drawn": FIVE_ENCOUNTERS, "pending": "", "bet_gold": 0}}, {})
	if run == null:
		return false
	_screen = _main._open_run(run)
	await create_timer(SLIDE_WAIT_SEC).timeout
	if not _screen.start_battle():
		push_error("The boss battle did not start")
		return false
	var frames := 0
	while run.phase == RunState.Phase.BATTLE and frames < MAX_FRAMES:
		_screen.playback.advance(STEP_SEC)
		await process_frame
		frames += 1
	var banner := _screen.layout.banner
	if run.phase != RunState.Phase.WON or not _screen.last_battle_won or banner.visible:
		push_error("The strong board should beat the boss, with no banner yet (phase %s)" % RunState.Phase.keys()[run.phase])
		return false
	await create_timer(BossHud.VICTORY_SEC - 0.4).timeout
	if banner.visible:
		push_error("The banner should wait for the boss victory moment")
		return false
	await create_timer(0.8).timeout
	if not banner.visible:
		push_error("The banner should follow the boss victory moment")
		return false
	return true


# The run of a fresh seed-31 start with one sword on the board, then
# `changes` (and `epiphany_changes` in its Kỳ Ngộ data), loaded and saved.
func _saved_run(changes: Dictionary, epiphany_changes: Dictionary) -> RunState:
	var start := RunState.new(_main._catalog, 31)
	start.start()
	var data := start.to_save_data()
	(data["epiphany"] as Dictionary).merge(epiphany_changes, true)
	data["pieces"] = [{"id": 1, "unit_id": "unit.blade_wanderer", "star": 1, "bench": -1, "col": 4, "rank": 1, "has_fought": true}]
	data["next_piece_id"] = 2
	data.merge(changes, true)
	var run := RunState.new(_main._catalog, 0)
	if not run.load_save_data(JSON.parse_string(JSON.stringify(data))) or not RunSave.save(run):
		push_error("The test run %s did not load" % [changes])
		return null
	return run


# Skips `cutscene` once its first line types (the opening wipe ignores it).
func _skip_when_typing(cutscene: CutsceneScreen) -> void:
	var frames := 0
	while cutscene.get_line_index() < 0 and frames < MAX_FRAMES:
		await process_frame
		frames += 1
	cutscene.skip()


# Holds a press on reward card `index` long enough to choose it, then waits
# for its animation.
func _hold_reward_card(index: int) -> void:
	var cards := _screen.reward_screen.find_children("*", "RewardCard", true, false)
	var center := (cards[index] as Control).get_global_rect().get_center()
	_push_mouse(center, true)
	await create_timer(0.5).timeout
	_push_mouse(center, false)
	await create_timer(1.0).timeout
