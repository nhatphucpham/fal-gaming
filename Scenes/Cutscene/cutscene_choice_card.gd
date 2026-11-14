class_name CutsceneChoiceCard
extends Control
## One choice of a cutscene: a cream card with a gold seal, a small heading
## (the kind: Hạ Mốc or Biến Dị) and the choice's text. A release on it
## emits `chosen`, the same way as a RewardCard.

signal chosen()

const CARD_SIZE := Vector2(316, 300)

var _heading: Label
var _text: Label
var _gesture := PointerGesture.new()
var _tween: Tween
var _is_down: bool = false


func _init() -> void:
	_gesture.is_long_press_enabled = false
	_gesture.tapped.connect(_choose_if_inside)
	_gesture.drag_ended.connect(_choose_if_inside)
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	pivot_offset = CARD_SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	var seal := EpiphanySeal.new()
	seal.position = Vector2(CARD_SIZE.x / 2.0 - 26.0, 18.0)
	seal.size = Vector2(52, 52)
	add_child(seal)
	_heading = _make_label(30, Vector2(12, 78), Vector2(CARD_SIZE.x - 24, 44), Palette.VERMILION_DARK)
	_text = _make_label(24, Vector2(16, 126), Vector2(CARD_SIZE.x - 32, 160), Palette.INK)


func setup(heading: String, text: String) -> void:
	_heading.text = heading
	_text.text = text


func get_heading() -> String:
	return _heading.text


func get_text() -> String:
	return _text.text


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
	GameTheme.make_panel(Palette.CREAM, 22, 10).draw(get_canvas_item(), Rect2(Vector2.ZERO, CARD_SIZE))
	draw_line(Vector2(36, 122), Vector2(CARD_SIZE.x - 36, 122), Palette.PAPER_DARK, 2.0)


func _choose_if_inside(pointer: Vector2) -> void:
	var local := get_global_transform_with_canvas().affine_inverse() * pointer
	if Rect2(Vector2.ZERO, size).has_point(local):
		chosen.emit()


func _update_pressed() -> void:
	if _gesture.is_pressed() == _is_down:
		return
	_is_down = _gesture.is_pressed()
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, ^"scale", Vector2(0.95, 0.95) if _is_down else Vector2.ONE, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _make_label(font_size: int, at: Vector2, label_size: Vector2, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.position = at
	label.size = label_size
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	add_child(label)
	return label
