extends SceneTree

# Headless test of casts on rigged figures, through UnitView, with the
# animators stepped by hand at fixed frames (Kit.Stepper): a wind-up holds
# its last key glowing until the cast ends, also through a charge, then
# releases by itself; a cancelled cast (stun, the battle's end) never
# strikes and drops its glow; slowing the battle mid-cast keeps the wind-up
# held; Breakthrough releases with the resolve; the horse's gallop never
# changes faster than its blend under a strike. The boss (outside the rig)
# straightens from a cancelled wind-up without stopping its drop in.

const Kit := preload("res://Tests/pose_test_kit.gd")
# A held pose may drift this far from its key (degrees) while breathing.
const HOLD_TOLERANCE: float = 2.0
const FAST: float = 4.0
const SETTLE_SEC: float = 0.6
# How much faster than its blend the gallop may change in one frame.
const GALLOP_MARGIN: float = 1.25


func _initialize() -> void:
	var ok := await _run()
	if ok:
		print("Pose cast test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	var checks: Array[Callable] = [
		_check_wind_up_holds, _check_wind_up_through_charge, _check_stun_cancels_cast, _check_battle_end_cancels_casts,
		_check_speed_change_mid_cast, _check_breakthrough, _check_gallop_fades, _check_boss_cancel_keeps_drop_in,
		_check_boss_wind_up_cancelled,
	]
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
	var stepper := Kit.Stepper.new()
	stepper.take(view)
	view.wind_up(0.6)
	var ok := await _expect_hold_until_release("Held wind-up", view, stepper, 0.6)
	await stepper.run(self, 1.6)
	ok = Kit.expect_rest("automatic release", view) and ok
	view.queue_free()
	return ok


# A charge during the wind-up's keys keeps the wind-up: the keys play on
# under the gallop, so by the end of the cast the rider is in the last
# wind key, glowing, and holds it until the release.
func _check_wind_up_through_charge() -> bool:
	var view := Kit.make_view(root, &"class.cavalry", 0)
	var stepper := Kit.Stepper.new()
	stepper.take(view)
	view.wind_up(1.0)
	await stepper.run(self, 0.3)
	view.glide_to(view.position + Vector2(0, -160), 0.3, &"charge")
	var ok := await _expect_hold_until_release("Wind-up after a charge", view, stepper, 0.7)
	await stepper.run(self, 1.5)
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
		var stepper := Kit.Stepper.new()
		stepper.take(view)
		view.wind_up(0.6)
		await stepper.run(self, 0.3)
		view.cancel_wind_up()
		ok = await Kit.expect_no_strike("%s stunned mid-cast" % class_id, view, stepper, self, 1.2) and ok
		view.queue_free()
	return ok


# The battle ends while units cast (side 0 loses, so nobody cheers): every
# cast ends there, without its strike, and the feet glow goes off.
func _check_battle_end_cancels_casts() -> bool:
	var playback := BattlePlayback.new()
	root.add_child(playback)
	var stepper := Kit.Stepper.new()
	var views: Array[UnitView] = []
	for index: int in 2:
		var view := Kit.make_view(root, [&"class.mage", &"class.cavalry"][index], 0)
		stepper.take(view)
		view.wind_up(0.8)
		view.skill_overlay.set_casting(true)
		playback._views[index] = view
		views.append(view)
	await stepper.run(self, 0.3)
	playback._on_battle_ended({"winner": 1, "reason": &"test"})
	var ok := true
	for view: UnitView in views:
		if view.skill_overlay.is_casting():
			push_error("%s: the feet glow should end with the battle" % view.unit.class_id)
			ok = false
	for view: UnitView in views:
		ok = await Kit.expect_no_strike("%s at the battle's end" % view.unit.class_id, view, stepper, self, 1.2) and ok
	playback._views.clear()
	playback.queue_free()
	for view: UnitView in views:
		view.queue_free()
	return ok


# Slowing the battle from x4 to x1 mid-cast slows the wind-up too: it must
# not release before the cast at x1 ends.
func _check_speed_change_mid_cast() -> bool:
	var view := Kit.make_view(root, &"class.sword", 0)
	var stepper := Kit.Stepper.new()
	stepper.take(view)
	view.playback_speed = FAST
	view.wind_up(1.0)
	await stepper.run(self, 0.1)
	view.playback_speed = 1.0
	await stepper.run(self, 0.5)
	var ok := true
	if not view.get_animator().is_winding or view.get_pose().values[UnitPose.TRAIL] > 0.0:
		push_error("At x1 the wind-up should still hold after 0.6 s")
		ok = false
	view.recoil(Vector2(0, -1))
	view.playback_speed = FAST
	await stepper.run(self, SETTLE_SEC)
	ok = Kit.expect_rest("after a speed change", view) and ok
	view.queue_free()
	return ok


