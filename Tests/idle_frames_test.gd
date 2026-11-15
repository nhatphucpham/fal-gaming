extends SceneTree

# Headless test that idle pieces of the screen leave frames undrawn, so low
# processor mode can skip them (Docs/systems/performance.md). A frame
# "changes" when RenderingServer.has_changed() says it would have to be
# drawn: the test draws by hand (force_draw) before each frame and asks
# after it. Checks: an idle unit view writes no transform, a full Khí bar
# and a cast glow process only while they show; idle figures and card
# pulses share the IdleTicks steps, so a board of them changes at most
# IdleTicks.STEPS_PER_SEC frames a second; formation outlines redraw only
# while a light, stamp, flash or shatter plays, and near-misses breathe on
# the shared steps.

const Kit := preload("res://Tests/pose_test_kit.gd")
const SETTLE_SEC: float = 0.4
const IDLE_FIGURES: int = 12


func _initialize() -> void:
	var ok := true
	var checks: Array[Callable] = [_check_still_view, _check_bar_and_overlay_processing, _check_shared_idle_frames, _check_still_outlines]
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


# Twelve breathing figures (each 10 redraws a second) and a glowing shop
# card with a merge hint redraw on the shared steps only: before, each
# figure had a phase of its own and nearly every frame redrew something.
func _check_shared_idle_frames() -> bool:
	var nodes: Array[Node] = []
	for index: int in IDLE_FIGURES:
		nodes.append(Kit.make_view(root, Kit.RIG_CLASS_IDS[index % 6], index % 2))
	var card := ShopCard.new()
	root.add_child(card)
	card.set_unit(Kit.make_unit(&"class.mage", &"race.human", 5))
	card.set_merge_hint(true)
	nodes.append(card)
	await create_timer(SETTLE_SEC).timeout
	var counts := await count_changed_frames(1.0)
	for node: Node in nodes:
		node.queue_free()
	await process_frame
	# One step more for a boundary at either end of the second.
	if counts[0] > IdleTicks.STEPS_PER_SEC + 1:
		push_error("Idle figures changed %d of %d frames in 1 s" % counts)
		return false
	if counts[0] < IdleTicks.PER_SEC:
		push_error("Idle figures should still breathe; only %d of %d frames changed" % counts)
		return false
	return true


# Outlines that are done animating leave every frame undrawn; a stamp and
# a shatter animate and then stop (the shattered one is gone); near-miss
# outlines breathe on the shared steps.
func _check_still_outlines() -> bool:
	var outlines := FormationOutlines.new()
	root.add_child(outlines)
	var cells: Array = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
	var global_cells: Array = cells.map(func(cell: Vector2i) -> Vector2i: return Battle.local_to_global(Battle.SIDE_A, cell.x, cell.y))
	outlines.show_side(Battle.SIDE_A, {"formations": [{"id": &"formation.idle_test", "cells": cells}]}, true)
	await process_frame
	var ok := true
	if not outlines.is_animating():
		push_error("A new formation should run its light and stamp its name")
		ok = false
	await create_timer(FormationOutlines.STAMP_SEC + 0.2).timeout
	var counts := await count_changed_frames(0.5)
	if outlines.is_animating() or counts[0] > 0:
		push_error("Still outlines changed %d of %d frames" % counts)
		ok = false
	outlines.roll_call()
	outlines.shatter(Battle.SIDE_A, &"formation.idle_test", global_cells)
	if outlines.get_broken(Battle.SIDE_A).size() != 1:
		push_error("The shattered outline should be listed while it fades")
		ok = false
	await create_timer(FormationOutlines.STAMP_SEC + 0.2).timeout
	counts = await count_changed_frames(0.5)
	if outlines.is_animating() or counts[0] > 0 or not outlines.get_broken(Battle.SIDE_A).is_empty():
		push_error("After a roll call and a shatter the outlines changed %d of %d frames" % counts)
		ok = false
	var near := {"near_formations": [{"id": &"formation.idle_test", "cells": [Vector2i(1, 1), Vector2i(2, 1)], "missing_cell": Vector2i(3, 1), "needed_class": &""}]}
	outlines.show_side(Battle.SIDE_A, near, false)
	counts = await count_changed_frames(1.0)
	if counts[0] > IdleTicks.STEPS_PER_SEC + 1 or counts[0] < IdleTicks.PER_SEC:
		push_error("A near-miss outline should breathe on the shared steps; it changed %d of %d frames" % counts)
		ok = false
	outlines.queue_free()
	await process_frame
	return ok
