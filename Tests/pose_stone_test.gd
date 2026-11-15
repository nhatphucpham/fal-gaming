extends SceneTree

# Headless test of stone (Hóa Đá) on figures, through UnitView, with the
# animators stepped by hand at fixed frames (Kit.Stepper): stone cancels a
# cast, freezes the pose, stops the redraws and keeps no hit flash or
# trail; a hit landing on a statue (an arrow in flight) neither flashes it
# nor makes it flinch, rigged or the boss; the thaw settles from the stone
# pose without a jump, and a strike released in the frame the stone came
# does not play after the thaw.

const Kit := preload("res://Tests/pose_test_kit.gd")
const FAST: float = 4.0
const SETTLE_SEC: float = 0.6
# The first frame after a thaw moves no value further than this (degrees).
const THAW_STEP: float = 1.0


func _initialize() -> void:
	var ok := await _run()
	if ok:
		print("Pose stone test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	var checks: Array[Callable] = [
		_check_stone_cancels_cast, _check_petrify, _check_petrify_after_hit, _check_statue_ignores_late_hit,
		_check_thaw_mid_clip, _check_stone_on_release,
	]
	for check: Callable in checks:
		if not await check.call():
			push_error("Pose stone test failed in %s" % check.get_method())
			return false
	return true


# Stone mid-cast cancels it: the statue does not glow, and after the thaw
# the figure settles to rest without a strike or a glow.
func _check_stone_cancels_cast() -> bool:
	var ok := true
	for class_id: StringName in Kit.RIG_CLASS_IDS:
		var view := Kit.make_view(root, class_id, 1)
		var stepper := Kit.Stepper.new()
		stepper.take(view)
		view.wind_up(0.6)
		await stepper.run(self, 0.3)
		view.set_petrified(true)
		var glow := view.get_pose().values[UnitPose.GLOW]
		if glow != 0.0 or view.get_animator().is_winding:
			push_error("%s turned to stone mid-cast should not glow (%.2f) or wind up" % [class_id, glow])
			ok = false
		await stepper.run(self, 0.6)
		view.set_petrified(false)
		ok = await Kit.expect_no_strike("%s thawed after a cast" % class_id, view, stepper, self, 1.2) and ok
		view.queue_free()
	return ok


# Stone freezes the pose, drops the trail and stops the redraws; the thaw
# settles to rest.
func _check_petrify() -> bool:
	var view := Kit.make_view(root, &"class.spear", 0)
	var stepper := Kit.Stepper.new()
	var animator := stepper.take(view)
	view.lunge(Vector2(40, -80))
	await stepper.run(self, 0.05)
	view.set_petrified(true)
	await stepper.step(self)
	var frozen := view.get_pose().values
	var draws := Kit.count_draws(view)
	await stepper.run(self, 0.5)
	var ok := true
	if view.get_pose().values != frozen or not animator.trail.is_empty() or draws[0] != 0:
		push_error("Stone should freeze the pose, drop the trail and stop the redraws (%d redraws)" % draws[0])
		ok = false
	view.set_petrified(false)
	view.playback_speed = FAST
	await stepper.run(self, SETTLE_SEC)
	ok = Kit.expect_rest("after the stone", view) and ok
	view.queue_free()
	return ok


# Turned to stone just after a hit: the statue keeps no white flash (in
# its pose or on its figure, at once) or trail.
func _check_petrify_after_hit() -> bool:
	var view := Kit.make_view(root, &"class.sword", 1)
	var stepper := Kit.Stepper.new()
	stepper.take(view)
	await stepper.run(self, 0.2)
	view.hit_flash()
	await stepper.run(self, 0.05)
	view.set_petrified(true)
	var figure := Kit.figure_of(view)
	var ok := Kit.expect_near("Figure flash right after the stone", figure.flash, 0.0)
	ok = Kit.expect_near("Shader flash right after the stone", _shader_flash(figure), 0.0) and ok
	await stepper.run(self, 0.5)
	var values := view.get_pose().values
	ok = Kit.expect_near("Flash of a statue made mid-hit", values[UnitPose.FLASH], 0.0) and ok
	ok = Kit.expect_near("Figure flash of a statue made mid-hit", figure.flash, 0.0) and ok
	ok = Kit.expect_near("Trail of a statue made mid-hit", values[UnitPose.TRAIL], 0.0) and ok
	view.queue_free()
	return ok


# A hit landing after the stone (an arrow in flight, delayed damage): the
# statue, rigged or the boss, stays as it is: no flash, no flinch.
func _check_statue_ignores_late_hit() -> bool:
	var ok := true
	for is_boss: bool in [false, true]:
		var unit := Kit.make_unit(&"class.colossus" if is_boss else &"class.sword")
		unit.is_boss = is_boss
		var view := UnitView.new()
		view.setup(unit, 1, 1)
		view.position = Vector2(200, 200)
		root.add_child(view)
		var stepper := Kit.Stepper.new()
		stepper.take(view)
		view.set_petrified(true)
		# The stone's own thud settles first.
		await create_timer(0.3).timeout
		var frozen := view.get_pose().values
		view.hit_flash()
		var figure := Kit.figure_of(view)
		var label := "Statue (%s) hit late" % unit.class_id
		for frame: int in 6:
			await stepper.step(self)
			ok = Kit.expect_near("%s: figure flash" % label, figure.flash, 0.0) and ok
			if not view.squash.is_equal_approx(Vector2.ONE) or view.get_pose().values != frozen:
				push_error("%s: should not flinch (squash %s) or change its pose" % [label, view.squash])
				ok = false
		if not is_boss:
			ok = Kit.expect_near("%s: shader flash" % label, _shader_flash(figure), 0.0) and ok
		view.queue_free()
	return ok


# Turned to stone mid-strike and thawed: the figure goes on from the stone
# pose (no jump to where the clip would be), easing to rest.
func _check_thaw_mid_clip() -> bool:
	var view := Kit.make_view(root, &"class.spear", 0)
	var stepper := Kit.Stepper.new()
	stepper.take(view)
	view.lunge(Vector2(40, -80))
	await stepper.run(self, 0.12)
	view.set_petrified(true)
	var frozen := view.get_pose().values
	await stepper.run(self, 0.3)
	view.set_petrified(false)
	await stepper.step(self)
	var thawed := view.get_pose().values
	var ok := true
	for index: int in thawed.size():
		if index != UnitPose.EYES and absf(thawed[index] - frozen[index]) > THAW_STEP:
			push_error("The thaw should start from the stone pose: %s jumped %.2f -> %.2f" % [UnitPose.KEYS[index], frozen[index], thawed[index]])
			ok = false
	await stepper.run(self, SETTLE_SEC)
	ok = Kit.expect_rest("after a thaw mid-strike", view) and ok
	view.queue_free()
	return ok


# The resolve and the stone in one frame (the strike starts, then the
# stone): the strike does not play after the thaw.
func _check_stone_on_release() -> bool:
	var view := Kit.make_view(root, &"class.sword", 0)
	var stepper := Kit.Stepper.new()
	stepper.take(view)
	view.wind_up(0.6)
	await stepper.run(self, 0.6)
	view.recoil(Vector2(0, -1))
	view.set_petrified(true)
	await stepper.run(self, 0.3)
	view.set_petrified(false)
	var ok := await Kit.expect_no_strike("Thawed after a strike cut by stone", view, stepper, self, 1.2)
	view.queue_free()
	return ok


func _shader_flash(figure: UnitFigure) -> float:
	return (figure.material as ShaderMaterial).get_shader_parameter(&"flash")
