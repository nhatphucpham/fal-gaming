extends SceneTree

# Headless test of casts and stone on rigged figures, through UnitView: a
# wind-up holds its last key glowing until the cast ends, also through a
# charge, then releases by itself; a cancelled cast (stun, stone) never
# strikes and drops its glow; stone freezes the pose and redraws and keeps
# no hit flash; slowing the battle mid-cast keeps the wind-up held;
# Breakthrough releases with the resolve; the horse's gallop never jumps
# under a strike.

const Kit := preload("res://Tests/pose_test_kit.gd")
# A held pose may drift this far from its key (degrees) while breathing.
const HOLD_TOLERANCE: float = 2.0
const FAST: float = 4.0
const SETTLE_SEC: float = 0.6


func _initialize() -> void:
	var ok := await _run()
	if ok:
		print("Pose cast test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	var checks: Array[Callable] = [
		_check_wind_up_holds, _check_wind_up_through_charge, _check_stun_cancels_cast, _check_stone_cancels_cast,
		_check_petrify, _check_petrify_after_hit, _check_speed_change_mid_cast, _check_breakthrough, _check_gallop_fades,
	]
	# The first frames after start-up are long: the cast timing checks
	# measure real time, so let them pass first.
	await create_timer(0.5).timeout
	for check: Callable in checks:
		if not await check.call():
			push_error("Pose cast test failed in %s" % check.get_method())
			return false
	return true


# A wind-up holds its last key, raised and glowing, through the whole
# grace window after the cast (no breathing back toward the stance), then
# releases by itself if no resolve came.
func _check_wind_up_holds() -> bool:
	var view := Kit.make_view(root, &"class.sword", 0)
	view.wind_up(0.6)
	var ok := await _expect_hold_until_release("Held wind-up", view, 0.6)
	await create_timer(1.6).timeout
	ok = Kit.expect_rest("automatic release", view) and ok
	view.queue_free()
	return ok


# A charge during the wind-up's keys keeps the wind-up: the keys play on
# under the gallop, so by the end of the cast the rider is in the last
# wind key, glowing, and holds it until the release.
func _check_wind_up_through_charge() -> bool:
	var view := Kit.make_view(root, &"class.cavalry", 0)
	view.wind_up(1.0)
	await create_timer(0.3).timeout
	view.glide_to(view.position + Vector2(0, -160), 0.3, &"charge")
	var ok := await _expect_hold_until_release("Wind-up after a charge", view, 0.7)
	await create_timer(1.5).timeout
	ok = Kit.expect_rest("after the charge's wind-up", view) and ok
	view.queue_free()
	return ok


# A stun mid-cast cancels it (the battle sends no resolve): the view drops
# the wind-up as skill playback does, and no strike plays: no trail, no
# step toward the target, the glow fading, then rest.
func _check_stun_cancels_cast() -> bool:
	var ok := true
	for class_id: StringName in Kit.RIG_CLASS_IDS:
		var view := Kit.make_view(root, class_id, 0)
		view.wind_up(0.6)
		await create_timer(0.3).timeout
		view.cancel_wind_up()
		ok = await _expect_no_strike("%s stunned mid-cast" % class_id, view, 1.2) and ok
		view.queue_free()
	return ok


# Stone mid-cast cancels it too: the statue does not glow, and after the
# thaw the figure settles to rest without a strike or a glow.
func _check_stone_cancels_cast() -> bool:
	var ok := true
	for class_id: StringName in Kit.RIG_CLASS_IDS:
		var view := Kit.make_view(root, class_id, 1)
		view.wind_up(0.6)
		await create_timer(0.3).timeout
		view.set_petrified(true)
		var glow := view.get_pose().values[UnitPose.GLOW]
		if glow != 0.0 or view.get_animator().is_winding:
			push_error("%s turned to stone mid-cast should not glow (%.2f) or wind up" % [class_id, glow])
			ok = false
		await create_timer(0.6).timeout
		view.set_petrified(false)
		ok = await _expect_no_strike("%s thawed after a cast" % class_id, view, 1.2) and ok
		view.queue_free()
	return ok


