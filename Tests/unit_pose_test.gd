extends SceneTree

# Headless test of the rigged unit figures. Drawing: every class (with the
# boss, the sage and an unknown one) x race (and an unknown one) x cost
# draws posed, unposed and as a bust without a script error. The rig: every
# class, view and clip solves to finite bones at sampled times, and every
# standing pose keeps its lowest foot on the ground line. The PoseAnimator
# through UnitView, for every class in both views: each action (attack,
# skill, hit, knockback, walk, cheer, and the battle's event orders) ends at
# the rest pose; death stays down without redraws; stone freezes the pose;
# figures outside the rig stay idle; idle redraws are throttled and a calm
# figure only blinks; the battle speed scales the clips, also mid-cast;
# Breakthrough releases with the resolve; glides and hops clear the lean.

const RIG_CLASS_IDS: Array[StringName] = [
	&"class.sword", &"class.shield", &"class.spear", &"class.archer", &"class.mage", &"class.cavalry",
	&"class.unknown_test",
]
const DRAWN_CLASS_IDS: Array[StringName] = [
	&"class.sword", &"class.shield", &"class.spear", &"class.archer", &"class.mage", &"class.cavalry",
	&"class.unknown_test", &"class.colossus", &"class.sage",
]
const RACE_IDS: Array[StringName] = [&"race.human", &"race.wolf", &"race.unknown_test"]
const VIEWS: Array[StringName] = [RigSolver.VIEW_BACK, RigSolver.VIEW_FRONT]
const CLIPS: Array[StringName] = [&"attackUp", &"attackDown", &"skillUp", &"skillDown", &"hit", &"die", &"fall", &"cheer"]
const SAMPLES: int = 5
const GROUND_TOLERANCE: float = 0.35
# Breathing moves the rest pose by up to 1.5 degrees.
const REST_TOLERANCE: float = 1.8
const TOLERANCE: float = 0.02
# Every animator test but the speed ones runs the battle at x4.
const FAST: float = 4.0
const SETTLE_SEC: float = 0.6


func _initialize() -> void:
	var ok := await _run()
	if ok:
		print("Unit pose test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	var checks: Array[Callable] = [
		_check_drawing, _check_clips_solve, _check_feet_on_ground, _check_actions_rest, _check_event_orders_rest,
		_check_wind_up_holds, _check_die, _check_petrify, _check_posed_off_idle, _check_idle_redraws,
		_check_calm_idle, _check_speed, _check_speed_change_mid_cast, _check_breakthrough, _check_glide_clears_lean,
	]
	for check: Callable in checks:
		if not await check.call():
			push_error("Unit pose test failed in %s" % check.get_method())
			return false
	return true


func _check_drawing() -> bool:
	var poses: Array[UnitPose] = [
		RigClips.get_stance(), RigClips.walk_pose(0.3), RigClips.get_clip(&"die")[3].pose,
		RigClips.get_clip(&"skillUp")[1].pose.with_fields({"trail": 1, "flash": 0.6, "eyes": 2, "dx": 4}),
	]
	var expected := DRAWN_CLASS_IDS.size() * RACE_IDS.size() * 5 * (poses.size() + 2)
	var drawn: Array[int] = [0]
	var canvas := Node2D.new()
	canvas.draw.connect(func() -> void:
		for class_id: StringName in DRAWN_CLASS_IDS:
			for race_id: StringName in RACE_IDS:
				for cost: int in range(1, 6):
					var unit := _make_unit(class_id, race_id, cost)
					for pose: UnitPose in poses:
						UnitPainter.draw_figure(canvas, unit, UnitPainter.FACING_UP, 0.5, Vector2(40, 80), 1.2, pose)
						drawn[0] += 1
					UnitPainter.draw_figure(canvas, unit, UnitPainter.FACING_DOWN, 0.0)
					drawn[0] += 1
					UnitPainter.draw_bust(canvas, unit, Vector2(60, 60), 1.6)
					drawn[0] += 1)
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	root.add_child(canvas)
	await process_frame
	await process_frame
	OS.remove_logger(errors)
	canvas.queue_free()
	if drawn[0] != expected or errors.count > 0:
		push_error("Drew %d of %d figures with %d errors (or _draw never ran)" % [drawn[0], expected, errors.count])
		return false
	return true


