extends SceneTree

# Headless test of the posed unit figures: every class (and an unknown one)
# x race (and an unknown one) x cost 1..5 draws in the rest pose and in each
# extreme pose without a script error (counted by a Logger), inside a real
# draw notification (the headless renderer still calls _draw; it only
# discards what is drawn);
# draw_figure without a pose and draw_bust still work. Then the
# PoseAnimator through UnitView: an attack turns the figure and settles at
# the combat stance, walking drops it, a wind-up holds until the next attack
# releases it, death ends dead-eyed and still, stone freezes the pose and
# its redraws, idle redraws are throttled (a calm figure only blinks), and
# the battle speed scales every pose animation, also when it changes
# mid-cast. Then real event orders from the battle replay, which must leave
# no skill pose behind: cavalry Breakthrough (wind-up, then charge and
# resolve in one tick), a resolve followed one tick later by a move or an
# attack, a cast followed by a cheer, and the automatic release.

const CLASS_IDS: Array[StringName] = [
	&"class.sword", &"class.shield", &"class.spear", &"class.archer", &"class.mage", &"class.cavalry",
	&"class.unknown_test",
]
const RACE_IDS: Array[StringName] = [&"race.human", &"race.wolf", &"race.unknown_test"]
const SETTLE_SEC: float = 0.8
const TOLERANCE: float = 0.02


func _initialize() -> void:
	var ok := await _run()
	if ok:
		print("Unit pose test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	var checks: Array[Callable] = [
		_check_drawing, _check_attack_stance, _check_walk_drops_stance, _check_wind_up,
		_check_die, _check_petrify, _check_idle_redraws, _check_calm_idle, _check_speed,
		_check_speed_change_mid_cast, _check_breakthrough, _check_move_after_resolve,
		_check_attack_after_resolve, _check_cheer_after_cast, _check_fallback_release,
	]
	for check: Callable in checks:
		if not await check.call():
			push_error("Unit pose test failed in %s" % check.get_method())
			return false
	return true