func _check_petrify() -> bool:
	var view := Kit.make_view(root, &"class.spear", 0)
	view.lunge(Vector2(40, -80))
	await create_timer(0.05).timeout
	view.set_petrified(true)
	await process_frame
	var frozen := view.get_pose().values
	var draws := Kit.count_draws(view)
	await create_timer(0.5).timeout
	var ok := true
	if view.get_pose().values != frozen or not view.get_animator().trail_weights.is_empty() or draws[0] != 0:
		push_error("Stone should freeze the pose, drop the trail and stop the redraws (%d redraws)" % draws[0])
		ok = false
	view.set_petrified(false)
	view.playback_speed = FAST
	await create_timer(SETTLE_SEC).timeout
	ok = Kit.expect_rest("after the stone", view) and ok
	view.queue_free()
	return ok


# Turned to stone just after a hit: the statue keeps no white flash (in
# its pose or on its figure, at once) or trail.
func _check_petrify_after_hit() -> bool:
	var view := Kit.make_view(root, &"class.sword", 1)
	await create_timer(0.2).timeout
	view.hit_flash()
	await create_timer(0.05).timeout
	view.set_petrified(true)
	var figure := _figure_of(view)
	var shader_flash: float = (figure.material as ShaderMaterial).get_shader_parameter(&"flash")
	var ok := Kit.expect_near("Figure flash right after the stone", figure.flash, 0.0)
	ok = Kit.expect_near("Shader flash right after the stone", shader_flash, 0.0) and ok
	await create_timer(0.5).timeout
	var values := view.get_pose().values
	ok = Kit.expect_near("Flash of a statue made mid-hit", values[UnitPose.FLASH], 0.0) and ok
	ok = Kit.expect_near("Figure flash of a statue made mid-hit", figure.flash, 0.0) and ok
	ok = Kit.expect_near("Trail of a statue made mid-hit", values[UnitPose.TRAIL], 0.0) and ok
	view.queue_free()
	return ok


# Slowing the battle from x4 to x1 mid-cast slows the wind-up too: it must
# not release before the cast at x1 ends.
func _check_speed_change_mid_cast() -> bool:
	var view := Kit.make_view(root, &"class.sword", 0)
	view.playback_speed = FAST
	view.wind_up(1.0)
	await create_timer(0.1).timeout
	view.playback_speed = 1.0
	await create_timer(0.5).timeout
	var ok := true
	if not view.get_animator().is_winding or view.get_pose().values[UnitPose.TRAIL] > 0.0:
		push_error("At x1 the wind-up should still hold after 0.6 s")
		ok = false
	view.recoil(Vector2(0, -1))
	view.playback_speed = FAST
	await create_timer(SETTLE_SEC).timeout
	ok = Kit.expect_rest("after a speed change", view) and ok
	view.queue_free()
	return ok


# Breakthrough: the battle sends the charge move and then the resolve in the
# same tick. The rider winds up, gallops, the strike plays with the resolve
# while the horse keeps galloping, and nothing of the skill pose stays.
func _check_breakthrough() -> bool:
	var view := Kit.make_view(root, &"class.cavalry", 0)
	view.wind_up(0.6)
	await create_timer(0.6).timeout
	view.glide_to(view.position + Vector2(0, -160), 0.6, &"charge")
	view.recoil(Vector2(0, -1))
	await create_timer(0.1).timeout
	var animator := view.get_animator()
	var ok := true
	if animator.is_winding or not animator.is_animating():
		push_error("The resolve should release the wind-up during the charge")
		ok = false
	if view.get_pose().values[UnitPose.HG] < 0.5:
		push_error("The horse should gallop during the charge")
		ok = false
	await create_timer(2.0).timeout
	ok = Kit.expect_rest("after Breakthrough", view) and ok
	view.queue_free()
	return ok


