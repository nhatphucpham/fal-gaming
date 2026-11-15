class_name UnitFigure
extends Node2D
## The drawn character inside a UnitView (or a cutscene, a boss card):
## redrawn only when its look, the hit flash or its pose changes (a
## PoseAnimator calls queue_redraw). The view moves, scales, flips and
## rotates it for whole-body animation. A rigged figure's hit flash is a
## shader on the figure (no redraw, no tinted copies of its meshes) that
## leaves the weapon trail and the glow their colours.

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
## redraws for it, at most PoseAnimator.ACTION_REDRAWS_PER_SEC and once at
## the end.
var flash: float = 0.0:
	set(value):
		flash = value
		if _is_rigged():
			_update_flash()
			return
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
## Screen pixels per figure unit, which sets how soft the lines are; 0
## takes it from the figure's transform when it draws. Owners that squash
## the figure set it, so a squash does not build another set of meshes.
var pixels_per_unit: float = 0.0

var _flash_slot: int = -1


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
