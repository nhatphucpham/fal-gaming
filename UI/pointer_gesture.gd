class_name PointerGesture
extends RefCounted
## Turns raw pointer events into tap, long press and drag, the same way for
## mouse and touch (touch arrives as emulated mouse events; see
## Docs/systems/board.md). A right click counts as a long press; other
## buttons are ignored while a press is held. A second finger, a cancelled
## touch or lost focus cancels the press (drag_cancelled for a drag).
## Positions are global canvas positions. The owner forwards _gui_input
## events, _input events (handle_global_input), notifications and update().
## [codeblock]
## var gesture := PointerGesture.new()
## gesture.tapped.connect(_on_tapped)
## func _gui_input(event): if gesture.handle_input(event): accept_event()
## func _process(delta): gesture.update(delta)
## [/codeblock]

signal tapped(position: Vector2)
signal long_pressed(position: Vector2)
## The pointer moved past the threshold while held; `start` is where it went down.
signal drag_started(start: Vector2, position: Vector2)
signal drag_moved(position: Vector2)
signal drag_ended(position: Vector2)

const LONG_PRESS_SEC: float = 0.4
const DRAG_THRESHOLD_PX: float = 14.0

var _is_down: bool = false
var _is_dragging: bool = false
var _long_press_fired: bool = false
var _held_sec: float = 0.0
var _start: Vector2 = Vector2.ZERO
var _last: Vector2 = Vector2.ZERO


## A drag in progress was abandoned without a drop; undo its effects.
signal drag_cancelled()

## Feeds one input event; true when the gesture used it.
func handle_input(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	if button != null and _is_down and button.button_index != MOUSE_BUTTON_LEFT:
		# A right click (or wheel) during a held press must not end or start
		# anything; the left release still finishes the gesture.
		return true
	if button != null:
		return _handle_button(button)
	var motion := event as InputEventMouseMotion
	if motion != null and _is_down:
		_handle_motion(motion.global_position)
		return true
	return false


## Advances the long-press timer; call every frame.
func update(delta: float) -> void:
	if not _is_down or _is_dragging or _long_press_fired:
		return
	_held_sec += delta
	if _held_sec >= LONG_PRESS_SEC:
		_long_press_fired = true
		long_pressed.emit(_last)


## Watches events outside the owner (call from its _input): a second finger
## or a cancelled touch cancels the press in progress.
func handle_global_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or not _is_down:
		return
	if touch.canceled or (touch.pressed and touch.index > 0):
		cancel()


## Forwards a notification; losing the window or app focus, or the mouse
## leaving the window, cancels the press in progress.
func handle_notification(what: int) -> void:
	if what in [Node.NOTIFICATION_WM_MOUSE_EXIT, Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_FOCUS_OUT]:
		cancel()


## Drops the current press. A drag in progress emits drag_cancelled.
func cancel() -> void:
	var was_dragging := _is_dragging
	_is_down = false
	_is_dragging = false
	if was_dragging:
		drag_cancelled.emit()


func is_dragging() -> bool:
	return _is_dragging


func _handle_button(button: InputEventMouseButton) -> bool:
	if button.button_index == MOUSE_BUTTON_RIGHT:
		if button.pressed:
			cancel()
			long_pressed.emit(button.global_position)
		return true
	if button.button_index != MOUSE_BUTTON_LEFT:
		return false
	if button.pressed:
		_is_down = true
		_is_dragging = false
		_long_press_fired = false
		_held_sec = 0.0
		_start = button.global_position
		_last = _start
		return true
	if not _is_down:
		return false
	_is_down = false
	if _is_dragging:
		_is_dragging = false
		drag_ended.emit(button.global_position)
	elif not _long_press_fired:
		tapped.emit(button.global_position)
	return true


func _handle_motion(position: Vector2) -> void:
	_last = position
	if _is_dragging:
		drag_moved.emit(position)
		return
	if _long_press_fired or position.distance_to(_start) < DRAG_THRESHOLD_PX:
		return
	_is_dragging = true
	drag_started.emit(_start, position)