# Every pose a figure can show (clip keys, the blends between them, rests
# and the run) solves to finite bones.
func _check_clips_solve() -> bool:
	for class_id: StringName in RIG_CLASS_IDS:
		var kit := RigKit.get_kit(class_id)
		for view: StringName in VIEWS:
			var poses: Array[UnitPose] = [kit.idle[view], kit.stance[view]]
			for clip: StringName in CLIPS:
				var from := kit.stance[view]
				for key: RigClips.ClipKey in kit.get_clip(clip, view):
					for sample: int in SAMPLES:
						poses.append(UnitPose.blend(from, key.pose, RigClips.eased(key.easing, (sample + 1.0) / SAMPLES)))
					from = key.pose
			for step: int in 20:
				poses.append(kit.get_walk_pose(step / 20.0, view))
			for pose: UnitPose in poses:
				if not _is_finite(RigSolver.solve(pose, view)):
					push_error("%s seen from %s solves to a NaN bone in %s" % [class_id, view, pose.values])
					return false
	return true


# A pose standing on its legs (leg IK on, no jump, not riding) puts each
# foot that its leg can reach where the sketch plants it: the ankle above
# the ground line at x = f, raised by the lift `l` and shifted by half the
# step `st` (a foot farther from the viewer shows higher on screen).
func _check_feet_on_ground() -> bool:
	var ok := true
	for class_id: StringName in RIG_CLASS_IDS:
		var kit := RigKit.get_kit(class_id)
		for view: StringName in VIEWS:
			var poses: Array[UnitPose] = [kit.idle[view], kit.stance[view]]
			for clip: StringName in [&"attackUp", &"attackDown", &"skillUp", &"skillDown", &"hit", &"cheer"]:
				for key: RigClips.ClipKey in kit.get_clip(clip, view):
					poses.append(key.pose)
			for pose: UnitPose in poses:
				var v := pose.values
				if v[UnitPose.IK] < 1.0 or v[UnitPose.JUMP] != 0.0 or v[UnitPose.RIDE] != 0.0:
					continue
				var frame := RigSolver.solve(pose, view)
				var toward := -1.0 if view == RigSolver.VIEW_BACK else 1.0
				for foot: Array in [[RigSolver.TH_F, RigSolver.FT_F, UnitPose.F_F, UnitPose.L_F, UnitPose.ST_F], [RigSolver.TH_B, RigSolver.FT_B, UnitPose.F_B, UnitPose.L_B, UnitPose.ST_B]]:
					var planted := Vector2(v[foot[2]], -RigSolver.ANKLE - v[foot[3]] + toward * v[foot[4]] * 0.5)
					if frame.bones[foot[0]].origin.distance_to(planted) > 2.0 * RigSolver.LEG:
						continue
					var ankle := frame.bones[foot[1]].origin
					if ankle.distance_to(planted) > GROUND_TOLERANCE:
						push_error("%s seen from %s puts a foot at %s, not %s" % [class_id, view, ankle, planted])
						ok = false
	return ok


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


# A wind-up holds raised and glowing until the cast ends, then releases by
# itself if no resolve came.
func _check_wind_up_holds() -> bool:
	var view := _make_view(&"class.sword", 0)
	var animator := view.get_animator()
	view.wind_up(0.6)
	await create_timer(0.55).timeout
	var ok := true
	if not animator.is_winding or view.get_pose().values[UnitPose.GLOW] < 0.5:
		push_error("A wind-up should hold and glow before the cast ends")
		ok = false
	await create_timer(PoseAnimator.RELEASE_GRACE_SEC + 0.1).timeout
	if animator.is_winding:
		push_error("A wind-up should release by itself just after the cast")
		ok = false
	await create_timer(1.6).timeout
	ok = _expect_rest("automatic release", view) and ok
	view.queue_free()
	return ok


