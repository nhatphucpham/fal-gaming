extends SceneTree

# Headless test of one stage through the real screens: Main starts a run,
# the units are bought and placed with the same taps the gestures call,
# the battle plays to its end at full speed, the banner's "Tiếp tục" opens
# the reward cards and a reward begins stage 2's preparation. It writes the
# run save like the game does and deletes it at the end.

const SEED: int = 4242
const MAX_FRAMES: int = 3000
const STEP_SEC: float = 0.25
const SLIDE_WAIT_SEC: float = 0.5

var _main: Node
var _screen: RunScreen


func _initialize() -> void:
	var ok := await _run()
	if _main != null:
		_main.queue_free()
	RunSave.delete()
	await process_frame
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
	var checks: Array[Callable] = [_check_place, _check_battle, _check_reward]
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