# Breakthrough: the battle sends the charge move and then the resolve in the
# same tick, before the cast's automatic release could. The rider winds up,
# gallops, the strike plays with the resolve while the horse keeps
# galloping, and nothing of the skill pose stays.
func _check_breakthrough() -> bool:
	var view := Kit.make_view(root, &"class.cavalry", 0)
	var stepper := Kit.Stepper.new()
	var animator := stepper.take(view)
	view.wind_up(0.6)
	await stepper.run(self, 0.5)
	var ok := true
	if not animator.is_winding:
		push_error("The wind-up should still hold 0.5 s into a 0.6 s cast")
		ok = false
	view.glide_to(view.position + Vector2(0, -160), 0.6, &"charge")
	view.recoil(Vector2(0, -1))
	# No frame has run: only the resolve can have released it.
	if animator.is_winding or not animator.is_animating():
		push_error("The resolve should release the wind-up during the charge")
		ok = false
	await stepper.run(self, 0.1)
	if view.get_pose().values[UnitPose.HG] < 0.5:
		push_error("The horse should gallop during the charge")
		ok = false
	await stepper.run(self, 2.0)
	ok = Kit.expect_rest("after Breakthrough", view) and ok
	view.queue_free()
	return ok


# A strike made as a charge starts and outlasting it: the horse's gallop
# rises and fades no faster than its blend (1 / WALK_BLEND_SEC a second),
# never jumping to or from the strike's own amount.
func _check_gallop_fades() -> bool:
	var view := Kit.make_view(root, &"class.cavalry", 0)
	var stepper := Kit.Stepper.new()
	stepper.take(view)
	await stepper.run(self, 0.2)
	view.glide_to(view.position + Vector2(0, -100), 0.15, &"charge")
	# Strikes during the gallop's blend-in, through the end of the charge.
	await stepper.run(self, 0.05)
	view.lunge(Vector2(0, -80))
	var last := view.get_pose().values[UnitPose.HG]
	var fastest := 0.0
	var highest := last
	for frame: int in roundi(0.6 / Kit.Stepper.FRAME):
		await stepper.step(self)
		var gallop := view.get_pose().values[UnitPose.HG]
		fastest = maxf(fastest, absf(gallop - last) / Kit.Stepper.FRAME)
		highest = maxf(highest, gallop)
		last = gallop
	view.queue_free()
	var limit := GALLOP_MARGIN / PoseAnimator.WALK_BLEND_SEC
	if fastest > limit or highest < 0.5 or last > 0.1:
		push_error("The gallop should rise past 0.5 (%.2f) and fade (%.2f) at most %.1f a second, not %.1f" % [highest, last, limit, fastest])
		return false
	return true


# The boss has no rig: cancelling a wind-up it is not playing (a stun as it
# drops in) leaves its drop in running, so it still becomes visible.
func _check_boss_cancel_keeps_drop_in() -> bool:
	var view := _make_boss()
	view.drop_in()
	await create_timer(0.03).timeout
	view.cancel_wind_up()
	await create_timer(1.0).timeout
	var ok := Kit.expect_near("Boss alpha after its drop in", view.modulate.a, 1.0)
	if not view.squash.is_equal_approx(Vector2.ONE) or not view.anim_offset.is_zero_approx():
		push_error("The boss should land unsquashed (%s, %s)" % [view.squash, view.anim_offset])
		ok = false
	view.queue_free()
	return ok


# A boss wind-up cancelled by a stun or by stone straightens the boss.
func _check_boss_wind_up_cancelled() -> bool:
	var ok := true
	for by_stone: bool in [false, true]:
		var view := _make_boss()
		view.wind_up(1.0)
		await create_timer(0.4).timeout
		if by_stone:
			view.set_petrified(true)
		else:
			view.cancel_wind_up()
		await create_timer(0.4).timeout
		if not view.squash.is_equal_approx(Vector2.ONE) or not view.anim_offset.is_zero_approx():
			push_error("A boss wind-up cancelled (stone %s) should straighten it (%s, %s)" % [by_stone, view.squash, view.anim_offset])
			ok = false
		view.queue_free()
	return ok


func _make_boss() -> UnitView:
	var unit := Kit.make_unit(&"class.colossus")
	unit.is_boss = true
	var view := UnitView.new()
	view.setup(unit, 1, 1)
	view.position = Vector2(200, 200)
	root.add_child(view)
	return view


# Steps from the wind-up's start until it releases by itself: each frame
# from shortly before the cast ends (`seconds`) holds the last wind key,
# and the release comes when the grace window ends, not before or after.
func _expect_hold_until_release(label: String, view: UnitView, stepper: Kit.Stepper, seconds: float) -> bool:
	var animator := view.get_animator()
	var held := Kit.wind_pose(view.unit.class_id, animator.view)
	var elapsed := 0.0
	var samples := 0
	var ok := true
	while animator.is_winding and elapsed < seconds + 1.0:
		await stepper.step(self)
		elapsed += Kit.Stepper.FRAME
		if animator.is_winding and elapsed > seconds - 0.05:
			samples += 1
			ok = _expect_held("%s at %.2f s" % [label, elapsed], view, held) and ok
	var due := seconds + PoseAnimator.RELEASE_GRACE_SEC
	if samples < 3 or animator.is_winding or absf(elapsed - due) > Kit.Stepper.FRAME * 1.5:
		push_error("%s: should hold (%d frames) and release by itself at %.2f s, not at %.2f s" % [label, samples, due, elapsed])
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
