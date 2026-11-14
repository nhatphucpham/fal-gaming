class_name RewardCard
extends Control
## A large reward card: a drawn icon, a title and one line of effect. A tap
## (press and release on the card) emits `chosen`; the card sinks while held.

signal chosen()

const CARD_SIZE := Vector2(208, 330)
const ICON_PX: float = 110.0

var icon_kind: StringName = &""
var _title: Label
var _effect: Label
var _is_down: bool = false
var _tween: Tween


func _init() -> void:
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
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if button.pressed:
		_is_down = true
		_scale_to(Vector2(0.95, 0.95), 0.06)
	elif _is_down:
		_is_down = false
		_scale_to(Vector2.ONE, 0.12)
		if Rect2(Vector2.ZERO, size).has_point(button.position):
			chosen.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _is_down:
		_is_down = false
		_scale_to(Vector2.ONE, 0.12)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, CARD_SIZE)
	GameTheme.make_panel(Palette.CREAM, 24, 10).draw(get_canvas_item(), rect)
	var medallion := Vector2(CARD_SIZE.x / 2.0, 100.0)
	draw_circle(medallion, 78.0, Palette.INK)
	draw_circle(medallion, 74.0, Palette.INDIGO)
	draw_circle(medallion, 66.0, Palette.INDIGO_DARK)
	IconPainter.draw(self, icon_kind, medallion, ICON_PX)
	draw_line(Vector2(28, 250), Vector2(CARD_SIZE.x - 28, 250), Palette.PAPER_DARK, 2.0)


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
