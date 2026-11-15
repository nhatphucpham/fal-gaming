extends RefCounted
## Shared set-up for the rig tests (unit_pose_test.gd, pose_animator_test.gd,
## pose_cast_test.gd, pose_stone_test.gd): the class, race and view lists, test units and views,
## redraw counting, an error counter, the rest-pose and no-strike checks,
## float checks and a Stepper that drives animators with fixed frames.

const RIG_CLASS_IDS: Array[StringName] = [
	&"class.sword", &"class.shield", &"class.spear", &"class.archer", &"class.mage", &"class.cavalry",
	&"class.unknown_test",
]
const RACE_IDS: Array[StringName] = [&"race.human", &"race.wolf", &"race.unknown_test"]
const VIEWS: Array[StringName] = [RigSolver.VIEW_BACK, RigSolver.VIEW_FRONT]
const TOLERANCE: float = 0.02
# Breathing moves the rest pose by up to 1.5 degrees.
const REST_TOLERANCE: float = 1.8


static func make_unit(class_id: StringName, race_id: StringName = &"race.human", cost: int = 3) -> UnitData:
	var unit := UnitData.new()
	unit.id = &"unit.pose_test"
	unit.class_id = class_id
	unit.race_id = race_id
	unit.cost = cost
	unit.element_id = &"element.ice"
	return unit


## A one-star human view of `class_id` on `side`, added under `root`.
static func make_view(root: Node, class_id: StringName, side: int) -> UnitView:
	var view := UnitView.new()
	view.setup(make_unit(class_id), side, 1)
	view.position = Vector2(200, 200)
	root.add_child(view)
	return view


## Counts the figure's redraws from now on, in a one-element array.
static func count_draws(view: UnitView) -> Array[int]:
	var draws: Array[int] = [0]
	for child: Node in view.get_children():
		if child is UnitFigure:
			(child as UnitFigure).draw.connect(func() -> void: draws[0] += 1)
	return draws


static func expect_near(label: String, value: float, expected: float, tolerance: float = TOLERANCE) -> bool:
	if absf(value - expected) > tolerance:
		push_error("%s should be %.2f, not %.3f" % [label, expected, value])
		return false
	return true


# The pose back at the animator's rest pose (up to breathing), with no
# clip, trail, glow, flash or step left, and the figure unsquashed.
static func expect_rest(label: String, view: UnitView) -> bool:
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
		ok = expect_near("%s: %s" % [label, UnitPose.KEYS[index]], values[index], 0.0) and ok
	if not view.squash.is_equal_approx(Vector2.ONE):
		push_error("%s: squash should be (1, 1), not %s" % [label, view.squash])
		ok = false
	return ok


# The enemy side attacks down the board.
static func ahead(view: UnitView) -> float:
	return 1.0 if view.side == 0 else -1.0



## The view's UnitFigure.
static func figure_of(view: UnitView) -> UnitFigure:
	for child: Node in view.get_children():
		if child is UnitFigure:
			return child
	return null


## The last key of the class's wind-up (the skill clip's first keys).
static func wind_pose(class_id: StringName, view: StringName) -> UnitPose:
	var kit := RigKit.get_kit(class_id)
	return kit.get_skill_clip(view)[kit.skill_wind_keys - 1].pose


## Steps `view` for `seconds` with `stepper`, checking every frame: no
## trail, no step toward the target (dx never grows past what showed), no
## glow coming back and no wind-up; then the rest pose.
static func expect_no_strike(label: String, view: UnitView, stepper: Stepper, tree: SceneTree, seconds: float) -> bool:
	var last := view.get_pose().values
	for frame: int in roundi(seconds / Stepper.FRAME):
		await stepper.step(tree)
		var values := view.get_pose().values
		var rising := values[UnitPose.DX] > maxf(last[UnitPose.DX], 0.0) + 0.001 or values[UnitPose.GLOW] > last[UnitPose.GLOW] + 0.001
		if values[UnitPose.TRAIL] > 0.0 or rising or view.get_animator().is_winding:
			push_error("%s: a strike or a glow plays (trail %.2f, dx %.2f, glow %.2f)" % [label, values[UnitPose.TRAIL], values[UnitPose.DX], values[UnitPose.GLOW]])
			return false
		last = values
	return expect_rest(label, view)


## Drives the animators it takes by hand, a fixed FRAME at a time, with a
## clock of its own (their redraw and blink timing): timing checks then
## do not depend on how fast the machine runs. The tree still draws once
## per step. A frozen animator (stone) is skipped, as the engine would.
class Stepper extends RefCounted:
	const FRAME: float = 1.0 / 60.0
	var seconds: float = 100.0
	var animators: Array[PoseAnimator] = []

	func now() -> float:
		return seconds

	## Stops `view`'s animator running by itself and drives it from now on.
	func take(view: UnitView) -> PoseAnimator:
		var animator := view.get_animator()
		animator.set_process(false)
		if not animator.is_node_ready():
			# Entering the tree turns processing back on.
			animator.ready.connect(animator.set_process.bind(false), CONNECT_ONE_SHOT)
		animator.set_clock(now)
		animators.append(animator)
		return animator

	func step(tree: SceneTree) -> void:
		seconds += FRAME
		for animator: PoseAnimator in animators:
			if is_instance_valid(animator) and animator.can_process():
				animator._process(FRAME)
		await tree.process_frame

	func run(tree: SceneTree, duration: float) -> void:
		for frame: int in roundi(duration / FRAME):
			await step(tree)


## Counts errors (not warnings) logged while it is added.
class ErrorCounter extends Logger:
	var count: int = 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1

	func _log_message(_message: String, _error: bool) -> void:
		pass
