class_name UnitFigure
extends Node2D
## The drawn character inside a UnitView (or a cutscene, a boss card):
## redrawn only when its look, the hit flash or its pose changes (a
## PoseAnimator calls queue_redraw). It knows which way it faces (`flip`)
## and how far its pose's step pushes it toward its target; the view
## moves, scales, mirrors and rotates it for whole-body animation. A
## rigged figure's hit flash is a shader on the figure (no redraw, no
## tinted copies of its meshes) that leaves the weapon trail and the glow
## their colours.

## A target less than this far to the side keeps the current facing.
const TURN_MIN_PX: float = 6.0
## How far a figure is pushed toward its target per unit of the pose's
## step forward (dx > 0) or back, in figure units (the sketch's board push
## of 4.6 and 2 px per dx at its 1.3 figure scale).
const PUSH_PER_STEP: float = 3.54
const PULL_PER_STEP: float = 1.54
## Whitens the pieces UnitPainter marks (UV.x 1) by its `flash`.
const FLASH_SHADER: Shader = preload("res://Scenes/Board/unit_flash.gdshader")

var unit: UnitData:
	set(value):
		unit = value
		# The flash material is set up now, so its shader compiles before
		# the first hit rather than on it.
		material = _make_flash_material() if _is_rigged() else null
		queue_redraw()
var facing: int = UnitPainter.FACING_UP:
	set(value):
		facing = value
		queue_redraw()
## 0..1, the hit flash: how far the figure is blended toward white (80% at
## most for a rigged figure, like the sketch). A figure outside the rig
## redraws for it once per IdleTicks step (PoseRedraws.ACTION_PER_SEC a
## second) and once at the end.
var flash: float = 0.0:
	set(value):
		flash = value
		if _is_rigged():
			_update_flash()
			return
		var slot := IdleTicks.current_step()
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
## Screen pixels per figure unit, which sets how soft the lines are; 0
## takes it from the figure's transform when it draws. Owners that squash
## the figure set it, so a squash does not build another set of meshes.
var pixels_per_unit: float = 0.0
## 1 faces right, -1 left: the owner mirrors the figure by it.
var flip: float = 1.0
## Toward the target (unit vector): where a step of the pose pushes.
var aim_direction := Vector2.UP

var _flash_slot: int = -1


## Faces side 0's way (up and right) or side 1's (down and left).
func face_side(side: int) -> void:
	flip = 1.0 if side == 0 else -1.0
	aim_direction = Vector2.UP if side == 0 else Vector2.DOWN


## Turns toward `direction` (board pixels) and returns the aim in the
## figure's own space (0 up, PI / 2 straight ahead). `off_hand` (archers)
## turns the bow hand toward the target; one shooting straight ahead turns
## as the sketch does, whose tie counts as "to the right" on both sides:
## flip -1. Other figures keep their facing for a straight target.
func turn_toward(direction: Vector2, off_hand: bool) -> float:
	if absf(direction.x) > TURN_MIN_PX:
		flip = signf(direction.x) * (-1.0 if off_hand else 1.0)
	elif off_hand:
		flip = -1.0
	if direction.length() > 0.001:
		aim_direction = direction.normalized()
	return atan2(absf(direction.x), -direction.y)


## The pose's step toward the target (dx) as a push of the whole figure
## along the attack direction, in figure units (the sketch's board).
func get_push() -> Vector2:
	if animator == null or animator.pose == null:
		return Vector2.ZERO
	var step := animator.pose.values[UnitPose.DX]
	return aim_direction * step * (PUSH_PER_STEP if step > 0.0 else PULL_PER_STEP)


func _draw() -> void:
	if unit == null:
		return
	var shown := animator.pose if animator != null else pose
	if _is_rigged():
		_update_flash()
	var pixels := pixels_per_unit if pixels_per_unit > 0.0 else absf(get_global_transform_with_canvas().get_scale().y)
	UnitPainter.draw_figure(self, unit, facing, flash, Vector2.ZERO, 1.0, shown, animator, pixels)


# One per figure: each flashes on its own.
static func _make_flash_material() -> ShaderMaterial:
	var flash_material := ShaderMaterial.new()
	flash_material.shader = FLASH_SHADER
	return flash_material


func _is_rigged() -> bool:
	return unit != null and UnitPainter.is_posable(unit.class_id)


# The flash of the view and of the pose's own (a hit clip), as a shader.
func _update_flash() -> void:
	var shown := animator.pose if animator != null else pose
	var amount := maxf(flash, shown.values[UnitPose.FLASH] if shown != null else 0.0)
	var flash_material := material as ShaderMaterial
	if flash_material == null:
		return
	flash_material.set_shader_parameter(&"flash", clampf(amount, 0.0, 1.0) * UnitPainter.FLASH_WHITE)
