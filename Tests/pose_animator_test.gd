extends SceneTree

# Headless test of the PoseAnimator through UnitView, for every class in
# both views: each action (attack, skill, hit, knockback, walk, cheer, and
# the battle's event orders) ends at the rest pose; death stays down
# without redraws; figures outside the rig stay idle; idle redraws are
# throttled at any battle speed, blinks still show at x4 and a calm figure
# only blinks; the battle speed scales the clips; glides and hops clear
# the lean; the trail takes a sample every frame; a long frame steps the
# clips by at most MAX_STEP_SEC; an archer shooting straight ahead turns
# its bow hand the way the sketch does. The timing checks step the
# animators by hand (Kit.Stepper). Casts and stone have their own tests,
# pose_cast_test.gd and pose_stone_test.gd.

const Kit := preload("res://Tests/pose_test_kit.gd")
# Every animator test but the speed ones runs the battle at x4.
const FAST: float = 4.0


func _initialize() -> void:
	var ok := await _run()
	if ok:
		print("Pose animator test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	var checks: Array[Callable] = [
		_check_actions_rest, _check_event_orders_rest, _check_die, _check_posed_off_idle, _check_idle_redraws,
		_check_blinks_at_speed, _check_calm_idle, _check_speed, _check_glide_clears_lean, _check_trail_every_frame,
		_check_step_cap, _check_archer_straight_shot,
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
		"attack": func(view: UnitView) -> void: view.lunge(Vector2(30, -80) * Kit.ahead(view)),
		"skill": func(view: UnitView) -> void:
			view.wind_up(0.4)
			await create_timer(0.4 / FAST).timeout
			view.recoil(Vector2(0, -80) * Kit.ahead(view)),
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
			view.recoil(Vector2(0, -1) * Kit.ahead(view))
			await create_timer(tick).timeout
			view.glide_to(view.position + Vector2(0, -80), 0.5, &"walk"),
		"attack after a resolve": func(view: UnitView) -> void:
			view.wind_up(0.45)
			await create_timer(0.45 / FAST).timeout
			view.recoil(Vector2(0, -1) * Kit.ahead(view))
			await create_timer(tick).timeout
			view.lunge(Vector2(0, -80) * Kit.ahead(view)),
		"cheer after a cast": func(view: UnitView) -> void:
			view.recoil(Vector2(0, -1) * Kit.ahead(view))
			await create_timer(tick * 2.0).timeout
			view.cheer(),
	}
	var ok := true
	for order: String in orders:
		ok = await _expect_rest_after(order, orders[order]) and ok
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
# x1 and at x4 alike (60 fixed frames of a second, stepped by hand).
func _check_idle_redraws() -> bool:
	var ok := true
	for speed: float in [1.0, FAST]:
		var view := Kit.make_view(root, &"class.archer", 0)
		var stepper := Kit.Stepper.new()
		stepper.take(view)
		view.playback_speed = speed
		await stepper.run(self, 0.3)
		var draws := Kit.count_draws(view)
		await stepper.run(self, 1.0)
		view.queue_free()
		var expected := PoseRedraws.IDLE_PER_SEC
		if draws[0] < expected - 1 or draws[0] > expected + 1:
			push_error("Idle at x%.0f should redraw %.0f times a second, not %d" % [speed, expected, draws[0]])
			ok = false
	return ok


