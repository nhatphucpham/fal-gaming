extends SceneTree

# Headless test of the PoseAnimator through UnitView, for every class in
# both views: each action (attack, skill, hit, knockback, walk, cheer, and
# the battle's event orders) ends at the rest pose; a wind-up holds its
# last key glowing until the cast ends, also through a charge, then
# releases by itself; death stays down without redraws; stone freezes the
# pose and drops a hit's flash; figures outside the rig stay idle; idle
# redraws are throttled at any battle speed and a calm figure only blinks;
# the battle speed scales the clips, also mid-cast; Breakthrough releases
# with the resolve; the horse's gallop fades out under a strike; glides
# and hops clear the lean; an archer shooting straight ahead turns its bow
# hand the way the sketch does.

const Kit := preload("res://Tests/pose_test_kit.gd")
# Breathing moves the rest pose by up to 1.5 degrees.
const REST_TOLERANCE: float = 1.8
# A held pose may drift this far from its key (degrees) while breathing.
const HOLD_TOLERANCE: float = 2.0
# Every animator test but the speed ones runs the battle at x4.
const FAST: float = 4.0
const SETTLE_SEC: float = 0.6


func _initialize() -> void:
	var ok := await _run()
	if ok:
		print("Pose animator test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	var checks: Array[Callable] = [
		_check_actions_rest, _check_event_orders_rest, _check_wind_up_holds, _check_wind_up_through_charge,
		_check_die, _check_petrify, _check_petrify_after_hit, _check_posed_off_idle, _check_idle_redraws,
		_check_calm_idle, _check_speed, _check_speed_change_mid_cast, _check_breakthrough, _check_gallop_fades,
		_check_glide_clears_lean, _check_archer_straight_shot,
	]
	for check: Callable in checks:
		if not await check.call():
			push_error("Pose animator test failed in %s" % check.get_method())
			return false
	return true


# Each action, for every class seen from both sides, ends at the rest pose:
# the stance after a fight action, idle after a walk or a cheer.
func _check_actions_rest() -> bool:
	var actions: Dictionary[String, Callable] = {
		"attack": func(view: UnitView) -> void: view.lunge(Vector2(30, -80) * _ahead(view)),
		"skill": func(view: UnitView) -> void:
			view.wind_up(0.4)
			await create_timer(0.4 / FAST).timeout
			view.recoil(Vector2(0, -80) * _ahead(view)),
		"hit": func(view: UnitView) -> void: view.hit_flash(),
		"knockback": func(view: UnitView) -> void: view.glide_to(view.position + Vector2(0, 40), 0.4, &"knockback"),
		"walk": func(view: UnitView) -> void: view.glide_to(view.position + Vector2(0, -80), 0.6, &"walk"),
		"cheer": func(view: UnitView) -> void: view.cheer(),
	}
	var ok := true
	for action: String in actions:
		ok = await _expect_rest_after(action, actions[action]) and ok
	return ok


# The battle replay's orders that once left a skill pose behind: a resolve
# followed one tick later by a move or an attack, a cast then a cheer.
func _check_event_orders_rest() -> bool:
	var tick := 0.05 / FAST
	var orders: Dictionary[String, Callable] = {
		"move after a resolve": func(view: UnitView) -> void:
			view.wind_up(0.45)
			await create_timer(0.45 / FAST).timeout
			view.recoil(Vector2(0, -1) * _ahead(view))
			await create_timer(tick).timeout
			view.glide_to(view.position + Vector2(0, -80), 0.5, &"walk"),
		"attack after a resolve": func(view: UnitView) -> void:
			view.wind_up(0.45)
			await create_timer(0.45 / FAST).timeout
			view.recoil(Vector2(0, -1) * _ahead(view))
			await create_timer(tick).timeout
			view.lunge(Vector2(0, -80) * _ahead(view)),
		"cheer after a cast": func(view: UnitView) -> void:
			view.recoil(Vector2(0, -1) * _ahead(view))
			await create_timer(tick * 2.0).timeout
			view.cheer(),
	}
	var ok := true
	for order: String in orders:
		ok = await _expect_rest_after(order, orders[order]) and ok
	return ok


# A wind-up holds its last key, raised and glowing, through the whole
# grace window after the cast (no breathing back toward the stance), then
# releases by itself if no resolve came.
func _check_wind_up_holds() -> bool:
	var view := Kit.make_view(root, &"class.sword", 0)
	view.wind_up(0.6)
	var ok := await _expect_hold_until_release("Held wind-up", view, 0.6)
	await create_timer(1.6).timeout
	ok = _expect_rest("automatic release", view) and ok
	view.queue_free()
	return ok