# Down for good: the last pose of the fall, no redraws, and no later action moves it.
func _check_die() -> bool:
	var ok := true
	for class_id: StringName in RIG_CLASS_IDS:
		var view := _make_view(class_id, 1)
		view.playback_speed = FAST
		view.die()
		await create_timer(0.5).timeout
		var fallen := view.get_pose().values
		var draws := _count_draws(view)
		view.lunge(Vector2(0, 80))
		view.wind_up(0.3)
		view.hit_flash()
		view.cheer()
		view.glide_to(view.position + Vector2(0, 40), 0.3, &"walk")
		await create_timer(0.4).timeout
		var fall := RigKit.get_kit(class_id).get_clip(&"fall", RigSolver.VIEW_FRONT)
		var last := fall[fall.size() - 1].pose.values
		if view.get_pose().values != fallen or fallen != last or draws[0] != 0:
			push_error("%s should stay down in its last fall pose without redraws (%d redraws)" % [class_id, draws[0]])
			ok = false
		view.queue_free()
	return ok


func _check_petrify() -> bool:
	var view := _make_view(&"class.spear", 0)
	view.lunge(Vector2(40, -80))
	await create_timer(0.05).timeout
	view.set_petrified(true)
	var frozen := view.get_pose().values
	var trail := view.get_animator().trail_weights.duplicate()
	var draws := _count_draws(view)
	await create_timer(0.5).timeout
	var ok := true
	if view.get_pose().values != frozen or view.get_animator().trail_weights != trail or draws[0] != 0:
		push_error("Stone should freeze the pose, the trail and the redraws (%d redraws)" % draws[0])
		ok = false
	view.set_petrified(false)
	view.playback_speed = FAST
	await create_timer(SETTLE_SEC).timeout
	ok = _expect_rest("after the stone", view) and ok
	view.queue_free()
	return ok


# Figures outside the rig (the boss, the sage) never pose or redraw while
# idle, even though Godot re-enables processing when they enter the tree.
func _check_posed_off_idle() -> bool:
	var ok := true
	for class_id: StringName in [&"class.colossus", &"class.sage"]:
		var view := _make_view(class_id, 1)
		await create_timer(0.3).timeout
		var draws := _count_draws(view)
		view.lunge(Vector2(0, 80))
		view.wind_up(0.2)
		view.get_animator().walk(0.2, false)
		await create_timer(1.0).timeout
		if draws[0] > 2 or view.get_animator().is_animating():
			push_error("%s should not pose; it redrew %d times in 1 s" % [class_id, draws[0]])
			ok = false
		view.queue_free()
	return ok


# Idle (no action) redraws about 10 times a second, not every frame.
func _check_idle_redraws() -> bool:
	var view := _make_view(&"class.archer", 0)
	await create_timer(0.3).timeout
	var draws := _count_draws(view)
	await create_timer(1.0).timeout
	view.queue_free()
	if draws[0] < 7 or draws[0] > 14:
		push_error("Idle should redraw about 10 times a second, not %d" % draws[0])
		return false
	return true


# A calm figure (bench, dimmed line-up) holds still and redraws only to
# blink, at most twice per blink.
func _check_calm_idle() -> bool:
	var view := _make_view(&"class.mage", 1)
	view.set_dim(0.4)
	await create_timer(0.3).timeout
	var torso := view.get_pose().values[UnitPose.TORSO]
	var draws := _count_draws(view)
	await create_timer(2.0).timeout
	var ok := true
	if draws[0] > 4 or view.get_pose().values[UnitPose.TORSO] != torso:
		push_error("A calm figure should only blink: %d redraws in 2 s" % draws[0])
		ok = false
	view.set_dim(0.0)
	draws = _count_draws(view)
	await create_timer(0.5).timeout
	if draws[0] < 3:
		push_error("A figure no longer dimmed should breathe again, %d redraws" % draws[0])
		ok = false
	view.queue_free()
	return ok


