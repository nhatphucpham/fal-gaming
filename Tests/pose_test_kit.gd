extends RefCounted
## Shared set-up for the rig tests (unit_pose_test.gd, pose_animator_test.gd):
## the class, race and view lists, test units and views, redraw counting,
## an error counter and float checks.

const RIG_CLASS_IDS: Array[StringName] = [
	&"class.sword", &"class.shield", &"class.spear", &"class.archer", &"class.mage", &"class.cavalry",
	&"class.unknown_test",
]
const RACE_IDS: Array[StringName] = [&"race.human", &"race.wolf", &"race.unknown_test"]
const VIEWS: Array[StringName] = [RigSolver.VIEW_BACK, RigSolver.VIEW_FRONT]
const TOLERANCE: float = 0.02


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


## Counts errors (not warnings) logged while it is added.
class ErrorCounter extends Logger:
	var count: int = 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1

	func _log_message(_message: String, _error: bool) -> void:
		pass