# A charge during a wind-up keeps it: the rider is back in the wind-up's
# last key, glowing, by the end of the cast, and holds it until the release.
func _check_wind_up_through_charge() -> bool:
	var view := Kit.make_view(root, &"class.cavalry", 0)
	view.wind_up(1.0)
	await create_timer(0.3).timeout
	view.glide_to(view.position + Vector2(0, -160), 0.3, &"charge")
	var ok := await _expect_hold_until_release("Wind-up after a charge", view, 0.7)
	await create_timer(1.5).timeout
	ok = _expect_rest("after the charge's wind-up", view) and ok
	view.queue_free()
	return ok


# Down for good: the last pose of the fall, no redraws, and no later action
# moves it. The animator alone is told to die so the view never hides
# (a hidden figure would not redraw anyway).
func _check_die() -> bool:
	var ok := true
	for class_id: StringName in Kit.RIG_CLASS_IDS:
		var view := Kit.make_view(root, class_id, 1)
		view.playback_speed = FAST
		var animator := view.get_animator()
		animator.die()
		var start := Time.get_ticks_msec()
		while animator.is_animating() and Time.get_ticks_msec() - start < 3000:
			await process_frame
		await create_timer(0.1).timeout
		var fallen := view.get_pose().values
		var draws := Kit.count_draws(view)
		view.lunge(Vector2(0, 80))
		view.wind_up(0.3)
		view.hit_flash()
		view.cheer()
		view.glide_to(view.position + Vector2(0, 40), 0.3, &"walk")
		await create_timer(0.4).timeout
		var fall := RigKit.get_kit(class_id).get_clip(&"fall", RigSolver.VIEW_FRONT)
		var last := fall[fall.size() - 1].pose.values
		if not view.is_visible_in_tree() or view.get_pose().values != fallen or fallen != last or draws[0] != 0:
			push_error("%s should stay down, shown, in its last fall pose without redraws (%d redraws)" % [class_id, draws[0]])
			ok = false
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
	ok = _expect_rest("after the stone", view) and ok
	view.queue_free()
	return ok


# Turned to stone just after a hit: the statue keeps no white flash or trail.
func _check_petrify_after_hit() -> bool:
	var view := Kit.make_view(root, &"class.sword", 1)
	await create_timer(0.2).timeout
	view.hit_flash()
	await create_timer(0.05).timeout
	view.set_petrified(true)
	await create_timer(0.5).timeout
	var values := view.get_pose().values
	var ok := Kit.expect_near("Flash of a statue made mid-hit", values[UnitPose.FLASH], 0.0)
	ok = Kit.expect_near("Trail of a statue made mid-hit", values[UnitPose.TRAIL], 0.0) and ok
	view.queue_free()
	return ok


# Figures outside the rig (the boss, the sage) never pose or redraw while
# idle, even though Godot re-enables processing when they enter the tree.
func _check_posed_off_idle() -> bool:
	var ok := true
	for class_id: StringName in [&"class.colossus", &"class.sage"]:
		var view := Kit.make_view(root, class_id, 1)
		await create_timer(0.3).timeout
		var draws := Kit.count_draws(view)
		view.lunge(Vector2(0, 80))
		view.wind_up(0.2)
		view.get_animator().walk(0.2, false)
		await create_timer(1.0).timeout
		if draws[0] > 2 or view.get_animator().is_animating():
			push_error("%s should not pose; it redrew %d times in 1 s" % [class_id, draws[0]])
			ok = false
		view.queue_free()
	return ok


# Idle (no action) redraws about 10 times a second, not every frame, at
# x1 and at x4 alike.
func _check_idle_redraws() -> bool:
	var ok := true
	for speed: float in [1.0, FAST]:
		var view := Kit.make_view(root, &"class.archer", 0)
		view.playback_speed = speed
		await create_timer(0.3).timeout
		var draws := Kit.count_draws(view)
		await create_timer(1.0).timeout
		view.queue_free()
		if draws[0] < 7 or draws[0] > 14:
			push_error("Idle at x%.0f should redraw about 10 times a second, not %d" % [speed, draws[0]])
			ok = false
	return ok


# A calm figure (bench, dimmed line-up) holds still and redraws only to
# blink, at most twice per blink.
func _check_calm_idle() -> bool:
	var view := Kit.make_view(root, &"class.mage", 1)
	view.set_dim(0.4)
	await create_timer(0.3).timeout
	var torso := view.get_pose().values[UnitPose.TORSO]
	var draws := Kit.count_draws(view)
	await create_timer(2.0).timeout
	var ok := true
	if draws[0] > 4 or view.get_pose().values[UnitPose.TORSO] != torso:
		push_error("A calm figure should only blink: %d redraws in 2 s" % draws[0])
		ok = false
	view.set_dim(0.0)
	draws = Kit.count_draws(view)
	await create_timer(0.5).timeout
	if draws[0] < 3:
		push_error("A figure no longer dimmed should breathe again, %d redraws" % draws[0])
		ok = false
	view.queue_free()
	return ok


