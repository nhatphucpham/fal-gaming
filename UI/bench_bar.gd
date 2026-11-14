class_name BenchBar
extends Control
## The bench: a row of slots where bought units wait. Each slot has an
## anchor node for its UnitView (scaled like the board, so a unit keeps its
## size when it moves between them). Taps, long presses and drags come out
## as signals with the slot index; target, hover and selection marks are
## drawn on request. Mouse and touch go through PointerGesture.

signal slot_tapped(slot: int)
signal slot_long_pressed(slot: int)
signal drag_started(slot: int, global_pointer: Vector2)
signal drag_moved(global_pointer: Vector2)
signal drag_ended(global_pointer: Vector2)
signal drag_cancelled()

const SLOT_SIZE := Vector2(104, 96)
const NO_SLOT: int = -1
## Where a unit's cell centre sits in its slot: low, so the figure stands.
const ANCHOR_OFFSET := Vector2(0, 4)

var _gesture := PointerGesture.new()
var _anchors: Array[Node2D] = []
var _targets: Array[int] = []
var _hover: int = NO_SLOT
var _selected: int = NO_SLOT
var _time: float = 0.0
var _piece_scale: float = 1.0
var _full_flash: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, SLOT_SIZE.y)
	_gesture.tapped.connect(func(pointer: Vector2) -> void: _emit_slot(slot_tapped, pointer))
	_gesture.long_pressed.connect(func(pointer: Vector2) -> void: _emit_slot(slot_long_pressed, pointer))
	_gesture.drag_started.connect(func(start: Vector2, pointer: Vector2) -> void: drag_started.emit(slot_at_global(start), pointer))
	_gesture.drag_moved.connect(func(pointer: Vector2) -> void: drag_moved.emit(pointer))
	_gesture.drag_ended.connect(func(pointer: Vector2) -> void: drag_ended.emit(pointer))
	_gesture.drag_cancelled.connect(func() -> void: drag_cancelled.emit())
	resized.connect(_layout)


## Makes `count` slots; units on them are drawn at `piece_scale`.
func setup(count: int, piece_scale: float) -> void:
	_piece_scale = piece_scale
	for anchor: Node2D in _anchors:
		anchor.queue_free()
	_anchors.clear()
	for index: int in count:
		var anchor := Node2D.new()
		anchor.name = "Slot%d" % index
		anchor.scale = Vector2(piece_scale, piece_scale)
		add_child(anchor)
		_anchors.append(anchor)
	_layout()


func get_slot_count() -> int:
	return _anchors.size()


## The node a slot's UnitView goes under (its origin is the unit's cell centre).
func get_slot_anchor(slot: int) -> Node2D:
	return _anchors[slot]


## The slot under a global canvas position, or NO_SLOT.
func slot_at_global(global_pointer: Vector2) -> int:
	var local := get_global_transform_with_canvas().affine_inverse() * global_pointer
	for index: int in _anchors.size():
		if _slot_rect(index).has_point(local):
			return index
	return NO_SLOT


func set_target_slots(slots: Array[int]) -> void:
	_targets = slots.duplicate()
	queue_redraw()


func set_hover_slot(slot: int) -> void:
	if slot != _hover:
		_hover = slot
		queue_redraw()


func set_selected_slot(slot: int) -> void:
	_selected = slot
	queue_redraw()


func clear_marks() -> void:
	set_target_slots([])
	set_hover_slot(NO_SLOT)
	set_selected_slot(NO_SLOT)


## Flashes every slot red: the bench is full.
func flash_full() -> void:
	create_tween().tween_method(func(value: float) -> void:
		_full_flash = value
		queue_redraw(), 1.0, 0.0, 0.45)


func cancel_gesture() -> void:
	_gesture.cancel()


func _gui_input(event: InputEvent) -> void:
	if _gesture.handle_input(event):
		accept_event()


func _input(event: InputEvent) -> void:
	_gesture.handle_global_input(event)


func _notification(what: int) -> void:
	if _gesture != null:
		_gesture.handle_notification(what)


func _process(delta: float) -> void:
	_gesture.update(delta)
	if _selected != NO_SLOT:
		_time += delta
		queue_redraw()


func _draw() -> void:
	for index: int in _anchors.size():
		var rect := _slot_rect(index).grow(-4.0)
		var fill := Palette.PANEL
		if _targets.has(index):
			fill = Palette.PANEL.lerp(Palette.JADE, 0.35)
		if index == _hover:
			fill = Palette.PANEL.lerp(Palette.JADE if _targets.has(index) else Palette.VERMILION, 0.7)
		fill = fill.lerp(Palette.VERMILION, _full_flash * 0.75)
		var box := GameTheme.make_panel(fill, 14, 5)
		box.border_color = Palette.INK
		box.draw(get_canvas_item(), rect)
		var floor_center := rect.get_center() + Vector2(0, rect.size.y * 0.3)
		draw_colored_polygon(UnitPainter.Brush.ellipse(floor_center, 34.0, 9.0, 18), Color(Palette.BACKDROP, 0.6))
		if index == _selected:
			var pulse := 1.0 + 0.04 * sin(_time * 7.0)
			var ring := Rect2(rect.get_center() - rect.size * pulse / 2.0, rect.size * pulse)
			draw_rect(ring, Palette.INK, false, 7.0)
			draw_rect(ring, Palette.GOLD, false, 4.0)


func _slot_rect(index: int) -> Rect2:
	var count := maxi(1, _anchors.size())
	var gap := (size.x - count * SLOT_SIZE.x) / (count + 1)
	return Rect2(Vector2(gap + index * (SLOT_SIZE.x + gap), 0.0), SLOT_SIZE)


func _layout() -> void:
	for index: int in _anchors.size():
		_anchors[index].position = _slot_rect(index).get_center() + ANCHOR_OFFSET
	queue_redraw()


func _emit_slot(bar_signal: Signal, pointer: Vector2) -> void:
	var slot := slot_at_global(pointer)
	if slot != NO_SLOT:
		bar_signal.emit(slot)
