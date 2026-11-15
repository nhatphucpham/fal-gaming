extends SceneTree

# Headless test that idle pieces of the screen leave frames undrawn, so low
# processor mode can skip them (Docs/systems/performance.md). A frame
# "changes" when RenderingServer.has_changed() says it would have to be
# drawn: the test draws by hand (force_draw) before each frame and asks
# after it. Checks: an idle unit view writes no transform, a full Khí bar
# and a cast glow process only while they show.

const Kit := preload("res://Tests/pose_test_kit.gd")
const SETTLE_SEC: float = 0.4


func _initialize() -> void:
	var ok := true
	var checks: Array[Callable] = [_check_still_view, _check_bar_and_overlay_processing]
	for check: Callable in checks:
		if not await check.call():
			push_error("Idle frames test failed in %s" % check.get_method())
			ok = false
	if ok:
		print("Idle frames test passed")
	quit(0 if ok else 1)


## Frames over `seconds` of real time that changed what would be drawn,
## and how many frames ran: [changed, frames].
func count_changed_frames(seconds: float) -> Array[int]:
	var changed := 0
	var frames := 0
	var end_msec := Time.get_ticks_msec() + roundi(seconds * 1000.0)
	RenderingServer.force_draw(false)
	while Time.get_ticks_msec() < end_msec:
		await process_frame
		frames += 1
		if RenderingServer.has_changed():
			changed += 1
			RenderingServer.force_draw(false)
	return [changed, frames]


# A calm figure (the bench) redraws only for its blinks; its view writes
# no transform every frame, so nearly every frame is left undrawn.
func _check_still_view() -> bool:
	var view := Kit.make_view(root, &"class.sword", 0)
	view.is_idle_calm = true
	await create_timer(SETTLE_SEC).timeout
	var counts := await count_changed_frames(1.0)
	view.queue_free()
	await process_frame
	# At most one blink (shut and open) falls in a second.
	if counts[0] > 2:
		push_error("A still unit view changed %d of %d frames in 1 s" % counts)
		return false
	return true


# The Khí bar processes only while full and shown; the skill overlay only
# while its cast glow shows.
func _check_bar_and_overlay_processing() -> bool:
	var view := Kit.make_view(root, &"class.mage", 0)
	await process_frame
	var bar: UnitBar = null
	for child: Node in view.get_children():
		if child is UnitBar:
			bar = child
	var ok := true
	view.set_qi(10, 100)
	ok = _expect_processing("half Khí bar", bar, false) and ok
	view.set_qi(100, 100)
	ok = _expect_processing("full Khí bar", bar, true) and ok
	view.is_hp_bar_shown = false
	ok = _expect_processing("hidden full Khí bar", bar, false) and ok
	ok = _expect_processing("skill overlay at rest", view.skill_overlay, false) and ok
	view.skill_overlay.set_casting(true)
	ok = _expect_processing("casting skill overlay", view.skill_overlay, true) and ok
	view.skill_overlay.clear()
	ok = _expect_processing("cleared skill overlay", view.skill_overlay, false) and ok
	view.queue_free()
	await process_frame
	return ok


func _expect_processing(label: String, node: Node, expected: bool) -> bool:
	if node == null or node.is_processing() != expected:
		push_error("The %s should %sprocess" % [label, "" if expected else "not "])
		return false
	return true
