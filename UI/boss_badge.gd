class_name BossBadge
extends PressButton
## The boss badge in the preparation's top bar, from the reveal stage on: a
## red tile with a small stone face and "Trùm". It pulses on the boss
## stage. A press opens the boss card (RunScreen connects `pressed`).

var _pulse: Tween


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	theme_type_variation = &"PrimaryButton"
	custom_minimum_size = Vector2(118, 56)
	text = "BOSS_BADGE"
	alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_theme_font_size_override(&"font_size", 24)


## Pulses (the boss stage) or rests.
func set_urgent(is_urgent: bool) -> void:
	if _pulse != null:
		_pulse.kill()
	modulate = Color.WHITE
	if not is_urgent:
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(self, ^"modulate", Color(1.25, 1.1, 1.0), 0.5)
	_pulse.tween_property(self, ^"modulate", Color.WHITE, 0.5)


func _draw() -> void:
	# A boulder face: grey stone, ember eyes.
	var center := Vector2(26.0, size.y / 2.0)
	draw_circle(center, 15.0, Palette.INK)
	draw_circle(center, 13.0, ExtraFigures.STONE)
	draw_circle(center + Vector2(-5, -2), 2.4, ExtraFigures.EMBER)
	draw_circle(center + Vector2(5, -2), 2.4, ExtraFigures.EMBER)
	draw_line(center + Vector2(-5, 6), center + Vector2(5, 6), Palette.INK, 2.0)