# A strike made as a charge starts and outlasting it: the horse's gallop
# rises and fades smoothly, never jumping to or from the strike's own amount.
func _check_gallop_fades() -> bool:
	var view := Kit.make_view(root, &"class.cavalry", 0)
	await create_timer(0.2).timeout
	view.glide_to(view.position + Vector2(0, -100), 0.15, &"charge")
	# Strikes during the gallop's blend-in, through the end of the charge.
	await create_timer(0.05).timeout
	view.lunge(Vector2(0, -80))
	var last := view.get_pose().values[UnitPose.HG]
	var worst := 0.0
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 600:
		await process_frame
		var gallop := view.get_pose().values[UnitPose.HG]
		worst = maxf(worst, absf(gallop - last))
		last = gallop
	view.queue_free()
	if worst > 0.2:
		push_error("The horse's gallop jumped by %.2f in one frame" % worst)
		return false
	return true


# Samples every frame from shortly before the cast ends (`seconds` from
# now) until the wind-up releases by itself: each sample holds the last
# wind key, and the release comes within the grace window.
func _expect_hold_until_release(label: String, view: UnitView, seconds: float) -> bool:
	var animator := view.get_animator()
	var held := _wind_pose(view.unit.class_id, animator.view)
	var start := Time.get_ticks_msec()
	var samples := 0
	var ok := true
	while animator.is_winding and Time.get_ticks_msec() - start < (seconds + 1.0) * 1000.0:
		var elapsed := (Time.get_ticks_msec() - start) * 0.001
		if elapsed > seconds - 0.05:
			samples += 1
			ok = _expect_held("%s at %.2f s" % [label, elapsed], view, held) and ok
		await process_frame
	var released_at := (Time.get_ticks_msec() - start) * 0.001
	if samples < 3 or animator.is_winding or released_at > seconds + PoseAnimator.RELEASE_GRACE_SEC + 0.1:
		push_error("%s: should hold (%d frames) and release by itself just after the cast, not at %.2f s" % [label, samples, released_at])
		ok = false
	return ok


# The pose at the view's figure close to `held` (the arms and blade, up to
# breathing) and glowing.
func _expect_held(label: String, view: UnitView, held: UnitPose) -> bool:
	var values := view.get_pose().values
	var ok := Kit.expect_near("%s: glow" % label, values[UnitPose.GLOW], 1.0, 0.1)
	for index: int in [UnitPose.UA_F, UnitPose.LA_F, UnitPose.BLADE]:
		ok = Kit.expect_near("%s: %s" % [label, UnitPose.KEYS[index]], values[index], held.values[index], HOLD_TOLERANCE) and ok
	return ok


# The last key of the class's wind-up (the skill clip's first keys).
func _wind_pose(class_id: StringName, view: StringName) -> UnitPose:
	var kit := RigKit.get_kit(class_id)
	var clip := kit.get_clip(&"skillUp" if view == RigSolver.VIEW_BACK else &"skillDown", view)
	return clip[kit.skill_wind_keys - 1].pose


# Samples every frame for `seconds`: no trail, no step toward the target
# (dx never grows past what showed), no glow coming back and no wind-up;
# then the rest pose.
func _expect_no_strike(label: String, view: UnitView, seconds: float) -> bool:
	var ok := true
	var last := view.get_pose().values
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		await process_frame
		var values := view.get_pose().values
		var rising := values[UnitPose.DX] > maxf(last[UnitPose.DX], 0.0) + 0.001 or values[UnitPose.GLOW] > last[UnitPose.GLOW] + 0.001
		if values[UnitPose.TRAIL] > 0.0 or rising or view.get_animator().is_winding:
			push_error("%s: a strike or a glow plays (trail %.2f, dx %.2f, glow %.2f)" % [label, values[UnitPose.TRAIL], values[UnitPose.DX], values[UnitPose.GLOW]])
			return false
		last = values
	return Kit.expect_rest(label, view) and ok


func _figure_of(view: UnitView) -> UnitFigure:
	for child: Node in view.get_children():
		if child is UnitFigure:
			return child
	return null
