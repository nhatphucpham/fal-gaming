class_name TimerBadge
extends Control
## The countdown in the top bar: a ring that empties and the seconds left.
## The preparation timer has a gold ring that turns red and pulses every
## second in the last `warn_from_sec` seconds. The battle clock has a steel
## ring on a darker face and a crossed-swords mark, and never warns, so the
## two cannot be mistaken for each other.
## [codeblock]
## badge.show_seconds(42, 60)          # preparation
## badge.show_battle_seconds(25, 30)   # battle time limit
## [/codeblock]

const RING_RADIUS_PX: float = 30.0
const SWORDS_RADIUS_PX: float = 15.0

var warn_from_sec: int = 10
var _seconds: int = 0
var _total: int = 1
var _is_battle: bool = false
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


## Shows the preparation's `seconds` of `total`; red pulse near the end.
func show_seconds(seconds: int, total: int) -> void:
	_is_battle = false
	_show(seconds, total)
	var is_warning := _seconds <= warn_from_sec
	_label.add_theme_color_override(&"font_color", Palette.VERMILION if is_warning else Palette.CREAM)
	if is_warning:
		_pulse()


## Shows a battle's time limit: `seconds` left of `total`, in the battle look.
func show_battle_seconds(seconds: int, total: int) -> void:
	if not _is_battle and _pulse_tween != null:
		_pulse_tween.kill()
		scale = Vector2.ONE
	_is_battle = true
	_show(seconds, total)
	_label.add_theme_color_override(&"font_color", Palette.STEEL)


func _show(seconds: int, total: int) -> void:
	_seconds = maxi(0, seconds)
	_total = maxi(1, total)
	_label.text = str(_seconds)
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	draw_circle(center, RING_RADIUS_PX + 4.0, Palette.INK)
	draw_circle(center, RING_RADIUS_PX, Palette.INDIGO_DARK if _is_battle else Palette.PANEL)
	var share := clampf(float(_seconds) / _total, 0.0, 1.0)
	var color := Palette.GOLD
	if _is_battle:
		color = Palette.STEEL
	elif _seconds <= warn_from_sec:
		color = Palette.VERMILION
	if share > 0.0:
		draw_arc(center, RING_RADIUS_PX - 3.0, -PI / 2.0, -PI / 2.0 + TAU * share, 40, color, 5.0, true)
	if _is_battle:
		_draw_swords(center + Vector2(RING_RADIUS_PX - 5.0, RING_RADIUS_PX - 9.0))


# Two crossed swords on a small ink disc, at the badge's lower right.
func _draw_swords(at: Vector2) -> void:
	draw_circle(at, SWORDS_RADIUS_PX, Palette.INK)
	draw_circle(at, SWORDS_RADIUS_PX - 2.0, Palette.VERMILION_DARK)
	var reach := SWORDS_RADIUS_PX - 5.5
	for side: float in [-1.0, 1.0]:
		var tip := at + Vector2(side * reach, -reach)
		var pommel := at + Vector2(-side * reach, reach)
		var along := (tip - pommel).normalized()
		var guard := pommel + along * 4.0
		var across := Vector2(-along.y, along.x) * 3.5
		draw_line(guard, tip, Palette.STEEL, 3.0, true)
		draw_line(guard - across, guard + across, Palette.GOLD, 2.0, true)
		draw_line(pommel, guard, Palette.WOOD, 2.0, true)


func _pulse() -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
	pivot_offset = size / 2.0
	scale = Vector2(1.22, 1.22)
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, ^"scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