func _check_speed() -> bool:
	var slow := Kit.make_view(root, &"class.shield", 0)
	var fast := Kit.make_view(root, &"class.shield", 0)
	fast.playback_speed = FAST
	var seconds := 0.0
	for key: RigClips.ClipKey in RigKit.get_kit(&"class.shield").get_clip(&"attackUp", RigSolver.VIEW_BACK):
		seconds += key.seconds
	slow.lunge(Vector2(0, -80))
	fast.lunge(Vector2(0, -80))
	await create_timer(seconds / FAST + PoseAnimator.REST_SETTLE_SEC / FAST + 0.15).timeout
	var ok := _expect_rest("attack at x4", fast)
	if not slow.get_animator().is_animating():
		push_error("At x1 the attack should still play after %.2f s" % (seconds / FAST))
		ok = false
	slow.queue_free()
	fast.queue_free()
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
	ok = _expect_rest("after a speed change", view) and ok
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
	ok = _expect_rest("after Breakthrough", view) and ok
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


# A knockback glide cut off by a new glide or hop must not leave the unit tilted.
func _check_glide_clears_lean() -> bool:
	var view := Kit.make_view(root, &"class.sword", 0)
	view.glide_to(view.position + Vector2(40, 0), 0.4, &"knockback")
	await create_timer(0.2).timeout
	if absf(view.lean) < 0.05:
		push_error("A knockback should tilt the unit, lean is %.3f" % view.lean)
		view.queue_free()
		return false
	view.glide_to(view.position + Vector2(0, 80), 0.3, &"walk")
	var ok := Kit.expect_near("Lean after a glide cut a knockback short", view.lean, 0.0)
	view.glide_to(view.position + Vector2(40, 0), 0.4, &"knockback")
	await create_timer(0.2).timeout
	view.hop_to(view.position + Vector2(0, 80), 0.3)
	ok = Kit.expect_near("Lean after a hop cut a knockback short", view.lean, 0.0) and ok
	view.queue_free()
	return ok


# Like the sketch, an archer shooting straight ahead turns its bow hand as
# if the target were on its side's own facing (so the player's archer faces
# left); other classes keep their facing. A target to the side still wins.
func _check_archer_straight_shot() -> bool:
	var ok := true
	for side: int in 2:
		var archer := Kit.make_view(root, &"class.archer", side)
		var sword := Kit.make_view(root, &"class.sword", side)
		var own := 1.0 if side == 0 else -1.0
		archer.recoil(Vector2(0, -200) * _ahead(archer))
		sword.lunge(Vector2(0, -80) * _ahead(sword))
		if archer.get_flip() != -own or sword.get_flip() != own:
			push_error("Side %d shooting straight: the archer should face %.0f (is %.0f), the sword %.0f (is %.0f)" % [side, -own, archer.get_flip(), own, sword.get_flip()])
			ok = false
		archer.recoil(Vector2(120, -200))
		if archer.get_flip() != -1.0:
			push_error("An archer shooting to the right should turn its bow hand right (flip -1), not %.0f" % archer.get_flip())
			ok = false
		archer.queue_free()
		sword.queue_free()
	return ok


# Runs `action` (func(view)) on every rigged class from both sides at x4
# and expects each to end at its rest pose.
func _expect_rest_after(label: String, action: Callable) -> bool:
	var views: Array[UnitView] = []
	for class_id: StringName in Kit.RIG_CLASS_IDS:
		for side: int in 2:
			var view := Kit.make_view(root, class_id, side)
			view.playback_speed = FAST
			views.append(view)
	for view: UnitView in views:
		action.call(view)
	await create_timer(1.0).timeout
	var ok := true
	for view: UnitView in views:
		ok = _expect_rest("%s, %s side %d" % [label, view.unit.class_id, view.side], view) and ok
		view.queue_free()
	return ok


# The pose back at the animator's rest pose (up to breathing), with no
# clip, trail, glow, flash or step left, and the figure unsquashed.
func _expect_rest(label: String, view: UnitView) -> bool:
	var animator := view.get_animator()
	var values := view.get_pose().values
	var rest := animator.get_stance().values
	var worst := 0.0
	var field := ""
	for index: int in values.size():
		var gap := absf(values[index] - rest[index])
		if index != UnitPose.EYES and gap > worst:
			worst = gap
			field = UnitPose.KEYS[index]
	var ok := true
	if worst > REST_TOLERANCE or animator.is_animating() or animator.is_winding:
		push_error("%s: should be at rest, %s is %.2f off (animating %s)" % [label, field, worst, animator.is_animating()])
		ok = false
	for index: int in [UnitPose.TRAIL, UnitPose.GLOW, UnitPose.FLASH, UnitPose.DX]:
		ok = Kit.expect_near("%s: %s" % [label, UnitPose.KEYS[index]], values[index], 0.0) and ok
	if not view.squash.is_equal_approx(Vector2.ONE):
		push_error("%s: squash should be (1, 1), not %s" % [label, view.squash])
		ok = false
	return ok


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


# The enemy side attacks down the board.
func _ahead(view: UnitView) -> float:
	return 1.0 if view.side == 0 else -1.0