func _check_drawing() -> bool:
	var poses := _extreme_poses()
	var expected := CLASS_IDS.size() * RACE_IDS.size() * 5 * (poses.size() + 2)
	var drawn: Array[int] = [0]
	var canvas := Node2D.new()
	canvas.draw.connect(func() -> void:
		for class_id: StringName in CLASS_IDS:
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


# A melee lunge turns the figure toward the target and ends at the combat
# stance; an archer's shot ends with the bow drawn again.
func _check_attack_stance() -> bool:
	var sword := _make_view(&"class.sword", 0)
	sword.lunge(Vector2(-60, -10))
	if sword.get_flip() != -1.0:
		push_error("A lunge to the left should turn the figure left")
		return false
	var archer := _make_view(&"class.archer", 1)
	archer.recoil(Vector2(0, 80))
	await create_timer(SETTLE_SEC).timeout
	var ok := _expect_near("sword strike", sword.get_pose().strike, -0.45)
	ok = _expect_near("archer strike", archer.get_pose().strike, -1.0) and ok
	ok = _expect_near("archer arrow", archer.get_pose().arrow, 1.0) and ok
	if archer.get_flip() != -1.0:
		push_error("A shot straight down keeps the facing of side 1 (left)")
		ok = false
	sword.queue_free()
	archer.queue_free()
	return ok


func _check_walk_drops_stance() -> bool:
	var view := _make_view(&"class.spear", 0)
	view.lunge(Vector2(0, -80))
	await create_timer(SETTLE_SEC).timeout
	view.glide_to(view.position + Vector2(0, -88), 0.3, &"walk")
	await create_timer(0.1).timeout
	var ok := true
	if view.get_pose().stride < 0.5:
		push_error("Walking should move the legs, stride %.2f" % view.get_pose().stride)
		ok = false
	await create_timer(SETTLE_SEC).timeout
	ok = _expect_near("strike after walking", view.get_pose().strike, 0.0) and ok
	ok = _expect_near("stride after walking", view.get_pose().stride, 0.0) and ok
	view.queue_free()
	return ok


# The wind-up holds the raised weapon until the resolve's recoil releases it.
func _check_wind_up() -> bool:
	var view := _make_view(&"class.cavalry", 0)
	view.wind_up(0.5)
	await create_timer(0.45).timeout
	var pose := view.get_pose()
	if pose.raise < 0.8 or pose.rear < 0.8 or pose.glow < 0.8:
		push_error("Wind-up should raise, rear and glow: %.2f %.2f %.2f" % [pose.raise, pose.rear, pose.glow])
		return false
	view.recoil(Vector2(0, -1))
	await create_timer(SETTLE_SEC).timeout
	var ok := _expect_near("raise after release", pose.raise, 0.0)
	ok = _expect_near("rear after release", pose.rear, 0.0) and ok
	ok = _expect_near("strike after release", pose.strike, -0.45) and ok
	view.queue_free()
	return ok


func _check_die() -> bool:
	var view := _make_view(&"class.mage", 1)
	view.die()
	await create_timer(1.2).timeout
	var pose := view.get_pose()
	var ok := _expect_near("limp after death", pose.limp, 1.0)
	if pose.eyes != UnitPose.Eyes.DEAD:
		push_error("A dead unit should have dead eyes, not %d" % pose.eyes)
		ok = false
	var sway := pose.sway
	var draws := _count_draws(view)
	await create_timer(0.4).timeout
	if pose.sway != sway or draws[0] != 0:
		push_error("A dead unit should not sway or redraw (%d redraws)" % draws[0])
		ok = false
	view.queue_free()
	return ok


func _check_petrify() -> bool:
	var view := _make_view(&"class.sword", 0)
	view.lunge(Vector2(40, -80))
	await create_timer(0.05).timeout
	view.set_petrified(true)
	var pose := view.get_pose()
	var frozen := [pose.strike, pose.trail, pose.sway, pose.eyes]
	var draws := _count_draws(view)
	await create_timer(0.5).timeout
	var ok := true
	if [pose.strike, pose.trail, pose.sway, pose.eyes] != frozen or draws[0] != 0:
		push_error("Stone should freeze the pose and its redraws: %s -> %s, %d redraws" % [frozen, [pose.strike, pose.trail, pose.sway, pose.eyes], draws[0]])
		ok = false
	view.set_petrified(false)
	await create_timer(SETTLE_SEC).timeout
	ok = _expect_near("strike after the stone", pose.strike, -0.45) and ok
	view.queue_free()
	return ok


# Idle (no action) redraws about 10 times a second, not every frame.
func _check_idle_redraws() -> bool:
	var view := _make_view(&"class.archer", 0)
	await create_timer(0.3).timeout
	var draws := _count_draws(view)
	var frames: Array[int] = [0]
	var count_frame := func() -> void: frames[0] += 1
	process_frame.connect(count_frame)
	await create_timer(1.0).timeout
	process_frame.disconnect(count_frame)
	view.queue_free()
	if draws[0] < 7 or draws[0] > 14:
		push_error("Idle should redraw about 10 times a second, not %d (in %d frames)" % [draws[0], frames[0]])
		return false
	return true


# A calm figure (bench, dimmed line-up) holds its sway and redraws only to
# blink, at most twice per blink.
func _check_calm_idle() -> bool:
	var view := _make_view(&"class.mage", 1)
	view.set_dim(0.4)
	await create_timer(0.3).timeout
	var sway := view.get_pose().sway
	var draws := _count_draws(view)
	await create_timer(2.0).timeout
	var ok := true
	if draws[0] > 4 or view.get_pose().sway != sway:
		push_error("A calm figure should only blink: %d redraws in 2 s, sway %.2f -> %.2f" % [draws[0], sway, view.get_pose().sway])
		ok = false
	view.set_dim(0.0)
	draws = _count_draws(view)
	await create_timer(0.5).timeout
	if draws[0] < 3:
		push_error("A figure no longer dimmed should sway again, %d redraws" % draws[0])
		ok = false
	view.queue_free()
	return ok


func _check_speed() -> bool:
	var slow := _make_view(&"class.shield", 0)
	var fast := _make_view(&"class.shield", 0)
	fast.playback_speed = 4.0
	slow.lunge(Vector2(0, -80))
	fast.lunge(Vector2(0, -80))
	await create_timer(0.2).timeout
	var ok := _expect_near("strike at x4 after 0.2 s", fast.get_pose().strike, -0.45)
	if absf(slow.get_pose().strike + 0.45) < 0.2:
		push_error("At x1 the swing should still be on after 0.2 s, strike %.2f" % slow.get_pose().strike)
		ok = false
	slow.queue_free()
	fast.queue_free()
	return ok


# Slowing the battle from x4 to x1 mid-cast slows the wind-up too: it must
# not release (and strike) before the cast at x1 ends.
func _check_speed_change_mid_cast() -> bool:
	var view := _make_view(&"class.sword", 0)
	view.playback_speed = 4.0
	view.wind_up(1.0)
	await create_timer(0.1).timeout
	view.playback_speed = 1.0
	await create_timer(0.5).timeout
	var pose := view.get_pose()
	var ok := true
	if pose.raise < 0.5 or pose.trail > 0.0:
		push_error("At x1 the wind-up should still hold after 0.6 s (raise %.2f, trail %.2f)" % [pose.raise, pose.trail])
		ok = false
	view.recoil(Vector2(0, -1))
	await create_timer(SETTLE_SEC).timeout
	ok = _expect_settled("after a speed change", view, -0.45) and ok
	view.queue_free()
	return ok


# Breakthrough: the battle sends the charge move and then the resolve in the
# same tick. The rider winds up, charges with the lance levelled and glowing,
# the strike lands with the resolve, and nothing of the skill pose stays.
func _check_breakthrough() -> bool:
	var view := _make_view(&"class.cavalry", 0)
	view.wind_up(0.6)
	await create_timer(0.6).timeout
	view.glide_to(view.position + Vector2(0, -160), 0.6, &"charge")
	view.recoil(Vector2(0, -1))
	await create_timer(0.05).timeout
	var pose := view.get_pose()
	var ok := true
	if pose.strike < 0.5 or pose.trail < 0.5:
		push_error("The release should strike with the resolve: strike %.2f, trail %.2f" % [pose.strike, pose.trail])
		ok = false
	await create_timer(0.4).timeout
	ok = _expect_near("lance during the charge", pose.strike, PoseAnimator.CHARGE_STRIKE) and ok
	ok = _expect_near("raise during the charge", pose.raise, 0.0) and ok
	if pose.stride < 0.5:
		push_error("The horse should gallop during the charge, stride %.2f" % pose.stride)
		ok = false
	await create_timer(1.2).timeout
	ok = _expect_settled("after Breakthrough", view, -0.45) and ok
	view.queue_free()
	return ok


func _check_move_after_resolve() -> bool:
	var view := _make_view(&"class.sword", 0)
	view.wind_up(0.45)
	await create_timer(0.45).timeout
	view.recoil(Vector2(0, -1))
	await create_timer(0.05).timeout
	view.glide_to(view.position + Vector2(0, -80), 0.5, &"walk")
	await create_timer(1.5).timeout
	var ok := _expect_settled("move one tick after the resolve", view, 0.0)
	view.queue_free()
	return ok


func _check_attack_after_resolve() -> bool:
	var view := _make_view(&"class.spear", 0)
	view.wind_up(0.45)
	await create_timer(0.45).timeout
	view.recoil(Vector2(0, -1))
	await create_timer(0.05).timeout
	view.lunge(Vector2(0, -80))
	await create_timer(1.5).timeout
	var ok := _expect_settled("attack one tick after the resolve", view, -0.45)
	view.queue_free()
	return ok


func _check_cheer_after_cast() -> bool:
	var view := _make_view(&"class.mage", 0)
	view.recoil(Vector2(0, -1))
	await create_timer(0.1).timeout
	view.cheer()
	await create_timer(1.8).timeout
	var ok := _expect_settled("cheer after a cast", view, 0.0)
	view.queue_free()
	return ok


# With no resolve the wind-up releases by itself just after the cast.
func _check_fallback_release() -> bool:
	var view := _make_view(&"class.sword", 0)
	view.wind_up(0.3)
	await create_timer(0.3 + PoseAnimator.RELEASE_GRACE_SEC + 0.05).timeout
	var ok := true
	if view.get_pose().trail < 0.5:
		push_error("The wind-up should release by itself, trail %.2f" % view.get_pose().trail)
		ok = false
	await create_timer(SETTLE_SEC).timeout
	ok = _expect_settled("after the automatic release", view, -0.45) and ok
	view.queue_free()
	return ok


func _extreme_poses() -> Array[UnitPose]:
	var fields: Array[Dictionary] = [
		{},
		{"stride": 1.0, "step": 1.3, "gallop": 1.3},
		{"strike": -1.0, "aim": 1.2},
		{"strike": 1.0, "trail": 0.8, "aim": 1.2},
		{"strike": 1.0, "aim": 0.0, "trail": 1.0},
		{"strike": 1.0, "aim": PI, "glow": 1.0},
		{"raise": 1.0, "glow": 1.0, "crouch": 1.0, "rear": 1.0, "eyes": UnitPose.Eyes.HAPPY},
		{"flinch": 1.0, "guard": 1.0, "eyes": UnitPose.Eyes.HURT, "sway": -1.0},
		{"limp": 1.0, "eyes": UnitPose.Eyes.DEAD, "sway": 1.0},
		{"eyes": UnitPose.Eyes.BLINK, "arrow": 0.0, "strike": -1.0},
	]
	var poses: Array[UnitPose] = []
	for entry: Dictionary in fields:
		var pose := UnitPose.new()
		for key: String in entry:
			pose.set(key, entry[key])
		poses.append(pose)
	return poses


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


# Every skill and hit field back at rest, the strike at `strike`, the
# figure unsquashed.
func _expect_settled(label: String, view: UnitView, strike: float) -> bool:
	var pose := view.get_pose()
	var ok := _expect_near("%s: strike" % label, pose.strike, strike)
	for field: String in ["raise", "crouch", "rear", "glow", "trail", "flinch", "guard", "stride"]:
		ok = _expect_near("%s: %s" % [label, field], pose.get(field), 0.0) and ok
	if not view.squash.is_equal_approx(Vector2.ONE):
		push_error("%s: squash should be (1, 1), not %s" % [label, view.squash])
		ok = false
	return ok


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