func _check_speed() -> bool:
	var slow := _make_view(&"class.shield", 0)
	var fast := _make_view(&"class.shield", 0)
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
	var view := _make_view(&"class.sword", 0)
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
	var view := _make_view(&"class.cavalry", 0)
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


# A knockback glide cut off by a new glide or hop must not leave the unit tilted.
func _check_glide_clears_lean() -> bool:
	var view := _make_view(&"class.sword", 0)
	view.glide_to(view.position + Vector2(40, 0), 0.4, &"knockback")
	await create_timer(0.2).timeout
	if absf(view.lean) < 0.05:
		push_error("A knockback should tilt the unit, lean is %.3f" % view.lean)
		view.queue_free()
		return false
	view.glide_to(view.position + Vector2(0, 80), 0.3, &"walk")
	var ok := _expect_near("Lean after a glide cut a knockback short", view.lean, 0.0)
	view.glide_to(view.position + Vector2(40, 0), 0.4, &"knockback")
	await create_timer(0.2).timeout
	view.hop_to(view.position + Vector2(0, 80), 0.3)
	ok = _expect_near("Lean after a hop cut a knockback short", view.lean, 0.0) and ok
	view.queue_free()
	return ok


# Runs `action` (func(view)) on every rigged class from both sides at x4
# and expects each to end at its rest pose.
func _expect_rest_after(label: String, action: Callable) -> bool:
	var views: Array[UnitView] = []
	for class_id: StringName in RIG_CLASS_IDS:
		for side: int in 2:
			var view := _make_view(class_id, side)
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
		ok = _expect_near("%s: %s" % [label, UnitPose.KEYS[index]], values[index], 0.0) and ok
	if not view.squash.is_equal_approx(Vector2.ONE):
		push_error("%s: squash should be (1, 1), not %s" % [label, view.squash])
		ok = false
	return ok


func _is_finite(frame: RigSolver.Frame) -> bool:
	for bone: Transform2D in frame.bones:
		for axis: Vector2 in [bone.x, bone.y, bone.origin]:
			if not axis.is_finite():
				return false
	return true


# The enemy side attacks down the board.
func _ahead(view: UnitView) -> float:
	return 1.0 if view.side == 0 else -1.0


func _make_unit(class_id: StringName, race_id: StringName, cost: int) -> UnitData:
	var unit := UnitData.new()
	unit.id = &"unit.pose_test"
	unit.class_id = class_id
	unit.race_id = race_id
	unit.cost = cost
	unit.element_id = &"element.ice"
	return unit


func _make_view(class_id: StringName, side: int) -> UnitView:
	var view := UnitView.new()
	view.setup(_make_unit(class_id, &"race.human", 3), side, 1)
	view.position = Vector2(200, 200)
	root.add_child(view)
	return view


# Counts the figure's redraws from now on, in a one-element array.
func _count_draws(view: UnitView) -> Array[int]:
	var draws: Array[int] = [0]
	for child: Node in view.get_children():
		if child is UnitFigure:
			(child as UnitFigure).draw.connect(func() -> void: draws[0] += 1)
	return draws


func _expect_near(label: String, value: float, expected: float) -> bool:
	if absf(value - expected) > TOLERANCE:
		push_error("%s should be %.2f, not %.3f" % [label, expected, value])
		return false
	return true


# Counts errors (not warnings) logged while it is added.
class ErrorCounter extends Logger:
	var count: int = 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1

	func _log_message(_message: String, _error: bool) -> void:
		pass
