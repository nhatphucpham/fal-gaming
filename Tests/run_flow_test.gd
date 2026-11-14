extends SceneTree

# Headless test of one stage through the real screens: Main starts a run,
# the units are bought and placed with the same taps the gestures call,
# the battle plays to its end at full speed, the banner's "Tiếp tục" opens
# the reward cards and a reward begins stage 2's preparation. A lost run
# deletes its save at the result banner. It writes the run save like the
# game does, but to TEST_SAVE_PATH (never the player's save), and deletes it.

const SEED: int = 4242
const TEST_SAVE_PATH: String = "user://run_save_test.json"
const MAX_FRAMES: int = 3000
const STEP_SEC: float = 0.25
const SLIDE_WAIT_SEC: float = 0.5

var _main: Node
var _screen: RunScreen


func _initialize() -> void:
	RunSave.path = TEST_SAVE_PATH
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
	var checks: Array[Callable] = [_check_place, _check_bench_gap_drag, _check_sell_zone_release, _check_battle, _check_reward, _check_loss_deletes_save]
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


func _check_reward() -> bool:
	var run := _screen.run
	_screen.continue_after_battle()
	await process_frame
	var options := run.get_reward_options()
	if not _screen.reward_screen.visible or options.is_empty():
		push_error("The reward cards did not open")
		return false
	_screen.reward_screen.choose(options[0])
	await process_frame
	if run.phase != RunState.Phase.PREP or run.stage != 2 or not _screen.controller.is_enabled:
		push_error("Expected stage 2's preparation, got stage %d in %s" % [run.stage, RunState.Phase.keys()[run.phase]])
		return false
	var saved := RunSave.load_run(_main._catalog)
	if saved == null or saved.stage != 2:
		push_error("The save should hold stage 2 after the reward")
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


func _push_mouse(at: Vector2, is_pressed: bool, is_canceled: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = is_pressed
	event.canceled = is_canceled
	event.position = at
	event.global_position = at
	root.push_input(event, true)


func _push_motion(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)
