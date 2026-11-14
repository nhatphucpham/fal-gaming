class_name PrepTimer
extends Node
## Counts the preparation time down in real seconds. It pauses while the
## window or app has lost focus or the browser tab is hidden, and a single
## long frame (a tab coming back) counts at most MAX_FRAME_SEC, so time
## never runs out unseen. A duration of 0 means no limit.
## [codeblock]
## timer.expired.connect(_start_battle)
## timer.start(60)
## [/codeblock]

signal expired()
## The whole seconds left changed (also once at start).
signal seconds_changed(seconds_left: int)

const MAX_FRAME_SEC: float = 0.25
const HIDDEN_POLL_SEC: float = 0.25

var time_left: float = 0.0
var is_running: bool = false
var _has_focus: bool = true
var _is_tab_hidden: bool = false
var _poll_left: float = 0.0
var _last_whole: int = -1


## Starts counting down from `seconds`; 0 stops the timer (no limit).
func start(seconds: int) -> void:
	time_left = float(seconds)
	is_running = seconds > 0
	_last_whole = -1
	_emit_seconds()


func stop() -> void:
	is_running = false


func is_paused() -> bool:
	return not _has_focus or _is_tab_hidden


func get_seconds_left() -> int:
	return ceili(time_left)


## Advances by `delta_sec` unless paused; tests call it directly.
func advance(delta_sec: float) -> void:
	if not is_running or is_paused():
		return
	time_left = maxf(0.0, time_left - minf(delta_sec, MAX_FRAME_SEC))
	_emit_seconds()
	if time_left <= 0.0:
		is_running = false
		expired.emit()


func _process(delta: float) -> void:
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = HIDDEN_POLL_SEC
		_is_tab_hidden = _read_tab_hidden()
	advance(delta)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			_has_focus = false
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			_has_focus = true


# Browsers stop drawing hidden tabs but do not always report lost focus.
func _read_tab_hidden() -> bool:
	if not OS.has_feature("web"):
		return false
	return bool(JavaScriptBridge.eval("document.hidden", true))


func _emit_seconds() -> void:
	var whole := get_seconds_left()
	if whole != _last_whole:
		_last_whole = whole
		seconds_changed.emit(whole)
