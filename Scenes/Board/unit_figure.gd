class_name UnitFigure
extends Node2D
## The drawn character inside a UnitView: redrawn only when its look, the
## hit flash or its pose changes (a PoseAnimator calls queue_redraw). The
## view moves, scales, flips and rotates it for whole-body animation.

var unit: UnitData:
	set(value):
		unit = value
		queue_redraw()
var facing: int = UnitPainter.FACING_UP:
	set(value):
		facing = value
		queue_redraw()
## 0..1, how far every fill is blended toward white.
var flash: float = 0.0:
	set(value):
		flash = value
		queue_redraw()
## The pose to draw; null draws the rest pose.
var pose: UnitPose:
	set(value):
		pose = value
		queue_redraw()


func _draw() -> void:
	if unit != null:
		UnitPainter.draw_figure(self, unit, facing, flash, Vector2.ZERO, 1.0, pose)