# At x4 a blink still shows: blinks last BLINK_SEC of real time, longer
# than the 10-a-second idle sampling, so over one blink period every
# figure, swaying or calm, shows shut eyes at least once.
func _check_blinks_at_speed() -> bool:
	var views: Array[UnitView] = []
	var stepper := Kit.Stepper.new()
	for calm: bool in [false, true]:
		for index: int in 3:
			var view := Kit.make_view(root, &"class.sword", index % 2)
			stepper.take(view)
			view.playback_speed = FAST
			view.is_idle_calm = calm
			views.append(view)
	var blinked: Array[bool] = []
	blinked.resize(views.size())
	var period := PoseRedraws.BLINK_PERIOD_SEC + 0.3
	for frame: int in roundi(period / Kit.Stepper.FRAME):
		await stepper.step(self)
		for index: int in views.size():
			if views[index].get_pose().values[UnitPose.EYES] == 1.0:
				blinked[index] = true
	var ok := true
	for index: int in views.size():
		if not blinked[index]:
			push_error("A figure at x4 (calm %s) never showed a blink in %.1f s" % [views[index].is_idle_calm, period])
			ok = false
		views[index].queue_free()
	return ok


# The weapon trail takes a sample on every frame of a swing, not one per
# redraw: frames within one redraw slot still add samples.
func _check_trail_every_frame() -> bool:
	var view := Kit.make_view(root, &"class.sword", 0)
	var stepper := Kit.Stepper.new()
	var animator := stepper.take(view)
	view.lunge(Vector2(0, -80))
	for frame: int in 120:
		if view.get_pose().values[UnitPose.TRAIL] > WeaponTrail.MIN:
			break
		await stepper.step(self)
	var before := animator.trail.weights.size()
	for frame: int in 3:
		animator._process(0.002)
	var added := animator.trail.weights.size() - before
	view.queue_free()
	if added != 3:
		push_error("Three frames of a swing should add three trail samples, not %d" % added)
		return false
	return true


# A long frame (a hitch) steps the clips by at most MAX_STEP_SEC, times
# the battle speed, so it does not skip a clip.
func _check_step_cap() -> bool:
	var view := Kit.make_view(root, &"class.sword", 0)
	var stepper := Kit.Stepper.new()
	var animator := stepper.take(view)
	view.playback_speed = 2.0
	view.lunge(Vector2(0, -80))
	var before := animator.get_clock()
	animator._process(1.0)
	var stepped := animator.get_clock() - before
	var ok := Kit.expect_near("Clock after a 1 s frame at x2", stepped, PoseAnimator.MAX_STEP_SEC * 2.0, 0.0001)
	if not animator.is_animating():
		push_error("A 1 s frame should not skip the attack clip")
		ok = false
	view.queue_free()
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
	var ok := Kit.expect_rest("attack at x4", fast)
	if not slow.get_animator().is_animating():
		push_error("At x1 the attack should still play after %.2f s" % (seconds / FAST))
		ok = false
	slow.queue_free()
	fast.queue_free()
	return ok


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


# Like the sketch, whose tie has no side term, an archer shooting straight
# ahead turns its bow hand the same way on both sides (flip -1), whatever
# it faced before; other classes keep their facing. A target to the side
# still wins.
func _check_archer_straight_shot() -> bool:
	var ok := true
	for side: int in 2:
		var archer := Kit.make_view(root, &"class.archer", side)
		var sword := Kit.make_view(root, &"class.sword", side)
		var own := 1.0 if side == 0 else -1.0
		# Shooting to the left first turns the bow hand left (flip 1).
		archer.recoil(Vector2(-120, -200) * Vector2(1, Kit.ahead(archer)))
		archer.recoil(Vector2(0, -200) * Kit.ahead(archer))
		sword.lunge(Vector2(0, -80) * Kit.ahead(sword))
		if archer.get_flip() != -1.0 or sword.get_flip() != own:
			push_error("Side %d shooting straight: the archer should face -1 (is %.0f), the sword %.0f (is %.0f)" % [side, archer.get_flip(), own, sword.get_flip()])
			ok = false
		archer.recoil(Vector2(-120, -200))
		if archer.get_flip() != 1.0:
			push_error("An archer shooting to the left should turn its bow hand left (flip 1), not %.0f" % archer.get_flip())
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
		ok = Kit.expect_rest("%s, %s side %d" % [label, view.unit.class_id, view.side], view) and ok
		view.queue_free()
	return ok