class_name RosterStrip
extends Control
## A horizontally scrolling row of UnitCards. A sideways swipe scrolls (with a
## little momentum); an upward drag picks a card up. Taps, long presses and
## card drags come out as signals with unit ids; the strip does not know what
## they do.
## [codeblock]
## strip.set_units(units)
## strip.card_tapped.connect(func(unit_id): strip.set_selected(unit_id))
## [/codeblock]

signal card_tapped(unit_id: StringName)
signal card_long_pressed(unit_id: StringName)
signal card_drag_started(unit_id: StringName, global_pointer: Vector2)
signal card_drag_moved(global_pointer: Vector2)
signal card_drag_ended(global_pointer: Vector2)
## A card drag stopped without a drop.
signal card_drag_cancelled()

const GAP_PX: float = 10.0
const SIDE_PADDING_PX: float = 16.0
const WHEEL_STEP_PX: float = 90.0
const FRICTION_PER_SEC: float = 5.0
## Width of the soft fade at an edge that has more cards beyond it.
const EDGE_FADE_PX: float = 48.0

var _gesture := PointerGesture.new()
var _content: Control
var _edge_fade: Control
var _max_scroll_px: float = 0.0
var _cards: Array[UnitCard] = []
var _scroll_px: float = 0.0
var _velocity_px: float = 0.0
var _is_card_drag: bool = false
var _drag_unit: StringName = &""
var _last_pointer_x: float = 0.0
var _last_move_msec: int = 0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, UnitCard.CARD_SIZE.y + 8)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	# Drawn above the cards: fades the edges that can still be scrolled to,
	# so a card cut by the screen edge reads as "more this way".
	_edge_fade = Control.new()
	_edge_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge_fade.draw.connect(_draw_edge_fade)
	add_child(_edge_fade)
	_gesture.tapped.connect(_on_tapped)
	_gesture.long_pressed.connect(_on_long_pressed)
	_gesture.drag_started.connect(_on_drag_started)
	_gesture.drag_moved.connect(_on_drag_moved)
	_gesture.drag_ended.connect(_on_drag_ended)
	_gesture.drag_cancelled.connect(_on_drag_cancelled)
	resized.connect(func() -> void: _set_scroll(_scroll_px))


## Replaces the cards, one per unit, in this order.
func set_units(units: Array[UnitData]) -> void:
	for card: UnitCard in _cards:
		card.queue_free()
	_cards.clear()
	for index: int in units.size():
		var card := UnitCard.new()
		card.setup(units[index])
		card.position = Vector2(SIDE_PADDING_PX + index * (UnitCard.CARD_SIZE.x + GAP_PX), 4)
		_content.add_child(card)
		_cards.append(card)
	_set_scroll(0.0)


## Highlights the card of `unit_id`; an empty id clears the highlight.
func set_selected(unit_id: StringName) -> void:
	for card: UnitCard in _cards:
		var selected := card.unit.id == unit_id
		if card.is_selected != selected:
			card.is_selected = selected


func get_card(unit_id: StringName) -> UnitCard:
	for card: UnitCard in _cards:
		if card.unit.id == unit_id:
			return card
	return null


## Stops any press in progress.
func cancel_gesture() -> void:
	_gesture.cancel()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT]:
		_set_scroll(_scroll_px - WHEEL_STEP_PX)
		accept_event()
		return
	if button != null and button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT]:
		_set_scroll(_scroll_px + WHEEL_STEP_PX)
		accept_event()
		return
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		_velocity_px = 0.0
	if _gesture.handle_input(event):
		accept_event()


func _input(event: InputEvent) -> void:
	_gesture.handle_global_input(event)


func _notification(what: int) -> void:
	if _gesture != null:
		_gesture.handle_notification(what)


func _process(delta: float) -> void:
	_gesture.update(delta)
	if absf(_velocity_px) > 5.0 and not _gesture.is_dragging():
		_set_scroll(_scroll_px + _velocity_px * delta)
		_velocity_px *= maxf(0.0, 1.0 - FRICTION_PER_SEC * delta)


func _card_at(global_pointer: Vector2) -> UnitCard:
	for card: UnitCard in _cards:
		if card.get_global_rect().has_point(global_pointer):
			return card
	return null


func _on_tapped(global_pointer: Vector2) -> void:
	var card := _card_at(global_pointer)
	if card != null:
		card.pop()
		card_tapped.emit(card.unit.id)


func _on_long_pressed(global_pointer: Vector2) -> void:
	var card := _card_at(global_pointer)
	if card != null:
		card_long_pressed.emit(card.unit.id)


func _on_drag_started(start: Vector2, global_pointer: Vector2) -> void:
	var travel := global_pointer - start
	var card := _card_at(start)
	_is_card_drag = card != null and travel.y < 0.0 and absf(travel.y) > absf(travel.x) * 0.8
	_last_pointer_x = global_pointer.x
	_last_move_msec = Time.get_ticks_msec()
	if _is_card_drag:
		_drag_unit = card.unit.id
		card_drag_started.emit(_drag_unit, global_pointer)
	else:
		_set_scroll(_scroll_px - travel.x)


func _on_drag_moved(global_pointer: Vector2) -> void:
	if _is_card_drag:
		card_drag_moved.emit(global_pointer)
		return
	var step := global_pointer.x - _last_pointer_x
	var now := Time.get_ticks_msec()
	var seconds := maxf(0.001, (now - _last_move_msec) / 1000.0)
	_velocity_px = lerpf(_velocity_px, -step / seconds, 0.5)
	_last_pointer_x = global_pointer.x
	_last_move_msec = now
	_set_scroll(_scroll_px - step)


func _on_drag_cancelled() -> void:
	_velocity_px = 0.0
	if _is_card_drag:
		_is_card_drag = false
		card_drag_cancelled.emit()


func _on_drag_ended(global_pointer: Vector2) -> void:
	if _is_card_drag:
		_is_card_drag = false
		card_drag_ended.emit(global_pointer)
	elif Time.get_ticks_msec() - _last_move_msec > 80:
		_velocity_px = 0.0


func _set_scroll(value: float) -> void:
	var content_width := SIDE_PADDING_PX * 2.0 + _cards.size() * (UnitCard.CARD_SIZE.x + GAP_PX) - GAP_PX
	_max_scroll_px = maxf(0.0, content_width - size.x)
	_scroll_px = clampf(value, 0.0, _max_scroll_px)
	_content.position.x = -_scroll_px
	_edge_fade.queue_redraw()


func _draw_edge_fade() -> void:
	var height := _edge_fade.size.y
	var solid := Palette.BACKDROP
	var clear := Color(solid, 0.0)
	if _scroll_px > 1.0:
		_fade_rect(0.0, height, solid, clear)
	if _scroll_px < _max_scroll_px - 1.0:
		_fade_rect(_edge_fade.size.x - EDGE_FADE_PX, height, clear, solid)


func _fade_rect(left: float, height: float, left_color: Color, right_color: Color) -> void:
	var points := PackedVector2Array([
		Vector2(left, 0), Vector2(left + EDGE_FADE_PX, 0),
		Vector2(left + EDGE_FADE_PX, height), Vector2(left, height),
	])
	var colors := PackedColorArray([left_color, right_color, right_color, left_color])
	_edge_fade.draw_polygon(points, colors)
