class_name ShopBar
extends Control
## The shop row: one ShopCard per offer. Taps, long presses and drags on a
## card come out as signals with the slot index; the bar does not know what
## they do. Uses PointerGesture, so mouse and touch behave the same.
## [codeblock]
## shop.show_offers(units, true)          # cards flip in
## shop.card_tapped.connect(func(slot): ...)
## [/codeblock]

signal card_tapped(slot: int)
signal card_long_pressed(slot: int)
signal card_drag_started(slot: int, global_pointer: Vector2)
signal card_drag_moved(global_pointer: Vector2)
signal card_drag_ended(global_pointer: Vector2)
signal card_drag_cancelled()

const FLIP_STAGGER_SEC: float = 0.05

var _gesture := PointerGesture.new()
var _cards: Array[ShopCard] = []
var _drag_slot: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, ShopCard.CARD_SIZE.y + 4)
	_gesture.tapped.connect(func(pointer: Vector2) -> void: _emit_slot(card_tapped, pointer))
	_gesture.long_pressed.connect(func(pointer: Vector2) -> void: _emit_slot(card_long_pressed, pointer))
	_gesture.drag_started.connect(_on_drag_started)
	_gesture.drag_moved.connect(func(pointer: Vector2) -> void:
		if _drag_slot >= 0:
			card_drag_moved.emit(pointer))
	_gesture.drag_ended.connect(_on_drag_ended)
	_gesture.drag_cancelled.connect(_on_drag_cancelled)
	resized.connect(_layout)


## Makes `count` empty cards.
func setup(count: int) -> void:
	for card: ShopCard in _cards:
		card.queue_free()
	_cards.clear()
	for index: int in count:
		var card := ShopCard.new()
		add_child(card)
		_cards.append(card)
	_layout()


## Shows one unit (or null for a bought slot) per card; `flip` turns the
## cards over one after another.
func show_offers(units: Array[UnitData], flip: bool) -> void:
	for index: int in _cards.size():
		_cards[index].set_unit(units[index] if index < units.size() else null)
		if flip:
			_cards[index].flip_in(index * FLIP_STAGGER_SEC)


## Empties one card (bought), with a quick squeeze.
func clear_slot(slot: int) -> void:
	var card := get_card(slot)
	if card == null:
		return
	card.set_unit(null)
	card.scale = Vector2(0.85, 0.85)
	create_tween().tween_property(card, ^"scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func get_card(slot: int) -> ShopCard:
	return _cards[slot] if slot >= 0 and slot < _cards.size() else null


func set_selected(slot: int) -> void:
	for index: int in _cards.size():
		if _cards[index].is_selected != (index == slot):
			_cards[index].is_selected = index == slot


## Dims what `gold` cannot buy and marks cards whose purchase merges.
func update_hints(gold: int, merges: Array[bool]) -> void:
	for index: int in _cards.size():
		var card := _cards[index]
		card.set_affordable(card.unit == null or card.unit.cost <= gold)
		card.set_merge_hint(index < merges.size() and merges[index])


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


func _slot_at(global_pointer: Vector2) -> int:
	for index: int in _cards.size():
		if _cards[index].unit != null and _cards[index].get_global_rect().has_point(global_pointer):
			return index
	return -1


func _emit_slot(bar_signal: Signal, pointer: Vector2) -> void:
	var slot := _slot_at(pointer)
	if slot >= 0:
		bar_signal.emit(slot)


func _on_drag_started(start: Vector2, pointer: Vector2) -> void:
	_drag_slot = _slot_at(start)
	if _drag_slot >= 0:
		card_drag_started.emit(_drag_slot, pointer)


func _on_drag_ended(pointer: Vector2) -> void:
	if _drag_slot >= 0:
		_drag_slot = -1
		card_drag_ended.emit(pointer)


func _on_drag_cancelled() -> void:
	if _drag_slot >= 0:
		_drag_slot = -1
		card_drag_cancelled.emit()


func _layout() -> void:
	if _cards.is_empty():
		return
	var gap := (size.x - _cards.size() * ShopCard.CARD_SIZE.x) / (_cards.size() + 1)
	for index: int in _cards.size():
		_cards[index].position = Vector2(gap + index * (ShopCard.CARD_SIZE.x + gap), 2.0)
