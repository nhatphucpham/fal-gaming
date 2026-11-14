class_name RewardCard
extends Control
## A large reward card: a drawn icon, a title and one line of effect. A tap
## or a short drag released on the card emits `chosen`; the card sinks while
## held. Input goes through PointerGesture, so a cancelled touch chooses
## nothing, and neither does a long press.

signal chosen()

const CARD_SIZE := Vector2(208, 330)
const ICON_PX: float = 110.0

var icon_kind: StringName = &""
var _title: Label
var _effect: Label
var _is_down: bool = false
var _tween: Tween
var _gesture := PointerGesture.new()


func _init() -> void:
	_gesture.tapped.connect(_choose_if_inside)
	_gesture.drag_ended.connect(_choose_if_inside)
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	pivot_offset = CARD_SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_title = _make_label(28, Vector2(8, 190), Vector2(CARD_SIZE.x - 16, 70))
	_effect = _make_label(22, Vector2(8, 258), Vector2(CARD_SIZE.x - 16, 62))
	_effect.add_theme_color_override(&"font_color", Palette.INK)
	_effect.add_theme_constant_override(&"outline_size", 0)


func setup(kind: StringName, title: String, effect: String) -> void:
	icon_kind = kind
	_title.text = title
	_effect.text = effect
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _gesture.handle_input(event):
		accept_event()
	_update_pressed()


func _input(event: InputEvent) -> void:
	_gesture.handle_global_input(event)
	_update_pressed()


func _notification(what: int) -> void:
	if _gesture != null:
		_gesture.handle_notification(what)
		_update_pressed()


func _process(delta: float) -> void:
	_gesture.update(delta)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, CARD_SIZE)
	GameTheme.make_panel(Palette.CREAM, 24, 10).draw(get_canvas_item(), rect)
	var medallion := Vector2(CARD_SIZE.x / 2.0, 100.0)
	draw_circle(medallion, 78.0, Palette.INK)
	draw_circle(medallion, 74.0, Palette.INDIGO)
	draw_circle(medallion, 66.0, Palette.INDIGO_DARK)
	IconPainter.draw(self, icon_kind, medallion, ICON_PX)
	draw_line(Vector2(28, 250), Vector2(CARD_SIZE.x - 28, 250), Palette.PAPER_DARK, 2.0)


func _choose_if_inside(pointer: Vector2) -> void:
	var local := get_global_transform_with_canvas().affine_inverse() * pointer
	if Rect2(Vector2.ZERO, size).has_point(local):
		chosen.emit()


# Sinks the card while a press is held and lifts it when the press ends.
func _update_pressed() -> void:
	if _gesture.is_pressed() == _is_down:
		return
	_is_down = _gesture.is_pressed()
	_scale_to(Vector2(0.95, 0.95) if _is_down else Vector2.ONE, 0.06 if _is_down else 0.12)


func _make_label(font_size: int, at: Vector2, label_size: Vector2) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.position = at
	label.size = label_size
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", Palette.VERMILION_DARK)
	label.add_theme_color_override(&"font_outline_color", Palette.CREAM)
	label.add_theme_constant_override(&"outline_size", 2)
	add_child(label)
	return label


func _scale_to(target: Vector2, seconds: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, ^"scale", target, seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
