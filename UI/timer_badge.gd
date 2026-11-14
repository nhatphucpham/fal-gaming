class_name TimerBadge
extends Control
## The countdown in the top bar: a ring that empties and the seconds left.
## In the last `warn_from_sec` seconds it turns red and pulses every second.
## [codeblock]
## badge.show_seconds(42, 60)
## [/codeblock]

const RING_RADIUS_PX: float = 30.0

var warn_from_sec: int = 10
var _seconds: int = 0
var _total: int = 1
var _label: Label
var _pulse_tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(80, 76)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", 30)
	_label.add_theme_color_override(&"font_outline_color", Palette.INK)
	_label.add_theme_constant_override(&"outline_size", 6)
	add_child(_label)


## Shows `seconds` of `total`; warns (red pulse) near the end when `can_warn`.
func show_seconds(seconds: int, total: int, can_warn: bool = true) -> void:
	_seconds = maxi(0, seconds)
	_total = maxi(1, total)
	_label.text = str(_seconds)
	var is_warning := can_warn and _seconds <= warn_from_sec
	_label.add_theme_color_override(&"font_color", Palette.VERMILION if is_warning else Palette.CREAM)
	if is_warning:
		_pulse()
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	draw_circle(center, RING_RADIUS_PX + 4.0, Palette.INK)
	draw_circle(center, RING_RADIUS_PX, Palette.PANEL)
	var share := clampf(float(_seconds) / _total, 0.0, 1.0)
	var color := Palette.VERMILION if _seconds <= warn_from_sec else Palette.GOLD
	if share > 0.0:
		draw_arc(center, RING_RADIUS_PX - 3.0, -PI / 2.0, -PI / 2.0 + TAU * share, 40, color, 5.0, true)


func _pulse() -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
	pivot_offset = size / 2.0
	scale = Vector2(1.22, 1.22)
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, ^"scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
