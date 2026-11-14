class_name ResourceChip
extends Control
## A rounded chip with a drawn icon and a number (gold, supply, level,
## morale, units on the board). The number ticks to a new value and the chip
## bounces; flash_lacking() shakes it red when the player could not afford
## something; burst() rings it for a level up.
## [codeblock]
## chip.setup(&"coin")
## chip.set_value(12)        # ticks from the shown value
## chip.flash_lacking()
## [/codeblock]

const ICON_PX: float = 38.0
const TICK_SEC: float = 0.3

var icon_kind: StringName = &"coin"
## Text shown after the number, e.g. "/6" for a capacity.
var suffix: String = ""
## Shows a plus sign before positive numbers (gains in the result banner).
var is_signed: bool = false

var _label: Label
var _value: int = 0
var _shown: float = 0.0
var _flash: float = 0.0
var _burst: float = 1.0
var _count_tween: Tween
var _bounce_tween: Tween
var _shake_tween: Tween
# The chip's layout position, kept while it shakes so repeated shakes never
# walk it sideways.
var _rest_x: float = 0.0
var _box: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(104, 60)
	_box = GameTheme.make_panel(Palette.PANEL, 30, 4)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override(&"font_size", 30)
	_label.add_theme_color_override(&"font_outline_color", Palette.INK)
	_label.add_theme_constant_override(&"outline_size", 5)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	resized.connect(_layout)


func setup(kind: StringName, text_suffix: String = "") -> void:
	icon_kind = kind
	suffix = text_suffix
	_show_number()
	queue_redraw()


## Shows `value`; animated ticks and a bounce unless `animate` is false.
func set_value(value: int, animate: bool = true) -> void:
	if value == _value and animate:
		return
	_value = value
	# A count still running would carry the number past this value.
	_kill(_count_tween)
	if not animate or not is_inside_tree():
		_shown = value
		_show_number()
		return
	_count_tween = create_tween()
	_count_tween.tween_method(_set_shown, _shown, float(value), TICK_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bounce()


func get_value() -> int:
	return _value


## The number on the chip now (between values while it ticks).
func get_shown_value() -> int:
	return roundi(_shown)


func set_suffix(text_suffix: String) -> void:
	suffix = text_suffix
	_show_number()


func bounce() -> void:
	_kill(_bounce_tween)
	pivot_offset = size / 2.0
	scale = Vector2(1.18, 1.18)
	_bounce_tween = create_tween()
	_bounce_tween.tween_property(self, ^"scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Red flash and a shake: "not enough of this".
func flash_lacking() -> void:
	if _shake_tween != null and _shake_tween.is_running():
		_shake_tween.kill()
	else:
		_rest_x = position.x
	position.x = _rest_x
	_flash = 1.0
	_shake_tween = create_tween()
	for offset_x: float in [-7.0, 6.0, -4.0, 3.0, 0.0]:
		_shake_tween.tween_property(self, ^"position:x", _rest_x + offset_x, 0.045)
	_shake_tween.parallel().tween_method(_set_flash, 1.0, 0.0, 0.35)


## A golden ring bursts out of the icon (level up).
func burst() -> void:
	bounce()
	create_tween().tween_method(_set_burst, 0.0, 1.0, 0.4).set_ease(Tween.EASE_OUT)


## Centre of the icon in global canvas coordinates (where sold units fly).
func get_icon_center() -> Vector2:
	return get_global_transform_with_canvas() * _icon_center()


func _draw() -> void:
	var fill := Palette.PANEL.lerp(Palette.VERMILION, _flash * 0.8)
	_box.bg_color = fill
	_box.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	if _burst < 1.0:
		var alpha := 1.0 - _burst
		draw_arc(_icon_center(), ICON_PX * (0.5 + _burst * 0.9), 0.0, TAU, 32, Color(Palette.GOLD, alpha), 5.0 * alpha + 1.0, true)
	IconPainter.draw(self, icon_kind, _icon_center(), ICON_PX)


func _icon_center() -> Vector2:
	return Vector2(10.0 + ICON_PX / 2.0, size.y / 2.0)


func _layout() -> void:
	var left := 14.0 + ICON_PX
	_label.position = Vector2(left, 0)
	_label.size = Vector2(maxf(0.0, size.x - left - 8.0), size.y)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _set_shown(value: float) -> void:
	_shown = value
	_show_number()


func _show_number() -> void:
	var shown := roundi(_shown)
	_label.text = ("+%d%s" if is_signed and shown > 0 else "%d%s") % [shown, suffix]


func _set_flash(value: float) -> void:
	_flash = value
	queue_redraw()


func _set_burst(value: float) -> void:
	_burst = value
	queue_redraw()


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
