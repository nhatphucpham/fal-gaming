class_name UnitFigure
extends Node2D
## The drawn character inside a UnitView (or a cutscene, a boss card):
## redrawn only when its look, the hit flash or its pose changes (a
## PoseAnimator calls queue_redraw). The view moves, scales, flips and
## rotates it for whole-body animation.

var unit: UnitData:
	set(value):
		unit = value
		queue_redraw()
var facing: int = UnitPainter.FACING_UP:
	set(value):
		facing = value
		queue_redraw()
## 0..1, how far every fill is blended toward white. While it fades the
## figure redraws at most PoseAnimator.ACTION_REDRAWS_PER_SEC, and once at
## the end.
var flash: float = 0.0:
	set(value):
		flash = value
		var slot := floori(Time.get_ticks_msec() * 0.001 * PoseAnimator.ACTION_REDRAWS_PER_SEC)
		if slot != _flash_slot or value <= 0.0 or value >= 1.0:
			_flash_slot = slot
			queue_redraw()
## The pose to draw when there is no animator; null draws the class's idle pose.
var pose: UnitPose:
	set(value):
		pose = value
		queue_redraw()
## Where the pose, the weapon trail and the idle sway come from; may be null.
var animator: PoseAnimator


var _flash_slot: int = -1


func _draw() -> void:
	if unit != null:
		UnitPainter.draw_figure(self, unit, facing, flash, Vector2.ZERO, 1.0, animator.pose if animator != null else pose, animator)
