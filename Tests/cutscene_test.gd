extends SceneTree

# Headless test of the cutscene screen: the story scene types its first
# line after the ink wipe, a tap finishes the line, the next tap moves on,
# "Bỏ qua" ends a scene without choices; one real touch (a phone tap, which
# also arrives as an emulated mouse click) taps once; a Kỳ Ngộ scene built
# from a run's pending choice skips to its two cards (never past them),
# taps do not pass the cards, and choosing one reports it at once and ends
# the scene with that index. All cutscene data validates.

const WIPE_WAIT_SEC: float = 0.8
const END_WAIT_SEC: float = 1.0

var _catalog: Catalog


func _initialize() -> void:
	_catalog = load("res://Data/catalog.tres") as Catalog
	var ok := await _run()
	if ok:
		print("Cutscene test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	var checks: Array[Callable] = [_check_data, _check_story_steps, _check_touch_tap, _check_choice]
	for check: Callable in checks:
		if not await check.call():
			push_error("Cutscene test failed in %s" % check.get_method())
			return false
	return true


# The story scene: Liễu Mi and Ba Khắc, 4-6 lines, no choices, valid.
func _check_data() -> bool:
	var story := EpiphanyCutscene.load_story()
	if story == null or not story.validate(_catalog).is_empty():
		push_error("The story scene is missing or invalid: %s" % (story.validate(_catalog) if story != null else []))
		return false
	if story.line_keys.size() < 4 or story.line_keys.size() > 6 or story.has_choices():
		push_error("The story scene needs 4-6 lines and no choice")
		return false
	return true


func _check_story_steps() -> bool:
	var story := EpiphanyCutscene.load_story()
	var screen := CutsceneScreen.new()
	root.add_child(screen)
	var results: Array[int] = []
	screen.finished.connect(func(choice: int) -> void: results.append(choice))
	screen.present(story, _catalog, "")
	screen.tap()
	if screen.get_line_index() != -1:
		push_error("A tap during the wipe should do nothing")
		return false
	await create_timer(WIPE_WAIT_SEC).timeout
	var full := TranslationServer.translate(story.line_keys[0])
	if screen.get_line_index() != 0 or screen.is_line_complete() or not full.begins_with(screen.get_visible_text()):
		push_error("The first line should be typing: '%s'" % screen.get_visible_text())
		return false
	screen.tap()
	if not screen.is_line_complete() or screen.get_visible_text() != full or screen.get_line_index() != 0:
		push_error("A tap should finish the line")
		return false
	screen.tap()
	if screen.get_line_index() != 1 or screen.is_line_complete():
		push_error("The next tap should start line 2")
		return false
	screen.skip()
	await create_timer(END_WAIT_SEC).timeout
	var ok := results == [-1] and screen.is_done()
	if not ok:
		push_error("Skipping a scene without choices should end it with -1, got %s" % [results])
	screen.queue_free()
	return ok


# A phone tap through Input (touch, then the emulated mouse click) finishes
# the typing line without moving on; a second tap moves on.
func _check_touch_tap() -> bool:
	if not ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true):
		push_error("The project should emulate the mouse from touch, as phones need")
		return false
	var screen := CutsceneScreen.new()
	root.add_child(screen)
	screen.present(EpiphanyCutscene.load_story(), _catalog, "")
	await create_timer(WIPE_WAIT_SEC).timeout
	await process_frame
	if screen.get_line_index() != 0 or screen.is_line_complete():
		push_error("The first line should be typing before the touch")
		return false
	var at := screen.get_global_rect().get_center()
	_touch_tap(at)
	await process_frame
	if screen.get_line_index() != 0 or not screen.is_line_complete():
		push_error("One touch should finish line 1 only, got line %d complete %s" % [screen.get_line_index(), screen.is_line_complete()])
		return false
	_touch_tap(at)
	await process_frame
	var ok := screen.get_line_index() == 1 and not screen.is_line_complete()
	if not ok:
		push_error("A second touch should start line 2, got line %d" % screen.get_line_index())
	screen.queue_free()
	return ok


# One finger down and up through Input, as a platform sends it (canvas
# position to window position); Godot emulates the mouse for it.
func _touch_tap(at: Vector2) -> void:
	for is_pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = is_pressed
		event.position = root.get_final_transform() * at
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _check_choice() -> bool:
	var run := _pending_run()
	if run == null:
		return false
	var data := EpiphanyCutscene.build(run)
	if data == null or not data.validate(_catalog).is_empty() or data.choice_titles.size() != 2:
		push_error("The Kỳ Ngộ scene should build with two choices")
		return false
	if data.right_unit != ExtraFigures.SAGE_UNIT_ID or _catalog.get_unit(data.left_unit).class_id != &"class.sword":
		push_error("A sword unit should talk to the sage, got %s" % data.left_unit)
		return false
	var screen := CutsceneScreen.new()
	root.add_child(screen)
	var results: Array[int] = []
	var made: Array[int] = []
	screen.finished.connect(func(choice: int) -> void: results.append(choice))
	screen.choice_made.connect(func(choice: int) -> void: made.append(choice))
	screen.present(data, _catalog, "Kỳ Ngộ")
	await create_timer(WIPE_WAIT_SEC).timeout
	if screen.choose(0):
		push_error("No choice before the cards are up")
		return false
	screen.skip()
	if not screen.is_choosing() or screen.get_choice_texts().size() != 2:
		push_error("Skipping should land on the two cards")
		return false
	screen.tap()
	screen.skip()
	await create_timer(0.3).timeout
	if not screen.is_choosing() or not results.is_empty():
		push_error("Taps and skips must not pass the choice")
		return false
	if not screen.choose(1) or screen.choose(0):
		push_error("Choosing should take one card once")
		return false
	if made != [1] or not results.is_empty():
		push_error("The choice should be reported at once, before the wipe ends: %s %s" % [made, results])
		return false
	await create_timer(END_WAIT_SEC + 0.5).timeout
	var ok := results == [1]
	if not ok:
		push_error("The scene should end with choice 1, got %s" % [results])
	screen.queue_free()
	return ok


# A run in its reward phase with a pending sword Kỳ Ngộ and one sword on
# the board.
func _pending_run() -> RunState:
	var start := RunState.new(_catalog, 31)
	start.start()
	var data := start.to_save_data()
	var epiphany := EpiphanyTracker.new(_catalog, 31).to_save_data()
	epiphany["pending_family"] = "milestone.class_sword"
	epiphany["pending_options"] = ["epiphany.sword_lower_2", "epiphany.sword_swift_edge"]
	epiphany["last_stage"] = 2
	data["epiphany"] = epiphany
	data["phase"] = "reward"
	data["stage"] = 2
	data["stages_cleared"] = 1
	data["rewards"] = ["reward.rest", "reward.hunt"]
	data["pieces"] = [{"id": 1, "unit_id": "unit.blade_wanderer", "star": 1, "bench": -1, "col": 4, "rank": 1, "has_fought": true}]
	data["next_piece_id"] = 2
	var run := RunState.new(_catalog, 0)
	if not run.load_save_data(JSON.parse_string(JSON.stringify(data))):
		push_error("The pending run did not load")
		return null
	return run
